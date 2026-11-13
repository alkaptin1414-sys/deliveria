import { HttpStatus, Inject, Injectable } from '@nestjs/common';
import { CourierAccountStatus, CourierDocKind, CourierSettlementKind, CourierVehicleKind } from '@prisma/client';
import { createReadStream, existsSync } from 'fs';
import { join } from 'path';
import { AuthService } from '../auth/auth.service';
import { ApiError } from '../common/api-error';
import {
  GOVERNORATES,
  buildEarningsReport,
  courierCanTake,
  courierOrderContact,
  requiredDocs,
  withinMatch,
} from '../domain/courier';
import { haversineMeters } from '../domain/geo';
import { minorToLabel } from '../domain/money';
import { normalizeEgyptPhone } from '../domain/phone';
import { OrdersService } from '../orders/orders.service';
import { PrismaService } from '../prisma/prisma.service';
import { RealtimeService } from '../realtime/realtime.service';

const ACTIVE = ['ACCEPTED', 'EN_ROUTE_PICKUP', 'PICKED_UP', 'EN_ROUTE_DROPOFF'] as const;

@Injectable()
export class CourierService {
  constructor(
    @Inject(PrismaService) private readonly prisma: PrismaService,
    @Inject(OrdersService) private readonly orders: OrdersService,
    @Inject(AuthService) private readonly auth: AuthService,
    @Inject(RealtimeService) private readonly realtime: RealtimeService,
  ) {}

  async me(userId: string) {
    const profile = await this.profile(userId);
    const [completed, earnings, rating] = await Promise.all([
      this.prisma.deliveryOrder.count({ where: { courierId: userId, status: 'DELIVERED' } }),
      this.earnings(userId),
      this.orders.courierRatings(userId, userId),
    ]);
    const active = await this.prisma.deliveryOrder.findFirst({
      where: { courierId: userId, status: { in: [...ACTIVE] } },
      include: { assignment: true, foodOrder: { include: { restaurant: { select: { name: true } } } } },
    });
    return {
      profile: this.presentProfile(profile),
      completed,
      rating: { count: rating.count, display: rating.display, label: rating.label },
      earnings: {
        totalMinor: earnings.totalMinor,
        totalLabel: earnings.totalLabel,
        todayMinor: earnings.todayMinor,
        todayLabel: earnings.todayLabel,
        todayOrders: earnings.periods.today.orderCount,
      },
      active: active ? this.presentJob(active) : null,
      documents: profile.documents.map((doc) => ({ id: doc.id, kind: doc.kind, createdAt: doc.createdAt })),
    };
  }

