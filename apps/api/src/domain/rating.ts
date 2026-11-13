export const RATING_LABELS: Record<number, string> = {
  1: 'سيئ جدًا',
  2: 'سيئ',
  3: 'متوسط',
  4: 'جيد جدًا',
  5: 'ممتاز',
};

export const POSITIVE_TAGS = ['الالتزام بالمواعيد', 'حسن التعامل', 'سرعة التوصيل', 'الحفاظ على الطلب'];
export const NEGATIVE_TAGS = ['صعوبة التواصل', 'التأخير', 'التعامل غير المناسب'];

const BLOCKED = ['رقم هاتفي', 'كلب', 'حقير'];
const PHONE = /01[0125]\d{8}/;

export function tagsForRating(rating: number): string[] {
  if (rating >= 4) return POSITIVE_TAGS;
  if (rating <= 2) return NEGATIVE_TAGS;
  return [...POSITIVE_TAGS, ...NEGATIVE_TAGS];
}

export function assertCommentAllowed(comment: string | undefined) {
  const text = comment?.trim() ?? '';
  if (text.length > 240) return 'التعليق أطول من الحد المسموح.';
  if (PHONE.test(text.replace(/\s/g, ''))) return 'لا تضع أرقام هواتف داخل التعليق.';
  if (BLOCKED.some((word) => text.includes(word))) return 'التعليق يحتوي على عبارة غير مسموح بنشرها.';
  return null;
}

export function summarizeRatings(ratings: number[]) {
  const histogram = { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 };
  for (const rating of ratings) {
    if (rating >= 1 && rating <= 5) histogram[rating as 1 | 2 | 3 | 4 | 5] += 1;
  }
  const count = ratings.length;
  if (count === 0) {
    return { count: 0, sum: 0, exact: null as number | null, display: null as number | null, histogram, label: 'لا توجد تقييمات بعد' };
  }
  const sum = ratings.reduce((total, rating) => total + rating, 0);
  const exact = sum / count;
  const display = Math.round(exact * 10) / 10;
  return { count, sum, exact, display, histogram, label: `${display} من 5` };
}

export const REVIEW_EDIT_MS = 24 * 60 * 60 * 1000;
