import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/models.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ui.dart';
import '../orders/courier_picker.dart';
import '../session/session_controller.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class RestaurantsPage extends ConsumerStatefulWidget {
  const RestaurantsPage({super.key});

  @override
  ConsumerState<RestaurantsPage> createState() => _RestaurantsPageState();
}

class _RestaurantsPageState extends ConsumerState<RestaurantsPage> {
  final _query = TextEditingController();
  String? _category;
  String _sort = 'rating';
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _restaurants = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider);
      final categories = await api.restaurantCategories();
      final restaurants = await api.restaurants(q: _query.text.trim(), category: _category, sort: _sort);
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _restaurants = restaurants;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() { _error = error.message; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المطاعم')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: AppField(label: 'ابحث عن مطعم أو أكلة', controller: _query, onChanged: (_) => _load()),
          ),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ChoiceChip(label: const Text('الكل'), selected: _category == null, onSelected: (_) { setState(() => _category = null); _load(); }),
                ),
                for (final category in _categories)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      label: Text(category['label'] as String? ?? ''),
                      selected: _category == category['code'],
                      onSelected: (_) { setState(() => _category = category['code'] as String); _load(); },
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                for (final item in const [('rating', 'التقييم'), ('eta', 'الوقت'), ('fee', 'الرسوم')])
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(label: Text(item.$2), selected: _sort == item.$1, onSelected: (_) { setState(() => _sort = item.$1); _load(); }),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.petrol))
                : _error != null
                    ? ErrorView(message: _error!, onRetry: _load)
                    : _restaurants.isEmpty
                        ? const Center(child: Text('لا توجد مطاعم في منطقة الخدمة.'))
                        : ListView.separated(
                            padding: const EdgeInsets.all(20),
                            itemCount: _restaurants.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (_, index) => RestaurantCard(
                              restaurant: _restaurants[index],
                              onTap: () => context.push('/restaurants/${_restaurants[index]['id']}'),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class RestaurantCard extends StatelessWidget {
  const RestaurantCard({super.key, required this.restaurant, required this.onTap});
  final Map<String, dynamic> restaurant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ordering = Map<String, dynamic>.from(restaurant['ordering'] as Map? ?? {});
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _Cover(color: restaurant['coverColor'] as String? ?? '#087F78', title: restaurant['name'] as String? ?? ''),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(restaurant['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text('${restaurant['cuisine'] ?? ''} · ${restaurant['categoryLabel'] ?? ''}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(restaurant['ratingLabel'] as String? ?? 'لا توجد تقييمات بعد', style: const TextStyle(fontSize: 12)),
                    Text('${restaurant['etaMinutes']} د · توصيل ${restaurant['deliveryFeeLabel']}', style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
                    Text(ordering['label'] as String? ?? '', style: const TextStyle(color: AppColors.petrol, fontWeight: FontWeight.w700, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RestaurantPage extends ConsumerStatefulWidget {
  const RestaurantPage({super.key, required this.id});
  final String id;

  @override
  ConsumerState<RestaurantPage> createState() => _RestaurantPageState();
}

class _RestaurantPageState extends ConsumerState<RestaurantPage> {
  Map<String, dynamic>? _restaurant;
  final List<Map<String, dynamic>> _lines = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final restaurant = await ref.read(apiProvider).restaurant(widget.id);
      if (mounted) setState(() { _restaurant = restaurant; _loading = false; });
    } on ApiException catch (error) {
      if (mounted) setState(() { _error = error.message; _loading = false; });
    }
  }

  Future<void> _add(Map<String, dynamic> item) async {
    if (ref.read(sessionProvider).user == null) {
      context.push('/login');
      return;
    }
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ItemSheet(item: item),
    );
    if (result == null) return;
    setState(() => _lines.add(result));
    try {
      await ref.read(apiProvider).saveCart(widget.id, _lines.map((line) => {
        'itemId': line['itemId'],
        'quantity': line['quantity'],
        'optionIds': line['optionIds'],
        'note': line['note'],
      }).toList());
    } on ApiException catch (error) {
      setState(() => _lines.remove(result));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = _restaurant;
    final sections = ((restaurant?['sections'] as List?) ?? []).cast<Map>();
    return Scaffold(
      appBar: AppBar(title: Text(restaurant?['name'] as String? ?? 'المطعم')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.petrol))
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _Cover(color: restaurant?['coverColor'] as String? ?? '#087F78', title: restaurant?['name'] as String? ?? '', wide: true),
                    const SizedBox(height: 12),
                    Text(restaurant?['name'] as String? ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                    Text('${restaurant?['cuisine'] ?? ''} · ${restaurant?['ratingLabel'] ?? ''}', style: const TextStyle(color: AppColors.muted)),
                    Text('${restaurant?['etaMinutes']} دقيقة · توصيل ${restaurant?['deliveryFeeLabel']} · الحد الأدنى ${restaurant?['minOrderLabel']}', style: const TextStyle(fontSize: 13)),
                    Text((restaurant?['ordering'] as Map?)?['label'] as String? ?? '', style: const TextStyle(color: AppColors.petrol, fontWeight: FontWeight.w700)),
                    if (((restaurant?['offers'] as List?) ?? []).isNotEmpty)
                      Padding(padding: const EdgeInsets.only(top: 8), child: Text((restaurant!['offers'] as List).first['title'] as String)),
                    for (final section in sections) ...[
                      const SizedBox(height: 16),
                      Text(section['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                      for (final raw in (section['items'] as List? ?? []))
                        _MenuTile(item: Map<String, dynamic>.from(raw), onAdd: () => _add(Map<String, dynamic>.from(raw))),
                    ],
                  ],
                ),
      bottomNavigationBar: _lines.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AppButton(label: 'السلة (${_lines.length})', onPressed: () => context.push('/restaurants/${widget.id}/cart')),
              ),
            ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.item, required this.onAdd});
  final Map<String, dynamic> item;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final available = item['available'] == true;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
                if ((item['description'] as String?)?.isNotEmpty == true) Text(item['description'] as String, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                Text(item['kind'] == 'COMBO' ? 'وجبة مجمعة · ${item['priceLabel']}' : item['priceLabel'] as String? ?? '', style: const TextStyle(color: AppColors.petrol, fontWeight: FontWeight.w700)),
                if (!available) const Text('غير متاح', style: TextStyle(color: AppColors.danger, fontSize: 12)),
              ],
            ),
          ),
          IconButton(onPressed: available ? onAdd : null, icon: const Icon(Icons.add_circle_outline, color: AppColors.petrol)),
        ],
      ),
    );
  }
}