  async apply(
    userId: string,
    input: {
      fullName: string;
      email?: string;
      governorate: string;
      area: string;
      vehicle: CourierVehicleKind;
      vehicleDetails?: string;
      plate?: string;
      termsAccepted: boolean;
      phone?: string;
    },
  ) {
    if (!input.termsAccepted) throw new ApiError('TERMS_REQUIRED', 'الموافقة على شروط العمل وسياسة الخصوصية مطلوبة.');
    if (!GOVERNORATES.includes(input.governorate)) throw new ApiError('INVALID_AREA', 'اختَر محافظة من القائمة.');
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new ApiError('UNAUTHENTICATED', 'سجّل الدخول للمتابعة.', HttpStatus.UNAUTHORIZED);
    if (user.role === 'ADMIN') throw new ApiError('FORBIDDEN', 'لا يمكن تحويل حساب الإدارة إلى مندوب.', HttpStatus.FORBIDDEN);
    if (user.role === 'CUSTOMER' && user.name && user.accountType) {
      throw new ApiError('ACCOUNT_EXISTS', 'هذا الرقم مسجّل كعميل. استخدم رقمًا آخر لحساب المندوب.');
    }
    const existing = await this.prisma.courierProfile.findUnique({ where: { userId } });
    if (existing && (existing.status === 'APPROVED' || existing.status === 'SUSPENDED')) {
      throw new ApiError('DOCUMENTS_LOCKED', 'لا يمكن إعادة تقديم الطلب بعد اعتماد الحساب أو إيقافه.');
    }
    const docs = await this.prisma.courierDocument.findMany({ where: { userId } });
    const kinds = new Set(docs.map((doc) => doc.kind));
    const missing = requiredDocs(input.vehicle).filter((kind) => !kinds.has(kind));
    const status: CourierAccountStatus = missing.length ? 'NEEDS_INFO' : 'PENDING_REVIEW';
    const data = {
      fullName: input.fullName.trim(),
      email: input.email?.trim() || null,
      governorate: input.governorate,
      area: input.area.trim(),
      vehicle: input.vehicle,
      vehicleDetails: input.vehicleDetails?.trim() || null,
      plate: input.plate?.trim() || null,
      status,
      reviewNote: missing.length ? `ناقص: ${missing.join(', ')}` : null,
      termsAcceptedAt: new Date(),
      available: false,
    };
    const profile = await this.prisma.courierProfile.upsert({
      where: { userId },
      update: data,
      create: { userId, ...data },
      include: { documents: true },
    });
    await this.prisma.courierDocument.updateMany({ where: { userId, profileId: null }, data: { profileId: profile.id } });
    let phone = user.phone;
    if (input.phone?.trim()) {
      const normalized = normalizeEgyptPhone(input.phone);
      if (!normalized) throw new ApiError('INVALID_PHONE', 'اكتب رقم موبايل مصري صحيح.');
      const taken = await this.prisma.user.findUnique({ where: { phone: normalized } });
      if (taken && taken.id !== userId) throw new ApiError('PHONE_EXISTS', 'رقم الموبايل مسجّل على حساب آخر.');
      phone = normalized;
    }
    if (!phone) throw new ApiError('PHONE_REQUIRED', 'اكتب رقم الموبايل الذي يتواصل به العملاء.');
    const updated = await this.prisma.user.update({
      where: { id: userId },
      data: { role: 'COURIER', name: data.fullName, phone },
    });
    const session = await this.auth.issueSession(updated);
    return { ...session, profile: this.presentProfile({ ...profile, documents: docs }) };
  }

  async setAvailability(userId: string, available: boolean, lat?: number, lng?: number) {
    const profile = await this.profile(userId);
    if (profile.status !== 'APPROVED') {
      throw new ApiError('COURIER_NOT_APPROVED', 'لا يمكن استقبال الطلبات قبل اعتماد الحساب.');
    }
    if (available && (lat == null || lng == null)) {
      throw new ApiError('LOCATION_REQUIRED', 'شارك موقعك الحالي لتصبح متاحًا. التتبع المستمر غير مفعّل.');
    }
    const saved = await this.prisma.courierProfile.update({
      where: { id: profile.id },
      data: {
        available,
        lat: available ? lat : profile.lat,
        lng: available ? lng : profile.lng,
        locationUpdatedAt: available ? new Date() : profile.locationUpdatedAt,
      },
      include: { documents: true },
    });
    return this.presentProfile(saved);
  }

