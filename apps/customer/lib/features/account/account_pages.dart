import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ui.dart';
import '../session/session_controller.dart';

class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider).user;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Text(user?.name ?? 'زائر', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            if (user != null) Text(user.phone, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 4),
            Text(user == null ? 'تصفح بدون تسجيل' : user.isBusiness ? 'حساب نشاط تجاري' : 'حساب شخصي', style: const TextStyle(color: AppColors.petrol, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            const SectionLabel('الحساب'),
            SurfaceGroup(children: [
              NavRow(icon: Icons.badge_outlined, title: 'بيانات الحساب', subtitle: 'الاسم والهاتف', onTap: () => context.push('/account/edit')),
              if (user?.isBusiness == true)
                NavRow(icon: Icons.storefront_outlined, title: 'بيانات النشاط', subtitle: 'العنوان ونوع النشاط', onTap: () => context.push('/account/business'), showDivider: false)
              else
                NavRow(icon: Icons.place_outlined, title: 'العناوين المحفوظة', onTap: () => context.go('/addresses'), showDivider: false),
            ]),
            const SizedBox(height: 18),
            const SectionLabel('الإعدادات'),
            SurfaceGroup(children: [
              NavRow(icon: Icons.notifications_outlined, title: 'الإشعارات', onTap: () => context.push('/account/notifications')),
              NavRow(icon: Icons.language, title: 'اللغة', subtitle: 'العربية', onTap: () => context.push('/account/language'), showDivider: false),
            ]),
            const SizedBox(height: 18),
            const SectionLabel('المساعدة'),
            SurfaceGroup(children: [
              NavRow(icon: Icons.support_agent_outlined, title: 'المساعدة والدعم', subtitle: 'شكوى على طلب أو تحصيل أو مندوب', onTap: () => context.push('/support/contact')),
              NavRow(icon: Icons.help_outline, title: 'الأسئلة الشائعة', onTap: () => context.push('/support/faq')),
              NavRow(icon: Icons.description_outlined, title: 'الشروط والأحكام', onTap: () => context.push('/legal/terms')),
              NavRow(icon: Icons.privacy_tip_outlined, title: 'سياسة الخصوصية', onTap: () => context.push('/legal/privacy'), showDivider: false),
            ]),
            const SizedBox(height: 18),
            AppButton(
              label: user == null ? 'تسجيل الدخول' : 'تسجيل الخروج',
              secondary: user != null,
              onPressed: () async {
                if (user == null) {
                  context.push('/login');
                  return;
                }
                await ref.read(sessionProvider.notifier).logout();
                if (context.mounted) context.go('/home');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key});

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  late final _name = TextEditingController(text: ref.read(sessionProvider).user?.name ?? '');
  bool _loading = false;

  Future<void> _save() async {
    setState(() => _loading = true);
    final user = await ref.read(apiProvider).updateMe({'name': _name.text.trim()});
    ref.read(sessionProvider.notifier).setUser(user);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider).user;
    return Scaffold(
      appBar: AppBar(title: const Text('بيانات الحساب')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            AppField(label: 'الاسم', controller: _name),
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerRight, child: Text(user?.phone ?? '', style: const TextStyle(color: AppColors.muted))),
            const Spacer(),
            AppButton(label: 'حفظ', loading: _loading, onPressed: _save),
          ],
        ),
      ),
    );
  }
}

class NotificationSettingsPage extends ConsumerStatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  ConsumerState<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends ConsumerState<NotificationSettingsPage> {
  late bool _orders = ref.read(sessionProvider).user?.notifOrders ?? true;
  late bool _chat = ref.read(sessionProvider).user?.notifChat ?? true;

  Future<void> _save(bool orders, bool chat) async {
    setState(() {
      _orders = orders;
      _chat = chat;
    });
    final user = await ref.read(apiProvider).updateMe({'notifOrders': orders, 'notifChat': chat});
    ref.read(sessionProvider.notifier).setUser(user);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإشعارات')),
      body: ListView(
        children: [
          SwitchListTile(title: const Text('تحديثات الطلب'), value: _orders, activeThumbColor: AppColors.petrol, onChanged: (value) => _save(value, _chat)),
          SwitchListTile(title: const Text('رسائل المندوب'), value: _chat, activeThumbColor: AppColors.petrol, onChanged: (value) => _save(_orders, value)),
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('إشعار الجوال يظهر خارج التطبيق مع صوت التنبيه إذا كان إذن الإشعارات مفعّلًا.', style: TextStyle(color: AppColors.muted)),
          ),
        ],
      ),
    );
  }
}

