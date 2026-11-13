import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/brand_art.dart';
import '../../core/widgets/ui.dart';
import '../session/session_controller.dart';

const _governorates = [
  'القاهرة', 'الجيزة', 'القليوبية', 'الإسكندرية', 'الشرقية', 'الدقهلية', 'الغربية', 'المنوفية', 'البحيرة', 'كفر الشيخ', 'دمياط', 'بورسعيد', 'الإسماعيلية', 'السويس', 'الفيوم', 'بني سويف', 'المنيا', 'أسيوط', 'سوهاج', 'قنا', 'الأقصر', 'أسوان', 'البحر الأحمر', 'الوادي الجديد', 'مطروح', 'شمال سيناء', 'جنوب سيناء',
];

const _statusLabel = {
  'PENDING_REVIEW': 'قيد المراجعة',
  'NEEDS_INFO': 'يحتاج إلى استكمال بيانات',
  'APPROVED': 'مقبول',
  'REJECTED': 'مرفوض',
  'SUSPENDED': 'موقوف إداريًا',
  'ACCEPTED': 'تم قبول الطلب',
  'EN_ROUTE_PICKUP': 'في الطريق للاستلام',
  'PICKED_UP': 'تم الاستلام',
  'EN_ROUTE_DROPOFF': 'في الطريق للتسليم',
  'DELIVERED': 'تم التسليم',
  'CANCELLED': 'ملغي',
};

const _settlementKind = {
  'WAGE_PAID': 'أجر مدفوع',
  'CASH_REMITTED': 'نقد مورّد',
  'ADJUSTMENT': 'تسوية',
};

class CourierShell extends StatelessWidget {
  const CourierShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final index = path.startsWith('/courier/history')
        ? 1
        : path.startsWith('/courier/earnings')
            ? 2
            : path.startsWith('/courier/account')
                ? 3
                : 0;
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        height: 72,
        selectedIndex: index,
        indicatorColor: AppColors.petrolSoft,
        onDestinationSelected: (value) {
          switch (value) {
            case 1:
              context.go('/courier/history');
            case 2:
              context.go('/courier/earnings');
            case 3:
              context.go('/courier/account');
            default:
              context.go('/courier');
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.work_outline), selectedIcon: Icon(Icons.work), label: 'العمل'),
          NavigationDestination(icon: Icon(Icons.history), label: 'السجل'),
          NavigationDestination(icon: Icon(Icons.payments_outlined), selectedIcon: Icon(Icons.payments), label: 'الأرباح'),
          NavigationDestination(icon: Icon(Icons.badge_outlined), selectedIcon: Icon(Icons.badge), label: 'حسابي'),
        ],
      ),
    );
  }
}

class CourierHomePage extends ConsumerStatefulWidget {
  const CourierHomePage({super.key});

  @override
  ConsumerState<CourierHomePage> createState() => _CourierHomePageState();
}