  async offers(userId: string) {
    const profile = await this.profile(userId);
    if (profile.status !== 'APPROVED' || !profile.available || profile.lat == null || profile.lng == null) {
      return [];
    }
    const busy = await this.prisma.deliveryOrder.findFirst({
      where: { courierId: userId, status: { in: [...ACTIVE] } },
    });
    if (busy) return [];
    const searching = await this.prisma.deliveryOrder.findMany({
      where: { status: 'SEARCHING' },
      include: { foodOrder: { include: { restaurant: { select: { name: true } } } } },
      take: 40,
      orderBy: { createdAt: 'asc' },
    });
    const open: string[] = [];
    for (const order of searching) {
      if (!courierCanTake(profile.vehicle, order.vehicle)) continue;
      if (order.preferredCourierId && order.preferredCourierId !== userId) continue;
      const existing = await this.prisma.courierOffer.findUnique({
        where: { orderId_profileId: { orderId: order.id, profileId: profile.id } },
      });
      if (existing && existing.status !== 'OPEN' && existing.status !== 'EXPIRED') continue;
      const here = { lat: profile.lat!, lng: profile.lng! };
      const pickup = { lat: order.pickupLat, lng: order.pickupLng };
      const targeted = order.preferredCourierId === userId;
      if (!targeted && !withinMatch(here, pickup)) continue;
      const payoutMinor = Math.max(0, order.feeMinor - order.platformMinor);
      const distanceMeters = Math.round(haversineMeters(here, pickup));
      const offer = await this.prisma.courierOffer.upsert({
        where: { orderId_profileId: { orderId: order.id, profileId: profile.id } },
        update: { payoutMinor, distanceMeters, status: 'OPEN' },
        create: { orderId: order.id, profileId: profile.id, payoutMinor, distanceMeters, status: 'OPEN' },
      });
      open.push(offer.id);
      if (offer.createdAt.getTime() > Date.now() - 2000) {
        this.realtime.publish(userId, { type: 'offers.changed', orderId: order.id });
      }
    }
    await this.prisma.courierOffer.updateMany({
      where: { profileId: profile.id, status: 'OPEN', id: { notIn: open.length ? open : ['none'] } },
      data: { status: 'EXPIRED', respondedAt: new Date() },
    });
    const rows = await this.prisma.courierOffer.findMany({
      where: { profileId: profile.id, status: 'OPEN' },
      include: { order: { include: { foodOrder: { include: { restaurant: { select: { name: true } } } } } } },
      orderBy: { distanceMeters: 'asc' },
    });
    return rows.map((row) => this.presentOffer(row));
  }

  async acceptOffer(userId: string, offerId: string) {
    const profile = await this.approved(userId);
    const offer = await this.prisma.courierOffer.findFirst({
      where: { id: offerId, profileId: profile.id, status: 'OPEN' },
      include: { order: true },
    });
    if (!offer) throw new ApiError('OFFER_CLOSED', 'العرض لم يعد متاحًا.');
    if (!profile.available) throw new ApiError('COURIER_OFFLINE', 'فعّل حالة متاح قبل قبول الطلب.');
    if (profile.vehicle !== 'MOTORCYCLE' && profile.vehicle !== 'CAR') {
      throw new ApiError('VEHICLE_UNAVAILABLE', 'وسيلة التوصيل هذه لا تستقبل طلبات إلى أن تعتمد الإدارة مطابقتها.');
    }
    const order = await this.orders.acceptForCourier(userId, offer.orderId, {
      name: profile.fullName,
      phone: profile.user.phone,
      vehicle: profile.vehicle as 'MOTORCYCLE' | 'CAR',
      plate: profile.plate,
      avatarUrl: profile.user.avatarUrl,
    });
    await this.prisma.courierOffer.update({
      where: { id: offer.id },
      data: { status: 'ACCEPTED', respondedAt: new Date() },
    });
    await this.prisma.courierOffer.updateMany({
      where: { orderId: offer.orderId, status: 'OPEN' },
      data: { status: 'EXPIRED', respondedAt: new Date() },
    });
    return order;
  }

  async declineOffer(userId: string, offerId: string) {
    const profile = await this.profile(userId);
    const offer = await this.prisma.courierOffer.findFirst({ where: { id: offerId, profileId: profile.id, status: 'OPEN' } });
    if (!offer) throw new ApiError('OFFER_CLOSED', 'العرض لم يعد متاحًا.');
    await this.prisma.courierOffer.update({
      where: { id: offer.id },
      data: { status: 'DECLINED', respondedAt: new Date() },
    });
    return { ok: true };
  }

  async advance(userId: string, orderId: string, status: 'EN_ROUTE_PICKUP' | 'PICKED_UP' | 'EN_ROUTE_DROPOFF') {
    await this.approved(userId);
    return this.orders.advanceForCourier(userId, orderId, status);
  }

  async deliver(userId: string, orderId: string, code: string) {
    await this.approved(userId);
    return this.orders.deliverForCourier(userId, orderId, code);
  }

