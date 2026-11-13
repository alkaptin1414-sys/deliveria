import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/firebase_account.dart';
import '../../core/models.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ui.dart';
import '../session/session_controller.dart';

void goAfterAuth(BuildContext context, WidgetRef ref, Map<String, dynamic> result, String intent) {
  final user = UserProfile.fromJson(Map<String, dynamic>.from(result['user'] as Map));
  ref.read(sessionProvider.notifier).setUser(user);
  if (user.isAdmin) {
    context.go('/admin');
    return;
  }
  if (user.isCourier) {
    context.go('/courier');
  } else if (intent == 'courier') {
    context.go('/courier/apply');
  } else {
    context.go(result['next'] == 'home' ? '/home' : '/profile-setup');
  }
}

class EmailAuthPage extends ConsumerStatefulWidget {
  const EmailAuthPage({super.key, this.registering = false, this.intent = 'login'});
  final bool registering;
  final String intent;

  @override
  ConsumerState<EmailAuthPage> createState() => _EmailAuthPageState();
}

class _EmailAuthPageState extends ConsumerState<EmailAuthPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (widget.registering && _password.text != _confirm.text) {
      setState(() => _error = 'كلمتا المرور غير متطابقتين.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      String? firebaseNote;
      try {
        await syncFirebaseAccount(
          email: _email.text.trim(),
          password: _password.text,
          registering: widget.registering,
          name: _name.text.trim(),
        );
      } on FirebaseAccountException catch (error) {
        firebaseNote = error.message;
      }
      Map<String, dynamic> result;
      try {
        result = widget.registering
            ? await ref.read(apiProvider).registerAccount(
                  name: _name.text.trim(),
                  email: _email.text.trim(),
                  password: _password.text,
                  role: widget.intent == 'courier' ? 'COURIER' : 'CUSTOMER',
                )
            : await ref.read(apiProvider).loginWithEmail(_email.text.trim(), _password.text);
      } on ApiException catch (error) {
        if (!widget.registering || error.code != 'EMAIL_EXISTS') rethrow;
        result = await ref.read(apiProvider).loginWithEmail(_email.text.trim(), _password.text);
      }
      if (!mounted) return;
      if (firebaseNote != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(firebaseNote)));
      }
      goAfterAuth(context, ref, result, widget.intent);
    } on ApiException catch (error) {
      final firebaseReady = Firebase.apps.isNotEmpty && FirebaseAuth.instance.currentUser != null;
      setState(() {
        _error = firebaseReady ? 'الحساب اتسجل في Firebase. ${error.message}' : error.message;
      });
    } on FirebaseException catch (error) {
      setState(() => _error = error.message ?? 'Firebase رفض إنشاء الحساب.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.registering ? (widget.intent == 'courier' ? 'إنشاء حساب مندوب' : 'إنشاء حساب عميل') : 'تسجيل الدخول';
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
          children: [
            const DeliveriaMark(size: 42),
            const SizedBox(height: 28),
            Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.2)),
            const SizedBox(height: 8),
            Text(
              widget.registering ? 'البريد وكلمة المرور يتحفظان على الخادم. كلمة المرور لا تُخزَّن كما هي.' : 'ادخل بالبريد وكلمة المرور.',
              style: const TextStyle(color: AppColors.muted, fontSize: 15),
            ),
            const SizedBox(height: 24),
            if (widget.registering) ...[
              TextField(controller: _name, textInputAction: TextInputAction.next, decoration: _field('الاسم بالكامل')),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: _field('البريد الإلكتروني'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: _obscure,
              decoration: _field('كلمة المرور').copyWith(
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                ),
              ),
            ),
            if (widget.registering) ...[
              const SizedBox(height: 12),
              TextField(controller: _confirm, obscureText: _obscure, decoration: _field('تأكيد كلمة المرور')),
              const SizedBox(height: 8),
              const Text('8 أحرف على الأقل.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 24),
            AppButton(label: widget.registering ? 'إنشاء الحساب' : 'دخول', loading: _loading, onPressed: _loading ? null : _submit),
            TextButton(
              onPressed: () => context.push('/phone', extra: widget.intent),
              child: const Text('دخول برقم الموبايل'),
            ),
            if (!widget.registering)
              TextButton(
                onPressed: () => context.push('/register', extra: 'customer'),
                child: const Text('إنشاء حساب جديد'),
              ),
          ],
        ),
      ),
    );
  }

  InputDecoration _field(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.petrol, width: 1.4)),
    );
  }
}

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key, this.intent = 'login'});
  final String intent;

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _phone = TextEditingController();
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref.read(apiProvider).requestOtp(_phone.text.trim());
      if (!mounted) return;
      context.push('/otp', extra: {...result, 'intent': widget.intent});
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
          children: [
              const DeliveriaMark(size: 42),
              const SizedBox(height: 28),
              const Text('أدخل رقم هاتفك', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.2)),
              const SizedBox(height: 8),
              const Text('هنبعتلك رمز من 6 أرقام لتأكيد الدخول.', style: TextStyle(color: AppColors.muted, fontSize: 15)),
              const SizedBox(height: 28),
              Text('رقم الموبايل', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkSoft)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: const Text('مصر  +20', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.4),
                      decoration: InputDecoration(
                        hintText: '01xxxxxxxxx',
                        filled: true,
                        fillColor: Colors.white,
                        errorText: _error,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.line)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.line)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.petrol, width: 1.4)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              AppButton(label: 'متابعة', loading: _loading, onPressed: _loading ? null : _submit),
            ],
        ),
      ),
    );
  }
}

