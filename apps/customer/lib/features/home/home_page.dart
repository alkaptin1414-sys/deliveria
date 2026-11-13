import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/brand_art.dart';
import '../../core/widgets/ui.dart';
import '../session/session_controller.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  List<Map<String, dynamic>> _active = [];
  List<Map<String, dynamic>> _restaurants = [];
  Map<String, dynamic>? _stats;
  String _place = 'حدد موقعك من العناوين';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _openRequest(String? preset) {
    if (ref.read(sessionProvider).user == null) {
      context.push('/login');
      return;
    }
    context.push('/request', extra: preset);
  }

  Future<void> _load() async {
    if (ref.read(sessionProvider).user == null) {
      try {
        final restaurants = await ref.read(apiProvider).restaurants();
        if (!mounted) return;
        setState(() {
          _restaurants = restaurants.take(4).toList();
          _loading = false;
          _error = null;
          _active = [];
        });
      } on ApiException catch (error) {
        if (mounted) setState(() { _error = error.message; _loading = false; });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider);
      final orders = await api.orders('active');
      final addresses = await api.addresses();
      Map<String, dynamic>? stats;
      Map<String, dynamic>? business;
      final user = ref.read(sessionProvider).user;
      String place = 'حدد موقعك من العناوين';
      if (user?.isBusiness == true) {
        try {
          business = await api.business();
          stats = await api.businessStats();
          place = business['addressLine'] as String? ?? place;
        } on ApiException catch (error) {
          if (error.code == 'NOT_FOUND' && mounted) {
            context.go('/business-setup');
            return;
          }
        }
      } else {
        for (final address in addresses) {
          if (address.isDefault) place = address.line;
        }
        if (place == 'حدد موقعك من العناوين' && addresses.isNotEmpty) place = addresses.first.line;
      }
      final restaurants = await api.restaurants();
      if (!mounted) return;
      setState(() {
        _restaurants = restaurants.take(4).toList();
        _active = orders.map((order) => order.json).toList();
        _stats = stats;
        _place = place;
        _loading = false;
      });
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
    final user = ref.watch(sessionProvider).user;
    final name = user?.firstName.isNotEmpty == true ? user!.firstName : 'بك';
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.petrol,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(greeting(), style: const TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w600)),
                        Text(name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1.15)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => context.push('/notifications'),
                    icon: const Icon(Icons.notifications_none, color: AppColors.ink),
                  ),
                  const SizedBox(width: 4),
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.petrolSoft,
                    child: Text(name.substring(0, 1), style: const TextStyle(color: AppColors.petrol, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.place_outlined, size: 16, color: AppColors.muted),
                  const SizedBox(width: 4),
                  Expanded(child: Text(_place, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.inkSoft, fontSize: 13))),
                ],
              ),
              const SizedBox(height: 18),
              if (_loading) const _HomeSkeleton() else if (_error != null) ErrorView(message: _error!, onRetry: _load) else if (user?.isBusiness == true) ...[
                _Hero(
                  title: 'طلب مندوب من المحل',
                  body: 'الاستلام من عنوان النشاط، وتكتب بيانات العميل ووجهة التسليم.',
                  action: 'اطلب مندوب',
                  onTap: () => _openRequest('SHOP'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: () => context.push('/quick'), child: const Text('طلب سريع')),
                const SizedBox(height: 16),
                _RestaurantStrip(restaurants: _restaurants),
                const SizedBox(height: 16),
                const SectionLabel('إدارة النشاط'),
                SurfaceGroup(
                  children: [
                    NavRow(icon: Icons.people_outline, title: 'عملائي', onTap: () => context.push('/customers')),
                    NavRow(icon: Icons.account_balance_wallet_outlined, title: 'الحسابات والتسويات', onTap: () => context.push('/finance')),
                    NavRow(icon: Icons.insights_outlined, title: 'التقارير', onTap: () => context.push('/reports'), showDivider: false),
                  ],
                ),
                if (_stats != null) ...[
                  const SizedBox(height: 16),
                  _Stats(stats: _stats!),
                ],
                if (_active.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const SectionLabel('الطلبات الجارية'),
                  for (final order in _active) ...[
                    _ActiveOrder(order: order, onOpen: () => context.push('/orders/${order['id']}')),
                    const SizedBox(height: 8),
                  ],
                ],
              ] else ...[
                _Hero(
                  title: 'محتاج مندوب؟',
                  body: 'مندوبك يوصّل طلبك بسرعة وأمان.',
                  action: 'اطلب مندوب الآن',
                  art: BrandArt.riderOnPetrol,
                  onTap: () => _openRequest(null),
                ),
                const SizedBox(height: 18),
                _RestaurantStrip(restaurants: _restaurants),
                const SizedBox(height: 18),
                const SectionLabel('الخدمات'),
                SurfaceGroup(
                  children: [
                    NavRow(
                      icon: Icons.local_shipping_outlined,
                      title: 'توصيل طلب',
                      subtitle: 'استلام من عنوان وتسليمه لعنوان آخر.',
                      onTap: () => _openRequest(null),
                    ),
                    NavRow(
                      icon: Icons.inventory_2_outlined,
                      title: 'إرسال غرض',
                      subtitle: 'طرد أو مستند أو غرض شخصي.',
                      showDivider: false,
                      onTap: () => _openRequest('PERSONAL'),
                    ),
                  ],
                ),
                if (_active.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const SectionLabel('طلبك الحالي'),
                  _ActiveOrder(order: _active.first, onOpen: () => context.push('/orders/${_active.first['id']}')),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.title, required this.body, required this.action, required this.onTap, this.art});
  final String title;
  final String body;
  final String action;
  final VoidCallback onTap;
  final String? art;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(color: AppColors.petrol, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(body, style: const TextStyle(color: Color(0xD9FFFFFF), fontSize: 14, height: 1.35)),
                  ],
                ),
              ),
              if (art != null) ...[
                const SizedBox(width: 8),
                BrandArt(art!, size: 72, semanticLabel: 'مندوب توصيل'),
              ],
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            width: double.infinity,
            child: FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.petrol,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(action, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveOrder extends StatelessWidget {
  const _ActiveOrder({required this.order, required this.onOpen});
  final Map<String, dynamic> order;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.petrol, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(order['recipientName'] as String? ?? order['statusTitle'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${order['publicNumber']} · ${order['statusTitle'] ?? ''}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                ],
              ),
            ),
            Text(
              const {'ACCEPTED', 'EN_ROUTE_PICKUP', 'PICKED_UP', 'EN_ROUTE_DROPOFF'}.contains(order['status']) ? 'تتبع المندوب' : 'متابعة',
              style: const TextStyle(color: AppColors.petrol, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.stats});
  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('طلبات اليوم', '${stats['today']}'),
      ('جارية', '${stats['active']}'),
      ('مصاريف التوصيل', stats['totalLabel'] as String? ?? money(stats['totalMinor'] as int? ?? 0)),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: Column(
                children: [
                  Text(item.$2, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(item.$1, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RestaurantStrip extends StatelessWidget {
  const _RestaurantStrip({required this.restaurants});
  final List<Map<String, dynamic>> restaurants;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: SectionLabel('المطاعم')),
            TextButton(onPressed: () => context.push('/restaurants'), child: const Text('عرض الكل')),
          ],
        ),
        if (restaurants.isEmpty)
          const Text('لا توجد مطاعم ظاهرة في منطقة الخدمة الآن.', style: TextStyle(color: AppColors.muted))
        else
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: restaurants.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, index) {
                final restaurant = restaurants[index];
                final ordering = Map<String, dynamic>.from(restaurant['ordering'] as Map? ?? {});
                return SizedBox(
                  width: 210,
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => context.push('/restaurants/${restaurant['id']}'),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(restaurant['name'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text(restaurant['cuisine'] as String? ?? '', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                            Text(restaurant['ratingLabel'] as String? ?? '', style: const TextStyle(fontSize: 12)),
                            Text('${restaurant['etaMinutes']} د · ${restaurant['deliveryFeeLabel']}', style: const TextStyle(fontSize: 12)),
                            Text(ordering['label'] as String? ?? '', style: const TextStyle(color: AppColors.petrol, fontSize: 12, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SkeletonBox(height: 132, radius: 18),
        SizedBox(height: 16),
        SkeletonBox(height: 148, radius: 16),
      ],
    );
  }
}
