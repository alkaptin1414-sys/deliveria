import { PrismaClient } from '@prisma/client';
import { randomInt } from 'crypto';

const base = 'http://127.0.0.1:3000/v1';
const prisma = new PrismaClient();
const results = [];
const record = (name, ok, detail) => {
  results.push({ name, ok });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name} ${detail ?? ''}`);
};
const j = async (res) => {
  const text = await res.text();
  try { return JSON.parse(text); } catch { return { raw: text }; }
};
const auth = (token) => ({ authorization: `Bearer ${token}`, 'content-type': 'application/json' });
const login = async (phone, profile) => {
  const sent = await j(await fetch(`${base}/auth/otp`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ phone }) }));
  const verified = await j(await fetch(`${base}/auth/otp/verify`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ challengeId: sent.challengeId, code: sent.devCode }) }));
  if (profile) {
    await fetch(`${base}/me/profile`, { method: 'POST', headers: auth(verified.accessToken), body: JSON.stringify({ name: 'عميل توصيل', accountType: 'PERSONAL' }) });
  }
  return verified.accessToken;
};

const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
const upload = async (token, kind) => {
  const body = new FormData();
  body.append('file', new Blob([png], { type: 'image/png' }), 'doc.png');
  const res = await fetch(`${base}/courier/documents?kind=${kind}`, { method: 'POST', headers: { authorization: `Bearer ${token}` }, body });
  return j(res);
};

const customerToken = await login(`010${randomInt(10000000, 99999999)}`, true);
const courierToken = await login(`010${randomInt(10000000, 99999999)}`, false);
const blocked = await j(await fetch(`${base}/courier/offers`, { headers: auth(customerToken) }));
record('منع العميل من واجهة المندوب', blocked.code === 'FORBIDDEN', blocked.code);

for (const kind of ['PORTRAIT', 'NATIONAL_ID', 'LICENSE', 'VEHICLE_REGISTRATION']) {
  const doc = await upload(courierToken, kind);
  if (!doc.id) record(`رفع ${kind}`, false, JSON.stringify(doc));
}
const applied = await j(await fetch(`${base}/courier/application`, {
  method: 'POST',
  headers: auth(courierToken),
  body: JSON.stringify({
    fullName: 'محمود عادل محمد',
    governorate: 'القاهرة',
    area: 'مدينة نصر',
    vehicle: 'MOTORCYCLE',
    plate: 'أ ب 1234',
    termsAccepted: true,
  }),
}));
const courierAccess = applied.accessToken;
record('تقديم طلب المندوب للمراجعة', applied.user?.role === 'COURIER' && applied.profile?.status === 'PENDING_REVIEW', applied.profile?.status || applied.code);
const early = await j(await fetch(`${base}/courier/availability`, { method: 'POST', headers: auth(courierAccess), body: JSON.stringify({ available: true, lat: 30.06, lng: 31.34 }) }));
record('منع غير المعتمد من التوفر', early.code === 'COURIER_NOT_APPROVED', early.code);

const adminPhone = `010${randomInt(10000000, 99999999)}`;
const adminTokenRaw = await login(adminPhone, true);
const adminUser = await prisma.user.findFirst({ where: { phone: `+20${adminPhone.slice(1)}` } });
await prisma.user.update({ where: { id: adminUser.id }, data: { role: 'ADMIN' } });
const adminToken = await login(adminPhone, false);
const reviewed = await j(await fetch(`${base}/admin/couriers/${applied.profile.id}/review`, {
  method: 'POST',
  headers: auth(adminToken),
  body: JSON.stringify({ status: 'APPROVED', note: 'المستندات مكتملة' }),
}));
record('اعتماد المندوب من الإدارة', reviewed.status === 'APPROVED', reviewed.status || reviewed.code);
const strangerReview = await j(await fetch(`${base}/admin/couriers/${applied.profile.id}/review`, {
  method: 'POST',
  headers: auth(customerToken),
  body: JSON.stringify({ status: 'SUSPENDED', note: 'محاولة' }),
}));
record('منع العميل من مراجعة المندوبين', strangerReview.code === 'FORBIDDEN', strangerReview.code);

const online = await j(await fetch(`${base}/courier/availability`, { method: 'POST', headers: auth(courierAccess), body: JSON.stringify({ available: true, lat: 30.06, lng: 31.34 }) }));
record('المندوب المعتمد يصبح متاحًا', online.available === true, String(online.available || online.code));
const place = (name, lat, lng) => ({ name, line: `${name} شارع عباس`, lat, lng });
const order = await j(await fetch(`${base}/orders`, {
  method: 'POST',
    headers: { ...auth(customerToken), 'idempotency-key': `courier-flow-${Date.now()}` },
  body: JSON.stringify({
    pickup: place('الاستلام', 30.062, 31.342),
    dropoff: place('التسليم', 30.07, 31.35),
    size: 'SMALL',
    fragile: false,
    vehicle: 'MOTORCYCLE',
    recipientName: 'مستلم',
    recipientPhone: '01033334444',
    parcelType: 'PACKAGE',
    parcelDescription: 'طرد صغير',
  }),
}));
record('إنشاء طلب عميل', order.status === 'SEARCHING', order.status || order.code);
const offers = await j(await fetch(`${base}/courier/offers`, { headers: auth(courierAccess) }));
const offer = Array.isArray(offers) ? offers.find((item) => item.orderId === order.id) : null;
record('وصول الطلب للمندوب المتاح', Boolean(offer) && offer.payoutMinor === order.feeMinor && !offer.recipientPhone, offer ? String(offer.payoutMinor) : JSON.stringify(offers).slice(0, 180));
const courierOrder = await j(await fetch(`${base}/orders`, {
  method: 'POST',
  headers: { ...auth(courierAccess), 'idempotency-key': 'courier-should-fail' },
  body: JSON.stringify({
    pickup: place('الاستلام', 30.062, 31.342),
    dropoff: place('التسليم', 30.07, 31.35),
    size: 'SMALL',
    fragile: false,
    vehicle: 'MOTORCYCLE',
    recipientName: 'مستلم',
    recipientPhone: '01033334444',
    parcelType: 'PACKAGE',
    parcelDescription: 'طرد صغير',
  }),
}));
record('منع المندوب من إنشاء طلب عميل', courierOrder.code === 'FORBIDDEN', courierOrder.code);
const accepted = await j(await fetch(`${base}/courier/offers/${offer.id}/accept`, { method: 'POST', headers: auth(courierAccess) }));
record('قبول الطلب', accepted.status === 'ACCEPTED' && accepted.courier?.id, accepted.status || accepted.code);
const again = await j(await fetch(`${base}/courier/offers`, { headers: auth(courierAccess) }));
record('لا عروض أثناء مهمة مفتوحة', Array.isArray(again) && again.length === 0, JSON.stringify(again).slice(0, 120));
for (const status of ['EN_ROUTE_PICKUP', 'PICKED_UP', 'EN_ROUTE_DROPOFF']) {
  const step = await j(await fetch(`${base}/courier/orders/${order.id}/advance`, { method: 'POST', headers: auth(courierAccess), body: JSON.stringify({ status }) }));
  record(`حالة ${status}`, step.status === status, step.status || step.code);
}
const skip = await j(await fetch(`${base}/courier/orders/${order.id}/advance`, { method: 'POST', headers: auth(courierAccess), body: JSON.stringify({ status: 'DELIVERED' }) }));
record('منع إنهاء التسليم بدون رمز', skip.code === 'INVALID_STATUS' || skip.code === 'REQUEST_FAILED', skip.code || skip.message);
const hidden = await j(await fetch(`${base}/orders/${order.id}/delivery-code`, { headers: auth(courierAccess) }));
const code = await j(await fetch(`${base}/orders/${order.id}/delivery-code`, { headers: auth(customerToken) }));
record('رمز التسليم للعميل فقط', (hidden.code === 'FORBIDDEN' || hidden.code === 'NOT_FOUND') && /^\d{4}$/.test(code.code), `${hidden.code} ${code.code}`);
const bad = await j(await fetch(`${base}/courier/orders/${order.id}/deliver`, { method: 'POST', headers: auth(courierAccess), body: JSON.stringify({ code: '0000' }) }));
const delivered = code.code === '0000' ? bad : await j(await fetch(`${base}/courier/orders/${order.id}/deliver`, { method: 'POST', headers: auth(courierAccess), body: JSON.stringify({ code: code.code }) }));
record('رفض رمز خاطئ ثم التسليم بالرمز', bad.code === 'CODE_INVALID' && delivered.status === 'DELIVERED', `${bad.code} ${delivered.status}`);
const earnings = await j(await fetch(`${base}/courier/earnings`, { headers: auth(courierAccess) }));
const row = earnings.orders?.find((item) => item.orderId === order.id);
const payoutSum = (earnings.orders ?? []).reduce((sum, item) => sum + item.payoutMinor, 0);
const cashSum = (earnings.orders ?? []).reduce((sum, item) => sum + item.cashCollectedMinor, 0);
record('تسجيل أجرة التوصيل دون احتساب النقد ربحًا', row && row.payoutMinor === order.feeMinor && earnings.totalMinor === payoutSum && earnings.totalMinor !== payoutSum + cashSum, `${earnings.totalMinor} ${payoutSum} ${cashSum}`);
const review = await j(await fetch(`${base}/orders/${order.id}/review`, { method: 'POST', headers: auth(customerToken), body: JSON.stringify({ rating: 5, tags: ['الالتزام بالمواعيد'], comment: 'مندوب محترم' }) }));
const duplicate = await j(await fetch(`${base}/orders/${order.id}/review`, { method: 'POST', headers: auth(customerToken), body: JSON.stringify({ rating: 1, tags: [] }) }));
const seen = await j(await fetch(`${base}/courier/ratings`, { headers: auth(courierAccess) }));
record('تقييم واحد يظهر للمندوب', review.rating === 5 && duplicate.code === 'REVIEW_EXISTS' && seen.count >= 1, `${review.rating} ${duplicate.code} ${seen.count}`);
const offline = await j(await fetch(`${base}/courier/orders/${order.id}/location`, { method: 'POST', headers: auth(courierAccess), body: JSON.stringify({ lat: 30.06, lng: 31.34 }) }));
record('رفض تحديث الموقع بعد انتهاء المهمة', offline.code === 'FORBIDDEN' || offline.code === 'INVALID_STATUS', offline.code);

void adminTokenRaw;
await prisma.$disconnect();
const failed = results.filter((item) => !item.ok);
console.log(`${results.length - failed.length}/${results.length}`);
process.exit(failed.length ? 1 : 0);
