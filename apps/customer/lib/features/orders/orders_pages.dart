import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/brand_art.dart';
import '../../core/widgets/ui.dart';
import '../session/session_controller.dart';

class OrdersPage extends ConsumerStatefulWidget {
  const OrdersPage({super.key});

  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  String _bucket = 'active';
  final _query = TextEditingController();
  bool _loading = true;
  String? _error;
  List<DeliveryOrder> _orders = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (ref.read(sessionProvider).user == null) {
      if (!mounted) return;
      setState(() {
        _orders = [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final orders = await ref.read(apiProvider).orders(_bucket, q: _query.text.trim());
      if (mounted) {
        setState(() {
          _orders = orders;
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
      appBar: AppBar(title: const Text('طلباتي')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: AppField(label: 'بحث', controller: _query, onChanged: (_) => _load()),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                for (final item in const [('active', 'النشطة'), ('completed', 'المكتملة'), ('cancelled', 'الملغاة')])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(item.$2),
                      selected: _bucket == item.$1,
                      onSelected: (_) {
                        setState(() => _bucket = item.$1);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Padding(padding: EdgeInsets.all(20), child: SkeletonBox(height: 88))
                : _error != null
                    ? ErrorView(message: _error!, onRetry: _load)
                    : _orders.isEmpty
                        ? _bucket == 'active'
                            ? DeliveryEmptyState(
                                asset: BrandArt.emptyOrders,
                                title: 'لسه مفيش طلبات',
                                body: 'أول طلب هيظهر هنا بعد ما تطلب مندوب.',
                                action: 'اطلب مندوب الآن',
                                onAction: () => context.push('/request'),
                              )
                            : const EmptyView(title: 'لا توجد طلبات', body: 'طلباتك في هذا القسم هتظهر هنا.')
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(20),
                              itemCount: _orders.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final order = _orders[index];
                                return Pressable(
                                  onTap: () => context.push('/orders/${order.id}/details'),
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(order.publicNumber, style: const TextStyle(fontWeight: FontWeight.w800)),
                                            const Spacer(),
                                            StatusChip(statusLabel(order.status)),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(whenLabel(order.createdAt), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                                        const SizedBox(height: 8),
                                        Text(order.pickup['line'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
                                        const Icon(Icons.south, size: 14, color: AppColors.muted),
                                        Text(order.dropoff['line'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
                                        const SizedBox(height: 8),
                                        Text(order.totalLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class OrderDetailPage extends ConsumerStatefulWidget {
  const OrderDetailPage({super.key, required this.id});
  final String id;

  @override
  ConsumerState<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends ConsumerState<OrderDetailPage> {
  DeliveryOrder? _order;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final order = await ref.read(apiProvider).order(widget.id);
      setState(() => _order = order);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل الطلب')),
      body: order == null
          ? (_error == null ? const Center(child: CircularProgressIndicator()) : ErrorView(message: _error!, onRetry: _load))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(order.publicNumber, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                StatusChip(order.statusTitle),
                const SizedBox(height: 16),
                _block('الاستلام', order.pickup['line'] as String, icon: Icons.trip_origin),
                _block('التسليم', order.dropoff['line'] as String, icon: Icons.place_outlined),
                _block('المستلم', '${order.json['recipientName']} · ${order.json['recipientPhone']}', icon: Icons.call_outlined),
                _block('الغرض', '${parcelLabel(order.json['parcelType'] as String)} · ${order.json['parcelDescription']}'),
                _block('الحجم', '${sizeLabel(order.json['size'] as String)}${order.json['fragile'] == true ? ' · قابل للكسر' : ''}'),
                _block('الوسيلة', vehicleLabel(order.json['vehicle'] as String)),
                _block('التكلفة', order.totalLabel),
                _block('الدفع', 'نقدًا'),
                if (order.courier != null) _block('المندوب', order.courier!['name'] as String? ?? ''),
                if (order.json['proof'] != null) _block('إثبات التسليم', (order.json['proof'] as Map)['method'] as String),
                const SizedBox(height: 8),
                const SectionLabel('سجل الحالة'),
                for (final item in (order.json['history'] as List? ?? []))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('${statusLabel((item as Map)['status'] as String)} · ${whenLabel(DateTime.parse(item['createdAt'] as String))}', style: const TextStyle(fontSize: 13)),
                  ),
                const SizedBox(height: 16),
                if (const {'ACCEPTED', 'EN_ROUTE_PICKUP', 'PICKED_UP', 'EN_ROUTE_DROPOFF'}.contains(order.status))
                  AppButton(label: 'تتبع المندوب', onPressed: () => context.push('/orders/${order.id}')),
                if (order.active && !const {'ACCEPTED', 'EN_ROUTE_PICKUP', 'PICKED_UP', 'EN_ROUTE_DROPOFF'}.contains(order.status))
                  AppButton(label: 'متابعة الطلب', onPressed: () => context.push('/orders/${order.id}')),
                if (!order.active) ...[
                  const SizedBox(height: 8),
                  AppButton(
                    label: 'إعادة نفس المشوار',
                    secondary: true,
                    onPressed: () => context.push('/request', extra: order),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _block(String title, String value, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: AppColors.petrol),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key, required this.id});
  final String id;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _text = TextEditingController();
  List<dynamic> _messages = [];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final messages = await ref.read(apiProvider).messages(widget.id);
    if (mounted) setState(() => _messages = messages);
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(apiProvider).sendMessage(widget.id, body);
      _text.clear();
      await _load();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المندوب')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index] as Map;
                final mine = message['sender'] == 'CUSTOMER';
                return Align(
                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
                    decoration: BoxDecoration(
                      color: mine ? AppColors.petrol : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: mine ? null : Border.all(color: AppColors.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(message['body'] as String, style: TextStyle(color: mine ? Colors.white : AppColors.ink)),
                        Text(clock(DateTime.parse(message['createdAt'] as String)), style: TextStyle(fontSize: 10, color: mine ? const Color(0xCCFFFFFF) : AppColors.muted)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          BottomBar(
            child: Row(
              children: [
                Expanded(child: TextField(controller: _text, decoration: const InputDecoration(hintText: 'اكتب رسالة', border: InputBorder.none))),
                IconButton(onPressed: _sending ? null : _send, icon: const Icon(Icons.send, color: AppColors.petrol)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ReviewPage extends ConsumerStatefulWidget {
  const ReviewPage({super.key, required this.id});
  final String id;

  @override
  ConsumerState<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends ConsumerState<ReviewPage> {
  int _rating = 0;
  final _tags = <String>{};
  final _comment = TextEditingController();
  bool _loading = false;
  bool _updating = false;
  String? _error;
  DeliveryOrder? _order;

  static const _labels = {1: 'سيئ جدًا', 2: 'سيئ', 3: 'متوسط', 4: 'جيد جدًا', 5: 'ممتاز'};
  static const _positive = ['الالتزام بالمواعيد', 'حسن التعامل', 'سرعة التوصيل', 'الحفاظ على الطلب'];
  static const _negative = ['صعوبة التواصل', 'التأخير', 'التعامل غير المناسب'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final order = await ref.read(apiProvider).order(widget.id);
    final existing = order.json['review'] as Map?;
    if (!mounted) return;
    setState(() {
      _order = order;
      if (existing != null) {
        _updating = true;
        _rating = existing['rating'] as int? ?? 0;
        _tags
          ..clear()
          ..addAll(((existing['tags'] as List?) ?? []).cast<String>());
        _comment.text = existing['comment'] as String? ?? '';
      }
    });
  }

  List<String> get _reasons => _rating >= 4 ? _positive : _rating > 0 && _rating <= 2 ? _negative : [..._positive, ..._negative];

  Future<void> _submit() async {
    if (_rating < 1) {
      setState(() => _error = 'اختر عدد النجوم.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).review(widget.id, _rating, _tags.toList(), _comment.text.trim(), update: _updating);
      if (mounted) context.pop();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final courier = _order?.courier;
    return Scaffold(
      appBar: AppBar(title: const Text('تقييم المندوب')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              const CircleAvatar(backgroundColor: AppColors.petrolSoft, child: Icon(Icons.person, color: AppColors.petrol)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(courier?['name'] as String? ?? 'المندوب', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                    Text(_order?.publicNumber ?? '', style: const TextStyle(color: AppColors.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text('إيه رأيك في تجربة التوصيل؟', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Row(
            children: List.generate(5, (index) {
              final value = index + 1;
              return IconButton(
                onPressed: () => setState(() {
                  _rating = value;
                  _tags.removeWhere((tag) => !_reasons.contains(tag));
                }),
                icon: Icon(value <= _rating ? Icons.star : Icons.star_border, color: AppColors.amber, size: 32),
              );
            }),
          ),
          if (_rating > 0) Text(_labels[_rating]!, style: const TextStyle(color: AppColors.petrol, fontWeight: FontWeight.w700)),
          if (_order != null && _order!.status != 'DELIVERED')
            const Padding(padding: EdgeInsets.only(top: 12), child: Text('التقييم يظهر بعد اكتمال التوصيل.')),
          const SizedBox(height: 12),
          if (_rating > 0)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in _reasons)
                FilterChip(
                  label: Text(tag),
                  selected: _tags.contains(tag),
                  onSelected: (selected) => setState(() => selected ? _tags.add(tag) : _tags.remove(tag)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          AppField(label: 'تعليق اختياري', controller: _comment, maxLines: 3),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: AppColors.danger))),
          const SizedBox(height: 16),
          AppButton(label: _updating ? 'حفظ التعديل' : 'إرسال التقييم', loading: _loading, onPressed: _submit),
          TextButton(onPressed: () => context.pop(), child: const Text('لاحقًا')),
        ],
      ),
    );
  }
}

class CourierRatingsPage extends ConsumerStatefulWidget {
  const CourierRatingsPage({super.key, required this.courierId});
  final String courierId;

  @override
  ConsumerState<CourierRatingsPage> createState() => _CourierRatingsPageState();
}

class _CourierRatingsPageState extends ConsumerState<CourierRatingsPage> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ref.read(apiProvider).courierRatings(widget.courierId);
      if (mounted) setState(() => _data = data);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final histogram = data == null ? null : Map<String, dynamic>.from(data['histogram'] as Map);
    final reviews = ((data?['reviews'] as List?) ?? []).cast<Map>();
    return Scaffold(
      appBar: AppBar(title: const Text('التقييمات')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.petrol))
          : _error != null
              ? ErrorView(message: _error!, onRetry: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _load();
                })
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(data?['label'] as String? ?? 'لا توجد تقييمات بعد', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                    Text('إجمالي التقييمات: ${data?['count'] ?? 0}', style: const TextStyle(color: AppColors.muted)),
                    const SizedBox(height: 16),
                    if (histogram != null)
                      for (final star in [5, 4, 3, 2, 1])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('${'★' * star}${'☆' * (5 - star)}  ${histogram['$star'] ?? 0}'),
                        ),
                    const SizedBox(height: 16),
                    for (final review in reviews)
                      if ((review['comment'] as String?)?.isNotEmpty == true)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
                          child: Text(review['comment'] as String),
                        ),
                  ],
                ),
    );
  }
}
