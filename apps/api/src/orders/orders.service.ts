import { HttpStatus, Inject, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  ActorType,
  DeliveryOrder,
  NotificationType,
  OrderStatus,
  PaymentMethod,
  Prisma,
} from '@prisma/client';
import { createCipheriv, createDecipheriv, createHash, randomBytes, randomInt } from 'crypto';
import { ApiError } from '../common/api-error';
import { CANCEL_REASONS, cancelPolicy } from '../domain/cancel-policy';
import { REVIEW_EDIT_MS, assertCommentAllowed, summarizeRatings, tagsForRating } from '../domain/rating';
import { CollectionError, collectionLabels, planCollection, SETTLEMENT_LABEL } from '../domain/collection';
import { estimatedRoadMeters, findServiceArea, haversineMeters, inEgypt, vehicleAllowed } from '../domain/geo';
import { customerTracking } from '../domain/tracking';
import { courierCanTake, withinMatch } from '../domain/courier';
import { minorToLabel, platformMinorFromBps, publicOrderNumber } from '../domain/money';
import {
  STATUS_COPY,
  assertTransition,
  TransitionError,
} from '../domain/order-state';
import { buildQuote, QuoteError } from '../domain/pricing';
import { normalizeEgyptPhone } from '../domain/phone';
import { PARCEL_TYPES } from '../catalog/catalog';
import { PushService } from '../notifications/push.service';
import { PrismaService } from '../prisma/prisma.service';
import { RealtimeService } from '../realtime/realtime.service';
import { CancelDto, CreateOrderDto, QuoteDto, ReviewDto } from './dto';

const ACTIVE: OrderStatus[] = [
  'SEARCHING',
  'ACCEPTED',
  'EN_ROUTE_PICKUP',
  'PICKED_UP',
  'EN_ROUTE_DROPOFF',
];

@Injectable()
export class OrdersService {
  constructor(
    @Inject(PrismaService) private readonly prisma: PrismaService,
    @Inject(RealtimeService) private readonly realtime: RealtimeService,
    @Inject(ConfigService) private readonly config: ConfigService,
    @Inject(PushService) private readonly push: PushService,
  ) {}

  async quote(userId: string, dto: QuoteDto) {
    return this.price(userId, dto);
  }

  async create(userId: string, idempotencyKey: string, dto: CreateOrderDto) {
    if (!idempotencyKey || idempotencyKey.length < 8) {
      throw new ApiError('IDEMPOTENCY_REQUIRED', 'تعذر تأكيد الطلب. حاول مرة أخرى.');
    }
    const existing = await this.prisma.deliveryOrder.findUnique({ where: { idempotencyKey } });
    if (existing) {
      if (existing.userId !== userId) throw new ApiError('FORBIDDEN', 'لا يمكن الوصول لهذا الطلب.', HttpStatus.FORBIDDEN);
      return this.present(existing, false);
    }
    const phone = normalizeEgyptPhone(dto.recipientPhone);
    if (!phone) throw new ApiError('INVALID_PHONE', 'رقم المستلم غير صحيح.');
    const parcel = PARCEL_TYPES.find((item) => item.code === dto.parcelType);
    if (!parcel) throw new ApiError('INVALID_PARCEL', 'اختَر نوع الغرض.');

    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (user?.role !== 'CUSTOMER') {
      throw new ApiError('FORBIDDEN', 'إنشاء الطلب متاح لحساب العميل فقط.', HttpStatus.FORBIDDEN);
    }
    if (!user?.accountType || !user.name) {
      throw new ApiError('PROFILE_INCOMPLETE', 'كمّل بيانات الحساب أولًا.');
    }
    const membership = await this.prisma.businessMember.findFirst({
      where: { userId },
      include: { business: true },
    });
    if (user.accountType === 'BUSINESS' && !membership) {
      throw new ApiError('BUSINESS_REQUIRED', 'كمّل بيانات النشاط التجاري أولًا.');
    }

    if (user.suspendedAt) {
      throw new ApiError('ACCOUNT_SUSPENDED', 'الحساب موقوف من الإدارة.', HttpStatus.FORBIDDEN);
    }
    const preferred = dto.courierId ? await this.chosenCourier(dto.courierId, true) : null;
    if (preferred) dto.vehicle = preferred.vehicle;
    const priced = await this.price(userId, dto);
    const order = await this.prisma.deliveryOrder.create({
      data: {
        publicNumber: await this.uniqueNumber(),
        idempotencyKey,
        userId,
        businessId: membership?.businessId,
        accountType: user.accountType,
        status: 'SEARCHING',
        pickupName: dto.pickup.name.trim(),
        pickupLine: dto.pickup.line.trim(),
        pickupDetails: dto.pickup.details?.trim(),
        pickupLat: dto.pickup.lat,
        pickupLng: dto.pickup.lng,
        dropoffName: dto.dropoff.name.trim(),
        dropoffLine: dto.dropoff.line.trim(),
        dropoffDetails: dto.dropoff.details?.trim(),
        dropoffLat: dto.dropoff.lat,
        dropoffLng: dto.dropoff.lng,
        recipientName: dto.recipientName.trim(),
        recipientPhone: phone,
        parcelType: parcel.code,
        parcelDescription: dto.parcelDescription.trim(),
        notes: dto.notes?.trim(),
        photoUrl: dto.photoUrl,
        size: dto.size,
        fragile: dto.fragile,
        vehicle: dto.vehicle,
        distanceMeters: priced.distanceMeters,
        feeMinor: priced.feeMinor,
        ...(await this.platformSnapshot(priced.feeMinor, preferred?.userId)),
        serviceFeeMinor: priced.serviceFeeMinor,
        extraMinor: priced.extraMinor,
        totalMinor: priced.totalMinor,
        etaMinutes: priced.etaMinutes,
        paymentMethod: PaymentMethod.CASH,
        paymentState: priced.collection.collectMinor > 0 ? 'PENDING' : 'NOT_REQUIRED',
        goodsMinor: priced.collection.goodsMinor,
        goodsPrepaid: priced.collection.goodsPrepaid,
        collectGoods: priced.collection.collectGoods,
        deliveryPayer: priced.collection.deliveryPayer,
        collectMinor: priced.collection.collectMinor,
        businessDueMinor: priced.collection.businessDueMinor,
        shopDeliveryChargeMinor: priced.collection.shopDeliveryChargeMinor,
        settlementStatus: priced.collection.settlementStatus,
        pricingVersion: priced.pricingVersion,
        preferredCourierId: preferred?.userId,
        preferredCourierName: preferred?.fullName,
        history: { create: { status: 'SEARCHING', actor: 'CUSTOMER' } },
      },
    });

    if (dto.saveRecipient && membership) {
      await this.prisma.savedRecipient.create({
        data: {
          userId,
          businessId: membership.businessId,
          name: dto.recipientName.trim(),
          phone,
          line: dto.dropoff.line.trim(),
          details: dto.dropoff.details?.trim(),
          lat: dto.dropoff.lat,
          lng: dto.dropoff.lng,
          consentAt: new Date(),
        },
      });
    }

    await this.notify(order, 'ORDER_CREATED');
    await this.notify(order, 'SEARCHING');
    return this.present(order, false);
  }

