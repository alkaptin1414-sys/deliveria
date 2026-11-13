# إعداد المشروع

## المتطلبات

- Node.js 20 أو أحدث
- Flutter stable
- PostgreSQL 16. يمكن استخدام Docker عبر `docker-compose.yml` (صورة PostGIS)، أو قاعدة التطوير المدمجة `npm run db:embedded`

## الخادم

```powershell
cd apps/api
copy .env.example .env
npm install
npm run db:embedded
```

اترك عملية قاعدة البيانات مفتوحة، ثم:

```powershell
npx prisma generate
npm run db:push
npm run db:seed
npm run dev
npm test
```

الخادم يعمل على `http://127.0.0.1:3000/v1`.

مفاتيح `JWT_ACCESS_SECRET` و`JWT_REFRESH_SECRET` و`OTP_PEPPER` يجب تغييرها قبل أي نشر. لا توضع مفاتيح الخرائط داخل تطبيق الموبايل. إن وُجد `GOOGLE_MAPS_API_KEY` في بيئة الخادم تُستخدم Distance Matrix، وإلا يُستخدم تقدير مسافة طريق على الخادم.

## التطبيق

محاكي أندرويد يصل إلى الخادم عبر `10.0.2.2`. ويندوز وسطح المكتب يستخدمان `127.0.0.1`. للتغيير:

```powershell
flutter run --dart-define=API_BASE=http://127.0.0.1:3000
```

الخط Cairo موجود في `apps/customer/assets/fonts`. الواجهة عربية واتجاهها من اليمين لليسار.

## محاكاة المندوب

مع `ENABLE_DEV_TOOLS=true` ومفتاح `x-dev-key`:

- `POST /v1/dev/orders/:id/accept`
- `POST /v1/dev/orders/:id/status` بجسم `{ "status": "EN_ROUTE_PICKUP" }`
- `POST /v1/dev/orders/:id/verify` بجسم `{ "code": "1234" }`
- `POST /v1/dev/orders/:id/support-complete` للحالات التي يتعذر فيها الرمز، مع تسجيل السبب

نسخة debug من التطبيق تعرض هذه الأوامر داخل شاشة المتابعة. نسخة release لا تعرضها، والواجهة تُغلق بالكامل في الإنتاج.
