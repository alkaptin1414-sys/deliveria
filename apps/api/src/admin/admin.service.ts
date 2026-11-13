import { HttpStatus, Inject, Injectable } from '@nestjs/common';
import { TicketStatus } from '@prisma/client';
import { ApiError } from '../common/api-error';
import { buildEarningsReport, dayStart } from '../domain/courier';
import { minorToLabel } from '../domain/money';
import { OrdersService } from '../orders/orders.service';
import { PrismaService } from '../prisma/prisma.service';

const ACTIVE_ORDERS = ['SEARCHING', 'ACCEPTED', 'EN_ROUTE_PICKUP', 'PICKED_UP', 'EN_ROUTE_DROPOFF'];

@Injectable()
export class AdminService {
  constructor(
    @Inject(PrismaService) private readonly prisma: PrismaService,
    @Inject(OrdersService) private readonly deliveries: OrdersService,
  ) {}

  async dashboard() {
    const today = dayStart(new Date());
    const [customers, courierCount, restaurants, pendingCouriers, approvedCouriers, suspendedCouriers, availableCouriers, orders, audits, earnings, wagePaid, cashRemitted] = await Promise.all([
      this.prisma.user.count({ where: { role: 'CUSTOMER' } }),
      this.prisma.courierProfile.count(),
      this.prisma.restaurant.count(),
      this.prisma.courierProfile.count({ where: { status: 'PENDING_REVIEW' } }),
      this.prisma.courierProfile.count({ where: { status: 'APPROVED' } }),
      this.prisma.courierProfile.count({ where: { status: 'SUSPENDED' } }),
      this.prisma.courierProfile.count({ where: { status: 'APPROVED', available: true } }),
      this.prisma.deliveryOrder.findMany({
        where: { createdAt: { gte: today } },
        select: { status: true, totalMinor: true, feeMinor: true, platformMinor: true, serviceFeeMinor: true },
      }),
      this.prisma.adminAudit.findMany({ orderBy: { createdAt: 'desc' }, take: 12 }),
      this.prisma.courierEarning.aggregate({ _sum: { payoutMinor: true, cashCollectedMinor: true } }),
      this.prisma.courierSettlement.aggregate({ where: { kind: 'WAGE_PAID' }, _sum: { amountMinor: true } }),
      this.prisma.courierSettlement.aggregate({ where: { kind: 'CASH_REMITTED' }, _sum: { amountMinor: true } }),
    ]);
    const countStatus = (names: string[]) => orders.filter((order) => names.includes(order.status)).length;
    const orderValue = orders.filter((order) => order.status !== 'CANCELLED').reduce((sum, order) => sum + order.totalMinor, 0);
    const deliveryFees = orders.filter((order) => order.status !== 'CANCELLED').reduce((sum, order) => sum + order.feeMinor, 0);
    const platformRevenue = orders.filter((order) => order.status === 'DELIVERED').reduce((sum, order) => sum + order.platformMinor + order.serviceFeeMinor, 0);
    const owedWages = (earnings._sum.payoutMinor ?? 0) - (wagePaid._sum.amountMinor ?? 0);
    const owedCash = (earnings._sum.cashCollectedMinor ?? 0) - (cashRemitted._sum.amountMinor ?? 0);
    return {
      customers,
      couriers: courierCount,
      restaurants,
      pendingCouriers,
      approvedCouriers,
      suspendedCouriers,
      availableCouriers,
      ordersToday: {
        new: countStatus(['SEARCHING']),
        active: countStatus(ACTIVE_ORDERS),
        delivered: countStatus(['DELIVERED']),
        cancelled: countStatus(['CANCELLED']),
        orderValueMinor: orderValue,
        orderValueLabel: minorToLabel(orderValue),
        deliveryFeesMinor: deliveryFees,
        deliveryFeesLabel: minorToLabel(deliveryFees),
        platformRevenueMinor: platformRevenue,
        platformRevenueLabel: minorToLabel(platformRevenue),
      },
      finance: {
        unsettledWagesMinor: owedWages,
        unsettledWagesLabel: minorToLabel(owedWages),
        unsettledCashMinor: owedCash,
        unsettledCashLabel: minorToLabel(owedCash),
      },
      attention: pendingCouriers,
      audits: audits.map((row) => ({ id: row.id, action: row.action, targetType: row.targetType, targetId: row.targetId, reason: row.reason, createdAt: row.createdAt })),
    };
  }

