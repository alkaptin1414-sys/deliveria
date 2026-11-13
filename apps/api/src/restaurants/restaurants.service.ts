import { Inject, Injectable, OnModuleInit } from '@nestjs/common';
import { HttpStatus } from '@nestjs/common';
import { MenuItemKind, Prisma } from '@prisma/client';
import { ApiError } from '../common/api-error';
import { applyOffer, orderingState, priceItem, RESTAURANT_CATEGORIES } from '../domain/food';
import { estimatedRoadMeters, findServiceArea, inEgypt } from '../domain/geo';
import { minorToLabel, publicOrderNumber } from '../domain/money';
import { buildQuote } from '../domain/pricing';
import { normalizeEgyptPhone } from '../domain/phone';
import { summarizeRatings } from '../domain/rating';
import { OrdersService } from '../orders/orders.service';
import { PrismaService } from '../prisma/prisma.service';
import { RealtimeService } from '../realtime/realtime.service';

const itemInclude = {
  groups: { include: { options: true } },
} satisfies Prisma.MenuItemInclude;

@Injectable()
export class RestaurantsService implements OnModuleInit {
  constructor(
    @Inject(PrismaService) private readonly prisma: PrismaService,
    @Inject(OrdersService) private readonly orders: OrdersService,
    @Inject(RealtimeService) private readonly realtime: RealtimeService,
  ) {}

  async onModuleInit() {
    const count = await this.prisma.restaurant.count();
    if (count === 0) await this.seedCatalog();
  }

  categories() {
    return RESTAURANT_CATEGORIES;
  }

  async list(query: { q?: string; category?: string; sort?: string }) {
    const restaurants = await this.prisma.restaurant.findMany({
      where: {
        active: true,
        ...(query.category ? { category: query.category as never } : {}),
        ...(query.q
          ? {
              OR: [
                { name: { contains: query.q, mode: 'insensitive' } },
                { cuisine: { contains: query.q, mode: 'insensitive' } },
                { items: { some: { name: { contains: query.q, mode: 'insensitive' } } } },
              ],
            }
          : {}),
      },
      include: { reviews: { select: { rating: true } } },
    });
    const areas = await this.prisma.serviceArea.findMany({ where: { active: true } });
    const visible = restaurants
      .filter((restaurant) => findServiceArea(restaurant, areas))
      .map((restaurant) => this.card(restaurant));
    const sort = query.sort ?? 'rating';
    visible.sort((a, b) => {
      if (sort === 'eta') return a.etaMinutes - b.etaMinutes;
      if (sort === 'fee') return a.deliveryFeeMinor - b.deliveryFeeMinor;
      return (b.rating ?? -1) - (a.rating ?? -1);
    });
    return visible;
  }

  async detail(id: string) {
    const restaurant = await this.prisma.restaurant.findUnique({
      where: { id },
      include: {
        reviews: { select: { rating: true } },
        offers: { where: { active: true } },
        sections: {
          orderBy: { sort: 'asc' },
          include: { items: { orderBy: { sort: 'asc' }, include: itemInclude } },
        },
      },
    });
    if (!restaurant || !restaurant.active) throw new ApiError('NOT_FOUND', 'المطعم غير موجود.', HttpStatus.NOT_FOUND);
    return {
      ...this.card(restaurant),
      description: restaurant.description,
      phone: restaurant.phone,
      addressLine: restaurant.addressLine,
      minOrderMinor: restaurant.minOrderMinor,
      minOrderLabel: minorToLabel(restaurant.minOrderMinor),
      offers: restaurant.offers.map((offer) => ({ id: offer.id, title: offer.title, percentOff: offer.percentOff })),
      sections: restaurant.sections.map((section) => ({
        id: section.id,
        name: section.name,
        items: section.items.map((item) => ({
          id: item.id,
          name: item.name,
          description: item.description,
          imageUrl: item.imageUrl,
          priceMinor: item.priceMinor,
          priceLabel: minorToLabel(item.priceMinor),
          available: item.available,
          kind: item.kind,
          groups: item.groups.map((group) => ({
            id: group.id,
            name: group.name,
            required: group.required,
            minSelect: group.minSelect,
            maxSelect: group.maxSelect,
            options: group.options.map((option) => ({
              id: option.id,
              name: option.name,
              priceMinor: option.priceMinor,
              priceLabel: option.priceMinor === 0 ? 'مجاني' : minorToLabel(option.priceMinor),
              available: option.available,
            })),
          })),
        })),
      })),
    };
  }