class _CourierHomePageState extends ConsumerState<CourierHomePage> {
  Map<String, dynamic>? _home;
  List<Map<String, dynamic>> _offers = [];
  String? _error;
  bool _loading = true;
  String _link = 'جارٍ الاتصال بالخادم';
  Timer? _timer;
  WebSocketChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _listen();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  void _listen() {
    final token = ref.read(sessionStoreProvider).accessToken;
    if (token == null) return;
    final base = AppConfig.apiBase.replaceFirst('http', 'ws');
    _channel = WebSocketChannel.connect(Uri.parse('$base/v1/realtime?token=$token'));
    _channel!.stream.listen((event) {
      final data = jsonDecode(event as String) as Map<String, dynamic>;
      if (data['type'] == 'offers.changed' || data['type'] == 'job.updated') _load(quiet: true);
    }, onError: (_) {
      if (mounted) setState(() => _link = 'انقطع الاتصال اللحظي. التحديث الدوري مستمر.');
    });
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet && mounted) setState(() => _error = null);
    try {
      final home = await ref.read(apiProvider).courierMe();
      final offers = await ref.read(apiProvider).courierOffers();
      if (!mounted) return;
      setState(() {
        _home = home;
        _offers = offers;
        _loading = false;
        _link = 'متصل بالخادم';
        _error = quiet ? _error : null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'COURIER_PROFILE_REQUIRED') {
        context.go('/courier/apply');
        return;
      }
      setState(() {
        _error = error.message;
        _link = error.code == 'OFFLINE' ? 'غير متصل بالخادم' : _link;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(backgroundColor: AppColors.canvas, body: Center(child: CircularProgressIndicator(color: AppColors.petrol)));
    final profile = Map<String, dynamic>.from(_home?['profile'] as Map? ?? {});
    final earnings = Map<String, dynamic>.from(_home?['earnings'] as Map? ?? {});
    final rating = Map<String, dynamic>.from(_home?['rating'] as Map? ?? {});
    final active = _home?['active'] == null ? null : Map<String, dynamic>.from(_home!['active'] as Map);
    final approved = profile['status'] == 'APPROVED';
    final todayOrders = earnings['todayOrders'];
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: RefreshIndicator(
        color: AppColors.petrol,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 24),
          children: [
            CourierAvailabilitySwitch(
              compact: true,
              approved: approved,
              available: profile['available'] == true,
              name: profile['fullName'] as String? ?? 'مندوب',
              onUpdated: _load,
            ),
            if (!approved) ...[
              const Text('لن تصلك طلبات قبل اعتماد الإدارة للحساب.', style: TextStyle(color: AppColors.muted, height: 1.4)),
              if (profile['status'] == 'NEEDS_INFO' || profile['status'] == 'REJECTED')
                Align(alignment: AlignmentDirectional.centerStart, child: TextButton(onPressed: () => context.push('/courier/apply'), child: const Text('استكمال البيانات'))),
              const SizedBox(height: 8),
            ],
            if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: const TextStyle(color: AppColors.danger, height: 1.4))),
            if (_link != 'متصل بالخادم') Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_link, style: const TextStyle(color: AppColors.muted, height: 1.4))),
            Row(
              children: [
                _Stat('طلبات اليوم', todayOrders is int ? '$todayOrders' : 'غير متاح'),
                const SizedBox(width: 8),
                _Stat('أرباح اليوم', earnings['todayLabel'] as String? ?? 'غير متاح'),
                const SizedBox(width: 8),
                _Stat('التقييم', rating['label'] as String? ?? 'لا توجد تقييمات'),
              ],
            ),
            const SizedBox(height: 16),
            const Text('الطلبات المتاحة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (_offers.isEmpty)
              _HomeCard(
                child: DeliveryEmptyState(
                  asset: BrandArt.emptyOffers,
                  artSize: 96,
                  title: 'مفيش طلبات متاحة حاليًا',
                  body: 'الطلبات الجديدة بتظهر هنا لما تكون متاحًا.',
                  action: 'تحديث الطلبات',
                  onAction: _load,
                ),
              ),
            for (final offer in _offers) _OfferCard(offer: offer, busy: false, onChanged: _load),
            const Text('الطلبات النشطة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (active == null)
              const _HomeCard(child: Text('لا يوجد طلب قيد التنفيذ.', style: TextStyle(color: AppColors.muted, height: 1.4)))
            else
              _HomeCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(active['publicNumber'] as String? ?? 'طلب جارٍ', style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(_statusLabel[active['status']] ?? 'قيد التنفيذ', style: const TextStyle(color: AppColors.muted)),
                    const SizedBox(height: 12),
                    CustomerContactCard(
                      embedded: true,
                      name: active['customerName'] as String? ?? active['recipientName'] as String?,
                      phone: active['customerPhone'] as String? ?? active['recipientPhone'] as String?,
                    ),
                    const SizedBox(height: 12),
                    AppButton(label: 'فتح الطلب', onPressed: () => context.push('/courier/job', extra: active)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class CourierAvailabilitySwitch extends ConsumerStatefulWidget {
  const CourierAvailabilitySwitch({
    super.key,
    required this.approved,
    required this.available,
    required this.onUpdated,
    this.name,
    this.compact = false,
  });

  final bool approved;
  final bool available;
  final Future<void> Function() onUpdated;
  final String? name;
  final bool compact;

  @override
  ConsumerState<CourierAvailabilitySwitch> createState() => _CourierAvailabilitySwitchState();
}

class _CourierAvailabilitySwitchState extends ConsumerState<CourierAvailabilitySwitch> {
  bool _busy = false;
  String? _error;

  Future<Position?> _position() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('سبب استخدام الموقع'),
        content: const Text('الموقع يُستخدم لإظهار طلبات قريبة وتحديث نقطة عملك أثناء مهمة. لا يوجد تتبع مستمر في الخلفية.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('رفض')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('متابعة')),
        ],
      ),
    );
    if (proceed != true) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (mounted) setState(() => _error = 'بدون إذن الموقع لا يمكن إظهارك متاحًا. اسمح بالموقع من إعدادات الهاتف.');
      return null;
    }
    try {
      return await Geolocator.getCurrentPosition();
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر قراءة الموقع. تأكد من الإنترنت وGPS ثم أعد المحاولة.');
      return null;
    }
  }

  Future<void> _toggle(bool value) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!value) {
        await ref.read(apiProvider).courierAvailability(false);
      } else {
        final position = await _position();
        if (position == null) return;
        await ref.read(apiProvider).courierAvailability(true, lat: position.latitude, lng: position.longitude);
      }
      await widget.onUpdated();
    } on ApiException catch (error) {
      setState(() => _error = error.code == 'OFFLINE' ? 'تعذر حفظ الحالة. لا يوجد اتصال بالخادم.' : error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final control = Switch(
      value: widget.available,
      activeThumbColor: AppColors.petrol,
      onChanged: !widget.approved || _busy ? null : _toggle,
    );
    final note = _error == null
        ? null
        : Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: AppColors.danger, height: 1.4)));
    if (widget.compact) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('مرحبًا، ${widget.name ?? 'مندوب'}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(widget.available ? 'تستقبل الطلبات' : 'لا تستقبل الطلبات', style: const TextStyle(color: AppColors.muted)),
                    ],
                  ),
                ),
                control,
              ],
            ),
            if (note != null) note,
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: Text('متاح لاستقبال الطلبات', style: TextStyle(fontWeight: FontWeight.w700))),
            control,
          ],
        ),
        const Text('الموقع يُرسل عند التوفر وأثناء المهمة فقط. الحالة المعروضة هي المحفوظة على الخادم.', style: TextStyle(color: AppColors.muted, height: 1.4)),
        if (note != null) note,
      ],
    );
  }
}

class CustomerContactCard extends StatelessWidget {
  const CustomerContactCard({super.key, this.name, this.phone, this.embedded = false});
  final String? name;
  final String? phone;
  final bool embedded;

  Future<void> _call(BuildContext context, String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد تطبيق اتصال على هذا الجهاز.')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد تطبيق اتصال على هذا الجهاز.')));
      }
    }
  }

  Future<void> _copy(BuildContext context, String phone) async {
    await Clipboard.setData(ClipboardData(text: phone));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ رقم العميل.')));
  }

  @override
  Widget build(BuildContext context) {
    final number = phone?.trim();
    if (number == null || number.isEmpty) return const SizedBox.shrink();
    final label = name?.trim();
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('بيانات العميل', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        if (label != null && label.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('اسم العميل', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4)),
        ],
        const SizedBox(height: 8),
        Text('رقم الهاتف', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        Text(number, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: AppButton(label: 'اتصال بالعميل', onPressed: () => _call(context, number))),
            const SizedBox(width: 8),
            SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: () => _copy(context, number),
                child: const Text('نسخ'),
              ),
            ),
          ],
        ),
      ],
    );
    if (embedded) return body;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
      child: body,
    );
  }
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
      child: child,
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppColors.muted, height: 1.3)),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.petrol)),
          ],
        ),
      ),
    );
  }
}

class _OfferCard extends ConsumerStatefulWidget {
  const _OfferCard({required this.offer, required this.busy, required this.onChanged});
  final Map<String, dynamic> offer;
  final bool busy;
  final Future<void> Function() onChanged;