  async couriers(q?: string) {
    const rows = await this.prisma.courierProfile.findMany({
      where: q
        ? {
            OR: [
              { fullName: { contains: q, mode: 'insensitive' } },
              { user: { phone: { contains: q } } },
              { user: { email: { contains: q, mode: 'insensitive' } } },
            ],
          }
        : undefined,
      include: { user: { select: { phone: true, email: true, suspendedAt: true } }, earnings: true },
      orderBy: { createdAt: 'desc' },
      take: 50,
    });
    return Promise.all(rows.map(async (row) => {
      const [completed, cancelled, rating] = await Promise.all([
        this.prisma.deliveryOrder.count({ where: { courierId: row.userId, status: 'DELIVERED' } }),
        this.prisma.deliveryOrder.count({ where: { courierId: row.userId, status: 'CANCELLED' } }),
        this.prisma.review.aggregate({ where: { courierId: row.userId, status: 'PUBLISHED' }, _avg: { rating: true }, _count: true }),
      ]);
      const busy = await this.prisma.deliveryOrder.findFirst({ where: { courierId: row.userId, status: { in: ACTIVE_ORDERS as never } } });
      const presence = row.user.suspendedAt || row.status === 'SUSPENDED' ? 'موقوف' : busy ? 'مشغول' : row.available ? 'متاح' : 'غير متصل';
      return {
        id: row.id,
        userId: row.userId,
        fullName: row.fullName,
        phone: row.user.phone,
        email: row.user.email,
        governorate: row.governorate,
        area: row.area,
        vehicle: row.vehicle,
        status: row.status,
        reviewNote: row.reviewNote,
        presence,
        completed,
        cancelled,
        rating: rating._avg.rating ? Math.round(rating._avg.rating * 10) / 10 : null,
        ratingCount: rating._count,
        payoutMinor: row.earnings.reduce((sum, item) => sum + item.payoutMinor, 0),
        payoutLabel: minorToLabel(row.earnings.reduce((sum, item) => sum + item.payoutMinor, 0)),
      };
    }));
  }

  async courier(id: string) {
    const row = await this.prisma.courierProfile.findUnique({
      where: { id },
      include: {
        user: { select: { phone: true, email: true, suspendedAt: true } },
        documents: true,
        earnings: { orderBy: { createdAt: 'desc' }, take: 20 },
        settlements: { orderBy: { createdAt: 'desc' }, take: 20 },
      },
    });
    if (!row) throw new ApiError('NOT_FOUND', 'المندوب غير موجود.', HttpStatus.NOT_FOUND);
    const [orders, reviews, audits, completed] = await Promise.all([
      this.prisma.deliveryOrder.findMany({
        where: { courierId: row.userId },
        orderBy: { createdAt: 'desc' },
        take: 20,
        select: { publicNumber: true, status: true, parcelType: true, feeMinor: true, platformMinor: true, pickupLine: true, dropoffLine: true, createdAt: true },
      }),
      this.prisma.review.findMany({
        where: { courierId: row.userId, status: 'PUBLISHED' },
        orderBy: { createdAt: 'desc' },
        take: 20,
        select: { rating: true, comment: true, createdAt: true },
      }),
      this.prisma.adminAudit.findMany({ where: { targetType: 'COURIER', targetId: id }, orderBy: { createdAt: 'desc' }, take: 20 }),
      this.prisma.deliveryOrder.count({ where: { courierId: row.userId, status: 'DELIVERED' } }),
    ]);
    const payout = row.earnings.reduce((sum, item) => sum + item.payoutMinor, 0);
    return {
      id: row.id,
      fullName: row.fullName,
      phone: row.user.phone,
      email: row.user.email,
      governorate: row.governorate,
      area: row.area,
      vehicle: row.vehicle,
      status: row.status,
      reviewNote: row.reviewNote,
      available: row.available,
      completed,
      payoutLabel: minorToLabel(payout),
      documents: row.documents.map((doc) => ({ kind: doc.kind, createdAt: doc.createdAt })),
      orders: orders.map((order) => ({
        publicNumber: order.publicNumber,
        status: order.status,
        parcelType: order.parcelType,
        pickupLine: order.pickupLine,
        dropoffLine: order.dropoffLine,
        feeLabel: minorToLabel(order.feeMinor),
        platformLabel: minorToLabel(order.platformMinor),
        createdAt: order.createdAt,
      })),
      reviews: reviews.map((review) => ({ rating: review.rating, comment: review.comment, createdAt: review.createdAt })),
      settlements: row.settlements.map((item) => ({
        kind: item.kind,
        amountLabel: minorToLabel(item.amountMinor),
        reason: item.reason,
        createdAt: item.createdAt,
      })),
      audits: audits.map((item) => ({ action: item.action, reason: item.reason, createdAt: item.createdAt })),
    };
  }