  async saveCart(userId: string, restaurantId: string, items: Array<{ itemId: string; quantity: number; optionIds?: string[]; note?: string }>) {
    await this.detail(restaurantId);
    const priced = await this.priceLines(restaurantId, items);
    const cart = await this.prisma.cart.upsert({
      where: { userId_restaurantId: { userId, restaurantId } },
      update: {},
      create: { userId, restaurantId },
    });
    await this.prisma.cartItem.deleteMany({ where: { cartId: cart.id } });
    if (priced.lines.length) {
      await this.prisma.cartItem.createMany({
        data: priced.lines.map((line) => ({
          cartId: cart.id,
          itemId: line.itemId,
          quantity: line.quantity,
          optionIds: line.optionIds,
          note: line.note,
        })),
      });
    }
    return this.cartView(userId, restaurantId);
  }

  async cart(userId: string, restaurantId: string) {
    return this.cartView(userId, restaurantId);
  }

  async quote(userId: string, restaurantId: string, addressId: string) {
    const restaurant = await this.prisma.restaurant.findUnique({ where: { id: restaurantId }, include: { offers: { where: { active: true } } } });
    if (!restaurant) throw new ApiError('NOT_FOUND', 'المطعم غير موجود.', HttpStatus.NOT_FOUND);
    const address = await this.prisma.address.findUnique({ where: { id: addressId } });
    if (!address || address.userId !== userId) throw new ApiError('NOT_FOUND', 'العنوان غير موجود.', HttpStatus.NOT_FOUND);
    const view = await this.cartView(userId, restaurantId);
    const discount = applyOffer(view.foodMinor, restaurant.offers[0]?.percentOff ?? 0);
    const quote = await this.deliveryQuote(restaurant, address);
    const state = orderingState(restaurant);
    return {
      ...state,
      minOrderMinor: restaurant.minOrderMinor,
      foodMinor: view.foodMinor,
      foodLabel: minorToLabel(view.foodMinor),
      discountMinor: discount.discountMinor,
      discountLabel: minorToLabel(discount.discountMinor),
      deliveryFeeMinor: quote.totalMinor,
      deliveryFeeLabel: minorToLabel(quote.totalMinor),
      totalMinor: discount.payableMinor + quote.totalMinor,
      totalLabel: minorToLabel(discount.payableMinor + quote.totalMinor),
      etaMinutes: restaurant.etaMinutes + quote.etaMinutes,
      lines: view.lines,
    };
  }

