import { PrismaClient } from '@prisma/client';

const base = 'http://127.0.0.1:3000/v1';
const dev = { 'x-dev-key': 'deliveria-dev', 'content-type': 'application/json' };
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
const login = async (phone) => {
  const sent = await j(await fetch(`${base}/auth/otp`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ phone }) }));
  const verified = await j(await fetch(`${base}/auth/otp/verify`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ challengeId: sent.challengeId, code: sent.devCode }) }));
  await fetch(`${base}/me/profile`, { method: 'POST', headers: auth(verified.accessToken), body: JSON.stringify({ name: 'عميل مطاعم', accountType: 'PERSONAL' }) });
  return verified.accessToken;
};

const listed = await j(await fetch(`${base}/restaurants`));
record('عرض مطاعم منطقة الخدمة', Array.isArray(listed) && listed.length >= 4, String(listed.length));
const open = listed.find((item) => item.name === 'كشري أبو طارق');
const closed = listed.find((item) => item.name === 'برجر المحطة');
const detail = await j(await fetch(`${base}/restaurants/${open.id}`));
const main = detail.sections[0].items[0];
const size = main.groups.find((group) => group.name === 'الحجم').options.find((option) => option.name === 'كبير');
const token = await login('01055550221');
const stranger = await login('01055550222');
const address = await j(await fetch(`${base}/addresses`, {
  method: 'POST',
  headers: auth(token),
  body: JSON.stringify({ label: 'HOME', name: 'البيت', governorate: 'القاهرة', city: 'القاهرة', area: 'مدينة نصر', line: 'شارع عباس العقاد', lat: 30.055, lng: 31.34, isDefault: true }),
}));
const unavailable = detail.sections.flatMap((section) => section.items).find((item) => item.available === false);
const sweets = listed.find((item) => item.name === 'حلواني السعادة');
const sweetsDetail = await j(await fetch(`${base}/restaurants/${sweets.id}`));
const hidden = sweetsDetail.sections.flatMap((section) => section.items).find((item) => item.available === false);
const blockedItem = await j(await fetch(`${base}/restaurants/${sweets.id}/cart`, { method: 'PUT', headers: auth(token), body: JSON.stringify({ items: [{ itemId: hidden.id, quantity: 1, optionIds: [] }] }) }));
record('رفض صنف غير متاح', blockedItem.code === 'ITEM_UNAVAILABLE', blockedItem.code);

await fetch(`${base}/restaurants/${closed.id}/cart`, { method: 'PUT', headers: auth(token), body: JSON.stringify({ items: [{ itemId: (await j(await fetch(`${base}/restaurants/${closed.id}`))).sections[1].items[0].id, quantity: 1 }] }) });
const closedOrder = await j(await fetch(`${base}/food-orders`, { method: 'POST', headers: { ...auth(token), 'idempotency-key': 'food-closed-01' }, body: JSON.stringify({ restaurantId: closed.id, addressId: address.id, recipientName: 'عميل', recipientPhone: '01033334444' }) }));
record('رفض مطعم مغلق', closedOrder.code === 'RESTAURANT_CLOSED', closedOrder.code);

const small = await j(await fetch(`${base}/restaurants/${open.id}/cart`, { method: 'PUT', headers: auth(token), body: JSON.stringify({ items: [{ itemId: main.id, quantity: 1, optionIds: [main.groups[0].options[0].id] }] }) }));
const belowMin = await j(await fetch(`${base}/food-orders`, { method: 'POST', headers: { ...auth(token), 'idempotency-key': 'food-min-01' }, body: JSON.stringify({ restaurantId: open.id, addressId: address.id, recipientName: 'عميل', recipientPhone: '01033334444' }) }));
record('الحد الأدنى للطلب', belowMin.code === 'MIN_ORDER', belowMin.code || JSON.stringify(small.foodMinor));