  async ping(userId: string, orderId: string, lat: number, lng: number) {
    const profile = await this.approved(userId);
    const active = await this.prisma.deliveryOrder.findFirst({
      where: { id: orderId, courierId: userId, status: { in: [...ACTIVE] } },
    });
    if (!active) throw new ApiError('FORBIDDEN', 'تحديث الموقع متاح أثناء مهمة معينة لك فقط.', HttpStatus.FORBIDDEN);
    await this.prisma.courierProfile.update({
      where: { id: profile.id },
      data: { lat, lng, locationUpdatedAt: new Date() },
    });
    return this.orders.moveOwnedCourier(userId, orderId, lat, lng);
  }

  async job(userId: string, orderId: string) {
    await this.profile(userId);
    const order = await this.prisma.deliveryOrder.findFirst({
      where: { id: orderId, courierId: userId },
      include: { foodOrder: { include: { restaurant: { select: { name: true } } } } },
    });
    if (!order) throw new ApiError('NOT_FOUND', 'هذا الطلب غير معيّن لك.', HttpStatus.NOT_FOUND);
    return this.presentJob(order);
  }

  async report(userId: string, orderId: string, message: string) {
    if (!message.trim()) throw new ApiError('NOTE_REQUIRED', 'اكتب وصف المشكلة.');
    const order = await this.prisma.deliveryOrder.findFirst({ where: { id: orderId, courierId: userId } });
    if (!order) throw new ApiError('FORBIDDEN', 'يمكن الإبلاغ عن الطلبات المسندة إليك فقط.', HttpStatus.FORBIDDEN);
    const ticket = await this.prisma.supportTicket.create({
      data: {
        userId,
        kind: 'COURIER',
        subject: `مشكلة في الطلب ${order.publicNumber}`,
        message: message.trim(),
        orderId: order.id,
      },
    });
    return { id: ticket.id, status: ticket.status, stored: true };
  }

  async history(userId: string) {
    await this.profile(userId);
    const orders = await this.prisma.deliveryOrder.findMany({
      where: { courierId: userId, status: { in: ['DELIVERED', 'CANCELLED'] } },
      include: { foodOrder: true, courierEarning: true },
      orderBy: { updatedAt: 'desc' },
      take: 50,
    });
    return orders.map((order) => ({
      id: order.id,
      publicNumber: order.publicNumber,
      status: order.status,
      kind: order.foodOrder ? 'FOOD' : 'PARCEL',
      pickupLine: order.pickupLine,
      dropoffLine: order.dropoffLine,
      payoutMinor: order.courierEarning?.payoutMinor ?? null,
      payoutLabel: order.courierEarning ? minorToLabel(order.courierEarning.payoutMinor) : null,
      createdAt: order.createdAt,
    }));
  }