  async checkout(
    userId: string,
    restaurantId: string,
    input: { addressId: string; recipientName: string; recipientPhone: string; notes?: string; scheduledFor?: string; courierId?: string; idempotencyKey: string },
  ) {
    if (!input.idempotencyKey || input.idempotencyKey.length < 8) {
      throw new ApiError('IDEMPOTENCY_REQUIRED', 'تعذر تأكيد الطلب. حاول مرة أخرى.');
    }
    const existing = await this.prisma.foodOrder.findUnique({ where: { idempotencyKey: input.idempotencyKey }, include: { lines: true, restaurant: true, deliveryOrder: true } });
    if (existing) {
      if (existing.userId !== userId) throw new ApiError('FORBIDDEN', 'لا يمكن الوصول لهذا الطلب.', HttpStatus.FORBIDDEN);
      return this.presentOrder(existing);
    }
    const restaurant = await this.prisma.restaurant.findUnique({ where: { id: restaurantId }, include: { offers: { where: { active: true } } } });
    if (!restaurant || !restaurant.active) throw new ApiError('NOT_FOUND', 'المطعم غير موجود.', HttpStatus.NOT_FOUND);
    const state = orderingState(restaurant);
    if (!state.acceptingNow && !state.scheduledOnly) throw new ApiError('RESTAURANT_CLOSED', 'المطعم مغلق ولا يستقبل طلبات الآن.');
    if (!state.acceptingNow && !input.scheduledFor) throw new ApiError('SCHEDULE_REQUIRED', 'هذا المطعم يستقبل طلبًا مجدولًا فقط.');
    const phone = normalizeEgyptPhone(input.recipientPhone);
    if (!phone) throw new ApiError('INVALID_PHONE', 'رقم المستلم غير صحيح.');
    const address = await this.prisma.address.findUnique({ where: { id: input.addressId } });
    if (!address || address.userId !== userId) throw new ApiError('NOT_FOUND', 'العنوان غير موجود.', HttpStatus.NOT_FOUND);
    const cart = await this.prisma.cart.findUnique({ where: { userId_restaurantId: { userId, restaurantId } }, include: { items: true } });
    if (!cart?.items.length) throw new ApiError('CART_EMPTY', 'السلة فارغة.');
    const priced = await this.priceLines(restaurantId, cart.items);
    const offer = restaurant.offers[0];
    const discount = applyOffer(priced.foodMinor, offer?.percentOff ?? 0);
    if (discount.payableMinor < restaurant.minOrderMinor) {
      throw new ApiError('MIN_ORDER', `الحد الأدنى للطلب ${minorToLabel(restaurant.minOrderMinor)}.`);
    }
    const quote = await this.deliveryQuote(restaurant, address);
    const preferred = input.courierId ? await this.orders.chosenCourier(input.courierId, true) : null;
    const totalMinor = discount.payableMinor + quote.totalMinor;
    const order = await this.prisma.foodOrder.create({
      data: {
        publicNumber: `FD-${publicOrderNumber().slice(3)}`,
        idempotencyKey: input.idempotencyKey,
        userId,
        restaurantId,
        scheduledFor: input.scheduledFor ? new Date(input.scheduledFor) : null,
        dropoffName: address.name,
        dropoffLine: address.line,
        dropoffDetails: address.details,
        dropoffLat: address.lat,
        dropoffLng: address.lng,
        recipientName: input.recipientName.trim(),
        recipientPhone: phone,
        notes: input.notes?.trim(),
        preferredCourierId: preferred?.userId,
        foodMinor: priced.foodMinor,
        deliveryFeeMinor: quote.feeMinor,
        extraMinor: quote.extraMinor,
        discountMinor: discount.discountMinor,
        totalMinor,
        lines: {
          create: priced.lines.map((line) => ({
            itemId: line.itemId,
            name: line.name,
            quantity: line.quantity,
            unitMinor: line.unitMinor,
            options: line.options,
            note: line.note,
            lineTotalMinor: line.lineTotalMinor,
          })),
        },
        events: { create: { status: 'PENDING_RESTAURANT', note: 'بانتظار قبول المطعم' } },
      },
      include: { lines: true, restaurant: true, deliveryOrder: true },
    });
    await this.prisma.cartItem.deleteMany({ where: { cartId: cart.id } });
    return this.presentOrder(order);
  }

  async myOrders(userId: string) {
    const orders = await this.prisma.foodOrder.findMany({
      where: { userId },
      include: { lines: true, restaurant: true, deliveryOrder: true },
      orderBy: { createdAt: 'desc' },
      take: 40,
    });
    return Promise.all(orders.map((order) => this.presentOrder(order)));
  }

  async myOrder(userId: string, id: string) {
    const order = await this.ownedFood(userId, id);
    return this.presentOrder(order);
  }

  async cancel(userId: string, id: string) {
    const order = await this.ownedFood(userId, id);
    if (['REJECTED', 'CANCELLED'].includes(order.status)) throw new ApiError('CANCEL_NOT_ALLOWED', 'الطلب مغلق بالفعل.');
    if (order.deliveryOrder && !['SEARCHING', 'NO_COURIER'].includes(order.deliveryOrder.status)) {
      throw new ApiError('CANCEL_NOT_ALLOWED', 'المندوب بدأ التحرك. الإلغاء من صفحة التتبع.');
    }
    if (order.deliveryOrderId) await this.orders.cancelSearchingFood(order.deliveryOrderId, 'ألغى العميل طلب الطعام.');
    const updated = await this.prisma.foodOrder.update({
      where: { id: order.id },
      data: { status: 'CANCELLED', events: { create: { status: 'CANCELLED', note: 'ألغاه العميل' } } },
      include: { lines: true, restaurant: true, deliveryOrder: true },
    });
    return this.presentOrder(updated);
  }