class OtpPage extends ConsumerStatefulWidget {
  const OtpPage({super.key, required this.payload});
  final Map<String, dynamic> payload;

  @override
  ConsumerState<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends ConsumerState<OtpPage> {
  final _controller = TextEditingController();
  String? _error;
  bool _loading = false;

  Future<void> _verify(String code) async {
    if (code.length < 6 || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref.read(apiProvider).verifyOtp(widget.payload['challengeId'] as String, code);
      if (!mounted) return;
      goAfterAuth(context, ref, result, widget.payload['intent'] as String? ?? 'login');
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final devCode = widget.payload['devCode'] as String?;
    return Scaffold(
      appBar: AppBar(),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('رمز التأكيد', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('اتبعث على ${widget.payload['phone']}', style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 28),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              onChanged: _verify,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: 8),
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: Colors.white,
                errorText: _error,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            if (devCode != null) ...[
              const SizedBox(height: 12),
              Text('رمز بيئة التطوير: $devCode', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ],
            const SizedBox(height: 28),
            AppButton(label: 'تأكيد', loading: _loading, onPressed: () => _verify(_controller.text)),
          ],
        ),
      ),
    );
  }
}

class ProfileSetupPage extends ConsumerStatefulWidget {
  const ProfileSetupPage({super.key});

  @override
  ConsumerState<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends ConsumerState<ProfileSetupPage> {
  final _name = TextEditingController();
  String _type = 'PERSONAL';
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await ref.read(apiProvider).completeProfile(_name.text.trim(), _type);
      ref.read(sessionProvider.notifier).setUser(user);
      if (!mounted) return;
      context.go(user.isBusiness ? '/business-setup' : '/home');
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          children: [
            const Text('حسابك هيبقى لمين؟', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, height: 1.25)),
            const SizedBox(height: 8),
            const Text('تقدر تطلب مندوب لنفسك أو لنشاطك التجاري.', style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 24),
            AppField(label: 'الاسم', controller: _name, hint: 'اسمك'),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: AppColors.danger))),
            const SizedBox(height: 16),
            _TypeCard(
              selected: _type == 'PERSONAL',
              title: 'حساب شخصي',
              body: 'لطلب مندوب لتوصيل الأغراض والمشاوير الشخصية.',
              icon: Icons.person_outline,
              onTap: () => setState(() => _type = 'PERSONAL'),
            ),
            const SizedBox(height: 10),
            _TypeCard(
              selected: _type == 'BUSINESS',
              title: 'حساب نشاط تجاري',
              body: 'للمحلات والصيدليات والمطاعم والشركات التي تحتاج توصيل الطلبات.',
              icon: Icons.storefront_outlined,
              onTap: () => setState(() => _type = 'BUSINESS'),
            ),
            const SizedBox(height: 24),
            AppButton(label: 'متابعة', loading: _loading, onPressed: _loading ? null : _submit),
          ],
        ),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.selected,
    required this.title,
    required this.body,
    required this.icon,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String body;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? AppColors.petrol : AppColors.line, width: selected ? 1.4 : 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? AppColors.petrol : AppColors.inkSoft),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(body, style: const TextStyle(color: AppColors.muted, fontSize: 13, height: 1.35)),
                ],
              ),
            ),
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? AppColors.petrol : AppColors.muted),
          ],
        ),
      ),
    );
  }
}
