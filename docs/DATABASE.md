# قاعدة البيانات

المخطط في `apps/api/prisma/schema.prisma`.

الكيانات: Users، BusinessProfiles، BusinessMembers، Addresses، DeliveryOrders، OrderStatusHistory، CourierAssignments، PricingRules، ServiceAreas، Notifications، ChatMessages، Reviews، DeliveryProofs، SavedRecipients، SupportTickets، DeviceTokens، OtpChallenges، RefreshSessions.

الإحداثيات مخزنة كأرقام عشرية، والمسافة تُحسب على الخادم. صورة PostGIS في `docker-compose.yml` جاهزة لنقل الأعمدة إلى `geography` لاحقًا دون تغيير عقد التطبيق.

مناطق الخدمة الأولية: القاهرة، الجيزة، القليوبية، والإسكندرية. قواعد السعر الأولية للموتوسيكل والسيارة تُزرع من `prisma/seed.ts`.

رمز التسليم يُخزن مشفرًا ومجزأً، ويُتحقق منه مرة واحدة على الخادم. الإكمال اليدوي يسجل `DeliveryProof` بطريقة `SUPPORT_OVERRIDE`.

صلاحيات الموظفين ممثلة في `BusinessMember` بالدورين `OWNER` و`STAFF` حتى يمكن إضافة موظفين لاحقًا. كل استعلام للطلبات والعناوين مقيد بالمستخدم المالك.