await fetch(`${base}/restaurants/${open.id}/cart`, { method: 'PUT', headers: auth(token), body: JSON.stringify({ items: [{ itemId: main.id, quantity: 1, optionIds: [size.id], note: 'بدون مخلل' }] }) });
const quote = await j(await fetch(`${base}/restaurants/${open.id}/cart/quote?addressId=${address.id}`, { headers: auth(token) }));
const order = await j(await fetch(`${base}/food-orders`, { method: 'POST', headers: { ...auth(token), 'idempotency-key': 'food-ok-01' }, body: JSON.stringify({ restaurantId: open.id, addressId: address.id, recipientName: 'عميل', recipientPhone: '01033334444', notes: 'عند الباب' }) }));
record('إنشاء طلب طعام', order.status === 'PENDING_RESTAURANT' && order.courierAssigned === false && order.totalMinor === quote.totalMinor, `${order.status} ${order.totalMinor}`);
const again = await j(await fetch(`${base}/food-orders`, { method: 'POST', headers: { ...auth(token), 'idempotency-key': 'food-ok-01' }, body: JSON.stringify({ restaurantId: open.id, addressId: address.id, recipientName: 'عميل', recipientPhone: '01033334444' }) }));
record('منع تكرار الطلب', again.id === order.id, again.id);

const prisma = new PrismaClient();
const customer = await prisma.user.findFirst({ where: { phone: '+201055550221' } });
const other = await prisma.user.findFirst({ where: { phone: '+201055550222' } });
await prisma.restaurantMember.create({ data: { userId: customer.id, restaurantId: open.id, role: 'OWNER' } });
await prisma.restaurantMember.create({ data: { userId: other.id, restaurantId: closed.id, role: 'OWNER' } });
const foreign = await j(await fetch(`${base}/restaurant/orders/${order.id}/accept`, { method: 'POST', headers: auth(stranger), body: JSON.stringify({ prepMinutes: 20 }) }));
record('منع مطعم من طلب مطعم آخر', foreign.code === 'NOT_FOUND', foreign.code);
const accepted = await j(await fetch(`${base}/restaurant/orders/${order.id}/accept`, { method: 'POST', headers: auth(token), body: JSON.stringify({ prepMinutes: 20 }) }));
const preparing = await j(await fetch(`${base}/restaurant/orders/${order.id}/preparing`, { method: 'POST', headers: auth(token) }));
const ready = await j(await fetch(`${base}/restaurant/orders/${order.id}/ready`, { method: 'POST', headers: auth(token) }));
record('قبول وتجهيز بدون مندوب', accepted.status === 'ACCEPTED' && preparing.status === 'PREPARING' && ready.status === 'READY' && ready.courierAssigned === false && ready.deliveryOrderId, ready.status);
await fetch(`${base}/dev/orders/${ready.deliveryOrderId}/accept`, { method: 'POST', headers: dev, body: '{}' });
const assigned = await j(await fetch(`${base}/food-orders/${order.id}`, { headers: auth(token) }));
record('تعيين المندوب بعد القبول الفعلي', assigned.courierAssigned === true && assigned.status === 'COURIER_ASSIGNED', assigned.status);
const earlyReview = await j(await fetch(`${base}/food-orders/${order.id}/review`, { method: 'POST', headers: auth(token), body: JSON.stringify({ rating: 5 }) }));
record('رفض تقييم المطعم قبل التسليم', earlyReview.code === 'REVIEW_NOT_READY', earlyReview.code);
for (const status of ['EN_ROUTE_PICKUP', 'PICKED_UP', 'EN_ROUTE_DROPOFF']) {
  await fetch(`${base}/dev/orders/${ready.deliveryOrderId}/status`, { method: 'POST', headers: dev, body: JSON.stringify({ status }) });
}
await fetch(`${base}/dev/orders/${ready.deliveryOrderId}/support-complete`, { method: 'POST', headers: dev, body: JSON.stringify({ note: 'تم' }) });
const reviewed = await j(await fetch(`${base}/food-orders/${order.id}/review`, { method: 'POST', headers: auth(token), body: JSON.stringify({ rating: 5, comment: 'الأكل وصل كويس' }) }));
const duplicateReview = await j(await fetch(`${base}/food-orders/${order.id}/review`, { method: 'POST', headers: auth(token), body: JSON.stringify({ rating: 1 }) }));
record('تقييم المطعم مرة واحدة', reviewed.rating === 5 && duplicateReview.code === 'REVIEW_EXISTS', duplicateReview.code);
const line = await prisma.foodOrderLine.findFirst({ where: { orderId: order.id } });
await prisma.menuItem.update({ where: { id: line.itemId }, data: { priceMinor: 100 } });
const stored = await prisma.foodOrderLine.findFirst({ where: { orderId: order.id } });
record('السعر محفوظ وقت الشراء', stored.unitMinor !== 100 && stored.name === line.name, String(stored.unitMinor));
await prisma.$disconnect();
const failed = results.filter((item) => !item.ok);
console.log(`FAILED ${failed.length}/${results.length}`);
if (failed.length) process.exit(1);
