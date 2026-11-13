import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/models.dart';
import 'core/theme/tokens.dart';
import 'features/account/account_pages.dart';
import 'features/admin/admin_page.dart';
import 'features/addresses/addresses_page.dart';
import 'features/auth/auth_pages.dart';
import 'features/business/business_hub.dart';
import 'features/business/business_setup_page.dart';
import 'features/home/home_page.dart';
import 'features/orders/orders_pages.dart';
import 'features/orders/request_page.dart';
import 'features/orders/tracking_page.dart';
import 'features/restaurants/restaurants_pages.dart';
import 'features/shell/main_shell.dart';
import 'features/splash/splash_page.dart';
import 'features/auth/welcome_page.dart';
import 'features/courier/courier_pages.dart';

class DeliveriaApp extends ConsumerWidget {
  const DeliveriaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'دليفريه',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
    );
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashPage()),
      GoRoute(path: '/welcome', builder: (_, __) => const WelcomePage()),
      GoRoute(path: '/login', builder: (_, __) => const EmailAuthPage()),
      GoRoute(
        path: '/register',
        builder: (_, state) => EmailAuthPage(registering: true, intent: state.extra as String? ?? 'customer'),
      ),
      GoRoute(path: '/phone', builder: (_, state) => LoginPage(intent: state.extra as String? ?? 'login')),
      GoRoute(
        path: '/otp',
        builder: (_, state) => OtpPage(payload: Map<String, dynamic>.from(state.extra as Map)),
      ),
      GoRoute(path: '/profile-setup', builder: (_, __) => const ProfileSetupPage()),
      GoRoute(path: '/business-setup', builder: (_, __) => const BusinessSetupPage()),
      GoRoute(path: '/customers', builder: (_, __) => const CustomersPage()),
      GoRoute(path: '/finance', builder: (_, __) => const FinancePage()),
      GoRoute(path: '/reports', builder: (_, __) => const ReportsPage()),
      GoRoute(path: '/quick', builder: (_, __) => const QuickOrderPage()),
      GoRoute(path: '/restaurants', builder: (_, __) => const RestaurantsPage()),
      GoRoute(path: '/restaurants/:id', builder: (_, state) => RestaurantPage(id: state.pathParameters['id']!)),
      GoRoute(path: '/restaurants/:id/cart', builder: (_, state) => FoodCartPage(restaurantId: state.pathParameters['id']!)),
      GoRoute(path: '/food-orders/:id', builder: (_, state) => FoodOrderPage(id: state.pathParameters['id']!)),
      ShellRoute(
        builder: (_, __, child) => MainShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomePage()),
          GoRoute(path: '/orders', builder: (_, __) => const OrdersPage()),
          GoRoute(path: '/addresses', builder: (_, __) => const AddressesPage()),
          GoRoute(path: '/account', builder: (_, __) => const AccountPage()),
        ],
      ),
      GoRoute(
        path: '/request',
        builder: (_, state) {
          final extra = state.extra;
          if (extra is DeliveryOrder) return RequestPage(reorder: extra);
          return RequestPage(preset: extra as String?);
        },
      ),
      GoRoute(path: '/orders/:id', builder: (_, state) => TrackingPage(id: state.pathParameters['id']!)),
      GoRoute(path: '/orders/:id/details', builder: (_, state) => OrderDetailPage(id: state.pathParameters['id']!)),
      GoRoute(path: '/orders/:id/chat', builder: (_, state) => ChatPage(id: state.pathParameters['id']!)),
      GoRoute(path: '/orders/:id/review', builder: (_, state) => ReviewPage(id: state.pathParameters['id']!)),
      GoRoute(path: '/couriers/:id/ratings', builder: (_, state) => CourierRatingsPage(courierId: state.pathParameters['id']!)),
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsPage()),
      GoRoute(path: '/account/edit', builder: (_, __) => const EditProfilePage()),
      GoRoute(path: '/account/notifications', builder: (_, __) => const NotificationSettingsPage()),
      GoRoute(path: '/account/language', builder: (_, __) => const LanguagePage()),
      GoRoute(path: '/account/business', builder: (_, __) => const SupportPage(kind: 'business')),
      GoRoute(path: '/support/contact', builder: (_, __) => const SupportPage(kind: 'contact')),
      GoRoute(path: '/support/faq', builder: (_, __) => const SupportPage(kind: 'faq')),
      GoRoute(path: '/legal/:kind', builder: (_, state) => SupportPage(kind: state.pathParameters['kind']!)),
      GoRoute(path: '/admin', builder: (_, __) => const AdminHomePage()),
      ShellRoute(
        builder: (_, __, child) => CourierShell(child: child),
        routes: [
          GoRoute(path: '/courier', builder: (_, __) => const CourierHomePage()),
          GoRoute(path: '/courier/history', builder: (_, __) => const CourierHistoryPage()),
          GoRoute(path: '/courier/earnings', builder: (_, __) => const CourierEarningsPage()),
          GoRoute(path: '/courier/account', builder: (_, __) => const CourierAccountPage()),
        ],
      ),
      GoRoute(path: '/courier/apply', builder: (_, __) => const CourierApplyPage()),
      GoRoute(
        path: '/courier/job',
        builder: (_, state) => CourierJobPage(job: Map<String, dynamic>.from(state.extra as Map? ?? {})),
      ),
      GoRoute(path: '/courier/ratings', builder: (_, __) => const CourierRatingsView()),
    ],
  );
});
