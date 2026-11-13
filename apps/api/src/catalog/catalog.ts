export const BUSINESS_CATEGORIES = [
  { code: 'PHARMACY', label: 'صيدلية' },
  { code: 'RESTAURANT', label: 'مطعم' },
  { code: 'SUPERMARKET', label: 'سوبر ماركت' },
  { code: 'CLOTHING', label: 'محل ملابس' },
  { code: 'PHONES', label: 'محل هواتف' },
  { code: 'ACCESSORIES', label: 'محل إكسسوارات' },
  { code: 'BAKERY', label: 'مخبز' },
  { code: 'COSMETICS', label: 'مستحضرات تجميل' },
  { code: 'ECOMMERCE', label: 'متجر إلكتروني' },
  { code: 'BOOKSTORE', label: 'مكتبة' },
  { code: 'LAUNDRY', label: 'مغسلة' },
  { code: 'OTHER', label: 'أنشطة أخرى' },
] as const;

export const PARCEL_TYPES = [
  { code: 'PACKAGE', label: 'طرد' },
  { code: 'DOCUMENTS', label: 'مستندات' },
  { code: 'FOOD', label: 'طعام' },
  { code: 'PERSONAL', label: 'أغراض شخصية' },
  { code: 'OTHER', label: 'غرض آخر' },
] as const;

export const PARCEL_SIZES = [
  { code: 'SMALL', label: 'صغير', hint: 'مغلف أو كيس يد' },
  { code: 'MEDIUM', label: 'متوسط', hint: 'شنطة أو كرتونة صغيرة' },
  { code: 'LARGE', label: 'كبير', hint: 'كرتونة كبيرة، سيارة فقط' },
] as const;

export const FAQ = [
  {
    question: 'إزاي أطلب مندوب؟',
    answer: 'من الرئيسية اضغط «اطلب مندوب الآن»، حدد الاستلام والتسليم، راجع السعر، ثم أكّد الطلب.',
  },
  {
    question: 'هل السعر بيتغير بعد التأكيد؟',
    answer: 'السعر المعروض قبل التأكيد هو سعر الطلب. أي تعديل لاحق بيتم من الخادم وبيظهر لك قبل ما يعتمد.',
  },
  {
    question: 'إيه طرق الدفع المتاحة؟',
    answer: 'حاليًا الدفع نقدًا عند التنفيذ. وسائل الدفع الإلكترونية هتتضاف بعد ربطها فعليًا.',
  },
  {
    question: 'إزاي المستلم يأكد الاستلام؟',
    answer: 'هيظهر لك رمز تسليم بعد استلام المندوب للغرض. المستلم يقوله للمندوب، والنظام يتحقق منه على الخادم.',
  },
];