class _ItemSheet extends StatefulWidget {
  const _ItemSheet({required this.item});
  final Map<String, dynamic> item;

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  final _selected = <String>{};
  final _note = TextEditingController();
  int _quantity = 1;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final groups = ((widget.item['groups'] as List?) ?? []).cast<Map>();
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(widget.item['name'] as String? ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(widget.item['priceLabel'] as String? ?? ''),
          for (final group in groups) ...[
            const SizedBox(height: 12),
            Text(group['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
            for (final option in ((group['options'] as List?) ?? []).cast<Map>())
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _selected.contains(option['id']),
                title: Text('${option['name']} · ${option['priceLabel']}'),
                onChanged: option['available'] == false
                    ? null
                    : (checked) => setState(() => checked == true ? _selected.add(option['id'] as String) : _selected.remove(option['id'])),
              ),
          ],
          AppField(label: 'طلب خاص، مثل إزالة مكوّن', controller: _note),
          Row(
            children: [
              IconButton(onPressed: () => setState(() => _quantity = _quantity > 1 ? _quantity - 1 : 1), icon: const Icon(Icons.remove)),
              Text('$_quantity'),
              IconButton(onPressed: () => setState(() => _quantity += 1), icon: const Icon(Icons.add)),
            ],
          ),
          if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.danger)),
          AppButton(
            label: 'أضف إلى السلة',
            onPressed: () {
              for (final group in groups) {
                final ids = ((group['options'] as List?) ?? []).cast<Map>().map((option) => option['id'] as String).toSet();
                final count = _selected.where(ids.contains).length;
                final min = group['minSelect'] as int? ?? 0;
                final max = group['maxSelect'] as int? ?? 1;
                if (count < min || count > max) {
                  setState(() => _error = 'اختر ${group['name']}');
                  return;
                }
              }
              Navigator.pop(context, {
                'itemId': widget.item['id'],
                'quantity': _quantity,
                'optionIds': _selected.toList(),
                'note': _note.text.trim(),
              });
            },
          ),
        ],
      ),
    );
  }
}

class FoodCartPage extends ConsumerStatefulWidget {
  const FoodCartPage({super.key, required this.restaurantId});
  final String restaurantId;

