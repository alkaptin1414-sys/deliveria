const base = 'http://127.0.0.1:3000/v1';

async function call(path, { method = 'GET', token, body } = {}) {
  const response = await fetch(`${base}${path}`, {
    method,
    headers: {
      Accept: 'application/json',
      ...(body ? { 'Content-Type': 'application/json' } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await response.json().catch(() => ({}));
  return { status: response.status, data };
}

const email = process.env.ADMIN_EMAIL;
const password = process.env.ADMIN_PASSWORD;
if (!email || !password) {
  console.error('ADMIN_EMAIL and ADMIN_PASSWORD are required');
  process.exit(1);
}

const admin = await call('/auth/login', { method: 'POST', body: { email, password } });
if (![200, 201].includes(admin.status) || admin.data.user?.role !== 'ADMIN' || admin.data.next !== 'admin') {
  console.error('admin login failed', admin.status, admin.data.code ?? admin.data.message ?? 'unexpected');
  process.exit(1);
}
const token = admin.data.accessToken;
const home = await call('/admin/home', { token });
const today = home.data.ordersToday ?? {};
const checks = [];
const ok = (name, pass) => checks.push({ name, pass });
ok('dashboard', home.status === 200 && typeof home.data.customers === 'number' && typeof home.data.restaurants === 'number');
ok('revenue separated', today.orderValueLabel && today.platformRevenueLabel && 'platformRevenueMinor' in today);
ok('couriers list', Array.isArray(home.data.couriers));

const phone = `010${String(Date.now()).slice(-8)}`;
const customer = await call('/auth/register', {
  method: 'POST',
  body: { name: 'عميل اختبار', email: `check-${Date.now()}@example.com`, password: 'testpass1', role: 'CUSTOMER' },
});
ok('customer created', customer.status === 200 || customer.status === 201);
const denied = await call('/admin/home', { token: customer.data.accessToken });
ok('customer blocked', denied.status === 403);

const finance = await call('/admin/finance', { token });
ok('finance', finance.status === 200 && 'platformRevenueMinor' in finance.data && 'cashCollectedMinor' in finance.data);
const areas = await call('/admin/areas', { token });
ok('areas', areas.status === 200 && Array.isArray(areas.data));
const tickets = await call('/admin/tickets', { token });
ok('tickets', tickets.status === 200 && Array.isArray(tickets.data));
const pricing = await call('/admin/pricing', {
  method: 'POST',
  token,
  body: { deliveryPlatformBps: finance.data.commissionBps ?? 0, serviceFeeMinor: finance.data.serviceFeeMinor ?? 0, reason: 'مراجعة اختبار دون تغيير السعر' },
});
ok('pricing audit', pricing.status === 200 || pricing.status === 201);
const again = await call('/admin/home', { token });
ok('audit written', Array.isArray(again.data.audits) && again.data.audits.some((row) => row.action === 'UPDATE_PRICING'));

const failed = checks.filter((item) => !item.pass);
console.log(JSON.stringify({ phone, passed: checks.length - failed.length, total: checks.length, failed }, null, 2));
process.exit(failed.length ? 1 : 0);
