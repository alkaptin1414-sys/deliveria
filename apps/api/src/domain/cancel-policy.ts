import { OrderStatus } from './order-state';

export const CANCEL_REASONS = [
  { code: 'NO_LONGER_NEEDED', label: 'لم أعد بحاجة إلى التوصيل' },
  { code: 'WRONG_ADDRESS', label: 'أدخلت عنوانًا خاطئًا' },
  { code: 'COURIER_LATE', label: 'تأخر المندوب' },
  { code: 'CREATED_BY_MISTAKE', label: 'تم إنشاء الطلب بالخطأ' },
  { code: 'OTHER', label: 'سبب آخر' },
] as const;

export type CancelCode = (typeof CANCEL_REASONS)[number]['code'];

export function cancelPolicy(input: {
  status: OrderStatus;
  deliveryFeeMinor: number;
  goodsMinor: number;
  alreadyCancelled: boolean;
}) {
  if (input.alreadyCancelled || input.status === 'CANCELLED' || input.status === 'DELIVERED') {
    return { allowed: false, feeMinor: 0, supportOnly: false, message: 'لا يمكن إلغاء هذا الطلب.' };
  }
  if (input.status === 'PICKED_UP' || input.status === 'EN_ROUTE_DROPOFF') {
    return {
      allowed: false,
      feeMinor: 0,
      supportOnly: true,
      message: 'المندوب استلم المنتجات. الإلغاء بعد الاستلام يتم عبر الدعم حتى لا تضيع البضاعة أو الأموال.',
    };
  }
  if (input.status === 'EN_ROUTE_PICKUP') {
    const feeMinor = input.deliveryFeeMinor > 0 ? Math.max(500, Math.round(input.deliveryFeeMinor * 0.3)) : 0;
    return {
      allowed: true,
      feeMinor: Math.min(feeMinor, input.deliveryFeeMinor),
      supportOnly: false,
      message: 'المندوب في الطريق للاستلام. إلغاء الطلب الآن عليه رسوم يحددها الخادم.',
    };
  }
  return {
    allowed: true,
    feeMinor: 0,
    supportOnly: false,
    message: 'يمكن إلغاء الطلب قبل تحرك المندوب بدون رسوم.',
  };
}