  @override
  ConsumerState<FoodCartPage> createState() => _FoodCartPageState();
}

class _FoodCartPageState extends ConsumerState<FoodCartPage> {
  Map<String, dynamic>? _cart;
  Map<String, dynamic>? _quote;
  List<SavedAddress> _addresses = [];
  String? _addressId;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _courierId;
  String? _courierName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(apiProvider);
      final cart = await api.cart(widget.restaurantId);
      final addresses = await api.addresses();
      if (!mounted) return;
      SavedAddress? selected;
      for (final address in addresses) {
        if (address.isDefault) selected = address;
      }
      selected ??= addresses.isEmpty ? null : addresses.first;
      setState(() {
        _cart = cart;
        _addresses = addresses;
        _addressId = selected?.id;
        _loading = false;
      });
      if (_addressId != null) await _price();
    } on ApiException catch (error) {
      if (mounted) setState(() { _error = error.message; _loading = false; });
    }
  }

  Future<void> _change(int index, int delta) async {
    final lines = ((_cart?['lines'] as List?) ?? []).map((line) => Map<String, dynamic>.from(line as Map)).toList();
    final next = (lines[index]['quantity'] as int) + delta;
    if (next <= 0) {
      lines.removeAt(index);
    } else {
      lines[index]['quantity'] = next;
    }
    final saved = await ref.read(apiProvider).saveCart(widget.restaurantId, lines.map((line) => {
      'itemId': line['itemId'],
      'quantity': line['quantity'],
      'optionIds': line['optionIds'],
      'note': line['note'],
    }).toList());
    if (!mounted) return;
    setState(() => _cart = saved);
    await _price();
  }

  Future<void> _price() async {
    if (_addressId == null) return;
    try {
      final quote = await ref.read(apiProvider).foodQuote(widget.restaurantId, _addressId!);
      if (mounted) setState(() => _quote = quote);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _chooseCourier() async {
    final picked = await pickCourier(context, ref.read(apiProvider));
    if (picked == null || !mounted) return;
    setState(() {
      _courierId = picked['id'] as String;
      _courierName = picked['name'] as String?;
    });
  }

  Future<void> _place() async {
    if (_courierId == null) {
      setState(() => _error = 'اختَر مندوبًا قبل تأكيد الطلب.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final order = await ref.read(apiProvider).placeFoodOrder(widget.restaurantId, {
        'addressId': _addressId,
        'recipientName': _name.text.trim(),
        'recipientPhone': _phone.text.trim(),
        'notes': _notes.text.trim(),
        'courierId': _courierId,
        if (_quote?['scheduledOnly'] == true) 'scheduledFor': DateTime.now().add(const Duration(hours: 2)).toUtc().toIso8601String(),
      }, 'food-${DateTime.now().microsecondsSinceEpoch}');
      if (mounted) context.go('/food-orders/${order['id']}');
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = ((_cart?['lines'] as List?) ?? []).cast<Map>();
    final quote = _quote;
    return Scaffold(
      appBar: AppBar(title: const Text('سلة الطعام')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.petrol))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (lines.isEmpty) const Text('السلة فارغة. أضف صنفًا من المنيو أولًا.'),
                for (var index = 0; index < lines.length; index++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${lines[index]['quantity']} × ${lines[index]['name']}'),
                    subtitle: Text(((lines[index]['options'] as List?) ?? []).map((option) => (option as Map)['name']).join('، ')),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(lines[index]['lineLabel'] as String? ?? ''),
                        IconButton(onPressed: () => _change(index, -1), icon: const Icon(Icons.remove_circle_outline)),
                        IconButton(onPressed: () => _change(index, 1), icon: const Icon(Icons.add_circle_outline)),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                for (final address in _addresses)
                  ChoiceChip(
                    label: Text(address.line),
                    selected: _addressId == address.id,
                    onSelected: (_) { setState(() => _addressId = address.id); _price(); },
                  ),
                TextButton(onPressed: () => context.push('/addresses'), child: const Text('عنوان جديد')),
                AppField(label: 'اسم المستلم', controller: _name),
                AppField(label: 'هاتف المستلم', controller: _phone),
                AppField(label: 'ملاحظات التوصيل', controller: _notes),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_courierName ?? 'لم يتم اختيار مندوب'),
                  subtitle: const Text('من يوصل طلبًا الآن لا يظهر حتى يسلّمه.'),
                  onTap: _busy ? null : _chooseCourier,
                ),
                AppButton(label: 'اختيار مندوب', secondary: true, onPressed: _busy ? null : _chooseCourier),
                const SizedBox(height: 8),
                if (quote != null) ...[
                  Text('الطعام: ${quote['foodLabel']}'),
                  Text('الخصم: ${quote['discountLabel']}'),
                  Text('التوصيل: ${quote['deliveryFeeLabel']}'),
                  Text('الإجمالي: ${quote['totalLabel']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  const Text('الدفع: نقدًا عند الاستلام'),
                ],
                if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.danger)),
                const SizedBox(height: 12),
                AppButton(label: 'تأكيد الطلب', loading: _busy, onPressed: lines.isEmpty ? null : _place),
              ],
            ),
    );
  }
}