  @override
  ConsumerState<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends ConsumerState<_OfferCard> {
  bool _busy = false;

  Future<void> _act(bool accept) async {
    setState(() => _busy = true);
    try {
      if (accept) {
        final job = await ref.read(apiProvider).courierAccept(widget.offer['id'] as String);
        if (!mounted) return;
        context.push('/courier/job', extra: job);
      } else {
        await ref.read(apiProvider).courierDecline(widget.offer['id'] as String);
      }
      await widget.onChanged();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pickup = Map<String, dynamic>.from(widget.offer['pickup'] as Map? ?? {});
    final dropoff = Map<String, dynamic>.from(widget.offer['dropoff'] as Map? ?? {});
    final kind = widget.offer['kind'] == 'FOOD' ? 'طعام من مطعم' : 'توصيل عادي';
    final toPickup = widget.offer['distanceToPickupMeters'] as int? ?? 0;
    final trip = widget.offer['tripMeters'] as int? ?? 0;
    final goods = widget.offer['goodsMinor'] as int? ?? 0;
    final collect = widget.offer['collectMinor'] as int? ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(widget.offer['publicNumber'] as String? ?? kind, style: const TextStyle(fontWeight: FontWeight.w800))),
              StatusChip(kind),
            ],
          ),
          if (widget.offer['restaurant'] != null) ...[
            const SizedBox(height: 8),
            Text(widget.offer['restaurant'] as String, style: const TextStyle(height: 1.4)),
          ],
          if ((widget.offer['description'] as String?)?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(widget.offer['description'] as String, style: const TextStyle(color: AppColors.muted, height: 1.4)),
          ],
          const SizedBox(height: 12),
          Text('مكان الاستلام', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          Text(pickup['line'] as String? ?? 'غير مسجّل', style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4)),
          const SizedBox(height: 8),
          Text('مكان التسليم', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          Text(dropoff['line'] as String? ?? 'غير مسجّل', style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4)),
          if (toPickup > 0 || trip > 0) ...[
            const SizedBox(height: 8),
            Text('${toPickup > 0 ? 'للموقع ${kmLabel(toPickup)}' : ''}${toPickup > 0 && trip > 0 ? ' · ' : ''}${trip > 0 ? 'الرحلة ${kmLabel(trip)}' : ''}', style: const TextStyle(color: AppColors.muted)),
          ],
          const SizedBox(height: 8),
          Text('أجرتك ${widget.offer['payoutLabel'] ?? ''}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.petrol)),
          if (goods > 0) Text('قيمة البضاعة ${widget.offer['goodsLabel'] ?? money(goods)} وليست من أجرتك', style: const TextStyle(height: 1.4)),
          if (collect > 0) Text('تحصيل نقدي ${widget.offer['collectLabel'] ?? money(collect)} وليس من أرباحك', style: const TextStyle(height: 1.4)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: AppButton(label: 'رفض', secondary: true, loading: _busy || widget.busy, onPressed: _busy ? null : () => _act(false))),
              const SizedBox(width: 8),
              Expanded(child: AppButton(label: 'قبول', loading: _busy || widget.busy, onPressed: _busy ? null : () => _act(true))),
            ],
          ),
        ],
      ),
    );
  }
}

class CourierJobPage extends ConsumerStatefulWidget {
  const CourierJobPage({super.key, required this.job});
  final Map<String, dynamic> job;

  @override
  ConsumerState<CourierJobPage> createState() => _CourierJobPageState();
}