  async list(userId: string, bucket: string, query?: string) {
    const where: Prisma.DeliveryOrderWhereInput = { userId };
    if (bucket === 'active') where.status = { in: ACTIVE };
    else if (bucket === 'completed') where.status = 'DELIVERED';
    else if (bucket === 'cancelled') where.status = { in: ['CANCELLED', 'NO_COURIER'] };
    else throw new ApiError('INVALID_FILTER', 'التبويب غير معروف.');
    const q = query?.trim();
    if (q) {
      where.OR = [
        { publicNumber: { contains: q, mode: 'insensitive' } },
        { recipientName: { contains: q, mode: 'insensitive' } },
        { recipientPhone: { contains: q } },
        { dropoffLine: { contains: q, mode: 'insensitive' } },
      ];
    }
    const orders = await this.prisma.deliveryOrder.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take: 50,
    });
    return orders.map((order) => this.present(order, false));
  }

  async get(userId: string, id: string) {
    return this.present(await this.owned(userId, id), true);
  }

  cancelPreview(userId: string, id: string) {
    return this.owned(userId, id).then((order) => this.previewCancel(order));
  }

  async cancel(userId: string, id: string, dto: CancelDto) {
    const order = await this.owned(userId, id);
    const policy = this.previewCancel(order);
    if (!policy.allowed) throw new ApiError('CANCEL_NOT_ALLOWED', policy.message);
    if (dto.code === 'OTHER' && !dto.reason?.trim()) {
      throw new ApiError('CANCEL_REASON_REQUIRED', 'اكتب سبب الإلغاء.');
    }
    if (order.cancellation) throw new ApiError('CANCEL_NOT_ALLOWED', 'تم إلغاء هذا الطلب من قبل.');
    const reason = CANCEL_REASONS.find((item) => item.code === dto.code)?.label;
    const note = dto.reason?.trim() || reason;
    const updated = await this.prisma.$transaction(async (tx) => {
      await tx.orderCancellation.create({
        data: { orderId: order.id, code: dto.code, reason: note, feeMinor: policy.feeMinor },
      });
      if (policy.feeMinor > 0) {
        await tx.ledgerEntry.create({
          data: {
            orderId: order.id,
            businessId: order.businessId,
            kind: 'CANCELLATION_FEE',
            amountMinor: policy.feeMinor,
            note: 'رسوم إلغاء مسجّلة، وليست تحويلًا ماليًا.',
          },
        });
      }
      await tx.courierOffer.updateMany({
        where: { orderId: order.id, status: 'OPEN' },
        data: { status: 'EXPIRED', respondedAt: new Date() },
      });
      return tx.deliveryOrder.update({
        where: { id: order.id },
        data: {
          status: 'CANCELLED',
          cancelledAt: new Date(),
          cancelReason: note,
          cancelCode: dto.code,
          cancelFeeMinor: policy.feeMinor,
          history: { create: { status: 'CANCELLED', actor: 'CUSTOMER', note } },
        },
        include: { history: { orderBy: { createdAt: 'asc' } }, proof: true, review: true, assignment: true, cancellation: true },
      });
    });
    await this.notify(updated, 'ORDER_CANCELLED');
    return this.present(updated, true);
  }

  async recordCollection(orderId: string, amountMinor: number, actor: 'COURIER' | 'SYSTEM' | 'SUPPORT') {
    if (!Number.isInteger(amountMinor) || amountMinor < 0) {
      throw new ApiError('INVALID_AMOUNT', 'مبلغ التحصيل غير صالح.');
    }
    return this.prisma.$transaction(async (tx) => {
      const order = await tx.deliveryOrder.findUnique({ where: { id: orderId }, include: { collection: true } });
      if (!order) throw new ApiError('NOT_FOUND', 'الطلب غير موجود.', HttpStatus.NOT_FOUND);
      if (order.collection) throw new ApiError('COLLECTION_EXISTS', 'تم تسجيل التحصيل مرة واحدة ولا يمكن تكراره.');
      if (amountMinor > order.collectMinor) throw new ApiError('INVALID_AMOUNT', 'لا يمكن تسجيل مبلغ أكبر من المطلوب تحصيله.');
      const status = amountMinor === 0 ? order.settlementStatus : amountMinor < order.collectMinor ? 'PARTIAL' : 'COLLECTED';
      await tx.collectionRecord.create({
        data: {
          orderId: order.id,
          collectedMinor: amountMinor,
          goodsMinor: Math.min(amountMinor, order.collectGoods ? order.goodsMinor : 0),
          deliveryMinor: Math.max(0, amountMinor - (order.collectGoods ? order.goodsMinor : 0)),
          actor,
        },
      });
      if (amountMinor > 0) {
        await tx.ledgerEntry.create({
          data: {
            orderId: order.id,
            businessId: order.businessId,
            kind: 'COLLECTION',
            amountMinor,
            note: 'تسجيل تحصيل نقدي. لا يعني أن المبلغ وصل إلى المحل.',
          },
        });
      }
      const updated = await tx.deliveryOrder.update({
        where: { id: order.id },
        data: { settlementStatus: status },
        include: { history: true, proof: true, review: true, assignment: true, cancellation: true },
      });
      return this.present(updated, true);
    });
  }

  async settle(businessId: string, items: Array<{ orderId: string; amountMinor: number }>, note?: string) {
    if (!items.length) throw new ApiError('INVALID_AMOUNT', 'اختر طلبات التسوية.');
    return this.prisma.$transaction(async (tx) => {
      const batch = await tx.settlementBatch.create({ data: { businessId, note } });
      for (const item of items) {
        if (!Number.isInteger(item.amountMinor) || item.amountMinor <= 0) {
          throw new ApiError('INVALID_AMOUNT', 'مبلغ التسوية غير صالح.');
        }
        const order = await tx.deliveryOrder.findUnique({ where: { id: item.orderId } });
        if (!order || order.businessId !== businessId) {
          throw new ApiError('NOT_FOUND', 'الطلب غير مرتبط بهذا النشاط.', HttpStatus.NOT_FOUND);
        }
        if (order.settlementStatus === 'DISPUTED') {
          throw new ApiError('SETTLEMENT_BLOCKED', 'لا يمكن تسوية طلب متنازع عليه.');
        }
        const owed = order.businessDueMinor + order.shopDeliveryChargeMinor;
        const remaining = owed - order.settledMinor;
        if (item.amountMinor > remaining) {
          throw new ApiError('SETTLEMENT_EXISTS', 'لا يمكن تسوية مبلغ أكبر من المتبقي أو تكرار تسوية مكتملة.');
        }
        await tx.settlementItem.create({
          data: { batchId: batch.id, orderId: order.id, amountMinor: item.amountMinor },
        });
        const settledMinor = order.settledMinor + item.amountMinor;
        await tx.deliveryOrder.update({
          where: { id: order.id },
          data: {
            settledMinor,
            settlementStatus: settledMinor >= owed && owed > 0 ? 'SETTLED' : 'PARTIAL',
          },
        });
        await tx.ledgerEntry.create({
          data: {
            orderId: order.id,
            businessId,
            kind: 'SETTLEMENT',
            amountMinor: item.amountMinor,
            note: 'قيد تسوية مسجّل من الإدارة. لا يوجد تحويل بنكي في هذه المرحلة.',
          },
        });
      }
      return tx.settlementBatch.findUnique({ where: { id: batch.id }, include: { items: true } });
    });
  }

  async retry(userId: string, id: string) {
    const order = await this.owned(userId, id);
    const updated = await this.transition(order, 'SEARCHING', 'CUSTOMER');
    return this.present(updated, true);
  }

  async deliveryCode(userId: string, id: string) {
    const order = await this.owned(userId, id);
    if (!order.deliveryCodeEnc || order.status !== 'EN_ROUTE_DROPOFF' || order.deliveryCodeUsedAt) {
      throw new ApiError('CODE_UNAVAILABLE', 'رمز التسليم غير متاح بعد.');
    }
    return { code: this.openCode(order.deliveryCodeEnc) };
  }

  async createFromFood(input: {
    foodOrderId: string;
    userId: string;
    pickup: { name: string; line: string; lat: number; lng: number };
    dropoff: { name: string; line: string; details?: string | null; lat: number; lng: number };
    recipientName: string;
    recipientPhone: string;
    notes?: string | null;
    description: string;
    foodMinor: number;
    deliveryFeeMinor: number;
    serviceFeeMinor?: number;
    distanceMeters: number;
    etaMinutes: number;
    pricingVersion: number;
    preferredCourierId?: string | null;
  }) {
    const idempotencyKey = `food-${input.foodOrderId}`;
    const existing = await this.prisma.deliveryOrder.findUnique({ where: { idempotencyKey } });
    if (existing) return existing;
    const user = await this.prisma.user.findUnique({ where: { id: input.userId } });
    const preferred = input.preferredCourierId ? await this.chosenCourier(input.preferredCourierId, false) : null;
    const order = await this.prisma.deliveryOrder.create({
      data: {
        publicNumber: await this.uniqueNumber(),
        idempotencyKey,
        userId: input.userId,
        accountType: user?.accountType ?? 'PERSONAL',
        status: 'SEARCHING',
        pickupName: input.pickup.name,
        pickupLine: input.pickup.line,
        pickupLat: input.pickup.lat,
        pickupLng: input.pickup.lng,
        dropoffName: input.dropoff.name,
        dropoffLine: input.dropoff.line,
        dropoffDetails: input.dropoff.details,
        dropoffLat: input.dropoff.lat,
        dropoffLng: input.dropoff.lng,
        recipientName: input.recipientName,
        recipientPhone: input.recipientPhone,
        parcelType: 'FOOD',
        parcelDescription: input.description,
        notes: input.notes,
        size: 'SMALL',
        fragile: false,
        vehicle: preferred?.vehicle ?? 'MOTORCYCLE',
        distanceMeters: input.distanceMeters,
        feeMinor: input.deliveryFeeMinor,
        ...(await this.platformSnapshot(input.deliveryFeeMinor, preferred?.userId)),
        serviceFeeMinor: input.serviceFeeMinor ?? 0,
        extraMinor: input.serviceFeeMinor ?? 0,
        totalMinor: input.deliveryFeeMinor + (input.serviceFeeMinor ?? 0),
        etaMinutes: input.etaMinutes,
        paymentMethod: 'CASH',
        paymentState: 'PENDING',
        goodsMinor: input.foodMinor,
        goodsPrepaid: false,
        collectGoods: true,
        deliveryPayer: 'RECIPIENT',
        collectMinor: input.foodMinor + input.deliveryFeeMinor + (input.serviceFeeMinor ?? 0),
        businessDueMinor: input.foodMinor,
        shopDeliveryChargeMinor: 0,
        settlementStatus: 'PENDING_COLLECTION',
        pricingVersion: input.pricingVersion,
        preferredCourierId: preferred?.userId,
        preferredCourierName: preferred?.fullName,
        history: { create: { status: 'SEARCHING', actor: 'SYSTEM', note: 'الطعام جاهز وبانتظار مندوب.' } },
      },
    });
    await this.notify(order, 'SEARCHING');
    return order;
  }

  async cancelSearchingFood(orderId: string, note: string) {
    const order = await this.prisma.deliveryOrder.findUnique({ where: { id: orderId } });
    if (!order) return null;
    if (order.status !== 'SEARCHING' && order.status !== 'NO_COURIER') {
      throw new ApiError('CANCEL_NOT_ALLOWED', 'المندوب بدأ التحرك. الإلغاء من صفحة التتبع حسب السياسة.');
    }
    const updated = await this.transition(order, 'CANCELLED', 'CUSTOMER', note);
    await this.prisma.deliveryOrder.update({
      where: { id: order.id },
      data: { cancelledAt: new Date(), cancelReason: note },
    });
    await this.prisma.courierOffer.updateMany({
      where: { orderId: order.id, status: 'OPEN' },
      data: { status: 'EXPIRED', respondedAt: new Date() },
    });
    await this.notify({ ...updated, status: 'CANCELLED' }, 'ORDER_CANCELLED');
    return updated;
  }

  async review(userId: string, id: string, dto: ReviewDto) {
    const order = await this.reviewable(userId, id);
    const existing = await this.prisma.review.findUnique({ where: { orderId: order.id } });
    if (existing) throw new ApiError('REVIEW_EXISTS', 'تم تقييم هذا الطلب من قبل.');
    const data = this.reviewData(dto);
    try {
      const review = await this.prisma.review.create({
        data: { orderId: order.id, userId, courierId: order.courierId!, ...data },
      });
      return this.presentReview(review);
    } catch (error) {
      if ((error as { code?: string }).code === 'P2002') {
        throw new ApiError('REVIEW_EXISTS', 'تم تقييم هذا الطلب من قبل.');
      }
      throw error;
    }
  }

  async updateReview(userId: string, id: string, dto: ReviewDto) {
    const order = await this.reviewable(userId, id);
    const review = await this.prisma.review.findUnique({ where: { orderId: order.id } });
    if (!review || review.userId !== userId) throw new ApiError('NOT_FOUND', 'لا يوجد تقييم لهذا الطلب.', HttpStatus.NOT_FOUND);
    if (review.status === 'EXCLUDED') throw new ApiError('REVIEW_LOCKED', 'هذا التقييم لم يعد قابلًا للتعديل.');
    if (Date.now() - review.createdAt.getTime() > REVIEW_EDIT_MS) {
      throw new ApiError('REVIEW_LOCKED', 'انتهت مدة تعديل التقييم.');
    }
    const updated = await this.prisma.review.update({
      where: { id: review.id },
      data: this.reviewData(dto),
    });
    return this.presentReview(updated);
  }

  async orderReview(userId: string, id: string) {
    const order = await this.owned(userId, id);
    const review = await this.prisma.review.findUnique({ where: { orderId: order.id } });
    return {
      eligible: order.status === 'DELIVERED' && Boolean(order.courierId),
      review: review && review.userId === userId ? this.presentReview(review) : null,
    };
  }

  async courierRatings(userId: string, courierId: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    const related = await this.prisma.deliveryOrder.findFirst({ where: { userId, courierId } });
    if (user?.role !== 'ADMIN' && userId !== courierId && !related) {
      throw new ApiError('FORBIDDEN', 'لا يمكن عرض تقييمات هذا المندوب.', HttpStatus.FORBIDDEN);
    }
    return this.ratingSummary(courierId);
  }

  async reportReview(userId: string, reviewId: string, reason: string) {
    const review = await this.prisma.review.findUnique({ where: { id: reviewId } });
    if (!review) throw new ApiError('NOT_FOUND', 'التقييم غير موجود.', HttpStatus.NOT_FOUND);
    const related = await this.prisma.deliveryOrder.findFirst({ where: { userId, courierId: review.courierId } });
    if (userId !== review.courierId && !related) {
      throw new ApiError('FORBIDDEN', 'لا يمكن الإبلاغ عن هذا التقييم.', HttpStatus.FORBIDDEN);
    }
    await this.prisma.reviewReport.upsert({
      where: { reviewId_userId: { reviewId, userId } },
      update: { reason: reason.trim() },
      create: { reviewId, userId, reason: reason.trim() },
    });
    return { ok: true };
  }

  async excludeReview(reviewId: string, reason: string) {
    const review = await this.prisma.review.update({
      where: { id: reviewId },
      data: { status: 'EXCLUDED', excludedReason: reason.trim() },
    });
    return this.presentReview(review);
  }

  async messages(userId: string, id: string) {
    await this.owned(userId, id);
    return this.prisma.chatMessage.findMany({
      where: { orderId: id },
      orderBy: { createdAt: 'asc' },
    });
  }

  async sendMessage(userId: string, id: string, body: string) {
    const order = await this.owned(userId, id);
    if (['CANCELLED', 'NO_COURIER', 'DELIVERED'].includes(order.status)) {
      throw new ApiError('CHAT_CLOSED', 'المحادثة غير متاحة لهذا الطلب.');
    }
    const message = await this.prisma.chatMessage.create({
      data: { orderId: id, sender: 'CUSTOMER', senderId: userId, body: body.trim() },
    });
    this.realtime.publish(userId, { type: 'chat.message', message });
    return message;
  }

  async acceptForDev(orderId: string, courier: {
    id: string;
    name: string;
    phone: string;
    vehicle: 'MOTORCYCLE' | 'CAR';
    plate: string;
    rating: number;
  }) {
    const order = await this.prisma.deliveryOrder.findUnique({ where: { id: orderId } });
    if (!order) throw new ApiError('NOT_FOUND', 'الطلب غير موجود.', HttpStatus.NOT_FOUND);
    const updated = await this.transition(order, 'ACCEPTED', 'COURIER');
    const saved = await this.prisma.deliveryOrder.update({
      where: { id: order.id },
      data: {
        courierId: courier.id,
        courierName: courier.name,
        courierPhone: courier.phone,
        courierVehicle: courier.vehicle,
        courierPlate: courier.plate,
        courierRating: courier.rating,
        assignment: {
          create: {
            courierId: courier.id,
            lat: order.pickupLat + 0.01,
            lng: order.pickupLng + 0.01,
          },
        },
      },
    });
    await this.notify({ ...saved, status: updated.status }, 'ORDER_ACCEPTED');
    return this.present(saved, true);
  }

  async advanceForDev(orderId: string, status: OrderStatus, actor: ActorType = 'COURIER') {
    const order = await this.prisma.deliveryOrder.findUnique({ where: { id: orderId } });
    if (!order) throw new ApiError('NOT_FOUND', 'الطلب غير موجود.', HttpStatus.NOT_FOUND);
    let code: string | null = null;
    if (status === 'EN_ROUTE_DROPOFF') {
      code = String(randomInt(0, 10000)).padStart(4, '0');
    }
    const updated = await this.transition(order, status, actor, undefined, code);
    const type = this.notificationFor(status);
    if (type) await this.notify(updated, type);
    return { order: this.present(updated, true), devDeliveryCode: code };
  }

  async moveCourier(orderId: string, lat: number, lng: number) {
    const order = await this.prisma.deliveryOrder.findUnique({
      where: { id: orderId },
      include: { assignment: true },
    });
    if (!order?.assignment) throw new ApiError('NOT_FOUND', 'لا يوجد مندوب معيّن.');
    if (!['ACCEPTED', 'EN_ROUTE_PICKUP', 'PICKED_UP', 'EN_ROUTE_DROPOFF'].includes(order.status)) {
      throw new ApiError('TRACKING_CLOSED', 'تحديث الموقع متاح بعد قبول الطلب وحتى التسليم أو الإلغاء.');
    }
    const moved = order.assignment.lat == null || haversineMeters({ lat: order.assignment.lat, lng: order.assignment.lng ?? lat }, { lat, lng }) >= 15;
    const waited = Date.now() - order.assignment.updatedAt.getTime() >= 12_000;
    if (!moved && !waited) return { ok: true, stored: false };
    await this.prisma.courierAssignment.update({
      where: { orderId },
      data: { lat, lng },
    });
    const fresh = await this.prisma.deliveryOrder.findUnique({ where: { id: orderId }, include: { assignment: true, foodOrder: { select: { id: true } } } });
    this.realtime.publish(order.userId, { type: 'order.updated', order: this.present(fresh!, true) });
    return { ok: true, stored: true };
  }

  private async stopTracking(orderId: string) {
    await this.prisma.courierAssignment.updateMany({ where: { orderId }, data: { lat: null, lng: null } });
  }

  async verifyDelivery(orderId: string, code: string, actor: ActorType) {
    const order = await this.prisma.deliveryOrder.findUnique({ where: { id: orderId } });
    if (!order) throw new ApiError('NOT_FOUND', 'الطلب غير موجود.', HttpStatus.NOT_FOUND);
    if (order.status !== 'EN_ROUTE_DROPOFF' || !order.deliveryCodeHash) {
      throw new ApiError('CODE_UNAVAILABLE', 'لا يمكن تأكيد التسليم في هذه الحالة.');
    }
    if (order.deliveryCodeUsedAt) {
      throw new ApiError('CODE_USED', 'تم استخدام رمز التسليم من قبل.');
    }
    const hash = this.hashCode(code);
    if (hash !== order.deliveryCodeHash) {
      throw new ApiError('CODE_INVALID', 'رمز التسليم غير صحيح.');
    }
    await this.prisma.deliveryOrder.update({
      where: { id: order.id },
      data: { deliveryCodeUsedAt: new Date() },
    });
    const updated = await this.transition(order, 'DELIVERED', actor === 'SUPPORT' ? 'SUPPORT' : 'SYSTEM');
    await this.prisma.deliveryOrder.update({
      where: { id: order.id },
      data: { deliveredAt: new Date(), paymentState: 'CAPTURED' },
    });
    await this.prisma.deliveryProof.create({
      data: { orderId: order.id, method: 'OTP', note: 'تم التحقق من رمز التسليم على الخادم.' },
    });
    await this.stopTracking(order.id);
    await this.notify(updated, 'DELIVERED');
    await this.recordCourierEarning(order.id);
    return this.present({ ...updated, status: 'DELIVERED', deliveredAt: new Date() }, true);
  }

  async supportComplete(orderId: string, note: string) {
    const order = await this.prisma.deliveryOrder.findUnique({ where: { id: orderId } });
    if (!order) throw new ApiError('NOT_FOUND', 'الطلب غير موجود.', HttpStatus.NOT_FOUND);
    if (order.status !== 'EN_ROUTE_DROPOFF' && order.status !== 'PICKED_UP') {
      throw new ApiError('OVERRIDE_NOT_ALLOWED', 'الإكمال اليدوي متاح فقط أثناء التنفيذ.');
    }
    if (order.status === 'PICKED_UP') {
      await this.transition(order, 'EN_ROUTE_DROPOFF', 'SUPPORT');
    }
    const current = await this.prisma.deliveryOrder.findUniqueOrThrow({ where: { id: orderId } });
    const updated = await this.transition(current, 'DELIVERED', 'SUPPORT', note);
    await this.prisma.deliveryOrder.update({
      where: { id: orderId },
      data: { deliveredAt: new Date(), paymentState: 'CAPTURED' },
    });
    await this.prisma.deliveryProof.create({
      data: { orderId, method: 'SUPPORT_OVERRIDE', note },
    });
    await this.stopTracking(orderId);
    await this.notify(updated, 'DELIVERED');
    await this.recordCourierEarning(orderId);
    return this.present(updated, true);
  }

  async acceptForCourier(
    userId: string,
    orderId: string,
    courier: { name: string; phone: string | null; vehicle: 'MOTORCYCLE' | 'CAR'; plate: string | null; avatarUrl: string | null },
  ) {
    const active = await this.prisma.deliveryOrder.findFirst({
      where: { courierId: userId, status: { in: ['ACCEPTED', 'EN_ROUTE_PICKUP', 'PICKED_UP', 'EN_ROUTE_DROPOFF'] } },
    });
    if (active) throw new ApiError('COURIER_BUSY', 'عندك طلب قيد التنفيذ. أنهه قبل قبول طلب جديد.');
    const summary = await this.ratingSummary(userId);
    const current = await this.prisma.deliveryOrder.findUnique({ where: { id: orderId }, select: { feeMinor: true } });
    const snapshot = await this.platformSnapshot(current?.feeMinor ?? 0, userId);
    const saved = await this.prisma.$transaction(async (tx) => {
      const claim = await tx.deliveryOrder.updateMany({
        where: { id: orderId, status: 'SEARCHING' },
        data: {
          status: 'ACCEPTED',
          platformBps: snapshot.platformBps,
          platformMinor: snapshot.platformMinor,
          courierId: userId,
          courierName: courier.name,
          courierPhone: courier.phone,
          courierAvatarUrl: courier.avatarUrl,
          courierVehicle: courier.vehicle,
          courierPlate: courier.plate,
          courierRating: summary.display,
        },
      });
      if (claim.count !== 1) throw new ApiError('OFFER_CLOSED', 'الطلب لم يعد متاحًا.');
      await tx.orderStatusHistory.create({ data: { orderId, status: 'ACCEPTED', actor: 'COURIER' } });
      await tx.courierAssignment.create({ data: { orderId, courierId: userId } });
      await tx.courierOffer.updateMany({
        where: { orderId, status: 'OPEN' },
        data: { status: 'EXPIRED', respondedAt: new Date() },
      });
      return tx.deliveryOrder.findUniqueOrThrow({ where: { id: orderId }, include: { assignment: true } });
    });
    await this.notify(saved, 'ORDER_ACCEPTED');
    return this.present(saved, true);
  }

  async advanceForCourier(userId: string, orderId: string, status: OrderStatus) {
    if (!['EN_ROUTE_PICKUP', 'PICKED_UP', 'EN_ROUTE_DROPOFF'].includes(status)) {
      throw new ApiError('INVALID_STATUS', 'لا يمكن إنهاء التسليم من هذه الخطوة.');
    }
    const order = await this.ownedByCourier(userId, orderId);
    const code = status === 'EN_ROUTE_DROPOFF' ? String(randomInt(0, 10000)).padStart(4, '0') : null;
    const updated = await this.transition(order, status, 'COURIER', undefined, code);
    const type = this.notificationFor(status);
    if (type) await this.notify(updated, type);
    return this.present(updated, true);
  }

  async deliverForCourier(userId: string, orderId: string, code: string) {
    await this.ownedByCourier(userId, orderId);
    return this.verifyDelivery(orderId, code, 'SYSTEM');
  }

  async moveOwnedCourier(userId: string, orderId: string, lat: number, lng: number) {
    await this.ownedByCourier(userId, orderId);
    return this.moveCourier(orderId, lat, lng);
  }

  private async ownedByCourier(userId: string, orderId: string) {
    const order = await this.prisma.deliveryOrder.findUnique({ where: { id: orderId } });
    if (!order || order.courierId !== userId) {
      throw new ApiError('FORBIDDEN', 'هذا الطلب غير معيّن لك.', HttpStatus.FORBIDDEN);
    }
    if (!['ACCEPTED', 'EN_ROUTE_PICKUP', 'PICKED_UP', 'EN_ROUTE_DROPOFF'].includes(order.status)) {
      throw new ApiError('INVALID_STATUS', 'الطلب ليس قيد التنفيذ.');
    }
    return order;
  }

  private async recordCourierEarning(orderId: string) {
    const order = await this.prisma.deliveryOrder.findUnique({ where: { id: orderId } });
    if (!order?.courierId) return;
    const profile = await this.prisma.courierProfile.findUnique({ where: { userId: order.courierId } });
    if (!profile) return;
    await this.prisma.courierEarning.upsert({
      where: { orderId: order.id },
      update: {},
      create: {
        profileId: profile.id,
        orderId: order.id,
        payoutMinor: Math.max(0, order.feeMinor - order.platformMinor),
        customerFeeMinor: order.totalMinor,
        goodsMinor: order.goodsMinor,
        cashCollectedMinor: order.collectMinor,
      },
    });
  }

  private writtenAddress(place: { lat: number; lng: number }) {
    return !Number.isFinite(place.lat) || !Number.isFinite(place.lng) || (place.lat === 0 && place.lng === 0);
  }

  private flatQuote(rule: { baseFeeMinor: number; minFeeMinor: number; mediumSurchargeMinor: number; largeSurchargeMinor: number; fragileSurchargeMinor: number; allowedSizes: string[]; version: number }, dto: QuoteDto) {
    if (!rule.allowedSizes.includes(dto.size)) {
      throw new QuoteError('SIZE_NOT_ALLOWED', dto.vehicle === 'MOTORCYCLE' ? 'الموتوسيكل لا يناسب هذا الحجم. اختر سيارة.' : 'هذا الحجم غير متاح للوسيلة المختارة.');
    }
    const extras: { code: string; label: string; amountMinor: number }[] = [];
    if (dto.size === 'MEDIUM' && rule.mediumSurchargeMinor > 0) extras.push({ code: 'SIZE_MEDIUM', label: 'حجم متوسط', amountMinor: rule.mediumSurchargeMinor });
    if (dto.size === 'LARGE' && rule.largeSurchargeMinor > 0) extras.push({ code: 'SIZE_LARGE', label: 'حجم كبير', amountMinor: rule.largeSurchargeMinor });
    if (dto.fragile && rule.fragileSurchargeMinor > 0) extras.push({ code: 'FRAGILE', label: 'قابل للكسر', amountMinor: rule.fragileSurchargeMinor });
    const extraMinor = extras.reduce((sum, line) => sum + line.amountMinor, 0);
    const feeMinor = Math.max(rule.minFeeMinor, rule.baseFeeMinor);
    return {
      distanceMeters: 0,
      feeMinor,
      extraMinor,
      totalMinor: feeMinor + extraMinor,
      extras,
      etaMinutes: 0,
      currency: 'EGP' as const,
      pricingVersion: rule.version,
    };
  }

  private async platformSnapshot(feeMinor: number, courierUserId?: string | null) {
    const personal = courierUserId
      ? await this.prisma.courierProfile.findUnique({ where: { userId: courierUserId }, select: { commissionBps: true } })
      : null;
    const config = personal?.commissionBps == null ? await this.prisma.platformConfig.findUnique({ where: { id: 1 } }) : null;
    const bps = personal?.commissionBps ?? config?.deliveryPlatformBps ?? 0;
    return { platformBps: bps, platformMinor: platformMinorFromBps(feeMinor, bps) };
  }

  private async price(userId: string, dto: QuoteDto) {
    void userId;
    const rule = await this.prisma.pricingRule.findUnique({ where: { vehicle: dto.vehicle } });
    if (!rule || !rule.active) {
      throw new ApiError('VEHICLE_UNAVAILABLE', 'وسيلة النقل دي غير متاحة حاليًا.');
    }
    const written = this.writtenAddress(dto.pickup) || this.writtenAddress(dto.dropoff);
    const distanceMeters = written ? 0 : await this.distance(dto.pickup, dto.dropoff);
    if (!written) {
      if (!inEgypt(dto.pickup) || !inEgypt(dto.dropoff)) {
        throw new ApiError('OUT_OF_SERVICE_AREA', 'اكتب عنوانًا داخل مصر مع المنطقة والمدينة.');
      }
      const areas = await this.prisma.serviceArea.findMany({ where: { active: true } });
      const pickupArea = findServiceArea(dto.pickup, areas);
      const dropoffArea = findServiceArea(dto.dropoff, areas);
      if ((pickupArea && !vehicleAllowed(pickupArea, dto.vehicle)) || (dropoffArea && !vehicleAllowed(dropoffArea, dto.vehicle))) {
        throw new ApiError('VEHICLE_UNAVAILABLE', 'وسيلة النقل دي غير متاحة في المنطقة.');
      }
    }
    const config = await this.prisma.platformConfig.findUnique({ where: { id: 1 } });
    const serviceFeeMinor = config?.serviceFeeMinor ?? 0;
    try {
      const quote = written
        ? this.flatQuote(rule, dto)
        : buildQuote({
            distanceMeters,
            vehicle: dto.vehicle,
            size: dto.size,
            fragile: dto.fragile,
            rule,
          });
      if (serviceFeeMinor > 0) {
        quote.extras.push({ code: 'SERVICE', label: 'رسوم الخدمة', amountMinor: serviceFeeMinor });
        quote.extraMinor += serviceFeeMinor;
        quote.totalMinor += serviceFeeMinor;
      }
      const plan = planCollection({
        goodsMinor: dto.goodsMinor ?? 0,
        goodsPrepaid: dto.goodsPrepaid ?? false,
        collectGoods: dto.collectGoods ?? false,
        deliveryPayer: dto.deliveryPayer ?? 'RECIPIENT',
        deliveryFeeMinor: quote.totalMinor,
        maxCollectMinor: Number(this.config.get('COD_MAX_MINOR') ?? 200_000),
      });
      return { ...quote, serviceFeeMinor, collection: collectionLabels(plan) };
    } catch (error) {
      if (error instanceof QuoteError) throw new ApiError(error.code, error.message);
      if (error instanceof CollectionError) {
        const message =
          error.code === 'COD_LIMIT'
            ? 'المبلغ المطلوب تحصيله يتجاوز الحد النقدي المسموح به.'
            : error.code === 'PREPAID_CONFLICT'
              ? 'لا يمكن تحصيل قيمة منتجات مدفوعة مسبقًا.'
              : 'قيمة المنتجات غير صالحة.';
        throw new ApiError(error.code, message);
      }
      throw error;
    }
  }

  private async reviewable(userId: string, id: string) {
    const order = await this.owned(userId, id);
    if (order.status !== 'DELIVERED') throw new ApiError('REVIEW_NOT_READY', 'التقييم متاح بعد اكتمال التوصيل.');
    if (!order.courierId) throw new ApiError('REVIEW_NOT_READY', 'لا يمكن تقييم طلب بلا مندوب.');
    return order;
  }

  private reviewData(dto: ReviewDto) {
    if (!Number.isInteger(dto.rating) || dto.rating < 1 || dto.rating > 5) {
      throw new ApiError('INVALID_RATING', 'عدد النجوم يجب أن يكون بين 1 و 5.');
    }
    const blocked = assertCommentAllowed(dto.comment);
    if (blocked) throw new ApiError('INVALID_COMMENT', blocked);
    const allowed = new Set(tagsForRating(dto.rating));
    return {
      rating: dto.rating,
      tags: (dto.tags ?? []).filter((tag) => allowed.has(tag)),
      comment: dto.comment?.trim() || null,
    };
  }

  private presentReview(review: { id: string; orderId: string; courierId: string; rating: number; tags: string[]; comment: string | null; status: string; createdAt: Date; updatedAt: Date }) {
    return {
      id: review.id,
      orderId: review.orderId,
      courierId: review.courierId,
      rating: review.rating,
      tags: review.tags,
      comment: review.comment,
      status: review.status,
      createdAt: review.createdAt,
      updatedAt: review.updatedAt,
      editableUntil: new Date(review.createdAt.getTime() + REVIEW_EDIT_MS),
    };
  }

  private async ratingSummary(courierId: string) {
    const reviews = await this.prisma.review.findMany({
      where: { courierId, status: 'PUBLISHED' },
      orderBy: { createdAt: 'desc' },
      select: { id: true, rating: true, tags: true, comment: true, createdAt: true },
    });
    const summary = summarizeRatings(reviews.map((review) => review.rating));
    return {
      courierId,
      ...summary,
      reviews: reviews.slice(0, 20).map((review) => ({
        id: review.id,
        rating: review.rating,
        tags: review.tags,
        comment: review.comment,
        createdAt: review.createdAt,
      })),
    };
  }

  private previewCancel(order: DeliveryOrder & { cancellation?: { id: string } | null }) {
    const policy = cancelPolicy({
      status: order.status,
      deliveryFeeMinor: order.totalMinor,
      goodsMinor: order.goodsMinor,
      alreadyCancelled: Boolean(order.cancellation) || order.status === 'CANCELLED',
    });
    return { ...policy, reasons: CANCEL_REASONS, feeLabel: minorToLabel(policy.feeMinor) };
  }

  private async distance(
    a: { lat: number; lng: number },
    b: { lat: number; lng: number },
  ): Promise<number> {
    const key = this.config.get<string>('GOOGLE_MAPS_API_KEY');
    if (!key) return estimatedRoadMeters(a, b);
    const url = new URL('https://maps.googleapis.com/maps/api/distancematrix/json');
    url.searchParams.set('origins', `${a.lat},${a.lng}`);
    url.searchParams.set('destinations', `${b.lat},${b.lng}`);
    url.searchParams.set('key', key);
    url.searchParams.set('mode', 'driving');
    const response = await fetch(url);
    const body = (await response.json()) as {
      rows?: Array<{ elements?: Array<{ status: string; distance?: { value: number } }> }>;
    };
    const value = body.rows?.[0]?.elements?.[0];
    if (value?.status === 'OK' && value.distance) return value.distance.value;
    return estimatedRoadMeters(a, b);
  }

  private async transition(
    order: DeliveryOrder,
    status: OrderStatus,
    actor: ActorType,
    note?: string,
    deliveryCode?: string | null,
  ) {
    try {
      assertTransition(order.status, status, actor);
    } catch (error) {
      if (error instanceof TransitionError) throw new ApiError('INVALID_STATUS', error.message);
      throw error;
    }
    return this.prisma.deliveryOrder.update({
      where: { id: order.id },
      data: {
        status,
        deliveryCodeHash: deliveryCode ? this.hashCode(deliveryCode) : undefined,
        deliveryCodeEnc: deliveryCode ? this.seal(deliveryCode) : undefined,
        history: { create: { status, actor, note } },
      },
    });
  }

  async publishCancellation(orderId: string) {
    const order = await this.prisma.deliveryOrder.findUnique({ where: { id: orderId } });
    if (!order) return;
    await this.prisma.courierOffer.updateMany({
      where: { orderId, status: 'OPEN' },
      data: { status: 'EXPIRED', respondedAt: new Date() },
    });
    await this.notify(order, 'ORDER_CANCELLED');
  }

  async selectableCouriers() {
    const busy = await this.prisma.deliveryOrder.findMany({
      where: { status: { in: ['ACCEPTED', 'EN_ROUTE_PICKUP', 'PICKED_UP', 'EN_ROUTE_DROPOFF'] }, courierId: { not: null } },
      select: { courierId: true },
    });
    const busyIds = new Set(busy.map((row) => row.courierId).filter((id): id is string => Boolean(id)));
    const rows = await this.prisma.courierProfile.findMany({
      where: { status: 'APPROVED', user: { suspendedAt: null, role: 'COURIER' } },
      orderBy: { fullName: 'asc' },
    });
    return rows
      .filter((row) => !busyIds.has(row.userId))
      .map((row) => ({
        id: row.userId,
        name: row.fullName,
        area: row.area,
        vehicle: row.vehicle,
        selectable: row.vehicle === 'MOTORCYCLE' || row.vehicle === 'CAR',
      }));
  }

  async chosenCourier(courierId: string, requireFree: boolean) {
    const profile = await this.prisma.courierProfile.findUnique({
      where: { userId: courierId },
      include: { user: { select: { suspendedAt: true, role: true } } },
    });
    if (!profile || profile.status !== 'APPROVED' || profile.user.role !== 'COURIER' || profile.user.suspendedAt) {
      throw new ApiError('COURIER_UNAVAILABLE', 'هذا المندوب غير متاح للاختيار.');
    }
    if (profile.vehicle !== 'MOTORCYCLE' && profile.vehicle !== 'CAR') {
      throw new ApiError('COURIER_UNAVAILABLE', 'هذا المندوب لا يستقبل طلبات إلى أن تعتمد الإدارة مركبته.');
    }
    if (requireFree) {
      const active = await this.prisma.deliveryOrder.findFirst({
        where: { courierId, status: { in: ['ACCEPTED', 'EN_ROUTE_PICKUP', 'PICKED_UP', 'EN_ROUTE_DROPOFF'] } },
      });
      if (active) throw new ApiError('COURIER_BUSY', 'هذا المندوب يوصل طلبًا الآن. يظهر مرة أخرى بعد التسليم.');
    }
    return { userId: profile.userId, fullName: profile.fullName, vehicle: profile.vehicle };
  }

  private async signalCouriers(order: DeliveryOrder) {
    const preferred = order.preferredCourierId;
    const profiles = await this.prisma.courierProfile.findMany({
      where: preferred
        ? { status: 'APPROVED', userId: preferred }
        : { status: 'APPROVED', available: true, lat: { not: null }, lng: { not: null } },
      select: { userId: true, lat: true, lng: true, vehicle: true },
    });
    for (const profile of profiles) {
      if (profile.vehicle !== 'MOTORCYCLE' && profile.vehicle !== 'CAR') continue;
      if (!courierCanTake(profile.vehicle, order.vehicle)) continue;
      if (!preferred) {
        if (profile.lat == null || profile.lng == null) continue;
        if (!withinMatch({ lat: profile.lat, lng: profile.lng }, { lat: order.pickupLat, lng: order.pickupLng })) continue;
      }
      const existing = await this.prisma.notification.findFirst({
        where: { userId: profile.userId, orderId: order.id, type: 'SEARCHING' },
      });
      if (!existing) {
        const notification = await this.prisma.notification.create({
          data: {
            userId: profile.userId,
            orderId: order.id,
            type: 'SEARCHING',
            title: 'طلب توصيل متاح',
            body: order.parcelType === 'FOOD' ? 'طلب طعام قريب من موقعك.' : 'طلب نقل قريب من موقعك.',
          },
        });
        this.realtime.publish(profile.userId, { type: 'notification', notification });
        const courier = await this.prisma.user.findUnique({ where: { id: profile.userId }, select: { notifOrders: true } });
        if (courier?.notifOrders !== false) {
          await this.push.send(profile.userId, 'طلب توصيل جديد', order.parcelType === 'FOOD' ? 'عميل طلب توصيل طعام.' : 'عميل طلب مندوبًا للتوصيل.', { orderId: order.id, type: 'SEARCHING' });
        }
      }
      this.realtime.publish(profile.userId, { type: 'offers.changed', orderId: order.id });
    }
  }

  private async notify(order: DeliveryOrder, type: NotificationType) {
    if (type === 'ORDER_CANCELLED' || type === 'DELIVERED') await this.stopTracking(order.id);
    await this.storeNotice(order.userId, order, type, this.copyFor(type, order), true);
    if (order.courierId && order.courierId !== order.userId) {
      await this.storeNotice(order.courierId, order, type, this.courierCopy(type, order), false);
    }
    if (type === 'SEARCHING') await this.signalCouriers(order);
  }

  private async storeNotice(
    userId: string,
    order: DeliveryOrder,
    type: NotificationType,
    copy: { title: string; body: string },
    customerView: boolean,
  ) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    const allowed = type === 'CHAT_MESSAGE' ? user?.notifChat !== false : user?.notifOrders !== false;
    if (allowed && user) {
      const notification = await this.prisma.notification.create({
        data: { userId, orderId: order.id, type, title: copy.title, body: copy.body },
      });
      this.realtime.publish(userId, { type: 'notification', notification });
      if (customerView && (type === 'ORDER_ACCEPTED' || type === 'PICKED_UP' || type === 'DELIVERED')) {
        await this.push.send(userId, copy.title, copy.body, { orderId: order.id, type });
      }
    }
    if (customerView) {
      const fresh = await this.prisma.deliveryOrder.findUnique({
        where: { id: order.id },
        include: { assignment: true, history: { orderBy: { createdAt: 'asc' } }, proof: true, review: true, foodOrder: { select: { id: true } } },
      });
      if (fresh) this.realtime.publish(userId, { type: 'order.updated', order: this.present(fresh, true) });
      return;
    }
    this.realtime.publish(userId, { type: 'job.updated', orderId: order.id, status: order.status });
  }

  private courierCopy(type: NotificationType, order: DeliveryOrder) {
    if (type === 'ORDER_CANCELLED') return { title: 'أُلغي طلب مسند إليك', body: `الطلب ${order.publicNumber} خرج من مهمتك.` };
    if (type === 'ORDER_ACCEPTED') return { title: 'تم إسناد الطلب', body: `الطلب ${order.publicNumber} أصبح مهمتك.` };
    if (type === 'DELIVERED') return { title: 'اكتملت المهمة', body: `تم تسجيل أجرة الطلب ${order.publicNumber}.` };
    return this.copyFor(type, order);
  }

  private copyFor(type: NotificationType, order: DeliveryOrder) {
    if (type === 'ORDER_CREATED') return { title: 'تم إنشاء طلبك', body: `طلب ${order.publicNumber} اتسجل.` };
    if (type === 'CHAT_MESSAGE') return { title: 'رسالة جديدة من المندوب', body: `على الطلب ${order.publicNumber}` };
    const status = type === 'ORDER_ACCEPTED' ? 'ACCEPTED' : type === 'COURIER_TO_PICKUP' ? 'EN_ROUTE_PICKUP' : type === 'PICKED_UP' ? 'PICKED_UP' : type === 'COURIER_NEAR_DROPOFF' ? 'EN_ROUTE_DROPOFF' : type === 'DELIVERED' ? 'DELIVERED' : type === 'ORDER_CANCELLED' ? 'CANCELLED' : type === 'NO_COURIER' ? 'NO_COURIER' : 'SEARCHING';
    return STATUS_COPY[status];
  }

  private notificationFor(status: OrderStatus): NotificationType | null {
    const map: Partial<Record<OrderStatus, NotificationType>> = {
      ACCEPTED: 'ORDER_ACCEPTED',
      EN_ROUTE_PICKUP: 'COURIER_TO_PICKUP',
      PICKED_UP: 'PICKED_UP',
      EN_ROUTE_DROPOFF: 'COURIER_NEAR_DROPOFF',
      DELIVERED: 'DELIVERED',
      CANCELLED: 'ORDER_CANCELLED',
      NO_COURIER: 'NO_COURIER',
      SEARCHING: 'SEARCHING',
    };
    return map[status] ?? null;
  }

  private async owned(userId: string, id: string) {
    const order = await this.prisma.deliveryOrder.findUnique({
      where: { id },
      include: { history: { orderBy: { createdAt: 'asc' } }, proof: true, review: true, assignment: true, cancellation: true, foodOrder: { select: { id: true } } },
    });
    if (!order || order.userId !== userId) {
      throw new ApiError('NOT_FOUND', 'الطلب غير موجود.', HttpStatus.NOT_FOUND);
    }
    return order;
  }

  private async uniqueNumber() {
    for (let i = 0; i < 5; i += 1) {
      const value = publicOrderNumber();
      const exists = await this.prisma.deliveryOrder.findUnique({ where: { publicNumber: value } });
      if (!exists) return value;
    }
    return publicOrderNumber();
  }

  private seal(code: string) {
    const key = createHash('sha256').update(this.config.getOrThrow<string>('OTP_PEPPER')).digest();
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', key, iv);
    const enc = Buffer.concat([cipher.update(code, 'utf8'), cipher.final()]);
    const tag = cipher.getAuthTag();
    return Buffer.concat([iv, tag, enc]).toString('base64');
  }

  private openCode(payload: string) {
    const raw = Buffer.from(payload, 'base64');
    const key = createHash('sha256').update(this.config.getOrThrow<string>('OTP_PEPPER')).digest();
    const decipher = createDecipheriv('aes-256-gcm', key, raw.subarray(0, 12));
    decipher.setAuthTag(raw.subarray(12, 28));
    return Buffer.concat([decipher.update(raw.subarray(28)), decipher.final()]).toString('utf8');
  }

  private hashCode(code: string) {
    return createHash('sha256')
      .update(`${this.config.getOrThrow<string>('OTP_PEPPER')}:delivery:${code}`)
      .digest('hex');
  }

  present(order: DeliveryOrder & { history?: unknown; proof?: unknown; review?: unknown; assignment?: { lat: number | null; lng: number | null; updatedAt?: Date } | null; foodOrder?: { id: string } | null }, detailed: boolean) {
    const tracking = customerTracking({
      status: order.status,
      lat: order.assignment?.lat ?? null,
      lng: order.assignment?.lng ?? null,
      updatedAt: order.assignment?.updatedAt ?? null,
      now: new Date(),
    });
    const base = {
      id: order.id,
      publicNumber: order.publicNumber,
      status: order.status,
      statusTitle: STATUS_COPY[order.status].title,
      accountType: order.accountType,
      pickup: {
        name: order.pickupName,
        line: order.pickupLine,
        details: order.pickupDetails,
        lat: order.pickupLat,
        lng: order.pickupLng,
      },
      dropoff: {
        name: order.dropoffName,
        line: order.dropoffLine,
        details: order.dropoffDetails,
        lat: order.dropoffLat,
        lng: order.dropoffLng,
      },
      recipientName: order.recipientName,
      recipientPhone: order.recipientPhone,
      parcelType: order.parcelType,
      parcelDescription: order.parcelDescription,
      size: order.size,
      fragile: order.fragile,
      vehicle: order.vehicle,
      distanceMeters: order.distanceMeters,
      feeMinor: order.feeMinor,
      extraMinor: order.extraMinor,
      totalMinor: order.totalMinor,
      totalLabel: minorToLabel(order.totalMinor),
      currency: order.currency,
      etaMinutes: order.etaMinutes,
      paymentMethod: order.paymentMethod,
      collection: {
        goodsMinor: order.goodsMinor,
        goodsLabel: minorToLabel(order.goodsMinor),
        goodsPrepaid: order.goodsPrepaid,
        collectGoods: order.collectGoods,
        deliveryPayer: order.deliveryPayer,
        collectMinor: order.collectMinor,
        collectLabel: minorToLabel(order.collectMinor),
        businessDueMinor: order.businessDueMinor,
        businessDueLabel: minorToLabel(order.businessDueMinor),
        shopDeliveryChargeMinor: order.shopDeliveryChargeMinor,
        shopDeliveryChargeLabel: minorToLabel(order.shopDeliveryChargeMinor),
        settledMinor: order.settledMinor,
        settledLabel: minorToLabel(order.settledMinor),
        settlementStatus: order.settlementStatus,
        settlementLabel: SETTLEMENT_LABEL[order.settlementStatus],
        goodsVerified: false,
      },
      chosenCourier: order.preferredCourierId
        ? { id: order.preferredCourierId, name: order.preferredCourierName }
        : null,
      courier: order.courierId
        ? {
            id: order.courierId,
            name: order.courierName,
            phone: order.courierPhone,
            avatarUrl: order.courierAvatarUrl,
            vehicle: order.courierVehicle,
            plate: order.courierPlate,
            rating: order.courierRating,
            lat: tracking.lat,
            lng: tracking.lng,
            tracking: tracking.active,
            locationFresh: tracking.fresh,
            locationUpdatedAt: tracking.updatedAt,
          }
        : null,
      foodOrderId: order.foodOrder?.id ?? null,
      createdAt: order.createdAt,
      updatedAt: order.updatedAt,
    };
    if (!detailed) return base;
    return {
      ...base,
      notes: order.notes,
      photoUrl: order.photoUrl,
      deliveredAt: order.deliveredAt,
      cancelledAt: order.cancelledAt,
      cancelReason: order.cancelReason,
      history: order.history ?? [],
      proof: order.proof ?? null,
      review: order.review ? this.presentReview(order.review as Parameters<OrdersService['presentReview']>[0]) : null,
      hasDeliveryCode: Boolean(order.deliveryCodeHash) && !order.deliveryCodeUsedAt,
    };
  }
}
