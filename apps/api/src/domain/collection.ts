export type DeliveryPayer = 'RECIPIENT' | 'BUSINESS';

export type SettlementStatus =
  | 'NOT_REQUIRED'
  | 'PENDING_COLLECTION'
  | 'COLLECTED'
  | 'AWAITING_SETTLEMENT'
  | 'PARTIAL'
  | 'SETTLED'
  | 'DISPUTED';

export class CollectionError extends Error {
  constructor(readonly code: 'INVALID_GOODS' | 'INVALID_FEE' | 'COD_LIMIT' | 'PREPAID_CONFLICT') {
    super(code);
  }
}

export const SETTLEMENT_LABEL: Record<SettlementStatus, string> = {
  NOT_REQUIRED: 'لا توجد تسوية',
  PENDING_COLLECTION: 'في انتظار التحصيل',
  COLLECTED: 'تم التحصيل',
  AWAITING_SETTLEMENT: 'في انتظار التسوية',
  PARTIAL: 'تسوية جزئية',
  SETTLED: 'تمت التسوية',
  DISPUTED: 'متنازع عليها',
};

export function planCollection(input: {
  goodsMinor: number;
  goodsPrepaid: boolean;
  collectGoods: boolean;
  deliveryPayer: DeliveryPayer;
  deliveryFeeMinor: number;
  maxCollectMinor: number;
}) {
  if (!Number.isInteger(input.goodsMinor) || input.goodsMinor < 0) {
    throw new CollectionError('INVALID_GOODS');
  }
  if (!Number.isInteger(input.deliveryFeeMinor) || input.deliveryFeeMinor < 0) {
    throw new CollectionError('INVALID_FEE');
  }
  if (input.goodsPrepaid && input.collectGoods) {
    throw new CollectionError('PREPAID_CONFLICT');
  }
  const collectGoods = input.goodsPrepaid ? false : input.collectGoods;
  const goodsCollected = collectGoods ? input.goodsMinor : 0;
  const deliveryCollected = input.deliveryPayer === 'RECIPIENT' ? input.deliveryFeeMinor : 0;
  const collectMinor = goodsCollected + deliveryCollected;
  if (collectMinor > input.maxCollectMinor) throw new CollectionError('COD_LIMIT');
  const businessDueMinor = goodsCollected;
  const shopDeliveryChargeMinor = input.deliveryPayer === 'BUSINESS' ? input.deliveryFeeMinor : 0;
  let settlementStatus: SettlementStatus = 'NOT_REQUIRED';
  if (collectMinor > 0) settlementStatus = 'PENDING_COLLECTION';
  else if (shopDeliveryChargeMinor > 0 || businessDueMinor > 0) settlementStatus = 'AWAITING_SETTLEMENT';
  return {
    goodsMinor: input.goodsMinor,
    goodsPrepaid: input.goodsPrepaid,
    collectGoods,
    deliveryPayer: input.deliveryPayer,
    deliveryFeeMinor: input.deliveryFeeMinor,
    collectMinor,
    businessDueMinor,
    shopDeliveryChargeMinor,
    settlementStatus,
    goodsVerified: false,
  };
}

export function collectionLabels(plan: ReturnType<typeof planCollection>) {
  return {
    ...plan,
    goodsLabel: minor(plan.goodsMinor),
    deliveryLabel: minor(plan.deliveryFeeMinor),
    collectLabel: minor(plan.collectMinor),
    businessDueLabel: minor(plan.businessDueMinor),
    shopDeliveryChargeLabel: minor(plan.shopDeliveryChargeMinor),
    settlementLabel: SETTLEMENT_LABEL[plan.settlementStatus],
    goodsNote: 'قيمة المنتجات كما أدخلها التاجر، وليست مبلغًا موثقًا من المنصة.',
  };
}

function minor(value: number) {
  const pounds = value / 100;
  const text = Number.isInteger(pounds) ? String(pounds) : pounds.toFixed(2);
  return `${text} ج.م`;
}