class _CourierJobPageState extends ConsumerState<CourierJobPage> {
  late Map<String, dynamic> _job = widget.job;
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;
  Timer? _timer;
  WebSocketChannel? _channel;
  StreamSubscription<Position>? _positions;
  GoogleMapController? _map;
  LatLng? _courierPoint;
  DateTime? _courierUpdatedAt;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _listen();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positions?.cancel();
    _channel?.sink.close();
    _code.dispose();
    super.dispose();
  }

  void _listen() {
    final token = ref.read(sessionStoreProvider).accessToken;
    if (token == null) return;
    final base = AppConfig.apiBase.replaceFirst('http', 'ws');
    _channel = WebSocketChannel.connect(Uri.parse('$base/v1/realtime?token=$token'));
    _channel!.stream.listen((event) {
      final data = jsonDecode(event as String) as Map<String, dynamic>;
      if (data['type'] == 'job.updated' && data['orderId'] == _job['id']) _refresh();
    });
  }

  Future<void> _refresh() async {
    final id = _job['id'] as String?;
    if (id == null) return;
    try {
      final job = await ref.read(apiProvider).courierJob(id);
      if (!mounted) return;
      setState(() => _job = job);
      _syncTracking(job['status'] as String?);
      if (job['status'] == 'CANCELLED') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أُلغي الطلب ولم يعد مسندًا إليك.')));
        context.go('/courier');
      }
    } on ApiException catch (error) {
      if (mounted && error.code == 'OFFLINE') setState(() => _error = error.message);
    }
  }

  String? get _next {
    switch (_job['status']) {
      case 'ACCEPTED':
        return 'EN_ROUTE_PICKUP';
      case 'EN_ROUTE_PICKUP':
        return 'PICKED_UP';
      case 'PICKED_UP':
        return 'EN_ROUTE_DROPOFF';
      default:
        return null;
    }
  }

  String get _nextLabel {
    switch (_next) {
      case 'EN_ROUTE_PICKUP':
        return 'توجهت إلى الاستلام';
      case 'PICKED_UP':
        return 'وصلت واستلمت الطلب';
      case 'EN_ROUTE_DROPOFF':
        return 'توجهت إلى العميل';
      default:
        return '';
    }
  }

  Future<void> _advance() async {
    final next = _next;
    if (next == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final job = await ref.read(apiProvider).courierAdvance(_job['id'] as String, next);
      if (mounted) setState(() => _job = job);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deliver() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).courierDeliver(_job['id'] as String, _code.text.trim());
      if (!mounted) return;
      context.go('/courier');
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncTracking(String? status) async {
    final live = status == 'ACCEPTED' || status == 'EN_ROUTE_PICKUP' || status == 'PICKED_UP' || status == 'EN_ROUTE_DROPOFF';
    if (!live) {
      await _positions?.cancel();
      _positions = null;
      return;
    }
    if (_positions != null) return;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (mounted) setState(() => _error = 'بدون إذن الموقع لا يرى العميل حركتك. الاتجاهات ما زالت متاحة.');
      return;
    }
    final settings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 20,
      intervalDuration: Duration(seconds: 15),
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationTitle: 'دليفريه',
        notificationText: 'موقعك يُحدَّث أثناء هذه المهمة فقط، ويتوقف عند التسليم أو الإلغاء.',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
    _positions = Geolocator.getPositionStream(locationSettings: settings).listen((position) async {
      final id = _job['id'] as String?;
      if (id == null) return;
      try {
        await ref.read(apiProvider).courierPing(id, position.latitude, position.longitude);
        if (!mounted) return;
        final point = LatLng(position.latitude, position.longitude);
        setState(() {
          _courierPoint = point;
          _courierUpdatedAt = DateTime.now();
          _error = null;
        });
        _map?.animateCamera(CameraUpdate.newLatLng(point));
      } on ApiException catch (error) {
        if (error.code == 'TRACKING_CLOSED') {
          await _positions?.cancel();
          _positions = null;
        }
      } catch (_) {}
    });
  }

  Future<void> _ping() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      setState(() => _error = 'تم رفض إذن الموقع. الاتجاهات ما زالت متاحة من الزر، والتحديث اليدوي متوقف.');
      return;
    }
    setState(() => _locating = true);
    try {
      final position = await Geolocator.getCurrentPosition();
      await ref.read(apiProvider).courierPing(_job['id'] as String, position.latitude, position.longitude);
      if (!mounted) return;
      final point = LatLng(position.latitude, position.longitude);
      setState(() {
        _courierPoint = point;
        _courierUpdatedAt = DateTime.now();
        _error = null;
      });
      _map?.animateCamera(CameraUpdate.newLatLng(point));
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر تحديث الموقع. تحقق من الإنترنت.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _directions(Map<String, dynamic> point) async {
    final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${point['lat']},${point['lng']}&travelmode=driving');
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (opened || !mounted) return;
    await Clipboard.setData(ClipboardData(text: url.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر فتح الخرائط. تم نسخ الرابط.')));
  }

  Future<void> _report() async {
    final bound = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إبلاغ الإدارة'),
        content: TextField(controller: bound, decoration: const InputDecoration(labelText: 'وصف المشكلة')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(context, bound.text.trim()), child: const Text('إرسال')),
        ],
      ),
    );
    if (text == null || text.length < 3) return;
    try {
      await ref.read(apiProvider).courierReport(_job['id'] as String, text);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('وصل البلاغ إلى الإدارة. حالة الطلب لم تتغير.')));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  bool _hasPoint(Map<String, dynamic> point) {
    final lat = point['lat'];
    final lng = point['lng'];
    if (lat is! num || lng is! num) return false;
    if (!lat.isFinite || !lng.isFinite) return false;
    return lat != 0 || lng != 0;
  }

  int _minor(String key) {
    final value = _job[key];
    if (value is int) return value;
    if (value is num) return value.round();
    return 0;
  }

  String? _text(String key) {
    final value = _job[key];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  bool get _needsCode => _job['status'] == 'EN_ROUTE_DROPOFF' || _job['hasDeliveryCode'] == true;

  @override
  Widget build(BuildContext context) {
    final pickup = Map<String, dynamic>.from((_job['pickup'] as Map?) ?? {});
    final dropoff = Map<String, dynamic>.from((_job['dropoff'] as Map?) ?? {});
    final pickupPoint = _hasPoint(pickup) ? LatLng((pickup['lat'] as num).toDouble(), (pickup['lng'] as num).toDouble()) : null;
    final dropoffPoint = _hasPoint(dropoff) ? LatLng((dropoff['lat'] as num).toDouble(), (dropoff['lng'] as num).toDouble()) : null;
    final mapTarget = _courierPoint ?? pickupPoint ?? dropoffPoint;
    final status = _job['status'] as String?;
    final fresh = _courierUpdatedAt != null && DateTime.now().difference(_courierUpdatedAt!) < const Duration(seconds: 90);
    final number = _job['publicNumber'] as String? ?? '';
    final phone = _text('recipientPhone');
    final recipient = _text('recipientName');
    final deliveryFee = _job['deliveryFeeMinor'] as int? ?? _job['feeMinor'] as int?;
    final payout = _job['payoutLabel'] as String? ?? money(_minor('payoutMinor'));
    final goods = _minor('goodsMinor');
    final platform = _minor('platformMinor');
    final collect = _job['collectMinor'] as int? ?? (_job['collection'] as Map?)?['collectMinor'] as int? ?? 0;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('تفاصيل الطلب')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (number.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
                        child: Text(number, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    const Spacer(),
                    StatusChip(_statusLabel[status] ?? 'غير متوفر', tone: status == 'CANCELLED' ? 'bad' : status == 'DELIVERED' ? 'ok' : 'warn'),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_job['kind'] == 'FOOD' || _job['parcelType'] == 'FOOD' ? 'طلب طعام' : 'توصيل عادي', style: const TextStyle(color: AppColors.muted)),
                if (_error != null && _next == null && !_needsCode) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: AppColors.danger, height: 1.4)),
                ],
                const SizedBox(height: 12),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (mapTarget == null)
                        const SizedBox(
                          height: 220,
                          child: Center(child: Text('موقعك غير متوفر حاليًا، ولا توجد إحداثيات للعنوان. اضغط تحديث الموقع.', textAlign: TextAlign.center, style: TextStyle(height: 1.4))),
                        )
                      else
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            height: 220,
                            child: GoogleMap(
                              initialCameraPosition: CameraPosition(target: mapTarget, zoom: 14),
                              onMapCreated: (controller) => _map = controller,
                              myLocationButtonEnabled: false,
                              zoomControlsEnabled: false,
                              markers: {
                                if (_courierPoint != null)
                                  Marker(
                                    markerId: const MarkerId('courier'),
                                    position: _courierPoint!,
                                    icon: BitmapDescriptor.defaultMarkerWithHue(fresh ? BitmapDescriptor.hueAzure : BitmapDescriptor.hueOrange),
                                  ),
                                if (pickupPoint != null)
                                  Marker(markerId: const MarkerId('pickup'), position: pickupPoint, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)),
                                if (dropoffPoint != null) Marker(markerId: const MarkerId('dropoff'), position: dropoffPoint),
                              },
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        _courierPoint == null
                            ? 'موقعك غير متوفر بعد. العلامة على الخريطة، إن ظهرت، عنوان استلام أو تسليم وليست تتبعًا حيًا.'
                            : fresh
                                ? 'موقعك · آخر تحديث ${whenLabel(_courierUpdatedAt!)}'
                                : 'آخر تحديث ${whenLabel(_courierUpdatedAt!)} وليس حديثًا. لا يُعرض كموقع حالي مؤكد.',
                        style: const TextStyle(height: 1.4),
                      ),
                      const SizedBox(height: 12),
                      AppButton(label: 'تحديث الموقع', secondary: true, loading: _locating, onPressed: _locating ? null : _ping),
                    ],
                  ),
                ),
                _placeCard('مكان الاستلام', Icons.storefront_outlined, pickup['name'] as String?, pickup['line'] as String? ?? '', pickupPoint == null ? null : () => _directions(pickup)),
                _placeCard('مكان التسليم', Icons.location_on_outlined, null, dropoff['line'] as String? ?? '', dropoffPoint == null ? null : () => _directions(dropoff)),
                CustomerContactCard(name: _text('customerName') ?? recipient, phone: _text('customerPhone') ?? phone),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('التفاصيل المالية', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      if (deliveryFee != null) _moneyRow('أجرة التوصيل', money(deliveryFee)),
                      if (platform > 0) _moneyRow('عمولة المنصة', money(platform)),
                      if (goods > 0) _moneyRow('قيمة البضاعة', _job['goodsLabel'] as String? ?? money(goods)),
                      if (collect > 0) _moneyRow('التحصيل عند التسليم', _job['collectLabel'] as String? ?? money(collect)),
                      const Divider(height: 20),
                      _moneyRow('أجرتك', payout, strong: true),
                      if (_text('restaurant') != null) ...[
                        const SizedBox(height: 8),
                        _moneyRow('المطعم', _text('restaurant')!),
                      ],
                      if (_text('description') != null) ...[
                        const SizedBox(height: 8),
                        Text(_text('description')!, style: const TextStyle(height: 1.4)),
                      ],
                    ],
                  ),
                ),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('مشكلة في الطلب', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      const Text('البلاغ يصل إلى الإدارة ولا يغيّر حالة الطلب.', style: TextStyle(color: AppColors.muted, height: 1.4)),
                      const SizedBox(height: 12),
                      AppButton(label: 'بلاغ عن مشكلة', secondary: true, onPressed: _report),
                    ],
                  ),
                ),
                if (_needsCode)
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('رمز التسليم', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        const Text('أدخل رمز العميل لتأكيد التسليم.', style: TextStyle(height: 1.4)),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _code,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                          decoration: const InputDecoration(
                            hintText: 'رمز التسليم',
                            filled: true,
                            fillColor: AppColors.canvas,
                          ),
                        ),
                      ],
                    ),
                  ),
                const Text('قف قبل تأكيد أي خطوة. لا تستخدم الهاتف أثناء القيادة. إغلاق التطبيق من المهام الأخيرة يوقف تحديث الموقع.', style: TextStyle(color: AppColors.muted, height: 1.4)),
              ],
            ),
          ),
          if (_next != null || _needsCode)
            BottomBar(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    Text(_error!, style: const TextStyle(color: AppColors.danger, height: 1.4)),
                    const SizedBox(height: 8),
                  ],
                  if (_next != null) AppButton(label: _nextLabel, loading: _busy, onPressed: _busy ? null : _advance),
                  if (_next != null && _needsCode) const SizedBox(height: 8),
                  if (_needsCode) AppButton(label: 'تأكيد التسليم', loading: _busy, onPressed: _busy ? null : _deliver),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
      child: child,
    );
  }

  Widget _placeCard(String title, IconData icon, String? name, String line, VoidCallback? directions) {
    final place = name?.trim();
    return _card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.petrol),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                if (place != null && place.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(place, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4)),
                ],
                const SizedBox(height: 4),
                Text(line.isEmpty ? 'العنوان غير مسجّل' : line, style: const TextStyle(height: 1.4)),
                if (directions != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      onPressed: directions,
                      icon: const Icon(Icons.directions_outlined, size: 18),
                      label: const Text('الاتجاهات'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _moneyRow(String label, String value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: TextStyle(color: strong ? AppColors.ink : AppColors.inkSoft, fontWeight: strong ? FontWeight.w800 : FontWeight.w500))),
          const SizedBox(width: 12),
          Flexible(child: Text(value, textAlign: TextAlign.end, style: TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w700, fontSize: strong ? 18 : 15))),
        ],
      ),
    );
  }
}