  async review(userId: string, id: string, rating: number, comment?: string) {
    const order = await this.ownedFood(userId, id);
    if (order.deliveryOrder?.status !== 'DELIVERED') throw new ApiError('REVIEW_NOT_READY', 'تقييم المطعم متاح بعد التسليم.');
    const existing = await this.prisma.restaurantReview.findUnique({ where: { orderId: order.id } });
    if (existing) throw new ApiError('REVIEW_EXISTS', 'تم تقييم هذا الطلب من قبل.');
    if (!Number.isInteger(rating) || rating < 1 || rating > 5) throw new ApiError('INVALID_RATING', 'عدد النجوم يجب أن يكون بين 1 و 5.');
    const review = await this.prisma.restaurantReview.create({
      data: { orderId: order.id, userId, restaurantId: order.restaurantId, rating, comment: comment?.trim() || null },
    });
    return { id: review.id, rating: review.rating, comment: review.comment, restaurantId: review.restaurantId };
  }

  async portalOrders(userId: string) {
    const member = await this.membership(userId);
    const orders = await this.prisma.foodOrder.findMany({
      where: { restaurantId: member.restaurantId },
      include: { lines: true, restaurant: true, deliveryOrder: true },
      orderBy: { createdAt: 'desc' },
      take: 50,
    });
    return Promise.all(orders.map((order) => this.presentOrder(order)));
  }

  async accept(userId: string, id: string, prepMinutes: number) {
    const order = await this.restaurantOrder(userId, id);
    if (order.status !== 'PENDING_RESTAURANT') throw new ApiError('ORDER_STATE', 'لا يمكن قبول الطلب في هذه الحالة.');
    return this.move(order.id, 'ACCEPTED', `وقت التجهيز ${prepMinutes} دقيقة`, { prepMinutes });
  }

  async reject(userId: string, id: string, reason: string) {
    const order = await this.restaurantOrder(userId, id);
    if (order.status !== 'PENDING_RESTAURANT') throw new ApiError('ORDER_STATE', 'لا يمكن رفض الطلب في هذه الحالة.');
    return this.move(order.id, 'REJECTED', reason, { rejectReason: reason });
  }

  async preparing(userId: string, id: string) {
    const order = await this.restaurantOrder(userId, id);
    if (order.status !== 'ACCEPTED') throw new ApiError('ORDER_STATE', 'قبول الطلب يسبق التجهيز.');
    return this.move(order.id, 'PREPARING', 'المطعم يجهّز الطعام');
  }

  async ready(userId: string, id: string) {
    const order = await this.restaurantOrder(userId, id);
    if (order.status !== 'PREPARING' && order.status !== 'ACCEPTED') throw new ApiError('ORDER_STATE', 'الطلب لم يصل لمرحلة التجهيز.');
    const distanceMeters = estimatedRoadMeters(order.restaurant, { lat: order.dropoffLat, lng: order.dropoffLng });
    const delivery = await this.orders.createFromFood({
      foodOrderId: order.id,
      userId: order.userId,
      pickup: { name: order.restaurant.name, line: order.restaurant.addressLine, lat: order.restaurant.lat, lng: order.restaurant.lng },
      dropoff: { name: order.dropoffName, line: order.dropoffLine, details: order.dropoffDetails, lat: order.dropoffLat, lng: order.dropoffLng },
      recipientName: order.recipientName,
      recipientPhone: order.recipientPhone,
      notes: order.notes,
      description: order.lines.map((line) => `${line.quantity}× ${line.name}`).join('، '),
      foodMinor: order.foodMinor - order.discountMinor,
      deliveryFeeMinor: order.deliveryFeeMinor,
      serviceFeeMinor: order.extraMinor,
      distanceMeters,
      etaMinutes: order.restaurant.etaMinutes + (order.prepMinutes ?? 0),
      pricingVersion: 1,
      preferredCourierId: order.preferredCourierId,
    });
    return this.move(order.id, 'READY', 'الطعام جاهز للاستلام', { deliveryOrder: { connect: { id: delivery.id } } });
  }

  async createItem(userId: string, input: { sectionId: string; name: string; description?: string; priceMinor: number; kind?: MenuItemKind; imageUrl?: string }) {
    const member = await this.membership(userId);
    const section = await this.prisma.menuSection.findUnique({ where: { id: input.sectionId } });
    if (!section || section.restaurantId !== member.restaurantId) throw new ApiError('NOT_FOUND', 'قسم المنيو غير موجود.', HttpStatus.NOT_FOUND);
    const item = await this.prisma.menuItem.create({
      data: {
        restaurantId: member.restaurantId,
        sectionId: section.id,
        name: input.name.trim(),
        description: input.description?.trim(),
        priceMinor: input.priceMinor,
        kind: input.kind ?? 'ITEM',
        imageUrl: input.imageUrl,
      },
    });
    return { id: item.id, name: item.name, priceMinor: item.priceMinor };
  }

