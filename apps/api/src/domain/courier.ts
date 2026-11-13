import { haversineMeters } from './geo';

export const COURIER_MATCH_METERS = 20_000;

export const GOVERNORATES = [
  'القاهرة',
  'الجيزة',
  'القليوبية',
  'الإسكندرية',
  'الشرقية',
  'الدقهلية',
  'الغربية',
  'المنوفية',
  'البحيرة',
  'كفر الشيخ',
  'دمياط',
  'بورسعيد',
  'الإسماعيلية',
  'السويس',
  'الفيوم',
  'بني سويف',
  'المنيا',
  'أسيوط',
  'سوهاج',
  'قنا',
  'الأقصر',
  'أسوان',
  'البحر الأحمر',
  'الوادي الجديد',
  'مطروح',
  'شمال سيناء',
  'جنوب سيناء',
];

const ACTIVE = ['ACCEPTED', 'EN_ROUTE_PICKUP', 'PICKED_UP', 'EN_ROUTE_DROPOFF'] as const;

export function isActiveDelivery(status: string): boolean {
  return (ACTIVE as readonly string[]).includes(status);
}

export function courierOrderContact(
  order: { status: string; courierId: string | null; recipientName: string; recipientPhone: string },
  viewerId: string,
): { name: string; phone: string } | null {
  if (!order.courierId || order.courierId !== viewerId) return null;
  if (!isActiveDelivery(order.status)) return null;
  const phone = order.recipientPhone.trim();
  if (!phone) return null;
  return { name: order.recipientName.trim(), phone };
}

export function requiredDocs(vehicle: 'MOTORCYCLE' | 'CAR' | 'BICYCLE' | 'OTHER'): Array<'PORTRAIT' | 'NATIONAL_ID' | 'LICENSE' | 'VEHICLE_REGISTRATION'> {
  const base = ['PORTRAIT', 'NATIONAL_ID'] as Array<'PORTRAIT' | 'NATIONAL_ID' | 'LICENSE' | 'VEHICLE_REGISTRATION'>;
  if (vehicle === 'MOTORCYCLE' || vehicle === 'CAR') return [...base, 'LICENSE', 'VEHICLE_REGISTRATION'];
  return base;
}

export function courierCanTake(vehicle: 'MOTORCYCLE' | 'CAR' | 'BICYCLE' | 'OTHER', orderVehicle: 'MOTORCYCLE' | 'CAR'): boolean {
  if (vehicle === 'BICYCLE' || vehicle === 'OTHER') return false;
  return vehicle === orderVehicle;
}

export function courierPayoutMinor(feeMinor: number): number {
  if (!Number.isInteger(feeMinor) || feeMinor < 0) throw new Error('INVALID_FEE');
  return feeMinor;
}

export function withinMatch(courier: { lat: number; lng: number }, pickup: { lat: number; lng: number }): boolean {
  return haversineMeters(courier, pickup) <= COURIER_MATCH_METERS;
}

export function weekStart(now: Date): Date {
  const start = new Date(now);
  start.setHours(0, 0, 0, 0);
  const sinceSaturday = (start.getDay() + 1) % 7;
  start.setDate(start.getDate() - sinceSaturday);
  return start;
}

export function dayStart(now: Date): Date {
  const start = new Date(now);
  start.setHours(0, 0, 0, 0);
  return start;
}

const CAIRO = 'Africa/Cairo';

function timeZoneOffsetMs(date: Date, timeZone: string): number {
  const dtf = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });
  const parts: Record<string, string> = {};
  for (const part of dtf.formatToParts(date)) {
    if (part.type !== 'literal') parts[part.type] = part.value;
  }
  const hour = Number(parts.hour) % 24;
  const asUtc = Date.UTC(Number(parts.year), Number(parts.month) - 1, Number(parts.day), hour, Number(parts.minute), Number(parts.second));
  return asUtc - date.getTime();
}

function zonedStart(now: Date, year: number, month: number, day: number, timeZone: string): Date {
  const offset = timeZoneOffsetMs(now, timeZone);
  let start = new Date(Date.UTC(year, month, day) - offset);
  const atStart = timeZoneOffsetMs(start, timeZone);
  if (atStart !== offset) start = new Date(Date.UTC(year, month, day) - atStart);
  return start;
}

export function cairoDayStart(now: Date): Date {
  const offset = timeZoneOffsetMs(now, CAIRO);
  const local = new Date(now.getTime() + offset);
  return zonedStart(now, local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate(), CAIRO);
}

export function cairoWeekStart(now: Date): Date {
  const day = cairoDayStart(now);
  const offset = timeZoneOffsetMs(day, CAIRO);
  const weekday = new Date(day.getTime() + offset).getUTCDay();
  const sinceSaturday = (weekday + 1) % 7;
  return new Date(day.getTime() - sinceSaturday * 86_400_000);
}

export function cairoMonthStart(now: Date): Date {
  const offset = timeZoneOffsetMs(now, CAIRO);
  const local = new Date(now.getTime() + offset);
  return zonedStart(now, local.getUTCFullYear(), local.getUTCMonth(), 1, CAIRO);
}