class CourierHistoryPage extends ConsumerStatefulWidget {
  const CourierHistoryPage({super.key});
  @override
  ConsumerState<CourierHistoryPage> createState() => _CourierHistoryPageState();
}

class _CourierHistoryPageState extends ConsumerState<CourierHistoryPage> {
  List<Map<String, dynamic>> _rows = [];
  String? _error;
  String _filter = 'ALL';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await ref.read(apiProvider).courierHistory();
      if (mounted) setState(() { _rows = rows; _loading = false; _error = null; });
    } on ApiException catch (error) {
      if (mounted) setState(() { _error = error.message; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _rows.where((row) => _filter == 'ALL' || row['status'] == _filter).toList();
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.petrol,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
          children: [
            const Text('سجل الطلبات', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              for (final item in ['ALL', 'DELIVERED', 'CANCELLED'])
                ChoiceChip(
                  label: Text(item == 'ALL' ? 'الكل' : (_statusLabel[item] ?? item)),
                  selected: _filter == item,
                  onSelected: (_) => setState(() => _filter = item),
                ),
            ]),
            if (_loading) const Padding(padding: EdgeInsets.only(top: 24), child: Center(child: CircularProgressIndicator(color: AppColors.petrol))),
            if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.danger)),
            if (!_loading && visible.isEmpty) const Padding(padding: EdgeInsets.only(top: 16), child: Text('لا توجد طلبات حاليًا.', style: TextStyle(color: AppColors.muted))),
            for (final row in visible)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(row['publicNumber'] as String? ?? 'بدون رقم', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(row['kind'] == 'FOOD' ? 'طلب طعام' : 'توصيل عادي'),
                  Text(_statusLabel[row['status']] ?? 'غير متوفر'),
                  Text('من ${row['pickupLine'] ?? 'غير متوفر'}'),
                  Text('إلى ${row['dropoffLine'] ?? 'غير متوفر'}'),
                  Text('الأجرة: ${row['payoutLabel'] ?? 'غير مسجّلة'}'),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

class CourierEarningsPage extends ConsumerStatefulWidget {
  const CourierEarningsPage({super.key});
  @override
  ConsumerState<CourierEarningsPage> createState() => _CourierEarningsPageState();
}

class _CourierEarningsPageState extends ConsumerState<CourierEarningsPage> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  String _period = 'all';
  String? _opening;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = _data == null);
    try {
      final data = await ref.read(apiProvider).courierEarnings();
      if (mounted) setState(() { _data = data; _error = null; _loading = false; });
    } on ApiException catch (error) {
      if (mounted) setState(() { _error = error.message; _loading = false; });
    }
  }

  Future<void> _open(String orderId) async {
    setState(() => _opening = orderId);
    try {
      final job = await ref.read(apiProvider).courierJob(orderId);
      if (mounted) context.push('/courier/job', extra: job);
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (_loading && data == null) {
      return const Scaffold(backgroundColor: AppColors.canvas, body: Center(child: CircularProgressIndicator(color: AppColors.petrol)));
    }
    if (data == null) {
      return Scaffold(backgroundColor: AppColors.canvas, body: ErrorView(message: _error ?? 'تعذر تحميل الأرباح.', onRetry: _load));
    }
    final periods = Map<String, dynamic>.from(data['periods'] as Map? ?? {});
    final period = Map<String, dynamic>.from(periods[_period] as Map? ?? {});
    final orders = ((data['orders'] as List?) ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .where((row) => ((row['periods'] as List?) ?? []).contains(_period))
        .toList();
    final from = period['from'] as String?;
    final settlements = ((data['settlements'] as List?) ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .where((row) {
          if (from == null) return true;
          final at = DateTime.tryParse(row['createdAt'] as String? ?? '');
          final start = DateTime.tryParse(from);
          return at != null && start != null && !at.isBefore(start);
        })
        .toList();
    final payout = period['payoutMinor'] as int? ?? 0;
    final listed = orders.fold<int>(0, (sum, row) => sum + (row['payoutMinor'] as int? ?? 0));
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.petrol,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 24),
          children: [
            const Text('الأرباح والمستحقات', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('ربحك هو أجرة التوصيل بعد عمولة المنصة. قيمة البضاعة والنقد المحصّل ليسا ربحًا.', style: TextStyle(color: AppColors.muted, height: 1.4)),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: AppColors.danger))),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in const [('today', 'اليوم'), ('week', 'هذا الأسبوع'), ('month', 'هذا الشهر'), ('all', 'الكل')])
                  ChoiceChip(
                    label: Text(item.$2),
                    selected: _period == item.$1,
                    onSelected: (_) => setState(() => _period = item.$1),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _earnCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('إجمالي أرباحك', style: TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 4),
                  Text(period['payoutLabel'] as String? ?? money(0), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.petrol)),
                  const SizedBox(height: 8),
                  Text('${period['orderCount'] ?? 0} طلب مكتمل', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(period['label'] as String? ?? '', style: const TextStyle(color: AppColors.muted, height: 1.4)),
                  if ((period['paidMinor'] as int? ?? 0) > 0) ...[
                    const SizedBox(height: 8),
                    Text('هذا الرقم يشمل أرباح الفترة قبل الصرف. صُرف منها ${period['paidLabel']}، والصافي بعد الصرف ${period['netLabel']}.', style: const TextStyle(height: 1.4)),
                  ],
                ],
              ),
            ),
            _earnCard(
              child: Column(
                children: [
                  _earnRow('أرباح المندوب', period['payoutLabel'] as String? ?? money(0), icon: Icons.payments_outlined),
                  _earnRow('الطلبات المكتملة', '${period['orderCount'] ?? 0}', icon: Icons.inventory_2_outlined),
                  if ((period['platformMinor'] as int? ?? 0) > 0) _earnRow('عمولة المنصة', period['platformLabel'] as String? ?? '', icon: Icons.percent),
                  _earnRow('صافي المستحقات في الفترة', period['netLabel'] as String? ?? money(0), icon: Icons.account_balance_wallet_outlined, strong: true),
                ],
              ),
            ),
            if (payout != listed)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('مجموع بطاقات الطلبات لا يطابق إجمالي الفترة. أعد تحميل الشاشة.', style: TextStyle(color: AppColors.danger, height: 1.4)),
              ),
            const Text('تفاصيل الطلبات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (orders.isEmpty)
              const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('لا توجد أرباح مكتملة في هذه الفترة.', style: TextStyle(color: AppColors.muted, height: 1.4))),
            for (final row in orders)
              _earnCard(
                child: InkWell(
                  onTap: _opening == null ? () => _open(row['orderId'] as String) : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(row['publicNumber'] as String? ?? 'بدون رقم', style: const TextStyle(fontWeight: FontWeight.w800))),
                          const Icon(Icons.chevron_left, color: AppColors.muted),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(whenLabel(DateTime.parse(row['deliveredAt'] as String)), style: const TextStyle(color: AppColors.muted)),
                      const SizedBox(height: 8),
                      _earnRow('أجرة التوصيل', row['feeLabel'] as String? ?? money(row['feeMinor'] as int? ?? 0)),
                      if ((row['platformMinor'] as int? ?? 0) > 0) _earnRow('عمولة المنصة', row['platformLabel'] as String? ?? ''),
                      _earnRow('صافي ربحك', row['payoutLabel'] as String? ?? money(0), strong: true),
                      const SizedBox(height: 4),
                      Text(row['earningStateLabel'] as String? ?? 'سُجّل عند التسليم', style: const TextStyle(color: AppColors.petrol, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            const Text('المستحقات والمدفوعات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _earnCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _earnRow('الرصيد المستحق حاليًا', data['unsettledWageLabel'] as String? ?? money(0), strong: true),
                  const Text('هذا الرصيد لكل الفترات بعد طرح ما صُرف، وليس مجموع الفترة المختارة فقط.', style: TextStyle(color: AppColors.muted, height: 1.4)),
                  const SizedBox(height: 8),
                  _earnRow('إجمالي ما صُرف في الفترة', period['paidLabel'] as String? ?? money(0)),
                  if ((data['cashCollectedMinor'] as int? ?? 0) > 0) ...[
                    _earnRow('نقد محصّل من العملاء', data['cashCollectedLabel'] as String? ?? ''),
                    _earnRow('نقد لم يُورَّد', data['unsettledCashLabel'] as String? ?? ''),
                  ],
                ],
              ),
            ),
            if (settlements.isEmpty)
              const Text('لم تُسجَّل عمليات صرف في هذه الفترة. غياب الصرف لا يعني أن المستحق صفر.', style: TextStyle(color: AppColors.muted, height: 1.4))
            else
              for (final row in settlements)
                _earnCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_settlementKind[row['kind']] ?? 'عملية', style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(row['amountLabel'] as String? ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      Text(whenLabel(DateTime.parse(row['createdAt'] as String)), style: const TextStyle(color: AppColors.muted)),
                      if ((row['reason'] as String?)?.isNotEmpty == true) Text(row['reason'] as String, style: const TextStyle(height: 1.4)),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _earnCard({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
      child: child,
    );
  }

  Widget _earnRow(String label, String value, {bool strong = false, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: AppColors.petrol),
            const SizedBox(width: 8),
          ],
          Expanded(child: Text(label, style: TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w500))),
          const SizedBox(width: 12),
          Flexible(child: Text(value, textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.w800, fontSize: strong ? 18 : 15, color: strong ? AppColors.petrol : AppColors.ink))),
        ],
      ),
    );
  }
}