class FoodOrderPage extends ConsumerStatefulWidget {
  const FoodOrderPage({super.key, required this.id});
  final String id;

  @override
  ConsumerState<FoodOrderPage> createState() => _FoodOrderPageState();
}

class _FoodOrderPageState extends ConsumerState<FoodOrderPage> {
  Map<String, dynamic>? _order;
  String? _error;
  bool _loading = true;
  int _rating = 0;
  Timer? _timer;
  WebSocketChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _listen();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => _load(quiet: true));
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
      if (data['type'] == 'food.updated' && data['foodOrderId'] == widget.id) _load(quiet: true);
      if (data['type'] == 'order.updated') _load(quiet: true);
    });
  }

  Future<void> _load({bool quiet = false}) async {
    try {
      final order = await ref.read(apiProvider).foodOrder(widget.id);
      if (mounted) setState(() { _order = order; _loading = false; _error = quiet ? _error : null; });
    } on ApiException catch (error) {
      if (mounted) setState(() { _error = error.message; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return Scaffold(
      appBar: AppBar(title: Text(order?['publicNumber'] as String? ?? 'طلب طعام')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.petrol))
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(order?['statusTitle'] as String? ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                    Text((order?['restaurant'] as Map?)?['name'] as String? ?? ''),
                    if (order?['prepMinutes'] != null) Text('وقت التجهيز: ${order!['prepMinutes']} دقيقة'),
                    if (order?['courierAssigned'] != true && order?['foodReady'] == true) const Text('بانتظار تعيين مندوب'),
                    if (order?['rejectReason'] != null) Text(order!['rejectReason'] as String),
                    const SizedBox(height: 12),
                    Text('الطعام ${order?['foodLabel']}'),
                    Text('التوصيل ${order?['deliveryFeeLabel']}'),
                    Text('الخصم ${order?['discountLabel']}'),
                    Text('الإجمالي ${order?['totalLabel']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(order?['paymentLabel'] as String? ?? ''),
                    const SizedBox(height: 12),
                    if (order?['deliveryOrderId'] != null && order?['courierAssigned'] == true)
                      AppButton(label: 'تتبع المندوب', onPressed: () => context.push('/orders/${order!['deliveryOrderId']}')),
                    if (['PENDING_RESTAURANT', 'ACCEPTED', 'PREPARING', 'READY'].contains(order?['restaurantStatus']) && order?['courierAssigned'] != true)
                      AppButton(label: 'إلغاء الطلب', secondary: true, onPressed: () async {
                        await ref.read(apiProvider).cancelFoodOrder(widget.id);
                        _load();
                      }),
                    if (order?['status'] == 'DELIVERED' && order?['review'] == null) ...[
                      const SizedBox(height: 16),
                      const Text('تقييم المطعم', style: TextStyle(fontWeight: FontWeight.w800)),
                      Row(children: List.generate(5, (index) => IconButton(onPressed: () => setState(() => _rating = index + 1), icon: Icon(index < _rating ? Icons.star : Icons.star_border, color: AppColors.amber)))),
                      AppButton(label: 'إرسال تقييم المطعم', onPressed: _rating == 0 ? null : () async {
                        await ref.read(apiProvider).reviewRestaurant(widget.id, _rating, null);
                        _load();
                      }),
                    ],
                  ],
                ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.color, required this.title, this.wide = false});
  final String color;
  final String title;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final parsed = Color(int.parse(color.replaceFirst('#', 'FF'), radix: 16));
    return Container(
      width: wide ? double.infinity : 72,
      height: wide ? 120 : 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: parsed, borderRadius: BorderRadius.circular(14)),
      child: Text(title.isEmpty ? '' : title.substring(0, 1), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
    );
  }
}