  async customers(q?: string) {
    return this.prisma.user.findMany({
      where: {
        role: 'CUSTOMER',
        ...(q
          ? {
              OR: [
                { name: { contains: q, mode: 'insensitive' } },
                { phone: { contains: q } },
                { email: { contains: q, mode: 'insensitive' } },
              ],
            }
          : {}),
      },
      select: { id: true, name: true, phone: true, email: true, suspendedAt: true, createdAt: true, _count: { select: { orders: true, tickets: true } } },
      orderBy: { createdAt: 'desc' },
      take: 50,
    });
  }

  async setSuspension(actorId: string, userId: string, suspended: boolean, reason: string) {
    if (reason.trim().length < 8 || !/[\u0600-\u06FF]/.test(reason)) {
      throw new ApiError('NOTE_REQUIRED', 'اكتب سبب الحظر أو فك الحظر بوضوح بالعربية.');
    }
    const user = await this.prisma.user.findUnique({ where: { id: userId }, include: { courierProfile: true } });
    if (!user || user.role === 'ADMIN') throw new ApiError('FORBIDDEN', 'لا يمكن إيقاف حساب الإدارة.', HttpStatus.FORBIDDEN);
    const active = user.role === 'COURIER'
      ? await this.prisma.deliveryOrder.findFirst({
          where: { courierId: userId, status: { in: ['ACCEPTED', 'EN_ROUTE_PICKUP', 'PICKED_UP', 'EN_ROUTE_DROPOFF'] } },
          select: { id: true, publicNumber: true, status: true },
        })
      : null;
    await this.prisma.$transaction(async (tx) => {
      await tx.user.update({ where: { id: userId }, data: { suspendedAt: suspended ? new Date() : null } });
      if (suspended) {
        await tx.refreshSession.updateMany({ where: { userId, revokedAt: null }, data: { revokedAt: new Date() } });
      }
      if (user.courierProfile) {
        await tx.courierProfile.update({
          where: { userId },
          data: {
            available: false,
            status: suspended ? 'SUSPENDED' : user.courierProfile.status === 'SUSPENDED' ? 'APPROVED' : user.courierProfile.status,
          },
        });
      }
      await tx.adminAudit.create({
        data: { actorId, action: suspended ? 'SUSPEND_USER' : 'RESTORE_USER', targetType: 'USER', targetId: userId, reason: reason.trim() },
      });
    });
    return {
      ok: true,
      suspended,
      activeOrder: active,
      warning: active ? `المندوب لديه طلب نشط ${active.publicNumber}. لم يُلغَ الطلب. أوقِف الحساب فقط، وعالج الطلب من شاشة الطلبات.` : null,
    };
  }

  async restaurants() {
    const rows = await this.prisma.restaurant.findMany({
      orderBy: { name: 'asc' },
      include: { _count: { select: { orders: true, items: true, reviews: true } } },
    });
    return rows.map((row) => ({
      id: row.id,
      name: row.name,
      phone: row.phone,
      shift: row.shift,
      active: row.active,
      opensAt: row.opensAt,
      closesAt: row.closesAt,
      minOrderMinor: row.minOrderMinor,
      deliveryFeeMinor: row.deliveryFeeMinor,
      orders: row._count.orders,
      items: row._count.items,
      reviews: row._count.reviews,
    }));
  }

  async restaurant(id: string) {
    const row = await this.prisma.restaurant.findUnique({
      where: { id },
      include: { sections: { orderBy: { sort: 'asc' }, include: { items: { orderBy: { sort: 'asc' } } } } },
    });
    if (!row) throw new ApiError('NOT_FOUND', 'المطعم غير موجود.', HttpStatus.NOT_FOUND);
    return {
      id: row.id,
      name: row.name,
      phone: row.phone,
      active: row.active,
      shift: row.shift,
      opensAt: row.opensAt,
      closesAt: row.closesAt,
      minOrderMinor: row.minOrderMinor,
      deliveryFeeMinor: row.deliveryFeeMinor,
      sections: row.sections.map((section) => ({
        id: section.id,
        name: section.name,
        items: section.items.map((item) => ({ id: item.id, name: item.name, priceMinor: item.priceMinor, available: item.available })),
      })),
    };
  }

  async updateRestaurant(actorId: string, id: string, input: { active?: boolean; shift?: 'OPEN' | 'CLOSED' | 'SCHEDULED'; minOrderMinor?: number; deliveryFeeMinor?: number; opensAt?: string; closesAt?: string }, reason: string) {
    if (!reason.trim()) throw new ApiError('NOTE_REQUIRED', 'سبب التعديل مطلوب.');
    const saved = await this.prisma.restaurant.update({ where: { id }, data: input });
    await this.audit(actorId, 'UPDATE_RESTAURANT', 'RESTAURANT', id, reason);
    return { id: saved.id, active: saved.active, shift: saved.shift };
  }