  async patchItem(userId: string, itemId: string, input: { available?: boolean; priceMinor?: number; name?: string; imageUrl?: string }) {
    const member = await this.membership(userId);
    const item = await this.prisma.menuItem.findUnique({ where: { id: itemId } });
    if (!item || item.restaurantId !== member.restaurantId) throw new ApiError('NOT_FOUND', 'الصنف غير موجود.', HttpStatus.NOT_FOUND);
    const updated = await this.prisma.menuItem.update({
      where: { id: item.id },
      data: {
        available: input.available,
        priceMinor: input.priceMinor,
        name: input.name?.trim(),
        imageUrl: input.imageUrl,
      },
    });
    return { id: updated.id, available: updated.available, priceMinor: updated.priceMinor, name: updated.name };
  }

  async sales(userId: string) {
    const member = await this.membership(userId);
    const orders = await this.prisma.foodOrder.findMany({
      where: { restaurantId: member.restaurantId, deliveryOrder: { status: 'DELIVERED' } },
    });
    const reviews = await this.prisma.restaurantReview.findMany({ where: { restaurantId: member.restaurantId } });
    const summary = summarizeRatings(reviews.map((review) => review.rating));
    return {
      deliveredCount: orders.length,
      salesMinor: orders.reduce((sum, order) => sum + order.foodMinor - order.discountMinor, 0),
      rating: summary.display,
      ratingCount: summary.count,
      ratingLabel: summary.label,
    };
  }

  private async move(id: string, status: 'ACCEPTED' | 'PREPARING' | 'READY' | 'REJECTED' | 'CANCELLED', note: string, extra: Prisma.FoodOrderUpdateInput = {}) {
    const updated = await this.prisma.foodOrder.update({
      where: { id },
      data: { status, ...extra, events: { create: { status, note } } },
      include: { lines: true, restaurant: true, deliveryOrder: true },
    });
    const titles: Record<typeof status, string> = {
      ACCEPTED: 'المطعم قبل الطلب',
      PREPARING: 'المطعم يجهّز الطعام',
      READY: 'الطعام جاهز وبدأ البحث عن مندوب',
      REJECTED: 'المطعم رفض الطلب',
      CANCELLED: 'تم إلغاء طلب الطعام',
    };
    const notification = await this.prisma.notification.create({
      data: { userId: updated.userId, type: 'TICKET_UPDATED', title: titles[status], body: note },
    });
    this.realtime.publish(updated.userId, { type: 'notification', notification });
    this.realtime.publish(updated.userId, { type: 'food.updated', foodOrderId: updated.id, status: updated.status });
    return this.presentOrder(updated);
  }

  private async restaurantOrder(userId: string, id: string) {
    const member = await this.membership(userId);
    const order = await this.prisma.foodOrder.findUnique({ where: { id }, include: { lines: true, restaurant: true, deliveryOrder: true } });
    if (!order || order.restaurantId !== member.restaurantId) throw new ApiError('NOT_FOUND', 'الطلب غير موجود.', HttpStatus.NOT_FOUND);
    return order;
  }

  private async membership(userId: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (user?.role === 'ADMIN') {
      const any = await this.prisma.restaurantMember.findFirst({ where: { userId } });
      if (any) return any;
    }
    const member = await this.prisma.restaurantMember.findFirst({ where: { userId } });
    if (!member) throw new ApiError('FORBIDDEN', 'هذه اللوحة خاصة بمطعمك.', HttpStatus.FORBIDDEN);
    return member;
  }

  private async ownedFood(userId: string, id: string) {
    const order = await this.prisma.foodOrder.findUnique({ where: { id }, include: { lines: true, restaurant: true, deliveryOrder: true, review: true } });
    if (!order || order.userId !== userId) throw new ApiError('NOT_FOUND', 'الطلب غير موجود.', HttpStatus.NOT_FOUND);
    return order;
  }

  private async cartView(userId: string, restaurantId: string) {
    const cart = await this.prisma.cart.findUnique({ where: { userId_restaurantId: { userId, restaurantId } }, include: { items: true } });
    if (!cart?.items.length) return { restaurantId, lines: [], foodMinor: 0, foodLabel: minorToLabel(0) };
    const priced = await this.priceLines(restaurantId, cart.items);
    return { restaurantId, ...priced, foodLabel: minorToLabel(priced.foodMinor) };
  }

