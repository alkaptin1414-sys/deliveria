import { cancelPolicy } from './cancel-policy';
import { applyOffer, orderingState, priceItem } from './food';
import { assertCommentAllowed, summarizeRatings, tagsForRating } from './rating';
import { CollectionError, planCollection } from './collection';
import { buildQuote, QuoteError } from './pricing';
import { normalizeEgyptPhone } from './phone';
import { assertTransition, customerCanCancel, TransitionError } from './order-state';
import { buildEarningsReport, cairoDayStart, courierCanTake, courierOrderContact, courierPayoutMinor, requiredDocs, weekStart } from './courier';
import { platformMinorFromBps } from './money';
import { customerTracking } from './tracking';
import { estimatedRoadMeters, findServiceArea } from './geo';

const motorcycle = {
  vehicle: 'MOTORCYCLE' as const,
  baseFeeMinor: 2000,
  perKmMinor: 450,
  minFeeMinor: 2500,
  maxDistanceMeters: 25000,
  fragileSurchargeMinor: 800,
  mediumSurchargeMinor: 500,
  largeSurchargeMinor: 0,
  maxWeightKg: 10,
  allowedSizes: ['SMALL', 'MEDIUM'] as Array<'SMALL' | 'MEDIUM' | 'LARGE'>,
  version: 1,
};

describe('live tracking', () => {
  const now = new Date('2026-10-17T12:00:00Z');
  it('shows a courier position only while heading to the customer and recently updated', () => {
    expect(customerTracking({ status: 'SEARCHING', lat: 30, lng: 31, updatedAt: now, now }).lat).toBeNull();
    expect(customerTracking({ status: 'ACCEPTED', lat: 30, lng: 31, updatedAt: now, now }).lat).toBe(30);
    expect(customerTracking({ status: 'DELIVERED', lat: 30, lng: 31, updatedAt: now, now }).active).toBe(false);
    const fresh = customerTracking({ status: 'EN_ROUTE_DROPOFF', lat: 30.1, lng: 31.2, updatedAt: new Date(now.getTime() - 20_000), now });
    expect(fresh.fresh).toBe(true);
    expect(fresh.lat).toBe(30.1);
    const stale = customerTracking({ status: 'EN_ROUTE_DROPOFF', lat: 30.1, lng: 31.2, updatedAt: new Date(now.getTime() - 180_000), now });
    expect(stale.fresh).toBe(false);
    expect(stale.lat).toBe(30.1);
  });
});

describe('courier policy', () => {
  it('pays the delivery fee only and matches vehicles strictly', () => {
    expect(courierPayoutMinor(3500)).toBe(3500);
    expect(courierCanTake('MOTORCYCLE', 'MOTORCYCLE')).toBe(true);
    expect(courierCanTake('CAR', 'MOTORCYCLE')).toBe(false);
    expect(courierCanTake('BICYCLE', 'MOTORCYCLE')).toBe(false);
    expect(requiredDocs('CAR')).toContain('LICENSE');
    expect(requiredDocs('BICYCLE')).not.toContain('LICENSE');
    const saturday = weekStart(new Date('2026-10-17T12:00:00'));
    expect(saturday.getDay()).toBe(6);
  });

  it('counts delivered earnings once in Cairo periods and keeps payouts after commission', () => {
    const now = new Date('2026-10-18T15:00:00.000Z');
    expect(cairoDayStart(now).toISOString()).toBe('2026-10-17T21:00:00.000Z');
    const report = buildEarningsReport(
      now,
      [
        { orderId: 'a', status: 'DELIVERED', publicNumber: 'A-1', payoutMinor: 4500, feeMinor: 5000, platformMinor: 500, cashCollectedMinor: 0, createdAt: new Date('2026-10-18T10:00:00.000Z'), deliveredAt: new Date('2026-10-18T10:00:00.000Z') },
        { orderId: 'a', status: 'DELIVERED', publicNumber: 'A-1', payoutMinor: 4500, feeMinor: 5000, platformMinor: 500, cashCollectedMinor: 0, createdAt: new Date('2026-10-18T10:00:00.000Z'), deliveredAt: new Date('2026-10-18T10:00:00.000Z') },
        { orderId: 'b', status: 'DELIVERED', publicNumber: 'B-2', payoutMinor: 4000, feeMinor: 4000, platformMinor: 0, cashCollectedMinor: 0, createdAt: new Date('2026-10-17T08:00:00.000Z'), deliveredAt: new Date('2026-10-17T08:00:00.000Z') },
        { orderId: 'c', status: 'DELIVERED', publicNumber: 'C-3', payoutMinor: 2700, feeMinor: 3000, platformMinor: 300, cashCollectedMinor: 1500, createdAt: new Date('2026-09-15T10:00:00.000Z'), deliveredAt: new Date('2026-09-15T10:00:00.000Z') },
        { orderId: 'd', status: 'CANCELLED', publicNumber: 'D-4', payoutMinor: 9000, feeMinor: 9000, platformMinor: 0, cashCollectedMinor: 0, createdAt: new Date('2026-10-18T11:00:00.000Z'), deliveredAt: null },
      ],
      [{ id: 's1', kind: 'WAGE_PAID', amountMinor: 2000, reason: 'صرف أجر', createdAt: new Date('2026-10-18T12:00:00.000Z') }],
    );
    expect(report.orders.map((row) => row.orderId)).toEqual(['a', 'b', 'c']);
    expect(report.totalMinor).toBe(11200);
    expect(report.periods.today.payoutMinor).toBe(4500);
    expect(report.periods.today.orderCount).toBe(1);
    expect(report.periods.today.platformMinor).toBe(500);
    expect(report.periods.today.netMinor).toBe(2500);
    expect(report.periods.week.payoutMinor).toBe(8500);
    expect(report.periods.week.orderCount).toBe(2);
    expect(report.periods.month.payoutMinor).toBe(8500);
    expect(report.periods.month.orderCount).toBe(2);
    expect(report.periods.all.orderCount).toBe(3);
    expect(report.periods.all.platformMinor).toBe(800);
    expect(report.unsettledWageMinor).toBe(9200);
    expect(report.paidWageMinor).toBe(2000);
    expect(report.periods.all.payoutMinor).toBe(report.orders.reduce((sum, row) => sum + row.payoutMinor, 0));
  });

  it('gives the assigned courier the order phone only while the job is active', () => {
    const order = { status: 'EN_ROUTE_DROPOFF', courierId: 'courier-1', recipientName: 'منى', recipientPhone: '+201012345678' };
    expect(courierOrderContact(order, 'courier-1')).toEqual({ name: 'منى', phone: '+201012345678' });
    expect(courierOrderContact(order, 'courier-2')).toBeNull();
    expect(courierOrderContact({ ...order, status: 'SEARCHING', courierId: null }, 'courier-1')).toBeNull();
    expect(courierOrderContact({ ...order, status: 'DELIVERED' }, 'courier-1')).toBeNull();
    expect(courierOrderContact({ ...order, status: 'CANCELLED' }, 'courier-1')).toBeNull();
  });

  it('splits a delivery fee by basis points without charging cancelled work', () => {
    expect(platformMinorFromBps(5000, 1000)).toBe(500);
    expect(5000 - platformMinorFromBps(5000, 1000)).toBe(4500);
    expect(platformMinorFromBps(1, 1)).toBe(0);
    expect(platformMinorFromBps(100, 50)).toBe(1);
  });
});

