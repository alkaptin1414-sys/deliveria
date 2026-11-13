import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/ui.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../session/session_controller.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      await Future.wait([
        ref.read(sessionProvider.notifier).bootstrap(),
        Future<void>.delayed(const Duration(milliseconds: 700)),
      ]).timeout(const Duration(seconds: 12));
    } catch (_) {}
    if (!mounted) return;
    final session = ref.read(sessionProvider);
    final user = session.user;
    if (user == null) {
      context.go('/welcome');
      return;
    }
    if (user.isAdmin) {
      context.go('/admin');
      return;
    }
    if (user.isCourier) {
      context.go('/courier');
      return;
    }
    if (user.name == null || user.accountType == null) {
      context.go('/profile-setup');
      return;
    }
    if (user.isBusiness) {
      try {
        await ref.read(apiProvider).business();
      } on ApiException catch (error) {
        if (error.code == 'NOT_FOUND' && mounted) {
          context.go('/business-setup');
          return;
        }
      }
    }
    if (!mounted) return;
    context.go('/home');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.petrol,
      body: Center(
        child: FadeTransition(
          opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut)),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DeliveriaMark(size: 72, onDark: true),
                SizedBox(height: 16),
                Wordmark(onDark: true, size: 34),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