  private async priceLines(restaurantId: string, items: Array<{ itemId: string; quantity: number; optionIds?: string[]; note?: string | null }>) {
    const rows = await this.prisma.menuItem.findMany({ where: { restaurantId, id: { in: items.map((item) => item.itemId) } }, include: itemInclude });
    const lines = items.map((item) => {
      const row = rows.find((candidate) => candidate.id === item.itemId);
      if (!row) throw new ApiError('ITEM_NOT_FOUND', 'صنف من مطعم آخر لا يمكن إضافته لهذا الطلب.');
      const priced = priceItem(row, item.optionIds ?? []);
      if ('error' in priced && priced.error) throw new ApiError('ITEM_UNAVAILABLE', priced.error);
      const result = priced as { unitMinor: number; options: Array<{ name: string; priceMinor: number; group: string }> };
      return {
        itemId: row.id,
        name: row.name,
        quantity: item.quantity,
        unitMinor: result.unitMinor,
        unitLabel: minorToLabel(result.unitMinor),
        options: result.options,
        optionIds: item.optionIds ?? [],
        note: item.note?.trim() || null,
        lineTotalMinor: result.unitMinor * item.quantity,
        lineLabel: minorToLabel(result.unitMinor * item.quantity),
      };
    });
    return { lines, foodMinor: lines.reduce((sum, line) => sum + line.lineTotalMinor, 0) };
  }

  private async deliveryQuote(pickup: { lat: number; lng: number }, dropoff: { lat: number; lng: number }) {
    const written = (pickup.lat === 0 && pickup.lng === 0) || (dropoff.lat === 0 && dropoff.lng === 0);
    if (!written && (!inEgypt(pickup) || !inEgypt(dropoff))) {
      throw new ApiError('OUT_OF_SERVICE_AREA', 'التوصيل متاح داخل مصر. اكتب المنطقة والمدينة.');
    }
    const rule = await this.prisma.pricingRule.findUnique({ where: { vehicle: 'MOTORCYCLE' } });
    if (!rule) throw new ApiError('PRICING_UNAVAILABLE', 'تعذر حساب رسوم التوصيل.');
    if (written) {
      const feeMinor = Math.max(rule.minFeeMinor, rule.baseFeeMinor);
      return { distanceMeters: 0, feeMinor, extraMinor: 0, totalMinor: feeMinor, extras: [], etaMinutes: 0, currency: 'EGP' as const, pricingVersion: rule.version };
    }
    try {
      const quote = buildQuote({
        distanceMeters: estimatedRoadMeters(pickup, dropoff),
        vehicle: 'MOTORCYCLE',
        size: 'SMALL',
        fragile: false,
        rule: { ...rule, allowedSizes: rule.allowedSizes as Array<'SMALL' | 'MEDIUM' | 'LARGE'> },
      });
      const config = await this.prisma.platformConfig.findUnique({ where: { id: 1 } });
      const serviceFeeMinor = config?.serviceFeeMinor ?? 0;
      if (serviceFeeMinor > 0) {
        quote.extras.push({ code: 'SERVICE', label: 'رسوم الخدمة', amountMinor: serviceFeeMinor });
        quote.extraMinor += serviceFeeMinor;
        quote.totalMinor += serviceFeeMinor;
      }
      return quote;
    } catch (error) {
      throw new ApiError('OUT_OF_RANGE', error instanceof Error ? error.message : 'العنوان خارج نطاق التوصيل.');
    }
  }

  private card(restaurant: { id: string; name: string; cuisine: string; category: string; coverColor: string; coverUrl: string | null; logoUrl: string | null; shift: 'OPEN' | 'CLOSED' | 'SCHEDULED'; acceptsScheduled: boolean; opensAt: string; closesAt: string; deliveryFeeMinor: number; etaMinutes: number; reviews?: Array<{ rating: number }> }) {
    const summary = summarizeRatings((restaurant.reviews ?? []).map((review) => review.rating));
    const state = orderingState(restaurant);
    const category = RESTAURANT_CATEGORIES.find((item) => item.code === restaurant.category);
    return {
      id: restaurant.id,
      name: restaurant.name,
      cuisine: restaurant.cuisine,
      category: restaurant.category,
      categoryLabel: category?.label ?? restaurant.cuisine,
      coverColor: restaurant.coverColor,
      coverUrl: restaurant.coverUrl,
      logoUrl: restaurant.logoUrl,
      etaMinutes: restaurant.etaMinutes,
      deliveryFeeMinor: restaurant.deliveryFeeMinor,
      deliveryFeeLabel: minorToLabel(restaurant.deliveryFeeMinor),
      rating: summary.display,
      ratingCount: summary.count,
      ratingLabel: summary.label,
      ordering: state,
    };
  }