describe('phone', () => {
  it('accepts Egyptian mobiles and normalizes them', () => {
    expect(normalizeEgyptPhone('01012345678')).toBe('+201012345678');
    expect(normalizeEgyptPhone('+20 11 1234 5678')).toBe('+201112345678');
    expect(normalizeEgyptPhone('012000')).toBeNull();
    expect(normalizeEgyptPhone('01312345678')).toBeNull();
  });
});

describe('pricing', () => {
  it('uses the server rule and adds fragile surcharge', () => {
    const quote = buildQuote({
      distanceMeters: 4000,
      vehicle: 'MOTORCYCLE',
      size: 'SMALL',
      fragile: true,
      rule: motorcycle,
    });
    expect(quote.feeMinor).toBe(2000 + Math.round(4 * 450));
    expect(quote.extraMinor).toBe(800);
    expect(quote.totalMinor).toBe(quote.feeMinor + 800);
  });

  it('rejects a large parcel on a motorcycle', () => {
    expect(() =>
      buildQuote({
        distanceMeters: 3000,
        vehicle: 'MOTORCYCLE',
        size: 'LARGE',
        fragile: false,
        rule: motorcycle,
      }),
    ).toThrow(QuoteError);
  });

  it('enforces the minimum fee', () => {
    const quote = buildQuote({
      distanceMeters: 500,
      vehicle: 'MOTORCYCLE',
      size: 'SMALL',
      fragile: false,
      rule: motorcycle,
    });
    expect(quote.feeMinor).toBe(2500);
  });
});

describe('order state', () => {
  it('allows the courier path and blocks skipping steps', () => {
    expect(() => assertTransition('SEARCHING', 'ACCEPTED', 'COURIER')).not.toThrow();
    expect(() => assertTransition('SEARCHING', 'DELIVERED', 'CUSTOMER')).toThrow(TransitionError);
    expect(customerCanCancel('EN_ROUTE_PICKUP')).toBe(true);
    expect(customerCanCancel('PICKED_UP')).toBe(false);
  });
});