class LanguagePage extends StatelessWidget {
  const LanguagePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اللغة')),
      body: const ListTile(
        title: Text('العربية'),
        subtitle: Text('لغة التطبيق'),
        trailing: Icon(Icons.check, color: AppColors.petrol),
      ),
    );
  }
}

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  List<dynamic> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(apiProvider).notifications();
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإشعارات')),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(20), child: SkeletonBox(height: 64))
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _items.isEmpty
                  ? const EmptyView(title: 'لا توجد إشعارات', body: 'تحديثات طلباتك هتظهر هنا.')
                  : ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = _items[index] as Map;
                        return ListTile(
                          title: Text(item['title'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(item['body'] as String),
                          onTap: () async {
                            await ref.read(apiProvider).readNotification(item['id'] as String);
                            final orderId = item['orderId'] as String?;
                            if (orderId != null && context.mounted) context.push('/orders/$orderId');
                          },
                        );
                      },
                    ),
    );
  }
}

class SupportPage extends ConsumerStatefulWidget {
  const SupportPage({super.key, required this.kind});
  final String kind;

  @override
  ConsumerState<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends ConsumerState<SupportPage> {
  final _subject = TextEditingController();
  final _message = TextEditingController();
  String _ticketKind = 'ORDER';
  List<dynamic> _faq = [];
  Map<String, dynamic>? _legal;
  String? _sent;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiProvider);
    if (widget.kind == 'faq') {
      final faq = await api.faq();
      if (mounted) setState(() => _faq = faq);
    } else if (widget.kind == 'terms' || widget.kind == 'privacy') {
      final legal = await api.legal(widget.kind);
      if (mounted) setState(() => _legal = legal);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.kind) {
      'faq' => 'الأسئلة الشائعة',
      'terms' => 'الشروط والأحكام',
      'privacy' => 'سياسة الخصوصية',
      'business' => 'النشاط',
      _ => 'الدعم',
    };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: widget.kind == 'contact'
          ? ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    for (final item in const [('ORDER', 'مشكلة في طلب'), ('COURIER', 'مندوب'), ('COLLECTION', 'تحصيل'), ('LATE', 'تأخر'), ('DAMAGED', 'تالف'), ('MISSING', 'مفقود'), ('OTHER', 'أخرى')])
                      ChoiceChip(label: Text(item.$2), selected: _ticketKind == item.$1, onSelected: (_) => setState(() => _ticketKind = item.$1)),
                  ],
                ),
                const SizedBox(height: 10),
                AppField(label: 'الموضوع', controller: _subject),
                const SizedBox(height: 10),
                AppField(label: 'الرسالة', controller: _message, maxLines: 4),
                const SizedBox(height: 16),
                AppButton(
                  label: 'إرسال',
                  onPressed: () async {
                    await ref.read(apiProvider).ticket(kind: _ticketKind, subject: _subject.text.trim(), message: _message.text.trim());
                    setState(() => _sent = 'وصلنا رسالتك وهنراجعها.');
                  },
                ),
                if (_sent != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_sent!)),
              ],
            )
          : widget.kind == 'faq'
              ? ListView(
                  children: [
                    for (final item in _faq)
                      ExpansionTile(title: Text((item as Map)['question'] as String), children: [
                        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), child: Text(item['answer'] as String)),
                      ]),
                  ],
                )
              : widget.kind == 'business'
                  ? const _BusinessInfo()
                  : Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(_legal?['body'] as String? ?? '', style: const TextStyle(height: 1.6)),
                    ),
    );
  }
}

class _BusinessInfo extends ConsumerStatefulWidget {
  const _BusinessInfo();

  @override
  ConsumerState<_BusinessInfo> createState() => _BusinessInfoState();
}

class _BusinessInfoState extends ConsumerState<_BusinessInfo> {
  Map<String, dynamic>? _business;

  @override
  void initState() {
    super.initState();
    ref.read(apiProvider).business().then((value) {
      if (mounted) setState(() => _business = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final business = _business;
    if (business == null) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(business['name'] as String, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(business['addressLine'] as String? ?? ''),
        Text(business['phone'] as String? ?? '', style: const TextStyle(color: AppColors.muted)),
        Text(business['category'] as String? ?? '', style: const TextStyle(color: AppColors.muted)),
      ],
    );
  }
}
