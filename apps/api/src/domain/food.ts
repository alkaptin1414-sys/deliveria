export const RESTAURANT_CATEGORIES = [
  { code: 'FAST_FOOD', label: 'وجبات سريعة' },
  { code: 'PIZZA', label: 'بيتزا' },
  { code: 'BURGER', label: 'برجر' },
  { code: 'GRILL', label: 'مشويات' },
  { code: 'EASTERN', label: 'أكل شرقي' },
  { code: 'DESSERT', label: 'حلويات' },
  { code: 'DRINKS', label: 'مشروبات' },
] as const;

export function cairoMinutes(now = new Date()) {
  const shifted = new Date(now.getTime() + 3 * 60 * 60 * 1000);
  return shifted.getUTCHours() * 60 + shifted.getUTCMinutes();
}

export function withinHours(opensAt: string, closesAt: string, now = new Date()) {
  const current = cairoMinutes(now);
  const open = toMinutes(opensAt);
  const close = toMinutes(closesAt);
  if (open === close) return true;
  if (open < close) return current >= open && current < close;
  return current >= open || current < close;
}

export function orderingState(input: {
  shift: 'OPEN' | 'CLOSED' | 'SCHEDULED';
  acceptsScheduled: boolean;
  opensAt: string;
  closesAt: string;
  now?: Date;
}) {
  if (input.shift === 'CLOSED') {
    return input.acceptsScheduled
      ? { acceptingNow: false, scheduledOnly: true, label: 'يستقبل طلبات مجدولة' }
      : { acceptingNow: false, scheduledOnly: false, label: 'مغلق' };
  }
  if (input.shift === 'SCHEDULED') {
    return { acceptingNow: false, scheduledOnly: true, label: 'يستقبل طلبات مجدولة' };
  }
  const open = withinHours(input.opensAt, input.closesAt, input.now);
  if (open) return { acceptingNow: true, scheduledOnly: false, label: 'مفتوح الآن' };
  return input.acceptsScheduled
    ? { acceptingNow: false, scheduledOnly: true, label: 'يستقبل طلبات مجدولة' }
    : { acceptingNow: false, scheduledOnly: false, label: 'مغلق' };
}

export interface PricedOption {
  name: string;
  priceMinor: number;
  group: string;
}

export function priceItem(
  item: {
    available: boolean;
    priceMinor: number;
    groups: Array<{
      name: string;
      required: boolean;
      minSelect: number;
      maxSelect: number;
      options: Array<{ id: string; name: string; priceMinor: number; available: boolean }>;
    }>;
  },
  optionIds: string[],
) {
  if (!item.available) return { error: 'هذا الصنف غير متاح حاليًا.' };
  const selected: PricedOption[] = [];
  const used = new Set<string>();
  for (const group of item.groups) {
    const chosen = group.options.filter((option) => optionIds.includes(option.id));
    if (chosen.length < group.minSelect || chosen.length > group.maxSelect || (group.required && chosen.length === 0)) {
      return { error: `اختر الخيارات المطلوبة في ${group.name}.` };
    }
    for (const option of chosen) {
      if (!option.available) return { error: `${option.name} غير متاحة.` };
      used.add(option.id);
      selected.push({ name: option.name, priceMinor: option.priceMinor, group: group.name });
    }
  }
  if (optionIds.some((id) => !used.has(id))) return { error: 'أحد الإضافات لم يعد متاحًا.' };
  const unitMinor = item.priceMinor + selected.reduce((sum, option) => sum + option.priceMinor, 0);
  return { unitMinor, options: selected };
}

export function applyOffer(foodMinor: number, percentOff: number) {
  const percent = Math.min(100, Math.max(0, percentOff));
  const discountMinor = Math.round((foodMinor * percent) / 100);
  return { discountMinor, payableMinor: foodMinor - discountMinor };
}

function toMinutes(value: string) {
  const [hour, minute] = value.split(':').map((part) => Number(part));
  return hour * 60 + (minute || 0);
}