class CourierAccountPage extends ConsumerStatefulWidget {
  const CourierAccountPage({super.key});
  @override
  ConsumerState<CourierAccountPage> createState() => _CourierAccountPageState();
}

class _CourierAccountPageState extends ConsumerState<CourierAccountPage> {
  Map<String, dynamic>? _home;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final home = await ref.read(apiProvider).courierMe();
      if (mounted) setState(() => _home = home);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = Map<String, dynamic>.from(_home?['profile'] as Map? ?? {});
    final rating = Map<String, dynamic>.from(_home?['rating'] as Map? ?? {});
    final documents = (_home?['documents'] as List?)?.map((item) => Map<String, dynamic>.from(item as Map)).toList() ?? [];
    final status = profile['status'] as String?;
    final vehicle = switch (profile['vehicle']) {
      'MOTORCYCLE' => 'موتوسيكل',
      'CAR' => 'سيارة',
      'BICYCLE' => 'دراجة',
      'OTHER' => 'أخرى',
      _ => null,
    };
    final note = profile['reviewNote'] as String?;
    final showNote = note != null && note.trim().isNotEmpty && (status == 'NEEDS_INFO' || status == 'REJECTED' || status == 'SUSPENDED');
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.petrol,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 24),
          children: [
            const Text('حسابي', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.danger)),
            if (_home == null && _error == null) const Padding(padding: EdgeInsets.only(top: 24), child: Center(child: CircularProgressIndicator(color: AppColors.petrol))),
            if (_home != null) ...[
              const SizedBox(height: 12),
              _HomeCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile['fullName'] as String? ?? 'بدون اسم', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    StatusChip(_statusLabel[status] ?? 'غير متوفر', tone: status == 'APPROVED' ? 'ok' : status == 'REJECTED' || status == 'SUSPENDED' ? 'bad' : 'warn'),
                    const SizedBox(height: 12),
                    _profileLine('وسيلة التنقل', vehicle),
                    _profileLine('المحافظة', profile['governorate'] as String?),
                    _profileLine('المنطقة', profile['area'] as String?),
                    _profileLine('لوحة المركبة', profile['plate'] as String?),
                    _profileLine('بيانات المركبة', profile['vehicleDetails'] as String?),
                    _profileLine('التقييم', rating['label'] as String? ?? 'لا توجد تقييمات بعد'),
                    _profileLine('طلبات مكتملة', '${_home?['completed'] ?? 0}'),
                    if (showNote) ...[
                      const SizedBox(height: 8),
                      const Text('ملاحظة الإدارة', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                      Text(note, style: const TextStyle(height: 1.4)),
                    ],
                  ],
                ),
              ),
              const Text('حالة العمل', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              _HomeCard(
                child: CourierAvailabilitySwitch(
                  approved: status == 'APPROVED',
                  available: profile['available'] == true,
                  onUpdated: _load,
                ),
              ),
              const Text('المستندات', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (documents.isEmpty) const Text('لا توجد مستندات مرفوعة.', style: TextStyle(color: AppColors.muted)),
              for (final doc in documents)
                Text(doc['kind'] == 'NATIONAL_ID' ? 'بطاقة الرقم القومي' : doc['kind'] == 'LICENSE' ? 'رخصة القيادة' : doc['kind'] == 'PORTRAIT' ? 'صورة شخصية' : doc['kind'] == 'VEHICLE_REGISTRATION' ? 'رخصة المركبة' : 'مستند'),
            ],
            const SizedBox(height: 8),
            const Text('التقييمات تأتي من العملاء بعد اكتمال الطلب، ولا يمكن تعديلها من هنا.'),
            TextButton(onPressed: () => context.push('/courier/ratings'), child: const Text('عرض التقييمات')),
            TextButton(onPressed: () => context.push('/support/contact'), child: const Text('الدعم والشكاوى')),
            TextButton(onPressed: () => context.push('/notifications'), child: const Text('الإشعارات')),
            TextButton(
              onPressed: () async {
                await ref.read(sessionProvider.notifier).logout();
                if (context.mounted) context.go('/welcome');
              },
              child: const Text('تسجيل الخروج'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileLine(String label, String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted))),
          const SizedBox(width: 12),
          Flexible(child: Text(text, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4))),
        ],
      ),
    );
  }
}