  async updateMenuItem(actorId: string, id: string, input: { priceMinor?: number; available?: boolean }, reason: string) {
    if (!reason.trim()) throw new ApiError('NOTE_REQUIRED', 'سبب التعديل مطلوب.');
    if (input.priceMinor != null && (!Number.isInteger(input.priceMinor) || input.priceMinor < 0)) {
      throw new ApiError('INVALID_AMOUNT', 'السعر غير صالح.');
    }
    const saved = await this.prisma.menuItem.update({ where: { id }, data: input });
    await this.audit(actorId, 'UPDATE_MENU_ITEM', 'MENU_ITEM', id, reason);
    return { id: saved.id, priceMinor: saved.priceMinor, available: saved.available };
  }

  async orders(status?: string) {
    return this.prisma.deliveryOrder.findMany({
      where: status ? { status: status as never } : undefined,
      orderBy: { createdAt: 'desc' },
      take: 40,
      select: {
        id: true,
        publicNumber: true,
        status: true,
        parcelType: true,
        totalMinor: true,
        feeMinor: true,
        platformMinor: true,
        paymentMethod: true,
        paymentState: true,
        courierName: true,
        pickupLine: true,
        dropoffLine: true,
        createdAt: true,
        user: { select: { name: true } },
      },
    });
  }

  async order(id: string) {
    const order = await this.prisma.deliveryOrder.findUnique({
      where: { id },
      include: { history: { orderBy: { createdAt: 'asc' } }, user: { select: { name: true, phone: true } }, foodOrder: { select: { restaurant: { select: { name: true } } } } },
    });
    if (!order) throw new ApiError('NOT_FOUND', 'الطلب غير موجود.', HttpStatus.NOT_FOUND);
    return {
      id: order.id,
      publicNumber: order.publicNumber,
      status: order.status,
      parcelType: order.parcelType,
      customer: order.user.name,
      phone: order.user.phone,
      restaurant: order.foodOrder?.restaurant.name ?? null,
      courier: order.courierName,
      pickupLine: order.pickupLine,
      dropoffLine: order.dropoffLine,
      totalMinor: order.totalMinor,
      totalLabel: minorToLabel(order.totalMinor),
      feeMinor: order.feeMinor,
      feeLabel: minorToLabel(order.feeMinor),
      platformMinor: order.platformMinor,
      platformLabel: minorToLabel(order.platformMinor),
      paymentMethod: order.paymentMethod,
      paymentState: order.paymentState,
      history: order.history,
    };
  }

  async cancelOrder(actorId: string, id: string, reason: string) {
    if (!reason.trim()) throw new ApiError('NOTE_REQUIRED', 'سبب الإلغاء مطلوب.');
    const order = await this.prisma.deliveryOrder.findUnique({ where: { id } });
    if (!order) throw new ApiError('NOT_FOUND', 'الطلب غير موجود.', HttpStatus.NOT_FOUND);
    if (!['SEARCHING', 'NO_COURIER', 'ACCEPTED', 'EN_ROUTE_PICKUP'].includes(order.status)) {
      throw new ApiError('CANCEL_NOT_ALLOWED', 'لا يمكن إلغاء الطلب بعد الاستلام.');
    }
    await this.prisma.deliveryOrder.update({
      where: { id },
      data: {
        status: 'CANCELLED',
        cancelledAt: new Date(),
        cancelReason: reason.trim(),
        cancelCode: 'OTHER',
        history: { create: { status: 'CANCELLED', actor: 'SUPPORT', note: reason.trim() } },
      },
    });
    await this.audit(actorId, 'CANCEL_ORDER', 'ORDER', id, reason);
    await this.deliveries.publishCancellation(id);
    return { ok: true };
  }