  private async presentOrder(order: {
    id: string;
    publicNumber: string;
    status: string;
    rejectReason: string | null;
    prepMinutes: number | null;
    scheduledFor: Date | null;
    foodMinor: number;
    deliveryFeeMinor: number;
    extraMinor: number;
    discountMinor: number;
    totalMinor: number;
    notes: string | null;
    recipientName: string;
    dropoffLine: string;
    createdAt: Date;
    restaurant: { id: string; name: string };
    lines: Array<{ id: string; name: string; quantity: number; unitMinor: number; lineTotalMinor: number; options: Prisma.JsonValue; note: string | null }>;
    deliveryOrder: { id: string; status: string; courierId: string | null; etaMinutes: number } | null;
    review?: { rating: number; comment: string | null } | null;
  }) {
    const phase = this.phase(order.status, order.deliveryOrder);
    return {
      id: order.id,
      publicNumber: order.publicNumber,
      restaurant: order.restaurant,
      status: phase.code,
      statusTitle: phase.title,
      restaurantStatus: order.status,
      courierAssigned: Boolean(order.deliveryOrder?.courierId),
      foodReady: order.status === 'READY' || Boolean(order.deliveryOrder),
      prepMinutes: order.prepMinutes,
      scheduledFor: order.scheduledFor,
      rejectReason: order.rejectReason,
      notes: order.notes,
      recipientName: order.recipientName,
      dropoffLine: order.dropoffLine,
      foodMinor: order.foodMinor,
      foodLabel: minorToLabel(order.foodMinor),
      deliveryFeeMinor: order.deliveryFeeMinor + order.extraMinor,
      deliveryFeeLabel: minorToLabel(order.deliveryFeeMinor + order.extraMinor),
      discountMinor: order.discountMinor,
      discountLabel: minorToLabel(order.discountMinor),
      totalMinor: order.totalMinor,
      totalLabel: minorToLabel(order.totalMinor),
      paymentMethod: 'CASH',
      paymentLabel: 'نقدًا عند الاستلام',
      deliveryOrderId: order.deliveryOrder?.id ?? null,
      etaMinutes: order.deliveryOrder?.etaMinutes ?? null,
      review: order.review ?? null,
      lines: order.lines.map((line) => ({
        id: line.id,
        name: line.name,
        quantity: line.quantity,
        unitMinor: line.unitMinor,
        lineTotalMinor: line.lineTotalMinor,
        lineLabel: minorToLabel(line.lineTotalMinor),
        options: line.options,
        note: line.note,
      })),
      createdAt: order.createdAt,
    };
  }

  private phase(status: string, delivery: { status: string; courierId: string | null } | null) {
    if (status === 'REJECTED') return { code: 'REJECTED', title: 'رفض المطعم الطلب' };
    if (status === 'CANCELLED') return { code: 'CANCELLED', title: 'تم الإلغاء' };
    if (status === 'PENDING_RESTAURANT') return { code: 'PENDING_RESTAURANT', title: 'في انتظار قبول المطعم' };
    if (status === 'ACCEPTED') return { code: 'ACCEPTED', title: 'تم قبول الطلب' };
    if (status === 'PREPARING') return { code: 'PREPARING', title: 'جارٍ تجهيز الطعام' };
    if (!delivery) return { code: 'READY', title: 'الطعام جاهز' };
    if (delivery.status === 'NO_COURIER') return { code: 'NO_COURIER', title: 'تعذر العثور على مندوب' };
    if (delivery.status === 'SEARCHING') return { code: 'READY', title: 'الطعام جاهز' };
    if (delivery.status === 'CANCELLED') return { code: 'CANCELLED', title: 'تم الإلغاء' };
    if (!delivery.courierId) return { code: 'READY', title: 'الطعام جاهز' };
    if (delivery.status === 'ACCEPTED' || delivery.status === 'EN_ROUTE_PICKUP') return { code: 'COURIER_ASSIGNED', title: 'تم تعيين المندوب' };
    if (delivery.status === 'PICKED_UP') return { code: 'PICKED_UP', title: 'المندوب استلم الطلب' };
    if (delivery.status === 'EN_ROUTE_DROPOFF') return { code: 'ON_THE_WAY', title: 'الطلب في الطريق' };
    if (delivery.status === 'DELIVERED') return { code: 'DELIVERED', title: 'تم التسليم' };
    return { code: status, title: status };
  }