export type EarningRow = {
  orderId: string;
  status: string;
  publicNumber: string;
  payoutMinor: number;
  feeMinor: number;
  platformMinor: number;
  cashCollectedMinor: number;
  createdAt: Date;
  deliveredAt: Date | null;
};

export type SettlementRow = {
  id: string;
  kind: 'WAGE_PAID' | 'CASH_REMITTED' | 'ADJUSTMENT';
  amountMinor: number;
  reason: string;
  createdAt: Date;
};

export type EarningsPeriodKey = 'today' | 'week' | 'month' | 'all';

function cairoLabel(date: Date): string {
  return new Intl.DateTimeFormat('ar-EG', { timeZone: CAIRO, day: 'numeric', month: 'long', year: 'numeric' }).format(date);
}

function periodBounds(now: Date): Record<EarningsPeriodKey, Date | null> {
  return {
    today: cairoDayStart(now),
    week: cairoWeekStart(now),
    month: cairoMonthStart(now),
    all: null,
  };
}

function periodTitle(key: EarningsPeriodKey, from: Date | null, now: Date): string {
  if (key === 'today') return `اليوم · ${cairoLabel(now)}`;
  if (key === 'week' && from) return `هذا الأسبوع · من ${cairoLabel(from)} إلى ${cairoLabel(now)}`;
  if (key === 'month' && from) return `هذا الشهر · ${new Intl.DateTimeFormat('ar-EG', { timeZone: CAIRO, month: 'long', year: 'numeric' }).format(now)}`;
  return `كل الفترات حتى ${cairoLabel(now)}`;
}

export function buildEarningsReport(now: Date, earnings: EarningRow[], settlements: SettlementRow[]) {
  const seen = new Set<string>();
  const delivered: EarningRow[] = [];
  for (const row of earnings) {
    if (row.status !== 'DELIVERED') continue;
    if (seen.has(row.orderId)) continue;
    seen.add(row.orderId);
    delivered.push(row);
  }
  const bounds = periodBounds(now);
  const keys: EarningsPeriodKey[] = ['today', 'week', 'month', 'all'];
  const inPeriod = (at: Date, from: Date | null) => from == null || at.getTime() >= from.getTime();
  const periods = Object.fromEntries(
    keys.map((key) => {
      const from = bounds[key];
      const orders = delivered.filter((row) => inPeriod(row.createdAt, from));
      const paid = settlements.filter((item) => item.kind === 'WAGE_PAID' && inPeriod(item.createdAt, from));
      const adjustments = settlements.filter((item) => item.kind === 'ADJUSTMENT' && inPeriod(item.createdAt, from));
      const payoutMinor = orders.reduce((sum, row) => sum + row.payoutMinor, 0);
      const platformMinor = orders.reduce((sum, row) => sum + row.platformMinor, 0);
      const adjustmentMinor = adjustments.reduce((sum, row) => sum + row.amountMinor, 0);
      const paidMinor = paid.reduce((sum, row) => sum + row.amountMinor, 0);
      return [
        key,
        {
          from: from?.toISOString() ?? null,
          to: now.toISOString(),
          label: periodTitle(key, from, now),
          orderCount: orders.length,
          payoutMinor,
          platformMinor,
          adjustmentMinor,
          paidMinor,
          netMinor: payoutMinor + adjustmentMinor - paidMinor,
          orderIds: orders.map((row) => row.orderId),
        },
      ];
    }),
  ) as Record<EarningsPeriodKey, {
    from: string | null;
    to: string;
    label: string;
    orderCount: number;
    payoutMinor: number;
    platformMinor: number;
    adjustmentMinor: number;
    paidMinor: number;
    netMinor: number;
    orderIds: string[];
  }>;
  const paidAll = settlements.filter((item) => item.kind === 'WAGE_PAID').reduce((sum, item) => sum + item.amountMinor, 0);
  const adjustmentsAll = settlements.filter((item) => item.kind === 'ADJUSTMENT').reduce((sum, item) => sum + item.amountMinor, 0);
  const remitted = settlements.filter((item) => item.kind === 'CASH_REMITTED').reduce((sum, item) => sum + item.amountMinor, 0);
  const payoutAll = periods.all.payoutMinor;
  const cashMinor = delivered.reduce((sum, row) => sum + row.cashCollectedMinor, 0);
  return {
    periods,
    totalMinor: payoutAll,
    todayMinor: periods.today.payoutMinor,
    weekMinor: periods.week.payoutMinor,
    monthMinor: periods.month.payoutMinor,
    unsettledWageMinor: payoutAll + adjustmentsAll - paidAll,
    paidWageMinor: paidAll,
    cashCollectedMinor: cashMinor,
    unsettledCashMinor: cashMinor - remitted,
    orders: delivered.map((row) => ({
      orderId: row.orderId,
      publicNumber: row.publicNumber,
      deliveredAt: row.deliveredAt?.toISOString() ?? row.createdAt.toISOString(),
      createdAt: row.createdAt.toISOString(),
      feeMinor: row.feeMinor,
      platformMinor: row.platformMinor,
      payoutMinor: row.payoutMinor,
      periods: keys.filter((key) => periods[key].orderIds.includes(row.orderId)),
    })),
    settlements,
  };
}