class CourierRatingsView extends ConsumerStatefulWidget {
  const CourierRatingsView({super.key});
  @override
  ConsumerState<CourierRatingsView> createState() => _CourierRatingsViewState();
}

class _CourierRatingsViewState extends ConsumerState<CourierRatingsView> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(apiProvider).myCourierRatings().then((data) {
      if (mounted) setState(() => _data = data);
    }).catchError((error) {
      if (mounted) setState(() => _error = error is ApiException ? error.message : 'تعذر تحميل التقييمات.');
    });
  }

  Future<void> _report(String id) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('الإبلاغ عن تقييم'),
        content: TextField(controller: reason, decoration: const InputDecoration(hintText: 'سبب الإبلاغ')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('إرسال')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiProvider).reportReview(id, reason.text.trim());
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final reviews = (_data?['reviews'] as List?)?.map((item) => Map<String, dynamic>.from(item as Map)).toList() ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('تقييماتي')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(_data?['label'] as String? ?? _error ?? ''),
          const SizedBox(height: 8),
          const Text('لا يمكنك تعديل تقييم العميل أو حذفه. الإبلاغ يراجع من الإدارة ولا يحذف التقييم السلبي لمجرد أنه سلبي.'),
          for (final review in reviews)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${review['rating']} نجوم'),
              subtitle: Text(review['comment'] as String? ?? ''),
              trailing: TextButton(onPressed: () => _report(review['id'] as String), child: const Text('إبلاغ')),
            ),
        ],
      ),
    );
  }
}