  private async seedCatalog() {
    const places = [
      this.place('grill-house', 'بيت المشاوي', 'مشويات', 'GRILL', 'OPEN', false, 40, 3500, '#087F78', 30.062, 31.34),
      this.place('pizza-oven', 'فرن البيتزا', 'بيتزا', 'PIZZA', 'OPEN', false, 35, 3000, '#0E6B66', 30.051, 31.28),
      this.place('station-burger', 'برجر المحطة', 'برجر', 'BURGER', 'CLOSED', false, 30, 2800, '#172334', 30.07, 31.32),
      this.place('happy-sweets', 'حلواني السعادة', 'حلويات', 'DESSERT', 'SCHEDULED', true, 45, 2500, '#C47B2B', 30.044, 31.24),
      this.place('koshary-tarek', 'كشري أبو طارق', 'أكل شرقي', 'EASTERN', 'OPEN', false, 25, 2500, '#087F78', 30.08, 31.3, 8000),
    ];
    for (const place of places) {
      const restaurant = await this.prisma.restaurant.create({ data: place.data });
      if (place.offer) {
        await this.prisma.restaurantOffer.create({ data: { restaurantId: restaurant.id, title: place.offer, percentOff: 10 } });
      }
      const meals = await this.prisma.menuSection.create({ data: { restaurantId: restaurant.id, name: 'الوجبات', sort: 1 } });
      const drinks = await this.prisma.menuSection.create({ data: { restaurantId: restaurant.id, name: 'المشروبات', sort: 2 } });
      const main = await this.prisma.menuItem.create({
        data: {
          restaurantId: restaurant.id,
          sectionId: meals.id,
          name: place.main,
          description: place.description,
          priceMinor: place.price,
          kind: place.combo ? 'COMBO' : 'ITEM',
          available: place.available,
        },
      });
      const size = await this.prisma.itemOptionGroup.create({
        data: { itemId: main.id, name: 'الحجم', required: true, minSelect: 1, maxSelect: 1 },
      });
      await this.prisma.itemOption.createMany({
        data: [
          { groupId: size.id, name: 'عادي', priceMinor: 0 },
          { groupId: size.id, name: 'كبير', priceMinor: 2000 },
        ],
      });
      const extras = await this.prisma.itemOptionGroup.create({
        data: { itemId: main.id, name: 'إضافات', required: false, minSelect: 0, maxSelect: 3 },
      });
      await this.prisma.itemOption.createMany({
        data: [
          { groupId: extras.id, name: 'بدون بصل', priceMinor: 0 },
          { groupId: extras.id, name: 'جبنة إضافية', priceMinor: 1500 },
        ],
      });
      await this.prisma.menuItem.create({
        data: { restaurantId: restaurant.id, sectionId: drinks.id, name: 'مشروب غازي', description: 'علبة باردة', priceMinor: 1500 },
      });
    }
  }

  private place(
    slug: string,
    name: string,
    cuisine: string,
    category: 'GRILL' | 'PIZZA' | 'BURGER' | 'DESSERT' | 'EASTERN',
    shift: 'OPEN' | 'CLOSED' | 'SCHEDULED',
    acceptsScheduled: boolean,
    etaMinutes: number,
    deliveryFeeMinor: number,
    coverColor: string,
    lat: number,
    lng: number,
    minOrderMinor = 0,
  ) {
    return {
      data: {
        slug,
        name,
        cuisine,
        category,
        description: `${name} داخل نطاق توصيل دليفريه.`,
        phone: '+201000000099',
        addressLine: 'القاهرة',
        lat,
        lng,
        shift,
        acceptsScheduled,
        opensAt: '10:00',
        closesAt: '23:30',
        minOrderMinor,
        deliveryFeeMinor,
        etaMinutes,
        coverColor,
      },
      main: cuisine,
      description: 'طبق من المنيو اليومي.',
      price: 7500,
      combo: category === 'BURGER',
      available: category !== 'DESSERT',
      offer: category === 'EASTERN' ? 'خصم 10% على الطلب' : null,
    };
  }
}
