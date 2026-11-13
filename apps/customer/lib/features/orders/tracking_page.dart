import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/brand_art.dart';
import '../../core/widgets/ui.dart';

class TrackingPage extends ConsumerStatefulWidget {
  const TrackingPage({super.key, required this.id});
  final String id;

  @override
  ConsumerState<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends ConsumerState<TrackingPage> {
  DeliveryOrder? _order;
  String? _code;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  WebSocketChannel? _channel;

  static const _steps = [
    'SEARCHING',
    'ACCEPTED',
    'EN_ROUTE_PICKUP',
    'PICKED_UP',
    'EN_ROUTE_DROPOFF',
    'DELIVERED',
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _listen();
  }

  Future<void> _load() async {
    try {
      final order = await ref.read(apiProvider).order(widget.id);
      String? code;
      if (order.status == 'EN_ROUTE_DROPOFF') {
        try {
          code = await ref.read(apiProvider).deliveryCode(order.id);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _order = order;
        _code = code;
        _loading = false;
        _error = null;
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

  void _listen() {
    final token = ref.read(sessionStoreProvider).accessToken;
    if (token == null) return;
    final base = AppConfig.apiBase.replaceFirst('http', 'ws');
    _channel = WebSocketChannel.connect(Uri.parse('$base/v1/realtime?token=$token'));
    _channel!.stream.listen((event) {
      final data = jsonDecode(event as String) as Map<String, dynamic>;
      if (data['type'] == 'order.updated') {
        final order = DeliveryOrder(Map<String, dynamic>.from(data['order'] as Map));
        if (order.id == widget.id && mounted) {
          setState(() => _order = order);
          if (_tracking(order.status)) _load();
        }
      }
    });
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }

  Future<void> _cancel() async {
    final preview = await ref.read(apiProvider).cancelPreview(widget.id);
    if (!mounted) return;
    final reasons = (preview['reasons'] as List? ?? []).cast<dynamic>();
    String code = reasons.isEmpty ? 'OTHER' : (reasons.first as Map)['code'] as String;
    final note = TextEditingController();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: StatefulBuilder(
          builder: (context, setSheet) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('إلغاء الطلب', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(preview['message'] as String? ?? ''),
              if ((preview['feeMinor'] as int? ?? 0) > 0)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text('رسوم الإلغاء: ${money(preview['feeMinor'] as int)}', style: const TextStyle(fontWeight: FontWeight.w800))),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final reason in reasons)
                    ChoiceChip(
                      label: Text((reason as Map)['label'] as String),
                      selected: code == reason['code'],
                      onSelected: (_) => setSheet(() => code = reason['code'] as String),
                    ),
                ],
              ),
              AppField(label: 'تفاصيل إضافية', controller: note),
              const SizedBox(height: 8),
              AppButton(label: 'تأكيد الإلغاء', onPressed: () => Navigator.pop(context, true)),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final order = await ref.read(apiProvider).cancel(widget.id, code: code, reason: note.text.trim());
      setState(() => _order = order);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retry() async {
    setState(() => _busy = true);
    try {
      final order = await ref.read(apiProvider).retry(widget.id);
      setState(() => _order = order);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.petrol))
          : _error != null && order == null
              ? ErrorView(message: _error!, onRetry: _load)
              : Stack(
                  children: [
                    _Map(order: order!),
                    DraggableScrollableSheet(
                      initialChildSize: 0.42,
                      minChildSize: 0.28,
                      maxChildSize: 0.86,
                      builder: (context, controller) {
                        return Container(
                          decoration: const BoxDecoration(
                            color: AppColors.canvas,
                            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                          ),
                          child: ListView(
                            controller: controller,
                            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                            children: [
                              Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(4)))),
                              const SizedBox(height: 14),
                              Text(order.statusTitle, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                              Text(order.publicNumber, style: const TextStyle(color: AppColors.muted)),
                              const SizedBox(height: 16),
                              if (order.status == 'SEARCHING')
                                Text(order.json['chosenCourier'] == null
                                    ? 'جاري البحث عن مندوب قريب منك'
                                    : 'بانتظار قبول ${((order.json['chosenCourier'] as Map)['name'] as String?) ?? 'المندوب الذي اخترته'}'),
                              if (order.status == 'NO_COURIER') ...[
                                const Text('لا يوجد مندوب متاح حاليًا.'),
                                const SizedBox(height: 12),
                                AppButton(label: 'إعادة المحاولة', loading: _busy, onPressed: _retry),
                                const SizedBox(height: 8),
                                AppButton(label: 'إلغاء الطلب', secondary: true, onPressed: _cancel),
                              ],
                              if (order.courier != null) _CourierCard(order: order, onChat: () => context.push('/orders/${order.id}/chat')),
                              if (_code != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('رمز التسليم', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                                      Text(_code!, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 6)),
                                      const Text('يقوله المستلم للمندوب. المندوب لا يراه قبل التسليم.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              if (order.json['collection'] is Map) _CollectionCard(data: Map<String, dynamic>.from(order.json['collection'] as Map)),
                              const SizedBox(height: 16),
                              _Stage(status: order.status),
                              const SizedBox(height: 8),
                              AppButton(label: 'المساعدة', secondary: true, onPressed: () => context.push('/support/contact')),
                              if (['SEARCHING', 'ACCEPTED', 'EN_ROUTE_PICKUP'].contains(order.status)) ...[
                                const SizedBox(height: 16),
                                AppButton(label: 'إلغاء الطلب', secondary: true, loading: _busy, onPressed: _cancel),
                              ],
                              if (order.status == 'DELIVERED') ...[
                                const SizedBox(height: 12),
                                const Row(
                                  children: [
                                    BrandArt(BrandArt.delivered, size: 36, semanticLabel: 'تم التسليم'),
                                    SizedBox(width: 8),
                                    Expanded(child: Text('تم التسليم. توقف عرض موقع المندوب.', style: TextStyle(fontWeight: FontWeight.w700))),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                AppButton(
                                  label: order.json['review'] == null ? 'قيّم المندوب' : 'تقييمك',
                                  onPressed: () => context.push('/orders/${order.id}/review'),
                                ),
                                if (order.json['foodOrderId'] != null) ...[
                                  const SizedBox(height: 8),
                                  AppButton(label: 'قيّم المطعم', secondary: true, onPressed: () => context.push('/food-orders/${order.json['foodOrderId']}')),
                                ],
                              ],
                              if (kDebugMode) _DevTools(id: order.id, onDone: _load),
                            ],
                          ),
                        );
                      },
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: CircleAvatar(
                          backgroundColor: Colors.white,
                          child: IconButton(onPressed: () => context.go('/home'), icon: const Icon(Icons.close)),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _Map extends ConsumerStatefulWidget {
  const _Map({required this.order});
  final DeliveryOrder order;

  @override
  ConsumerState<_Map> createState() => _MapState();
}

class _MapState extends ConsumerState<_Map> {
  List<LatLng> _road = [];
  int? _etaMinutes;
  String? _routeNote;
  LatLng? _routedFrom;
  GoogleMapController? _map;
  BitmapDescriptor? _courierIcon;

  @override
  void didUpdateWidget(covariant _Map oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadRoad();
  }

  @override
  void initState() {
    super.initState();
    _loadRoad();
    _loadCourierIcon();
  }

  Future<void> _loadCourierIcon() async {
    final info = await vg.loadPicture(const SvgAssetLoader(BrandArt.motorcycle), null);
    final image = await info.picture.toImage(96, 96);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    info.picture.dispose();
    image.dispose();
    if (!mounted || bytes == null) return;
    setState(() {
      _courierIcon = BitmapDescriptor.bytes(bytes.buffer.asUint8List(), width: 42);
    });
  }

  Future<void> _loadRoad() async {
    final courier = widget.order.courier;
    final live = _tracking(widget.order.status) && courier?['lat'] != null && courier?['lng'] != null;
    if (!live) {
      if (mounted) setState(() { _road = []; _etaMinutes = null; _routeNote = null; });
      return;
    }
    final from = LatLng((courier!['lat'] as num).toDouble(), (courier['lng'] as num).toDouble());
    final target = _towardPickup(widget.order.status) ? widget.order.pickup : widget.order.dropoff;
    if (!_hasPoint(target)) {
      if (mounted) setState(() { _road = []; _etaMinutes = null; _routeNote = null; });
      return;
    }
    final to = LatLng((target['lat'] as num).toDouble(), (target['lng'] as num).toDouble());
    if (_routedFrom != null && _meters(_routedFrom!, from) < 80 && _road.isNotEmpty) return;
    _routedFrom = from;
    _map?.animateCamera(CameraUpdate.newLatLng(from));
    try {
      final route = await ref.read(apiProvider).drivingRoute(from.latitude, from.longitude, to.latitude, to.longitude);
      final encoded = route['encodedPolyline'] as String?;
      if (encoded == null || encoded.isEmpty) throw Exception('empty');
      if (!mounted) return;
      setState(() {
        _road = _decodePolyline(encoded);
        _etaMinutes = (route['etaMinutes'] as num?)?.round();
        _routeNote = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _road = [];
        _etaMinutes = null;
        _routeNote = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _road = [];
        _etaMinutes = null;
        _routeNote = 'تعذر حساب مسار القيادة. موقع المندوب ما زال ظاهرًا.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final dropoff = _hasPoint(order.dropoff) ? LatLng((order.dropoff['lat'] as num).toDouble(), (order.dropoff['lng'] as num).toDouble()) : null;
    final pickup = _hasPoint(order.pickup) ? LatLng((order.pickup['lat'] as num).toDouble(), (order.pickup['lng'] as num).toDouble()) : null;
    final courier = order.courier;
    final showCourier = _tracking(order.status) && courier?['lat'] != null;
    final courierPoint = showCourier ? LatLng((courier!['lat'] as num).toDouble(), (courier['lng'] as num).toDouble()) : null;
    final fresh = courier?['locationFresh'] == true;
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: courierPoint ?? dropoff ?? const LatLng(30.0444, 31.2357), zoom: 14),
          onMapCreated: (controller) => _map = controller,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          markers: {
            if (dropoff != null) Marker(markerId: const MarkerId('dropoff'), position: dropoff),
            if (pickup != null && _towardPickup(order.status)) Marker(markerId: const MarkerId('pickup'), position: pickup, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)),
            if (courierPoint != null)
              Marker(
                markerId: const MarkerId('courier'),
                position: courierPoint,
                icon: _courierIcon ?? BitmapDescriptor.defaultMarkerWithHue(fresh ? BitmapDescriptor.hueAzure : BitmapDescriptor.hueOrange),
                infoWindow: InfoWindow(title: fresh ? 'موقع المندوب الحالي' : 'آخر موقع معروف'),
              ),
          },
          polylines: {
            if (_road.length > 1) Polyline(polylineId: const PolylineId('drive'), points: _road, color: AppColors.petrol, width: 5),
          },
        ),
        if (_tracking(order.status))
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Text(
                courierPoint == null
                    ? 'جارٍ تحديث موقع المندوب'
                    : fresh
                        ? (_etaMinutes == null ? 'الموقع محدث. وقت الوصول غير متاح الآن.' : 'وصول تقريبي حسب الطرق: $_etaMinutes د')
                        : 'آخر تحديث ليس حديثًا. لا يُعرض كموقع حالي مؤكد.',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        if (_routeNote != null)
          Positioned(
            left: 12,
            right: 12,
            top: 72,
            child: Container(
              padding: const EdgeInsets.all(8),
              color: Colors.white,
              child: Text(_routeNote!),
            ),
          ),
      ],
    );
  }
}

double _meters(LatLng a, LatLng b) {
  const earth = 6371000.0;
  final dLat = (b.latitude - a.latitude) * math.pi / 180;
  final dLng = (b.longitude - a.longitude) * math.pi / 180;
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final h = math.pow(math.sin(dLat / 2), 2) + math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLng / 2), 2);
  return 2 * earth * math.asin(math.sqrt(h.toDouble()));
}

List<LatLng> _decodePolyline(String encoded) {
  final points = <LatLng>[];
  var index = 0;
  var lat = 0;
  var lng = 0;
  while (index < encoded.length) {
    var shift = 0;
    var result = 0;
    int byte;
    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    lat += (result & 1) != 0 ? ~(result >> 1) : result >> 1;
    shift = 0;
    result = 0;
    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    lng += (result & 1) != 0 ? ~(result >> 1) : result >> 1;
    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return points;
}

bool _hasPoint(Map<String, dynamic> point) {
  final lat = (point['lat'] as num?)?.toDouble() ?? 0;
  final lng = (point['lng'] as num?)?.toDouble() ?? 0;
  return lat != 0 || lng != 0;
}

bool _tracking(String status) => const {'ACCEPTED', 'EN_ROUTE_PICKUP', 'PICKED_UP', 'EN_ROUTE_DROPOFF'}.contains(status);

bool _towardPickup(String status) => status == 'ACCEPTED' || status == 'EN_ROUTE_PICKUP';

String _ago(String iso) {
  final at = DateTime.tryParse(iso);
  if (at == null) return 'غير متوفر';
  final minutes = DateTime.now().difference(at.toLocal()).inMinutes;
  if (minutes < 1) return 'الآن';
  if (minutes < 60) return 'منذ $minutes د';
  return 'منذ ${minutes ~/ 60} س';
}

class _CourierCard extends StatelessWidget {
  const _CourierCard({required this.order, required this.onChat});
  final DeliveryOrder order;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final courier = order.courier!;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
      child: Row(
        children: [
          const CircleAvatar(backgroundColor: AppColors.petrolSoft, child: Icon(Icons.person, color: AppColors.petrol)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(courier['name'] as String? ?? 'مندوب', style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('${vehicleLabel(courier['vehicle'] as String? ?? '')} · ${courier['plate'] ?? ''}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                if (_tracking(order.status) && courier['lat'] == null) const Text('جارٍ تحديث موقع المندوب', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                if (courier['locationUpdatedAt'] != null) Text('آخر تحديث: ${_ago(courier['locationUpdatedAt'] as String)}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                TextButton(
                  onPressed: () => context.push('/couriers/${courier['id']}/ratings'),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 28)),
                  child: const Text('التقييمات'),
                ),
              ],
            ),
          ),
          if (courier['phone'] != null)
            IconButton(onPressed: () => launchUrl(Uri.parse('tel:${courier['phone']}')), icon: const Icon(Icons.call)),
          IconButton(onPressed: onChat, icon: const Icon(Icons.chat_bubble_outline)),
        ],
      ),
    );
  }
}

IconData _stageIcon(String status) => switch (status) {
  'SEARCHING' => Icons.search,
  'ACCEPTED' => Icons.how_to_reg_outlined,
  'EN_ROUTE_PICKUP' => Icons.two_wheeler,
  'PICKED_UP' => Icons.shopping_bag_outlined,
  'EN_ROUTE_DROPOFF' => Icons.place_outlined,
  'DELIVERED' => Icons.inventory_2_outlined,
  _ => Icons.circle_outlined,
};

class _Stage extends StatelessWidget {
  const _Stage({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final current = _TrackingPageState._steps.indexOf(status);
    return Column(
      children: [
        for (var i = 0; i < _TrackingPageState._steps.length; i++)
          Row(
            children: [
              Icon(_stageIcon(_TrackingPageState._steps[i]), size: 16, color: i <= current ? AppColors.petrol : AppColors.muted),
              const SizedBox(width: 8),
              Expanded(child: Text(statusLabel(_TrackingPageState._steps[i]), style: TextStyle(fontWeight: i == current ? FontWeight.w800 : FontWeight.w500, color: i <= current ? AppColors.ink : AppColors.muted))),
            ],
          ),
      ],
    );
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('التحصيل والتسوية', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('قيمة المنتجات: ${money(data['goodsMinor'] as int? ?? 0)}'),
          Text('المطلوب من المستلم: ${money(data['collectMinor'] as int? ?? 0)}'),
          Text('المستحق للمحل: ${money(data['businessDueMinor'] as int? ?? 0)}'),
          Text('حالة التحصيل: ${data['settlementLabel'] ?? ''}'),
          const Text('اكتمال التوصيل لا يعني أن الأموال وصلت إلى المحل.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ],
      ),
    );
  }
}

class _DevTools extends ConsumerWidget {
  const _DevTools({required this.id, required this.onDone});
  final String id;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> call(String action, [Map<String, dynamic>? body]) async {
      await ref.read(apiProvider).dev(id, action, body);
      onDone();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('بيئة التطوير فقط', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          Wrap(
            spacing: 8,
            children: [
              TextButton(onPressed: () => call('accept'), child: const Text('قبول')),
              TextButton(onPressed: () => call('status', {'status': 'EN_ROUTE_PICKUP'}), child: const Text('للطريق')),
              TextButton(onPressed: () => call('status', {'status': 'PICKED_UP'}), child: const Text('استلام')),
              TextButton(onPressed: () => call('status', {'status': 'EN_ROUTE_DROPOFF'}), child: const Text('للتسليم')),
              TextButton(onPressed: () => call('status', {'status': 'NO_COURIER'}), child: const Text('لا مندوب')),
            ],
          ),
        ],
      ),
    );
  }
}
