import { Body, Controller, Delete, Get, Inject, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { Type } from 'class-transformer';
import { IsIn, IsNumber, IsOptional, IsString, Length, Max, Min } from 'class-validator';
import { AddressLabel, BusinessCategory } from '@prisma/client';
import { HttpStatus } from '@nestjs/common';
import { AuthGuard } from '../common/auth.guard';
import { AuthUser, CurrentUser } from '../common/current-user.decorator';
import { ApiError } from '../common/api-error';
import { BUSINESS_CATEGORIES } from '../catalog/catalog';
import { inEgypt } from '../domain/geo';
import { minorToLabel } from '../domain/money';
import { normalizeEgyptPhone } from '../domain/phone';
import { PrismaService } from '../prisma/prisma.service';

class BusinessDto {
  @IsString()
  @Length(2, 80)
  name!: string;

  @IsIn(BUSINESS_CATEGORIES.map((item) => item.code))
  category!: BusinessCategory;

  @IsString()
  @Length(2, 60)
  managerName!: string;

  @IsString()
  phone!: string;

  @IsString()
  @Length(3, 180)
  addressLine!: string;

  @IsOptional()
  @IsString()
  details?: string;

  @IsOptional()
  @IsString()
  governorate?: string;

  @IsOptional()
  @IsString()
  city?: string;

  @IsOptional()
  @IsString()
  area?: string;

  @Type(() => Number)
  @IsNumber()
  @Min(-90)
  @Max(90)
  lat!: number;

  @Type(() => Number)
  @IsNumber()
  @Min(-180)
  @Max(180)
  lng!: number;

  @IsOptional()
  @IsString()
  logoUrl?: string;
}

class RecipientDto {
  @IsString()
  @Length(2, 60)
  name!: string;

  @IsString()
  phone!: string;

  @IsOptional()
  @IsString()
  line?: string;

  @IsOptional()
  @IsString()
  details?: string;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  lat?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  lng?: number;

  @IsOptional()
  @IsString()
  @Length(0, 240)
  notes?: string;
}

@Controller('business')
@UseGuards(AuthGuard)
export class BusinessController {
  constructor(@Inject(PrismaService) private readonly prisma: PrismaService) {}

  @Get()
  async get(@CurrentUser() user: AuthUser) {
    const member = await this.membership(user.id);
    return { role: member.role, ...member.business };
  }

  @Post()
  async create(@CurrentUser() user: AuthUser, @Body() dto: BusinessDto) {
    const existing = await this.prisma.businessMember.findFirst({ where: { userId: user.id } });
    if (existing) throw new ApiError('BUSINESS_EXISTS', 'النشاط التجاري مسجّل بالفعل.');
    const account = await this.prisma.user.findUnique({ where: { id: user.id } });
    if (account?.accountType !== 'BUSINESS') {
      throw new ApiError('BUSINESS_ACCOUNT_REQUIRED', 'نوع الحساب لازم يكون نشاط تجاري.');
    }
    const phone = normalizeEgyptPhone(dto.phone);
    if (!phone) throw new ApiError('INVALID_PHONE', 'رقم هاتف النشاط غير صحيح.');
    await this.ensureCovered(dto.lat, dto.lng);
    const business = await this.prisma.businessProfile.create({
      data: {
        ...dto,
        phone,
        members: { create: { userId: user.id, role: 'OWNER' } },
      },
    });
    await this.prisma.address.create({
      data: {
        userId: user.id,
        businessId: business.id,
        label: AddressLabel.SHOP,
        name: business.name,
        governorate: dto.governorate?.trim() || 'غير محدد',
        city: dto.city?.trim() || 'غير محدد',
        area: dto.area?.trim() || 'غير محدد',
        line: dto.addressLine,
        details: dto.details,
        phone,
        lat: dto.lat,
        lng: dto.lng,
        isDefault: true,
      },
    });
    return business;
  }

  @Patch()
  async update(@CurrentUser() user: AuthUser, @Body() dto: BusinessDto) {
    const member = await this.membership(user.id);
    if (member.role !== 'OWNER') throw new ApiError('FORBIDDEN', 'تعديل بيانات النشاط لصاحب الحساب.', HttpStatus.FORBIDDEN);
    const phone = normalizeEgyptPhone(dto.phone);
    if (!phone) throw new ApiError('INVALID_PHONE', 'رقم هاتف النشاط غير صحيح.');
    await this.ensureCovered(dto.lat, dto.lng);
    const business = await this.prisma.businessProfile.update({
      where: { id: member.businessId },
      data: { ...dto, phone },
    });
    const shop = await this.prisma.address.findFirst({
      where: { userId: user.id, businessId: business.id, label: 'SHOP' },
    });
    if (shop) {
      await this.prisma.address.update({
        where: { id: shop.id },
        data: {
          name: business.name,
          line: dto.addressLine,
          details: dto.details,
          phone,
          lat: dto.lat,
          lng: dto.lng,
          governorate: dto.governorate?.trim() || shop.governorate,
          city: dto.city?.trim() || shop.city,
          area: dto.area?.trim() || shop.area,
        },
      });
    }
    return business;
  }

  @Get('stats')
  async stats(@CurrentUser() user: AuthUser) {
    const member = await this.membership(user.id);
    const start = new Date();
    start.setHours(0, 0, 0, 0);
    const where = { businessId: member.businessId, createdAt: { gte: start } };
    const [today, completed, active, spend] = await Promise.all([
      this.prisma.deliveryOrder.count({ where }),
      this.prisma.deliveryOrder.count({ where: { ...where, status: 'DELIVERED' } }),
      this.prisma.deliveryOrder.count({
        where: {
          businessId: member.businessId,
          status: { in: ['SEARCHING', 'ACCEPTED', 'EN_ROUTE_PICKUP', 'PICKED_UP', 'EN_ROUTE_DROPOFF'] },
        },
      }),
      this.prisma.deliveryOrder.aggregate({ where, _sum: { totalMinor: true } }),
    ]);
    const totalMinor = spend._sum.totalMinor ?? 0;
    return { today, completed, active, totalMinor, totalLabel: minorToLabel(totalMinor) };
  }

  @Get('recipients')
  async recipients(@CurrentUser() user: AuthUser, @Query('q') q?: string) {
    const member = await this.membership(user.id);
    const query = q?.trim();
    return this.prisma.savedRecipient.findMany({
      where: {
        businessId: member.businessId,
        ...(query
          ? {
              OR: [
                { name: { contains: query, mode: 'insensitive' } },
                { phone: { contains: query.replace(/\s/g, '') } },
              ],
            }
          : {}),
      },
      orderBy: { createdAt: 'desc' },
      take: 40,
    });
  }

  @Patch('recipients/:id')
  async updateRecipient(@CurrentUser() user: AuthUser, @Param('id') id: string, @Body() dto: RecipientDto) {
    const member = await this.membership(user.id);
    const phone = normalizeEgyptPhone(dto.phone);
    if (!phone) throw new ApiError('INVALID_PHONE', 'رقم العميل غير صحيح.');
    const existing = await this.prisma.savedRecipient.findFirst({ where: { id, businessId: member.businessId } });
    if (!existing) throw new ApiError('NOT_FOUND', 'العميل غير موجود في دفتر هذا النشاط.', HttpStatus.NOT_FOUND);
    return this.prisma.savedRecipient.update({
      where: { id },
      data: { name: dto.name.trim(), phone, line: dto.line, details: dto.details, lat: dto.lat, lng: dto.lng, notes: dto.notes },
    });
  }

  @Delete('recipients/:id')
  async deleteRecipient(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    const member = await this.membership(user.id);
    const existing = await this.prisma.savedRecipient.findFirst({ where: { id, businessId: member.businessId } });
    if (!existing) throw new ApiError('NOT_FOUND', 'العميل غير موجود في دفتر هذا النشاط.', HttpStatus.NOT_FOUND);
    await this.prisma.savedRecipient.delete({ where: { id } });
    return { ok: true };
  }

  @Get('finance')
  async finance(@CurrentUser() user: AuthUser) {
    const member = await this.membership(user.id);
    const orders = await this.prisma.deliveryOrder.findMany({ where: { businessId: member.businessId } });
    const sum = (pick: (order: (typeof orders)[number]) => number) => orders.reduce((total, order) => total + pick(order), 0);
    const collectedStatuses = ['COLLECTED', 'PARTIAL', 'SETTLED', 'AWAITING_SETTLEMENT'];
    const goodsCollected = sum((order) => (collectedStatuses.includes(order.settlementStatus) && order.collectGoods ? order.goodsMinor : 0));
    const summary = {
      goodsCollectedMinor: goodsCollected,
      deliveryMinor: sum((order) => order.totalMinor),
      businessDueMinor: sum((order) => order.businessDueMinor),
      settledMinor: sum((order) => order.settledMinor),
      pendingMinor: sum((order) => Math.max(0, order.businessDueMinor + order.shopDeliveryChargeMinor - order.settledMinor)),
      disputedMinor: sum((order) => (order.settlementStatus === 'DISPUTED' ? order.businessDueMinor : 0)),
    };
    const ledger = await this.prisma.ledgerEntry.findMany({
      where: { businessId: member.businessId },
      orderBy: { createdAt: 'desc' },
      take: 50,
      include: { order: { select: { publicNumber: true, goodsMinor: true, totalMinor: true, collectMinor: true, businessDueMinor: true, settlementStatus: true, createdAt: true } } },
    });
    return {
      summary: Object.fromEntries(Object.entries(summary).map(([key, value]) => [key, value])) as typeof summary,
      labels: Object.fromEntries(Object.entries(summary).map(([key, value]) => [key.replace('Minor', 'Label'), minorToLabel(value)])),
      entries: ledger,
      note: 'التسوية هنا سجل محاسبي فقط. لا يوجد تحويل مالي تلقائي قبل اعتماد نظام الإدارة.',
    };
  }

  @Get('reports')
  async reports(@CurrentUser() user: AuthUser, @Query('from') from?: string, @Query('to') to?: string) {
    const member = await this.membership(user.id);
    const start = from ? new Date(from) : new Date(new Date().setHours(0, 0, 0, 0));
    const end = to ? new Date(to) : new Date();
    if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) {
      throw new ApiError('INVALID_FILTER', 'فترة التقرير غير صالحة.');
    }
    const orders = await this.prisma.deliveryOrder.findMany({
      where: { businessId: member.businessId, createdAt: { gte: start, lte: end } },
    });
    const count = (status?: string) => orders.filter((order) => (status ? order.status === status : true)).length;
    const sum = (pick: (order: (typeof orders)[number]) => number) => orders.reduce((total, order) => total + pick(order), 0);
    const active = orders.filter((order) => ['SEARCHING', 'ACCEPTED', 'EN_ROUTE_PICKUP', 'PICKED_UP', 'EN_ROUTE_DROPOFF'].includes(order.status)).length;
    return {
      from: start,
      to: end,
      orders: orders.length,
      completed: count('DELIVERED'),
      cancelled: orders.filter((order) => order.status === 'CANCELLED' || order.status === 'NO_COURIER').length,
      active,
      deliveryMinor: sum((order) => order.totalMinor),
      goodsCollectedMinor: sum((order) => (order.collectGoods && order.settlementStatus !== 'PENDING_COLLECTION' && order.settlementStatus !== 'NOT_REQUIRED' ? order.goodsMinor : 0)),
      businessDueMinor: sum((order) => order.businessDueMinor),
      settledMinor: sum((order) => order.settledMinor),
    };
  }

  @Post('recipients')
  async saveRecipient(@CurrentUser() user: AuthUser, @Body() dto: RecipientDto) {
    const member = await this.membership(user.id);
    const phone = normalizeEgyptPhone(dto.phone);
    if (!phone) throw new ApiError('INVALID_PHONE', 'رقم العميل غير صحيح.');
    return this.prisma.savedRecipient.create({
      data: {
        userId: user.id,
        businessId: member.businessId,
        name: dto.name.trim(),
        phone,
        line: dto.line,
        details: dto.details,
        lat: dto.lat,
        lng: dto.lng,
        notes: dto.notes,
        consentAt: new Date(),
      },
    });
  }

  private async membership(userId: string) {
    const member = await this.prisma.businessMember.findFirst({
      where: { userId },
      include: { business: true },
    });
    if (!member) throw new ApiError('NOT_FOUND', 'لا يوجد نشاط تجاري مرتبط بهذا الحساب.', HttpStatus.NOT_FOUND);
    return member;
  }

  private async ensureCovered(lat: number, lng: number) {
    if (lat === 0 && lng === 0) return;
    if (!inEgypt({ lat, lng })) {
      throw new ApiError('OUT_OF_SERVICE_AREA', 'موقع النشاط يجب أن يكون داخل مصر.');
    }
  }
}