  async earnings(userId: string) {
    const profile = await this.profile(userId);
    const [rows, settlements] = await Promise.all([
      this.prisma.courierEarning.findMany({
        where: { profileId: profile.id },
        orderBy: { createdAt: 'desc' },
        include: { order: { select: { publicNumber: true, status: true, feeMinor: true, platformMinor: true, deliveredAt: true } } },
      }),
      this.prisma.courierSettlement.findMany({ where: { profileId: profile.id }, orderBy: { createdAt: 'desc' } }),
    ]);
    const report = buildEarningsReport(
      new Date(),
      rows.map((row) => ({
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
      settlements.map((item) => ({
        id: item.id,
        kind: item.kind,
        amountMinor: item.amountMinor,
        reason: item.reason,
        createdAt: item.createdAt,
      })),
    );
    const labelPeriod = (period: (typeof report.periods)['all']) => ({
      ...period,
      payoutLabel: minorToLabel(period.payoutMinor),
      platformLabel: minorToLabel(period.platformMinor),
      paidLabel: minorToLabel(period.paidMinor),
      netLabel: minorToLabel(period.netMinor),
    });
    return {
      totalMinor: report.totalMinor,
      totalLabel: minorToLabel(report.totalMinor),
      todayMinor: report.todayMinor,
      todayLabel: minorToLabel(report.todayMinor),
      weekMinor: report.weekMinor,
      weekLabel: minorToLabel(report.weekMinor),
      monthMinor: report.monthMinor,
      monthLabel: minorToLabel(report.monthMinor),
      unsettledWageMinor: report.unsettledWageMinor,
      unsettledWageLabel: minorToLabel(report.unsettledWageMinor),
      paidWageMinor: report.paidWageMinor,
      paidWageLabel: minorToLabel(report.paidWageMinor),
      cashCollectedMinor: report.cashCollectedMinor,
      cashCollectedLabel: minorToLabel(report.cashCollectedMinor),
      unsettledCashMinor: report.unsettledCashMinor,
      unsettledCashLabel: minorToLabel(report.unsettledCashMinor),
      periods: {
        today: labelPeriod(report.periods.today),
        week: labelPeriod(report.periods.week),
        month: labelPeriod(report.periods.month),
        all: labelPeriod(report.periods.all),
      },
      orders: report.orders.map((row) => ({
        ...row,
        feeLabel: minorToLabel(row.feeMinor),
        platformLabel: minorToLabel(row.platformMinor),
        payoutLabel: minorToLabel(row.payoutMinor),
        earningState: 'RECORDED',
        earningStateLabel: 'سُجّل عند التسليم',
      })),
      settlements: report.settlements.map((item) => ({
        id: item.id,
        kind: item.kind,
        amountMinor: item.amountMinor,
        amountLabel: minorToLabel(item.amountMinor),
        reason: item.reason,
        createdAt: item.createdAt,
      })),
    };
  }

  async ratings(userId: string) {
    await this.profile(userId);
    return this.orders.courierRatings(userId, userId);
  }

  async attachDocument(userId: string, kind: CourierDocKind, storageName: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user || (user.role === 'CUSTOMER' && user.name && user.accountType)) {
      throw new ApiError('FORBIDDEN', 'رفع مستندات المندوب غير متاح لهذا الحساب.', HttpStatus.FORBIDDEN);
    }
    const profile = await this.prisma.courierProfile.findUnique({ where: { userId } });
    if (profile && !['NEEDS_INFO', 'REJECTED', 'PENDING_REVIEW'].includes(profile.status)) {
      throw new ApiError('DOCUMENTS_LOCKED', 'لا يمكن تغيير المستندات بعد اعتماد الحساب.');
    }
    return this.prisma.courierDocument.create({
      data: { userId, profileId: profile?.id, kind, storageName },
      select: { id: true, kind: true, createdAt: true },
    });
  }

  async openDocument(actor: { id: string; role: string }, documentId: string) {
    const doc = await this.prisma.courierDocument.findUnique({ where: { id: documentId } });
    if (!doc) throw new ApiError('NOT_FOUND', 'المستند غير موجود.', HttpStatus.NOT_FOUND);
    if (actor.role !== 'ADMIN' && doc.userId !== actor.id) {
      throw new ApiError('FORBIDDEN', 'لا يمكن فتح هذا المستند.', HttpStatus.FORBIDDEN);
    }
    const path = join(process.cwd(), 'private-uploads', doc.storageName);
    if (!existsSync(path)) throw new ApiError('NOT_FOUND', 'الملف غير موجود.', HttpStatus.NOT_FOUND);
    return { stream: createReadStream(path), name: doc.storageName };
  }

  async adminList() {
    const rows = await this.prisma.courierProfile.findMany({
      include: { user: true, documents: true },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
    return rows.map((row) => ({ ...this.presentProfile(row), phone: row.user.phone, documents: row.documents.map((doc) => ({ id: doc.id, kind: doc.kind })) }));
  }

  async adminReview(actorId: string, profileId: string, status: CourierAccountStatus, note?: string) {
    if (!['APPROVED', 'REJECTED', 'NEEDS_INFO', 'SUSPENDED', 'PENDING_REVIEW'].includes(status)) {
      throw new ApiError('INVALID_STATUS', 'حالة المراجعة غير معروفة.');
    }
    const needsNote = status === 'REJECTED' || status === 'NEEDS_INFO' || status === 'SUSPENDED';
    const trimmedNote = note?.trim() ?? '';
    if (needsNote && (trimmedNote.length < 8 || !/[\u0600-\u06FF]/.test(trimmedNote))) {
      throw new ApiError('NOTE_REQUIRED', 'اكتب سببًا واضحًا بالعربية، لا يُحفظ نص مثل ggg.');
    }
    const profile = await this.prisma.courierProfile.update({
      where: { id: profileId },
      data: {
        status,
        reviewNote: needsNote ? trimmedNote : null,
        available: status === 'APPROVED' ? undefined : false,
      },
      include: { documents: true, user: true },
    });
    await this.prisma.notification.create({
      data: {
        userId: profile.userId,
        type: 'TICKET_UPDATED',
        title: 'حالة حساب المندوب',
        body: note?.trim() || 'تم تحديث حالة الحساب.',
      },
    });
    await this.prisma.adminAudit.create({
      data: {
        actorId,
        action: 'REVIEW_COURIER',
        targetType: 'COURIER',
        targetId: profileId,
        reason: note?.trim() || status,
      },
    });
    return this.presentProfile(profile);
  }

  async adminSettle(actorId: string, profileId: string, kind: CourierSettlementKind, amountMinor: number, reason: string) {
    if (!reason.trim()) throw new ApiError('NOTE_REQUIRED', 'سبب التسوية مطلوب.');
    if (!Number.isInteger(amountMinor) || amountMinor === 0) throw new ApiError('INVALID_AMOUNT', 'المبلغ غير صالح.');
    if (kind !== 'ADJUSTMENT' && amountMinor < 0) throw new ApiError('INVALID_AMOUNT', 'مبلغ التسوية يجب أن يكون موجبًا.');
    const profile = await this.prisma.courierProfile.findUnique({ where: { id: profileId } });
    if (!profile) throw new ApiError('NOT_FOUND', 'حساب المندوب غير موجود.', HttpStatus.NOT_FOUND);
    const summary = await this.earnings(profile.userId);
    if (kind === 'WAGE_PAID' && amountMinor > summary.unsettledWageMinor) {
      throw new ApiError('INVALID_AMOUNT', 'المبلغ أكبر من أجر التوصيل غير المسوّى.');
    }
    if (kind === 'CASH_REMITTED' && amountMinor > summary.unsettledCashMinor) {
      throw new ApiError('INVALID_AMOUNT', 'المبلغ أكبر من النقد غير المورّد.');
    }
    const saved = await this.prisma.courierSettlement.create({
      data: { profileId, kind, amountMinor, reason: reason.trim(), actorId },
    });
    await this.prisma.adminAudit.create({
      data: { actorId, action: 'SETTLE_COURIER', targetType: 'COURIER', targetId: profileId, reason: reason.trim() },
    });
    return saved;
  }

  private async profile(userId: string) {
    const profile = await this.prisma.courierProfile.findUnique({ where: { userId }, include: { documents: true, user: true } });
    if (!profile) throw new ApiError('COURIER_PROFILE_REQUIRED', 'كمّل طلب التسجيل كمندوب أولًا.');
    return profile;
  }

  private async approved(userId: string) {
    const profile = await this.profile(userId);
    if (profile.status !== 'APPROVED') throw new ApiError('COURIER_NOT_APPROVED', 'الحساب غير معتمد لاستقبال الطلبات.');
    return profile;
  }

  private presentProfile(profile: {
    id: string;
    status: CourierAccountStatus;
    fullName: string;
    email: string | null;
    governorate: string;
    area: string;
    vehicle: CourierVehicleKind;
    vehicleDetails: string | null;
    plate: string | null;
    reviewNote: string | null;
    available: boolean;
    lat: number | null;
    lng: number | null;
    locationUpdatedAt: Date | null;
    documents?: Array<{ id: string; kind: CourierDocKind }>;
  }) {
    return {
      id: profile.id,
      status: profile.status,
      fullName: profile.fullName,
      email: profile.email,
      governorate: profile.governorate,
      area: profile.area,
      vehicle: profile.vehicle,
      vehicleDetails: profile.vehicleDetails,
      plate: profile.plate,
      reviewNote: profile.reviewNote,
      available: profile.available,
      hasLocation: profile.lat != null && profile.lng != null,
      locationUpdatedAt: profile.locationUpdatedAt,
      tracking: false,
      trackingNote: 'التتبع المستمر غير مفعّل. الموقع يُرسل فقط عند التوفر أو أثناء مهمة وبضغط تحديث الموقع.',
    };
  }

  private presentOffer(row: {
    id: string;
    payoutMinor: number;
    distanceMeters: number;
    order: {
      id: string;
      parcelType: string;
      parcelDescription: string;
      pickupName: string;
      pickupLine: string;
      pickupLat: number;
      pickupLng: number;
      dropoffLine: string;
      dropoffLat: number;
      dropoffLng: number;
      distanceMeters: number;
      feeMinor: number;
      platformMinor: number;
      goodsMinor: number;
      collectMinor: number;
      publicNumber: string;
      foodOrder?: { id: string; restaurant?: { name: string } | null } | null;
    };
  }) {
    const payoutMinor = Math.max(0, row.order.feeMinor - row.order.platformMinor);
    return {
      id: row.id,
      orderId: row.order.id,
      publicNumber: row.order.publicNumber,
      kind: row.order.foodOrder ? 'FOOD' : 'PARCEL',
      parcelType: row.order.parcelType,
      description: row.order.parcelDescription,
      restaurant: row.order.foodOrder?.restaurant?.name ?? null,
      pickup: { name: row.order.pickupName, line: row.order.pickupLine, lat: row.order.pickupLat, lng: row.order.pickupLng },
      dropoff: { line: row.order.dropoffLine, lat: row.order.dropoffLat, lng: row.order.dropoffLng },
      tripMeters: row.order.distanceMeters,
      distanceToPickupMeters: row.distanceMeters,
      payoutMinor,
      payoutLabel: minorToLabel(payoutMinor),
      deliveryFeeMinor: row.order.feeMinor,
      deliveryFeeLabel: minorToLabel(row.order.feeMinor),
      platformMinor: row.order.platformMinor,
      collectMinor: row.order.collectMinor,
      collectLabel: minorToLabel(row.order.collectMinor),
      goodsMinor: row.order.goodsMinor,
      goodsLabel: minorToLabel(row.order.goodsMinor),
    };
  }

  private presentJob(order: {
    id: string;
    publicNumber: string;
    status: string;
    parcelType: string;
    parcelDescription: string;
    pickupName: string;
    pickupLine: string;
    pickupLat: number;
    pickupLng: number;
    dropoffLine: string;
    dropoffLat: number;
    dropoffLng: number;
    courierId: string | null;
    recipientName: string;
    recipientPhone: string;
    distanceMeters: number;
    feeMinor: number;
    platformMinor: number;
    collectMinor: number;
    goodsMinor: number;
    notes: string | null;
    foodOrder?: { id: string; publicNumber?: string; restaurant?: { name: string } | null } | null;
  }) {
    const payoutMinor = Math.max(0, order.feeMinor - order.platformMinor);
    const contact = courierOrderContact(order, order.courierId ?? '');
    return {
      id: order.id,
      publicNumber: order.publicNumber,
      status: order.status,
      kind: order.foodOrder ? 'FOOD' : 'PARCEL',
      parcelType: order.parcelType,
      description: order.parcelDescription,
      notes: order.notes,
      restaurant: order.foodOrder?.restaurant?.name ?? null,
      foodNumber: order.foodOrder?.publicNumber ?? null,
      pickup: { name: order.pickupName, line: order.pickupLine, lat: order.pickupLat, lng: order.pickupLng },
      dropoff: { line: order.dropoffLine, lat: order.dropoffLat, lng: order.dropoffLng },
      recipientName: contact?.name || null,
      recipientPhone: contact?.phone ?? null,
      customerName: contact?.name || null,
      customerPhone: contact?.phone ?? null,
      distanceMeters: order.distanceMeters,
      payoutMinor,
      payoutLabel: minorToLabel(payoutMinor),
      deliveryFeeMinor: order.feeMinor,
      platformMinor: order.platformMinor,
      collectMinor: order.collectMinor,
      collectLabel: minorToLabel(order.collectMinor),
      goodsMinor: order.goodsMinor,
      goodsLabel: minorToLabel(order.goodsMinor),
    };
  }
}
