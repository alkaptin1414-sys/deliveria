import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/ui.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
          children: [
            const DeliveriaMark(size: 64),
            const SizedBox(height: 16),
            const Wordmark(size: 32),
            const SizedBox(height: 8),
            const Text('Deliveria', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 28),
            const Text('أهلاً بيك في دليفريه', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.ink, height: 1.3)),
            const SizedBox(height: 8),
            const Text('اختَر نوع الحساب. النوع بيتسجل على الخادم مع هويتك، مش جوه التطبيق فقط.', style: TextStyle(color: AppColors.muted, height: 1.5)),
            const SizedBox(height: 28),
            _Choice(
              title: 'التسجيل كعميل',
              body: 'اطلب طعام، أو اطلب مندوب لنقل الأغراض.',
              onTap: () => context.push('/register', extra: 'customer'),
            ),
            const SizedBox(height: 12),
            _Choice(
              title: 'التسجيل كمندوب دليفري',
              body: 'استقبل طلبات التوصيل بعد مراجعة بياناتك واعتماد الحساب.',
              onTap: () => context.push('/register', extra: 'courier'),
            ),
            const SizedBox(height: 28),
            AppButton(label: 'تسجيل الدخول', onPressed: () => context.push('/login')),
            const SizedBox(height: 8),
            TextButton(onPressed: () => context.go('/home'), child: const Text('تصفح كزائر')),
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.title, required this.body, required this.onTap});
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink)),
              const SizedBox(height: 6),
              Text(body, style: const TextStyle(color: AppColors.muted, height: 1.4)),
            ],
          ),
        ),
      ),
    );
  }
}