  async finance() {
    const config = await this.prisma.platformConfig.findUnique({ where: { id: 1 } });
    const [earnings, settlements, platform] = await Promise.all([
      this.prisma.courierEarning.aggregate({ _sum: { payoutMinor: true, cashCollectedMinor: true, customerFeeMinor: true, goodsMinor: true } }),
      this.prisma.courierSettlement.findMany({ orderBy: { createdAt: 'desc' }, take: 30, include: { profile: { select: { fullName: true } } } }),
      this.prisma.deliveryOrder.aggregate({ where: { status: 'DELIVERED' }, _sum: { platformMinor: true, serviceFeeMinor: true, feeMinor: true, totalMinor: true } }),
    ]);
    return {
      orderValueMinor: platform._sum.totalMinor ?? 0,
      orderValueLabel: minorToLabel(platform._sum.totalMinor ?? 0),
      deliveryFeesMinor: platform._sum.feeMinor ?? 0,
      deliveryFeesLabel: minorToLabel(platform._sum.feeMinor ?? 0),
      platformRevenueMinor: (platform._sum.platformMinor ?? 0) + (platform._sum.serviceFeeMinor ?? 0),
      platformRevenueLabel: minorToLabel((platform._sum.platformMinor ?? 0) + (platform._sum.serviceFeeMinor ?? 0)),
      courierWagesMinor: earnings._sum.payoutMinor ?? 0,
      courierWagesLabel: minorToLabel(earnings._sum.payoutMinor ?? 0),
      cashCollectedMinor: earnings._sum.cashCollectedMinor ?? 0,
      cashCollectedLabel: minorToLabel(earnings._sum.cashCollectedMinor ?? 0),
      goodsMinor: earnings._sum.goodsMinor ?? 0,
      goodsLabel: minorToLabel(earnings._sum.goodsMinor ?? 0),
      commissionBps: config?.deliveryPlatformBps ?? 0,
      serviceFeeMinor: config?.serviceFeeMinor ?? 0,
      settlements: settlements.map((row) => ({
        id: row.id,
        courier: row.profile.fullName,
        kind: row.kind,
        amountMinor: row.amountMinor,
        amountLabel: minorToLabel(row.amountMinor),
        reason: row.reason,
        createdAt: row.createdAt,
      })),
    };
  }

  async setPricing(actorId: string, deliveryPlatformBps: number, serviceFeeMinor: number, reason: string) {
    if (!reason.trim()) throw new ApiError('NOTE_REQUIRED', 'سبب تعديل التسعير مطلوب.');
    if (!Number.isInteger(deliveryPlatformBps) || deliveryPlatformBps < 0 || deliveryPlatformBps > 10000) {
      throw new ApiError('INVALID_AMOUNT', 'نسبة العمولة يجب أن تكون بين 0 و 10000 نقطة أساس.');
    }
    if (!Number.isInteger(serviceFeeMinor) || serviceFeeMinor < 0) throw new ApiError('INVALID_AMOUNT', 'رسم الخدمة غير صالح.');
    const previous = await this.prisma.platformConfig.findUnique({ where: { id: 1 } });
    const saved = await this.prisma.platformConfig.upsert({
      where: { id: 1 },
      update: { deliveryPlatformBps, serviceFeeMinor },
      create: { id: 1, deliveryPlatformBps, serviceFeeMinor },
    });
    await this.audit(actorId, 'UPDATE_PRICING', 'PLATFORM', '1', `من ${previous?.deliveryPlatformBps ?? 0} إلى ${deliveryPlatformBps} نقطة أساس. ${reason.trim()}`);
    return saved;
  }

  async areas() {
    return this.prisma.serviceArea.findMany({ orderBy: { name: 'asc' } });
  }

  async setArea(actorId: string, id: string, active: boolean, reason: string) {
    if (!reason.trim()) throw new ApiError('NOTE_REQUIRED', 'سبب تغيير المنطقة مطلوب.');
    const saved = await this.prisma.serviceArea.update({ where: { id }, data: { active } });
    await this.audit(actorId, active ? 'ENABLE_AREA' : 'DISABLE_AREA', 'AREA', id, reason);
    return saved;
  }

