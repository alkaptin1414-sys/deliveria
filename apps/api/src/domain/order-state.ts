export type OrderStatus =
  | 'SEARCHING'
  | 'ACCEPTED'
  | 'EN_ROUTE_PICKUP'
  | 'PICKED_UP'
  | 'EN_ROUTE_DROPOFF'
  | 'DELIVERED'
  | 'CANCELLED'
  | 'NO_COURIER';

export type Actor = 'CUSTOMER' | 'COURIER' | 'SYSTEM' | 'SUPPORT';

const TRANSITIONS: Record<OrderStatus, Partial<Record<OrderStatus, Actor[]>>> = {
  SEARCHING: {
    ACCEPTED: ['COURIER', 'SYSTEM'],
    CANCELLED: ['CUSTOMER', 'SUPPORT'],
    NO_COURIER: ['SYSTEM'],
  },
  NO_COURIER: {
    SEARCHING: ['CUSTOMER'],
    CANCELLED: ['CUSTOMER', 'SUPPORT'],
  },
  ACCEPTED: {
    EN_ROUTE_PICKUP: ['COURIER', 'SYSTEM'],
    CANCELLED: ['CUSTOMER', 'SUPPORT'],
  },
  EN_ROUTE_PICKUP: {
    PICKED_UP: ['COURIER', 'SYSTEM'],
    CANCELLED: ['CUSTOMER', 'SUPPORT'],
  },
  PICKED_UP: {
    EN_ROUTE_DROPOFF: ['COURIER', 'SYSTEM', 'SUPPORT'],
  },
  EN_ROUTE_DROPOFF: {
    DELIVERED: ['SYSTEM', 'SUPPORT'],
  },
  DELIVERED: {},
  CANCELLED: {},
};

export class TransitionError extends Error {
  constructor(message: string) {
    super(message);
  }
}

export function assertTransition(from: OrderStatus, to: OrderStatus, actor: Actor): void {
  const allowed = TRANSITIONS[from][to];
  if (!allowed || !allowed.includes(actor)) {
    throw new TransitionError(`لا يمكن نقل الطلب من ${from} إلى ${to}.`);
  }
}

export function customerCanCancel(status: OrderStatus): boolean {
  return ['SEARCHING', 'NO_COURIER', 'ACCEPTED', 'EN_ROUTE_PICKUP'].includes(status);
}

export const STATUS_COPY: Record<OrderStatus, { title: string; body: string }> = {
  SEARCHING: {
    title: 'جاري البحث عن مندوب',
    body: 'بنبحث عن مندوب قريب من عنوان الاستلام.',
  },
  ACCEPTED: {
    title: 'تم قبول طلبك',
    body: 'المندوب قبل الطلب ويستعد للتحرك.',
  },
  EN_ROUTE_PICKUP: {
    title: 'المندوب في الطريق للاستلام',
    body: 'المندوب متجه إلى عنوان الاستلام.',
  },
  PICKED_UP: {
    title: 'تم استلام الطلب',
    body: 'المندوب استلم الغرض.',
  },
  EN_ROUTE_DROPOFF: {
    title: 'المندوب في الطريق للتسليم',
    body: 'شارك رمز التسليم مع المستلم فقط.',
  },
  DELIVERED: {
    title: 'اكتمل التوصيل',
    body: 'تم تسليم الطلب.',
  },
  CANCELLED: {
    title: 'تم إلغاء الطلب',
    body: 'الطلب اتلغى ولن يتم تعيين مندوب.',
  },
  NO_COURIER: {
    title: 'لا يوجد مندوب متاح',
    body: 'مفيش مندوب قريب حاليًا. تقدر تعيد المحاولة أو تلغي الطلب.',
  },
};
