export type VehicleType = 'MOTORCYCLE' | 'CAR';
export type ParcelSize = 'SMALL' | 'MEDIUM' | 'LARGE';

export interface PricingRule {
  vehicle: VehicleType;
  baseFeeMinor: number;
  perKmMinor: number;
  minFeeMinor: number;
  maxDistanceMeters: number;
  fragileSurchargeMinor: number;
  mediumSurchargeMinor: number;
  largeSurchargeMinor: number;
  maxWeightKg: number;
  allowedSizes: ParcelSize[];
  version: number;
}

export interface ExtraLine {
  code: string;
  label: string;
  amountMinor: number;
}

export interface Quote {
  distanceMeters: number;
  feeMinor: number;
  extraMinor: number;
  totalMinor: number;
  extras: ExtraLine[];
  etaMinutes: number;
  currency: 'EGP';
  pricingVersion: number;
}

export type QuoteErrorCode =
  | 'DISTANCE_TOO_SHORT'
  | 'DISTANCE_TOO_LONG'
  | 'SIZE_NOT_ALLOWED'
  | 'VEHICLE_UNAVAILABLE';

export class QuoteError extends Error {
  constructor(
    readonly code: QuoteErrorCode,
    message: string,
  ) {
    super(message);
  }
}

const SIZE_LABEL: Record<ParcelSize, string> = {
  SMALL: 'حجم صغير',
  MEDIUM: 'حجم متوسط',
  LARGE: 'حجم كبير',
};

export function buildQuote(input: {
  distanceMeters: number;
  vehicle: VehicleType;
  size: ParcelSize;
  fragile: boolean;
  rule: PricingRule;
}): Quote {
  const { distanceMeters, vehicle, size, fragile, rule } = input;
  if (distanceMeters < 200) {
    throw new QuoteError('DISTANCE_TOO_SHORT', 'عنوانا الاستلام والتسليم قريبان جدًا.');
  }
  if (distanceMeters > rule.maxDistanceMeters) {
    throw new QuoteError(
      'DISTANCE_TOO_LONG',
      'المسافة أبعد من نطاق هذه الوسيلة. جرّب سيارة أو قسّم الطلب.',
    );
  }
  if (!rule.allowedSizes.includes(size)) {
    throw new QuoteError(
      'SIZE_NOT_ALLOWED',
      vehicle === 'MOTORCYCLE'
        ? 'الموتوسيكل لا يناسب هذا الحجم. اختر سيارة.'
        : 'هذا الحجم غير متاح للوسيلة المختارة.',
    );
  }

  const km = distanceMeters / 1000;
  const distanceFee = Math.round(km * rule.perKmMinor);
  const feeMinor = Math.max(rule.minFeeMinor, rule.baseFeeMinor + distanceFee);
  const extras: ExtraLine[] = [];
  if (size === 'MEDIUM' && rule.mediumSurchargeMinor > 0) {
    extras.push({
      code: 'SIZE_MEDIUM',
      label: SIZE_LABEL.MEDIUM,
      amountMinor: rule.mediumSurchargeMinor,
    });
  }
  if (size === 'LARGE' && rule.largeSurchargeMinor > 0) {
    extras.push({
      code: 'SIZE_LARGE',
      label: SIZE_LABEL.LARGE,
      amountMinor: rule.largeSurchargeMinor,
    });
  }
  if (fragile && rule.fragileSurchargeMinor > 0) {
    extras.push({
      code: 'FRAGILE',
      label: 'قابل للكسر',
      amountMinor: rule.fragileSurchargeMinor,
    });
  }
  const extraMinor = extras.reduce((sum, line) => sum + line.amountMinor, 0);
  const speedKmh = vehicle === 'MOTORCYCLE' ? 24 : 20;
  const travelMinutes = Math.round((km / speedKmh) * 60);
  const etaMinutes = Math.max(12, travelMinutes + 8);

  return {
    distanceMeters,
    feeMinor,
    extraMinor,
    totalMinor: feeMinor + extraMinor,
    extras,
    etaMinutes,
    currency: 'EGP',
    pricingVersion: rule.version,
  };
}