  async tickets(query: { status?: string; kind?: string; q?: string; from?: string; to?: string; take?: number; skip?: number }) {
    const take = Math.min(Math.max(query.take ?? 30, 1), 100);
    const skip = Math.max(query.skip ?? 0, 0);
    const q = query.q?.trim();
    const from = query.from ? new Date(query.from) : null;
    const to = query.to ? new Date(query.to) : null;
    const where = {
      ...(query.status ? { status: query.status as TicketStatus } : {}),
      ...(query.kind ? { kind: query.kind as never } : {}),
      ...((from && !Number.isNaN(from.getTime())) || (to && !Number.isNaN(to.getTime()))
        ? { createdAt: { ...(from && !Number.isNaN(from.getTime()) ? { gte: from } : {}), ...(to && !Number.isNaN(to.getTime()) ? { lte: to } : {}) } }
        : {}),
      ...(q
        ? {
            OR: [
              { publicNumber: { contains: q, mode: 'insensitive' as const } },
              { subject: { contains: q, mode: 'insensitive' as const } },
              { user: { name: { contains: q, mode: 'insensitive' as const } } },
              { user: { phone: { contains: q } } },
              { user: { email: { contains: q, mode: 'insensitive' as const } } },
            ],
          }
        : {}),
    };
    const [rows, unread] = await Promise.all([
      this.prisma.supportTicket.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        take,
        skip,
        include: {
          user: { select: { name: true, phone: true, email: true, role: true } },
          messages: { orderBy: { createdAt: 'asc' } },
        },
      }),
      this.prisma.supportTicket.count({ where: { adminReadAt: null, status: { in: ['OPEN', 'IN_REVIEW'] } } }),
    ]);
    const orderIds = rows.map((row) => row.orderId).filter((id): id is string => Boolean(id));
    const orders = orderIds.length
      ? await this.prisma.deliveryOrder.findMany({ where: { id: { in: orderIds } }, select: { id: true, publicNumber: true } })
      : [];
    const numbers = new Map(orders.map((order) => [order.id, order.publicNumber]));
    return {
      unread,
      items: rows.map((row) => ({
        id: row.id,
        publicNumber: row.publicNumber,
        name: row.user.name,
        phone: row.user.phone,
        email: row.user.email,
        role: row.user.role,
        orderId: row.orderId,
        orderNumber: row.orderId ? numbers.get(row.orderId) ?? null : null,
        kind: row.kind,
        subject: row.subject,
        message: row.message,
        status: row.status,
        createdAt: row.createdAt,
        unread: row.adminReadAt == null,
        messages: row.messages.map((item) => ({ body: item.body, sender: item.sender, internal: item.internal, createdAt: item.createdAt })),
      })),
    };
  }

  async setTicket(actorId: string, id: string, status: TicketStatus, note: string, internal = false) {
    if (!note.trim()) throw new ApiError('NOTE_REQUIRED', 'ملاحظة الشكوى مطلوبة.');
    const ticket = await this.prisma.supportTicket.findUnique({ where: { id } });
    if (!ticket) throw new ApiError('NOT_FOUND', 'البلاغ غير موجود.', HttpStatus.NOT_FOUND);
    const saved = await this.prisma.supportTicket.update({
      where: { id },
      data: {
        status,
        adminReadAt: new Date(),
        messages: { create: { sender: 'SUPPORT', senderId: actorId, body: note.trim(), internal } },
      },
    });
    if (!internal) {
      await this.prisma.notification.create({
        data: { userId: ticket.userId, type: 'TICKET_UPDATED', title: 'رد على البلاغ', body: note.trim() },
      });
    }
    await this.audit(actorId, 'UPDATE_TICKET', 'TICKET', id, note);
    return { id: saved.id, status: saved.status };
  }

  async reviews() {
    const [couriers, restaurants] = await Promise.all([
      this.prisma.review.findMany({ orderBy: { createdAt: 'desc' }, take: 30, include: { reports: true } }),
      this.prisma.restaurantReview.findMany({ orderBy: { createdAt: 'desc' }, take: 30 }),
    ]);
    return { couriers, restaurants };
  }

  async notifyUser(actorId: string, userId: string, title: string, body: string) {
    if (!title.trim() || !body.trim()) throw new ApiError('NOTE_REQUIRED', 'عنوان الإشعار ونصه مطلوبان.');
    const saved = await this.prisma.notification.create({
      data: { userId, type: 'TICKET_UPDATED', title: title.trim(), body: body.trim() },
    });
    await this.audit(actorId, 'NOTIFY_USER', 'USER', userId, title.trim());
    return { id: saved.id, stored: true, pushed: false, note: 'الإشعار محفوظ داخل التطبيق. الإرسال عبر Firebase غير مفعّل.' };
  }

  async users(query: { role?: string; status?: string; q?: string; from?: string; to?: string; take?: number; skip?: number }) {
    const take = Math.min(Math.max(query.take ?? 30, 1), 100);
    const skip = Math.max(query.skip ?? 0, 0);
    const role = query.role === 'COURIER' || query.role === 'CUSTOMER' ? query.role : undefined;
    const q = query.q?.trim();
    const from = query.from ? new Date(query.from) : null;
    const to = query.to ? new Date(query.to) : null;
    const rows = await this.prisma.user.findMany({
      where: {
        role: role ?? { in: ['CUSTOMER', 'COURIER'] },
        ...(query.status === 'SUSPENDED' ? { suspendedAt: { not: null } } : {}),
        ...(query.status === 'ACTIVE' ? { suspendedAt: null } : {}),
        ...(query.status && ['PENDING_REVIEW', 'NEEDS_INFO', 'REJECTED', 'APPROVED'].includes(query.status)
          ? { courierProfile: { status: query.status as 'PENDING_REVIEW' | 'NEEDS_INFO' | 'REJECTED' | 'APPROVED' } }
          : {}),
        ...((from && !Number.isNaN(from.getTime())) || (to && !Number.isNaN(to.getTime()))
          ? {
              createdAt: {
                ...(from && !Number.isNaN(from.getTime()) ? { gte: from } : {}),
                ...(to && !Number.isNaN(to.getTime()) ? { lte: to } : {}),
              },
            }
          : {}),
        ...(q
          ? {
              OR: [
                { name: { contains: q, mode: 'insensitive' } },
                { phone: { contains: q } },
                { email: { contains: q, mode: 'insensitive' } },
              ],
            }
          : {}),
      },
      include: { courierProfile: { include: { earnings: true } }, _count: { select: { orders: true } } },
      orderBy: { createdAt: 'desc' },
      take,
      skip,
    });
    const courierIds = rows.filter((row) => row.role === 'COURIER').map((row) => row.id);
    const [assigned, ratings, bans] = await Promise.all([
      courierIds.length
        ? this.prisma.deliveryOrder.groupBy({ by: ['courierId'], where: { courierId: { in: courierIds } }, _count: { _all: true } })
        : [],
      courierIds.length
        ? this.prisma.review.groupBy({ by: ['courierId'], where: { courierId: { in: courierIds }, status: 'PUBLISHED' }, _avg: { rating: true }, _count: { _all: true } })
        : [],
      this.prisma.adminAudit.findMany({
        where: { targetId: { in: rows.map((row) => row.id) }, action: { in: ['SUSPEND_USER', 'RESTORE_USER'] } },
        orderBy: { createdAt: 'desc' },
        take: 200,
      }),
    ]);
    const assignedCount = new Map(assigned.map((row) => [row.courierId, row._count._all]));
    const ratingByCourier = new Map(ratings.map((row) => [row.courierId, { average: row._avg.rating, count: row._count._all }]));
    return rows.map((row) => ({
      id: row.id,
      profileId: row.courierProfile?.id ?? null,
      name: row.name,
      phone: row.phone,
      email: row.email,
      role: row.role,
      accountType: row.accountType,
      createdAt: row.createdAt,
      suspendedAt: row.suspendedAt,
      status: row.suspendedAt ? 'SUSPENDED' : row.courierProfile?.status ?? 'ACTIVE',
      orders: row.role === 'COURIER' ? assignedCount.get(row.id) ?? 0 : row._count.orders,
      rating: ratingByCourier.get(row.id)?.average ?? null,
      ratingCount: ratingByCourier.get(row.id)?.count ?? 0,
      payoutMinor: row.courierProfile?.earnings.reduce((sum, item) => sum + item.payoutMinor, 0) ?? null,
      payoutLabel: row.courierProfile ? minorToLabel(row.courierProfile.earnings.reduce((sum, item) => sum + item.payoutMinor, 0)) : null,
      commissionBps: row.courierProfile?.commissionBps ?? null,
      banHistory: bans.filter((item) => item.targetId === row.id).slice(0, 8).map((item) => ({ action: item.action, reason: item.reason, createdAt: item.createdAt, actorId: item.actorId })),
    }));
  }

  async earnings(take = 30, skip = 0) {
    const profiles = await this.prisma.courierProfile.findMany({
      orderBy: { fullName: 'asc' },
      take: Math.min(Math.max(take, 1), 100),
      skip: Math.max(skip, 0),
      include: {
        user: { select: { phone: true } },
        earnings: { include: { order: { select: { status: true, feeMinor: true, platformMinor: true, deliveredAt: true } } } },
        settlements: true,
      },
    });
    return profiles.map((profile) => this.earningRow(profile));
  }

  async earningDetail(profileId: string) {
    const profile = await this.prisma.courierProfile.findUnique({
      where: { id: profileId },
      include: {
        user: { select: { phone: true, email: true } },
        earnings: { include: { order: { select: { status: true, publicNumber: true, feeMinor: true, platformMinor: true, deliveredAt: true } } } },
        settlements: { orderBy: { createdAt: 'desc' } },
      },
    });
    if (!profile) throw new ApiError('NOT_FOUND', 'المندوب غير موجود.', HttpStatus.NOT_FOUND);
    const report = buildEarningsReport(
      new Date(),
      profile.earnings.map((row) => ({
        orderId: row.orderId,
        status: row.order.status,
        publicNumber: row.order.publicNumber,
        payoutMinor: row.payoutMinor,
        feeMinor: row.order.feeMinor,
        platformMinor: row.order.platformMinor,
        cashCollectedMinor: row.cashCollectedMinor,
        createdAt: row.createdAt,
        deliveredAt: row.order.deliveredAt,
      })),
      profile.settlements.map((item) => ({ id: item.id, kind: item.kind, amountMinor: item.amountMinor, reason: item.reason, createdAt: item.createdAt })),
    );
    return {
      name: profile.fullName,
      phone: profile.user.phone,
      email: profile.user.email,
      commissionBps: profile.commissionBps,
      todayLabel: minorToLabel(report.todayMinor),
      weekLabel: minorToLabel(report.weekMinor),
      monthLabel: minorToLabel(report.monthMinor),
      totalLabel: minorToLabel(report.totalMinor),
      unsettledLabel: minorToLabel(report.unsettledWageMinor),
      paidLabel: minorToLabel(report.paidWageMinor),
      orders: report.orders.map((row) => ({ ...row, feeLabel: minorToLabel(row.feeMinor), platformLabel: minorToLabel(row.platformMinor), payoutLabel: minorToLabel(row.payoutMinor) })),
      settlements: report.settlements.map((item) => ({ ...item, amountLabel: minorToLabel(item.amountMinor) })),
    };
  }

  async setCourierCommission(actorId: string, profileId: string, bps: number | null, reason: string) {
    if (reason.trim().length < 8) throw new ApiError('NOTE_REQUIRED', 'سبب تعديل النسبة مطلوب.');
    if (bps != null && (!Number.isInteger(bps) || bps < 0 || bps > 10000)) {
      throw new ApiError('INVALID_AMOUNT', 'النسبة يجب أن تكون بين 0% و 100%.');
    }
    const profile = await this.prisma.courierProfile.findUnique({ where: { id: profileId } });
    if (!profile) throw new ApiError('NOT_FOUND', 'المندوب غير موجود.', HttpStatus.NOT_FOUND);
    const saved = await this.prisma.courierProfile.update({ where: { id: profileId }, data: { commissionBps: bps } });
    await this.audit(actorId, 'SET_COURIER_COMMISSION', 'COURIER', profileId, `من ${profile.commissionBps ?? 'العامة'} إلى ${bps ?? 'العامة'}. ${reason.trim()}`);
    return { commissionBps: saved.commissionBps };
  }

  async audits(take = 40, skip = 0) {
    const rows = await this.prisma.adminAudit.findMany({
      orderBy: { createdAt: 'desc' },
      take: Math.min(Math.max(take, 1), 100),
      skip: Math.max(skip, 0),
    });
    const actors = await this.prisma.user.findMany({
      where: { id: { in: [...new Set(rows.map((row) => row.actorId))] } },
      select: { id: true, name: true, email: true },
    });
    const names = new Map(actors.map((actor) => [actor.id, actor.name || actor.email || 'مسؤول']));
    return rows.map((row) => ({ ...row, actorName: names.get(row.actorId) ?? 'مسؤول' }));
  }

  private earningRow(profile: {
    id: string;
    fullName: string;
    user: { phone: string | null };
    commissionBps: number | null;
    earnings: Array<{ orderId: string; payoutMinor: number; createdAt: Date; order: { status: string; feeMinor: number; platformMinor: number; deliveredAt: Date | null } }>;
    settlements: Array<{ kind: string; amountMinor: number; createdAt: Date }>;
  }) {
    const seen = new Set<string>();
    const rows = profile.earnings.filter((row) => {
      if (row.order.status !== 'DELIVERED' || seen.has(row.orderId)) return false;
      seen.add(row.orderId);
      return true;
    });
    const fee = rows.reduce((sum, row) => sum + row.order.feeMinor, 0);
    const platform = rows.reduce((sum, row) => sum + row.order.platformMinor, 0);
    const payout = rows.reduce((sum, row) => sum + row.payoutMinor, 0);
    const paid = profile.settlements.filter((item) => item.kind === 'WAGE_PAID').reduce((sum, item) => sum + item.amountMinor, 0);
    const adjustments = profile.settlements.filter((item) => item.kind === 'ADJUSTMENT').reduce((sum, item) => sum + item.amountMinor, 0);
    const dates = [...rows.map((row) => row.createdAt), ...profile.settlements.map((item) => item.createdAt)];
    return {
      id: profile.id,
      name: profile.fullName,
      phone: profile.user.phone,
      completed: rows.length,
      feeLabel: minorToLabel(fee),
      platformLabel: minorToLabel(platform),
      payoutLabel: minorToLabel(payout),
      unsettledLabel: minorToLabel(payout + adjustments - paid),
      paidLabel: minorToLabel(paid),
      commissionBps: profile.commissionBps,
      lastActivity: dates.sort((a, b) => b.getTime() - a.getTime())[0] ?? null,
    };
  }

  async audit(actorId: string, action: string, targetType: string, targetId: string | null, reason: string) {
    await this.prisma.adminAudit.create({ data: { actorId, action, targetType, targetId, reason: reason.trim() } });
  }
}
