import { PrismaClient } from '@prisma/client';

const base = 'http://127.0.0.1:3000/v1';
const dev = { 'x-dev-key': 'deliveria-dev', 'content-type': 'application/json' };
const results = [];
const record = (name, ok, detail) => {
  results.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name} ${detail ?? ''}`);
};
const j = async (res) => {
  const text = await res.text();
  try {
    return JSON.parse(text);
  } catch {
    return { raw: text, status: res.status };
  }
};
const login = async (phone) => {
  const sent = await j(await fetch(`${base}/auth/otp`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ phone }) }));
  if (!sent.challengeId) throw new Error(`otp failed ${JSON.stringify(sent)}`);
  const verified = await j(await fetch(`${base}/auth/otp/verify`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ challengeId: sent.challengeId, code: sent.devCode }),
  }));
  if (!verified.accessToken) throw new Error(`login failed ${JSON.stringify(verified)}`);
  await fetch(`${base}/me/profile`, {
    method: 'POST',
    headers: auth(verified.accessToken),
    body: JSON.stringify({ name: 'عميل تجربة', accountType: 'PERSONAL' }),
  });
  return verified.accessToken;
};
const auth = (token) => ({ authorization: `Bearer ${token}`, 'content-type': 'application/json' });
const order = async (token, key) => j(await fetch(`${base}/orders`, {
  method: 'POST',
  headers: { ...auth(token), 'idempotency-key': key },
  body: JSON.stringify({
    pickup: { name: 'بيت', line: 'مدينة نصر', lat: 30.05, lng: 31.25 },
    dropoff: { name: 'مكتب', line: 'مصر الجديدة', lat: 30.06, lng: 31.26 },
    size: 'SMALL',
    fragile: false,
    vehicle: 'MOTORCYCLE',
    recipientName: 'مستلم',
    recipientPhone: '01022223333',
    parcelType: 'DOCUMENTS',
    parcelDescription: 'أوراق',
  }),
}));
const deliver = async (id) => {
  await fetch(`${base}/dev/orders/${id}/accept`, { method: 'POST', headers: dev, body: '{}' });
  for (const status of ['EN_ROUTE_PICKUP', 'PICKED_UP', 'EN_ROUTE_DROPOFF']) {
    await fetch(`${base}/dev/orders/${id}/status`, { method: 'POST', headers: dev, body: JSON.stringify({ status }) });
  }
  return j(await fetch(`${base}/dev/orders/${id}/support-complete`, { method: 'POST', headers: dev, body: JSON.stringify({ note: 'test' }) }));
};

const a = await login('01055550111');
const b = await login('01055550112');
const early = await order(a, 'rate-early-05');
if (!early.id) throw new Error(`order failed ${JSON.stringify(early)}`);
const earlyReview = await j(await fetch(`${base}/orders/${early.id}/review`, { method: 'POST', headers: auth(a), body: JSON.stringify({ rating: 5 }) }));
record('رفض طلب غير مكتمل', earlyReview.code === 'REVIEW_NOT_READY', earlyReview.code);

const mine = await order(a, 'rate-ok-05');
const done = await deliver(mine.id);
record('اكتمال الطلب', done.status === 'DELIVERED', done.status || done.code);

const noCourier = await order(a, 'rate-nocourier-05');
const prisma = new PrismaClient();
await prisma.deliveryOrder.update({ where: { id: noCourier.id }, data: { status: 'DELIVERED' } });
const noCourierReview = await j(await fetch(`${base}/orders/${noCourier.id}/review`, { method: 'POST', headers: auth(a), body: JSON.stringify({ rating: 4 }) }));
record('رفض طلب بلا مندوب', noCourierReview.code === 'REVIEW_NOT_READY', noCourierReview.code);

const other = await j(await fetch(`${base}/orders/${mine.id}/review`, { method: 'POST', headers: auth(b), body: JSON.stringify({ rating: 5 }) }));
record('رفض تقييم طلب لا يخص المستخدم', other.code === 'NOT_FOUND', other.code);

const bad = await j(await fetch(`${base}/orders/${mine.id}/review`, { method: 'POST', headers: auth(a), body: JSON.stringify({ rating: 9 }) }));
record('رفض نجوم خارج 1-5', bad.statusCode === 400 || Boolean(bad.message), JSON.stringify(bad).slice(0, 180));

const phone = await j(await fetch(`${base}/orders/${mine.id}/review`, { method: 'POST', headers: auth(a), body: JSON.stringify({ rating: 5, comment: '01012345678' }) }));
record('رفض رقم هاتف في التعليق', phone.code === 'INVALID_COMMENT', phone.code);

const first = await j(await fetch(`${base}/orders/${mine.id}/review`, { method: 'POST', headers: auth(a), body: JSON.stringify({ rating: 5, tags: ['حسن التعامل'], comment: 'ممتاز' }) }));
record('تقييم طلب مكتمل', first.rating === 5 && first.courierId === 'dev-courier', first.courierId);

const dup = await j(await fetch(`${base}/orders/${mine.id}/review`, { method: 'POST', headers: auth(a), body: JSON.stringify({ rating: 1 }) }));
record('منع التكرار', dup.code === 'REVIEW_EXISTS', dup.code);

const edited = await j(await fetch(`${base}/orders/${mine.id}/review/update`, { method: 'POST', headers: auth(a), body: JSON.stringify({ rating: 3, comment: 'تم التعديل' }) }));
record('تعديل نفس السجل', edited.id === first.id && edited.rating === 3, edited.id);

const rows = await prisma.review.count({ where: { orderId: mine.id } });
record('صف واحد بعد التعديل', rows === 1, String(rows));

const summary = await j(await fetch(`${base}/couriers/dev-courier/ratings`, { headers: auth(a) }));
record('تحديث المتوسط', summary.display === 3 && summary.count >= 1, JSON.stringify({ display: summary.display, count: summary.count }));

const stranger = await j(await fetch(`${base}/couriers/dev-courier/ratings`, { headers: auth(b) }));
record('رفض ملخص غير مصرح', stranger.code === 'FORBIDDEN', stranger.code);

const again = await login('01055550111');
const stored = await j(await fetch(`${base}/orders/${mine.id}/review`, { headers: auth(again) }));
record('بقاء التقييم بعد جلسة جديدة', stored.review?.rating === 3 && stored.review?.courierId === 'dev-courier', stored.review?.courierId);

const emptyUser = await login('01055550113');
const empty = await j(await fetch(`${base}/couriers/dev-courier/ratings`, { headers: auth(emptyUser) }));
record('رفض ملف مندوب بلا علاقة', empty.code === 'FORBIDDEN', empty.code);

await prisma.deliveryOrder.update({ where: { id: noCourier.id }, data: { courierId: 'courier-none' } });
const emptyProfile = await j(await fetch(`${base}/couriers/courier-none/ratings`, { headers: auth(again) }));
record('لا توجد تقييمات بعد', emptyProfile.label === 'لا توجد تقييمات بعد' && emptyProfile.display === null, emptyProfile.label);
await prisma.deliveryOrder.update({ where: { id: mine.id }, data: { courierId: 'courier-empty' } });

await prisma.user.update({ where: { phone: '+201055550111' }, data: { role: 'ADMIN' } });
const admin = await login('01055550111');
const excluded = await j(await fetch(`${base}/admin/reviews/${first.id}/exclude`, {
  method: 'POST',
  headers: auth(admin),
  body: JSON.stringify({ reason: 'تعليق مخالف' }),
}));
const afterExclude = await j(await fetch(`${base}/couriers/courier-empty/ratings`, { headers: auth(again) }));
record('استبعاد التقييم من المتوسط', excluded.status === 'EXCLUDED' && afterExclude.count === 0, `${excluded.status} count=${afterExclude.count}`);
await prisma.user.update({ where: { phone: '+201055550111' }, data: { role: 'CUSTOMER' } });

await prisma.$disconnect();
const failed = results.filter((item) => !item.ok);
console.log(`FAILED ${failed.length}/${results.length}`);
if (failed.length) process.exit(1);