class CourierApplyPage extends ConsumerStatefulWidget {
  const CourierApplyPage({super.key});
  @override
  ConsumerState<CourierApplyPage> createState() => _CourierApplyPageState();
}

class _CourierApplyPageState extends ConsumerState<CourierApplyPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _area = TextEditingController();
  final _plate = TextEditingController();
  final _details = TextEditingController();
  String _governorate = 'القاهرة';
  String _vehicle = 'MOTORCYCLE';
  bool _terms = false;
  bool _loading = false;
  String? _error;
  final _docs = <String, String>{};

  Future<void> _pick(String kind) async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (file == null) return;
    try {
      await ref.read(apiProvider).uploadCourierDoc(file.path, kind);
      if (mounted) setState(() => _docs[kind] = 'تم الرفع');
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    }
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await ref.read(apiProvider).applyCourier({
        'fullName': _name.text.trim(),
        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'phone': _phone.text.trim(),
        'governorate': _governorate,
        'area': _area.text.trim(),
        'vehicle': _vehicle,
        'vehicleDetails': _details.text.trim(),
        'plate': _plate.text.trim(),
        'termsAccepted': _terms,
      });
      ref.read(sessionProvider.notifier).setUser(user);
      if (!mounted) return;
      context.go('/courier');
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final needsVehicleDocs = _vehicle == 'MOTORCYCLE' || _vehicle == 'CAR';
    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل مندوب')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('الحساب لن يستقبل طلبات قبل مراجعة المستندات واعتماد الإدارة.'),
          const SizedBox(height: 8),
          const Text('رمز التحقق يُرسل فعليًا في الإنتاج عند ربط بوابة رسائل. في بيئة التطوير يظهر الرمز داخل الشاشة فقط.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 16),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'الاسم بالكامل')),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الموبايل')),
          TextField(controller: _email, decoration: const InputDecoration(labelText: 'البريد الإلكتروني (اختياري)')),
          DropdownButtonFormField<String>(
            initialValue: _governorate,
            items: [for (final item in _governorates) DropdownMenuItem(value: item, child: Text(item))],
            onChanged: (value) => setState(() => _governorate = value ?? _governorate),
            decoration: const InputDecoration(labelText: 'المحافظة'),
          ),
          TextField(controller: _area, decoration: const InputDecoration(labelText: 'المنطقة')),
          DropdownButtonFormField<String>(
            initialValue: _vehicle,
            items: const [
              DropdownMenuItem(value: 'MOTORCYCLE', child: Text('دراجة نارية')),
              DropdownMenuItem(value: 'CAR', child: Text('سيارة')),
              DropdownMenuItem(value: 'BICYCLE', child: Text('دراجة')),
              DropdownMenuItem(value: 'OTHER', child: Text('أخرى')),
            ],
            onChanged: (value) => setState(() => _vehicle = value ?? _vehicle),
            decoration: const InputDecoration(labelText: 'وسيلة التوصيل'),
          ),
          TextField(controller: _details, decoration: const InputDecoration(labelText: 'بيانات المركبة')),
          TextField(controller: _plate, decoration: const InputDecoration(labelText: 'اللوحة إن وجدت')),
          const SizedBox(height: 8),
          _doc('PORTRAIT', 'صورة شخصية'),
          _doc('NATIONAL_ID', 'الرقم القومي'),
          if (needsVehicleDocs) ...[
            _doc('LICENSE', 'رخصة القيادة'),
            _doc('VEHICLE_REGISTRATION', 'رخصة المركبة'),
          ],
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _terms,
            onChanged: (value) => setState(() => _terms = value ?? false),
            title: const Text('أوافق على شروط العمل وسياسة الخصوصية'),
          ),
          TextButton(onPressed: () => context.push('/legal/terms'), child: const Text('شروط العمل')),
          TextButton(onPressed: () => context.push('/legal/privacy'), child: const Text('سياسة الخصوصية')),
          if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.danger)),
          AppButton(label: 'إرسال للمراجعة', loading: _loading, onPressed: _loading ? null : _submit),
        ],
      ),
    );
  }

  Widget _doc(String kind, String label) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(_docs[kind] ?? 'لم تُرفع'),
      trailing: TextButton(onPressed: () => _pick(kind), child: const Text('رفع')),
    );
  }
}
