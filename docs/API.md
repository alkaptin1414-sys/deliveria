# واجهة الخادم

الأساس: `/v1`

الأخطاء بالشكل `{ "code", "message" }` والرسالة عربية.

## الدخول

| الطريقة | المسار | الوصف |
| --- | --- | --- |
| POST | `/auth/otp` | إرسال رمز لرقم مصري |
| POST | `/auth/otp/verify` | التحقق وإصدار الجلسة |
| POST | `/auth/refresh` | تجديد الجلسة |
| POST | `/auth/logout` | إنهاء الجلسة |
| GET | `/me` | الحساب الحالي |
| POST | `/me/profile` | الاسم ونوع الحساب |
| PATCH | `/me` | تعديل الاسم وإعدادات الإشعار |

## النشاط والعناوين

| الطريقة | المسار | الوصف |
| --- | --- | --- |
| POST/GET/PATCH | `/business` | بيانات النشاط. القراءة لصاحب العضوية فقط |
| GET | `/business/stats` | أرقام اليوم |
| GET/POST | `/business/recipients` | عملاء محفوظون بموافقة |
| CRUD | `/addresses` | عناوين المستخدم فقط |

أنواع الأنشطة تُرجع من `GET /catalog/business-categories` حتى تُضاف أنواع جديدة دون تعديل التطبيق.

## الطلبات

| الطريقة | المسار | الوصف |
| --- | --- | --- |
| POST | `/orders/quote` | سعر ومسافة من الخادم |
| POST | `/orders` | إنشاء. يتطلب `Idempotency-Key` |
| GET | `/orders?bucket=active\|completed\|cancelled` | قائمة المالك |
| GET | `/orders/:id` | التفاصيل |
| POST | `/orders/:id/cancel` | إلغاء وفق سياسة الحالة |
| POST | `/orders/:id/retry` | إعادة البحث بعد عدم توفر مندوب |
| GET | `/orders/:id/delivery-code` | الرمز لصاحب الطلب عند التوجه للتسليم |
| POST | `/orders/:id/review` | تقييم بعد الاكتمال |
| GET/POST | `/orders/:id/messages` | محادثة أطراف الطلب |

السعر والحالة لا يُؤخذان من جسم طلب العميل. الدفع المقبول حاليًا هو النقد فقط.

## المندوب

`/courier/orders/:id/accept` محجوزة لدور المندوب. تطبيق المندوب غير منفذ، لذلك المسار يرفض حساب العميل.

التحديث اللحظي عبر WebSocket على `/v1/realtime?token=`.

## أخرى

- `GET /notifications`
- `GET /support/faq`
- `POST /support/tickets`
- `GET /legal/terms` و`/legal/privacy`
- `POST /uploads?purpose=avatar|parcel|logo`