describe('collection', () => {
  const fee = 2500;
  it('collects goods and delivery from the recipient', () => {
    const plan = planCollection({
      goodsMinor: 50000,
      goodsPrepaid: false,
      collectGoods: true,
      deliveryPayer: 'RECIPIENT',
      deliveryFeeMinor: fee,
      maxCollectMinor: 200000,
    });
    expect(plan.collectMinor).toBe(52500);
    expect(plan.businessDueMinor).toBe(50000);
    expect(plan.settlementStatus).toBe('PENDING_COLLECTION');
  });

  it('lets the shop pay delivery while the courier still collects the goods', () => {
    const plan = planCollection({
      goodsMinor: 50000,
      goodsPrepaid: false,
      collectGoods: true,
      deliveryPayer: 'BUSINESS',
      deliveryFeeMinor: fee,
      maxCollectMinor: 200000,
    });
    expect(plan.collectMinor).toBe(50000);
    expect(plan.shopDeliveryChargeMinor).toBe(fee);
  });

  it('does not collect prepaid goods again', () => {
    const plan = planCollection({
      goodsMinor: 50000,
      goodsPrepaid: true,
      collectGoods: false,
      deliveryPayer: 'RECIPIENT',
      deliveryFeeMinor: fee,
      maxCollectMinor: 200000,
    });
    expect(plan.collectMinor).toBe(fee);
    expect(plan.businessDueMinor).toBe(0);
    expect(plan.collectGoods).toBe(false);
  });

  it('rejects a cash collection above the courier limit', () => {
    expect(() =>
      planCollection({
        goodsMinor: 500000,
        goodsPrepaid: false,
        collectGoods: true,
        deliveryPayer: 'RECIPIENT',
        deliveryFeeMinor: fee,
        maxCollectMinor: 200000,
      }),
    ).toThrow(CollectionError);
  });
});

describe('cancel policy', () => {
  it('is free before the courier moves and blocked after pickup', () => {
    expect(cancelPolicy({ status: 'SEARCHING', deliveryFeeMinor: 2500, goodsMinor: 0, alreadyCancelled: false }).feeMinor).toBe(0);
    expect(cancelPolicy({ status: 'EN_ROUTE_PICKUP', deliveryFeeMinor: 2500, goodsMinor: 50000, alreadyCancelled: false }).allowed).toBe(true);
    expect(cancelPolicy({ status: 'PICKED_UP', deliveryFeeMinor: 2500, goodsMinor: 50000, alreadyCancelled: false }).allowed).toBe(false);
    expect(cancelPolicy({ status: 'DELIVERED', deliveryFeeMinor: 2500, goodsMinor: 0, alreadyCancelled: false }).allowed).toBe(false);
  });
});

describe('ratings', () => {
  it('averages counted stars to one decimal', () => {
    const summary = summarizeRatings([5, 4, 5, 3, 5]);
    expect(summary.sum).toBe(22);
    expect(summary.exact).toBeCloseTo(4.4);
    expect(summary.display).toBe(4.4);
    expect(summary.histogram[5]).toBe(3);
  });

  it('does not treat an empty profile as a bad score', () => {
    expect(summarizeRatings([]).label).toBe('لا توجد تقييمات بعد');
    expect(summarizeRatings([]).display).toBeNull();
  });

  it('offers different reasons for low and high scores', () => {
    expect(tagsForRating(5)).toContain('حسن التعامل');
    expect(tagsForRating(1)).toContain('التأخير');
    expect(tagsForRating(5)).not.toContain('التأخير');
  });

  it('rejects phone numbers inside comments', () => {
    expect(assertCommentAllowed('كلمني 01012345678')).toBeTruthy();
    expect(assertCommentAllowed('التسليم كان واضح')).toBeNull();
  });
});

describe('food', () => {
  it('prices paid extras and rejects an unavailable item', () => {
    const item = {
      available: true,
      priceMinor: 8000,
      groups: [
        {
          name: 'إضافات',
          required: false,
          minSelect: 0,
          maxSelect: 2,
          options: [
            { id: 'cheese', name: 'جبنة', priceMinor: 1500, available: true },
            { id: 'onion', name: 'بدون بصل', priceMinor: 0, available: true },
          ],
        },
      ],
    };
    expect(priceItem(item, ['cheese', 'onion']).unitMinor).toBe(9500);
    expect(priceItem({ ...item, available: false }, []).error).toBeTruthy();
  });

  it('blocks a closed restaurant that does not take scheduled orders', () => {
    const state = orderingState({ shift: 'CLOSED', acceptsScheduled: false, opensAt: '10:00', closesAt: '23:00' });
    expect(state.acceptingNow).toBe(false);
    expect(state.scheduledOnly).toBe(false);
    expect(applyOffer(10000, 10).payableMinor).toBe(9000);
  });
});

describe('geo', () => {
  it('estimates a longer road distance than the straight line', () => {
    const meters = estimatedRoadMeters(
      { lat: 30.0444, lng: 31.2357 },
      { lat: 30.0626, lng: 31.2497 },
    );
    expect(meters).toBeGreaterThan(1500);
  });

  it('matches a configured service box', () => {
    const area = findServiceArea(
      { lat: 30.05, lng: 31.24 },
      [
        {
          name: 'القاهرة',
          minLat: 29.9,
          maxLat: 30.2,
          minLng: 31.1,
          maxLng: 31.5,
          motorcycles: true,
          cars: true,
          active: true,
        },
      ],
    );
    expect(area?.name).toBe('القاهرة');
  });
});
