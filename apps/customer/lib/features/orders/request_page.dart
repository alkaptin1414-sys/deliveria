import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ui.dart';
import 'courier_picker.dart';
import '../session/session_controller.dart';

class RequestPage extends ConsumerStatefulWidget {
  const RequestPage({super.key, this.preset, this.reorder});
  final String? preset;
  final DeliveryOrder? reorder;

  @override
  ConsumerState<RequestPage> createState() => _RequestPageState();
}

class _RequestPageState extends ConsumerState<RequestPage> {
  int _step = 0;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  String _idempotency = DateTime.now().microsecondsSinceEpoch.toString();

  PlaceInput? _pickup;
  PlaceInput? _dropoff;
  bool _lockPickup = false;

  final _pickupLine = TextEditingController();
  final _dropoffLine = TextEditingController();
  final _pickupDetails = TextEditingController();
  final _dropoffDetails = TextEditingController();
  final _recipientName = TextEditingController();
  final _recipientPhone = TextEditingController();
  final _description = TextEditingController();
  final _notes = TextEditingController();
  final _goods = TextEditingController();

  String _parcel = 'PACKAGE';
  String _size = 'SMALL';
  bool _fragile = false;
  String _vehicle = 'MOTORCYCLE';
  bool _saveRecipient = false;
  bool _goodsPrepaid = false;
  bool _collectGoods = false;
  String _deliveryPayer = 'RECIPIENT';
  List<dynamic> _suggestions = [];
  Map<String, dynamic>? _quote;
  List<dynamic> _vehicles = [];
  List<SavedAddress> _addresses = [];
  String? _courierId;
  String? _courierName;

  @override
  void initState() {
    super.initState();
    if (widget.preset == 'PERSONAL') _parcel = 'PERSONAL';
    _lockPickup = widget.preset == 'SHOP';
    _prepare();
  }

  @override
  void dispose() {
    _pickupLine.dispose();
    _dropoffLine.dispose();
    _pickupDetails.dispose();
    _dropoffDetails.dispose();
    _recipientName.dispose();
    _recipientPhone.dispose();
    _description.dispose();
    _notes.dispose();
    _goods.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    try {
      final api = ref.read(apiProvider);
      final addresses = await api.addresses();
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('order_draft');
      if (raw != null) {
        final draft = jsonDecode(raw) as Map<String, dynamic>;
        _idempotency = draft['key'] as String? ?? _idempotency;
      }
      SavedAddress? shop;
      final businessAccount = ref.read(sessionProvider).user?.isBusiness == true;
      for (final address in addresses) {
        if (businessAccount && address.label == 'SHOP') {
          shop = address;
          break;
        }
        if (address.isDefault) shop ??= address;
      }
      final reorder = widget.reorder;
      if (reorder != null) {
        final pickup = reorder.pickup;
        final dropoff = reorder.dropoff;
        _pickup = PlaceInput(name: pickup['name'] as String, line: pickup['line'] as String, details: pickup['details'] as String?, lat: (pickup['lat'] as num).toDouble(), lng: (pickup['lng'] as num).toDouble());
        _dropoff = PlaceInput(name: dropoff['name'] as String, line: dropoff['line'] as String, details: dropoff['details'] as String?, lat: (dropoff['lat'] as num).toDouble(), lng: (dropoff['lng'] as num).toDouble());
        _pickupLine.text = _pickup!.line;
        _dropoffLine.text = _dropoff!.line;
        _recipientName.text = reorder.json['recipientName'] as String? ?? '';
        _recipientPhone.text = (reorder.json['recipientPhone'] as String? ?? '').replaceFirst('+20', '0');
        _description.text = reorder.json['parcelDescription'] as String? ?? '';
        _parcel = reorder.json['parcelType'] as String? ?? _parcel;
        _size = reorder.json['size'] as String? ?? _size;
        _fragile = reorder.json['fragile'] as bool? ?? false;
        _vehicle = reorder.json['vehicle'] as String? ?? _vehicle;
      } else if (shop != null) {
        _pickup = PlaceInput(name: shop.name, line: shop.line, details: shop.details, lat: shop.lat, lng: shop.lng);
        _pickupLine.text = shop.line;
        _pickupDetails.text = shop.details ?? '';
      }
      final user = ref.read(sessionProvider).user;
      if (user?.isBusiness == true && _recipientName.text.isEmpty) {
        _saveRecipient = true;
      }
      if (!mounted) return;
      setState(() {
        _addresses = addresses;
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

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('order_draft', jsonEncode({'key': _idempotency}));
  }

  PlaceInput? _written(String name, String raw) {
    final line = raw.trim();
    if (line.length < 3) return null;
    return PlaceInput(name: name, line: line, lat: 0, lng: 0);
  }

  Future<void> _loadQuote() async {
    if (_pickup == null || _dropoff == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider);
      final vehicles = await api.vehicles(_pickup!.lat, _pickup!.lng);
      if (vehicles.isEmpty) {
        setState(() => _error = 'الخدمة غير متاحة في عنوان الاستلام.');
        return;
      }
      if (!vehicles.any((item) => (item as Map)['code'] == _vehicle)) {
        _vehicle = (vehicles.first as Map)['code'] as String;
      }
      final quote = await api.quote({
        'pickup': _pickup!.toJson(),
        'dropoff': _dropoff!.toJson(),
        'size': _size,
        'fragile': _fragile,
        'vehicle': _vehicle,
        ..._collectionBody(),
      });
      if (!mounted) return;
      setState(() {
        _vehicles = vehicles;
        _quote = quote;
      });
    } on ApiException catch (error) {
      setState(() {
        _quote = null;
        _error = error.message;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _chooseCourier() async {
    final picked = await pickCourier(context, ref.read(apiProvider));
    if (picked == null || !mounted) return;
    final vehicle = picked['vehicle'] as String?;
    setState(() {
      _courierId = picked['id'] as String;
      _courierName = picked['name'] as String?;
      if (vehicle == 'MOTORCYCLE' || vehicle == 'CAR') _vehicle = vehicle!;
      _quote = null;
    });
    await _loadQuote();
  }

  Future<void> _submit() async {
    if (_quote == null || _submitting) return;
    if (_courierId == null) {
      setState(() => _error = 'اختَر مندوبًا قبل تأكيد الطلب.');
      return;
    }
    setState(() => _submitting = true);
    try {
      final order = await ref.read(apiProvider).createOrder({
        'pickup': _pickup!.copyWith(details: _pickupDetails.text).toJson(),
        'dropoff': _dropoff!.copyWith(name: 'التسليم', details: _dropoffDetails.text).toJson(),
        'size': _size,
        'fragile': _fragile,
        'vehicle': _vehicle,
        'courierId': _courierId,
        'recipientName': _recipientName.text.trim(),
        'recipientPhone': _recipientPhone.text.trim(),
        'parcelType': _parcel,
        'parcelDescription': _description.text.trim(),
        'notes': _notes.text.trim(),
        'saveRecipient': _saveRecipient,
        ..._collectionBody(),
      }, _idempotency);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('order_draft');
      if (!mounted) return;
      context.go('/orders/${order.id}');
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Map<String, dynamic> _collectionBody() {
    final pounds = double.tryParse(_goods.text.replaceAll(',', '.')) ?? 0;
    return {
      'goodsMinor': (pounds * 100).round(),
      'goodsPrepaid': _goodsPrepaid,
      'collectGoods': _goodsPrepaid ? false : _collectGoods,
      'deliveryPayer': _deliveryPayer,
    };
  }

  Future<void> _suggest(String value) async {
    if (ref.read(sessionProvider).user?.isBusiness != true || value.trim().length < 3) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }
    try {
      final items = await ref.read(apiProvider).recipients(q: value.trim());
      if (mounted) setState(() => _suggestions = items);
    } catch (_) {}
  }

  Future<void> _next() async {
    if (_step == 0) {
      final pickup = _lockPickup && _pickup != null ? _pickup : _written('الاستلام', _pickupLine.text);
      final dropoff = _written('التسليم', _dropoffLine.text);
      if (pickup == null || dropoff == null) {
        setState(() => _error = 'اكتب عنوان الاستلام وعنوان التسليم.');
        return;
      }
      setState(() {
        _pickup = pickup;
        _dropoff = dropoff;
        _quote = null;
        _error = null;
      });
      setState(() {
        _step = 1;
        _error = null;
      });
      _persist();
      return;
    }
    if (_recipientName.text.trim().length < 2 || _recipientPhone.text.trim().length < 10 || _description.text.trim().length < 2) {
      setState(() => _error = 'كمّل اسم المستلم ورقمه ووصف الغرض.');
      return;
    }
    setState(() => _step = 2);
    _loadQuote();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step > 0) setState(() => _step -= 1);
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(ref.read(sessionProvider).user?.isBusiness == true && widget.preset == 'SHOP' ? 'توصيل من المحل' : 'طلب مندوب'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: () {
            if (_step > 0) {
              setState(() => _step -= 1);
            } else {
              context.pop();
            }
          },
        ),
      ),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(20), child: SkeletonBox(height: 180))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: List.generate(3, (index) {
                          return Expanded(
                            child: Container(
                              height: 3,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              color: index <= _step ? AppColors.petrol : AppColors.line,
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        const ['الاستلام والتسليم', 'تفاصيل الطلب', 'السعر والتأكيد'][_step],
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.petrol),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    children: [
                      if (_step == 0) ..._locations(),
                      if (_step == 1) ..._details(),
                      if (_step == 2) ..._review(),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
                      ],
                    ],
                  ),
                ),
                BottomBar(
                  child: AppButton(
                    label: _step == 2 ? 'تأكيد وطلب مندوب' : 'متابعة',
                    loading: _submitting,
                    onPressed: _submitting ? null : (_step == 2 ? _submit : _next),
                  ),
                ),
              ],
            ),
      ),
    );
  }

  List<Widget> _locations() {
    final pickupLocked = _lockPickup && _pickup != null;
    return [
      const Text('الاستلام والتسليم', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      const Text('اكتب العنوان كما تعرفه. لن يُحدَّد على الخريطة ولن تُحسب مسافة.', style: TextStyle(color: AppColors.muted)),
      const SizedBox(height: 14),
      AppField(label: 'عنوان الاستلام', controller: _pickupLine, hint: 'مثال: شارع التسعين، التجمع، القاهرة', enabled: !pickupLocked),
      if (!pickupLocked) TextButton(onPressed: _chooseSaved, child: const Text('استخدام عنوان محفوظ')),
      const SizedBox(height: 8),
      AppField(label: 'تفاصيل الاستلام', controller: _pickupDetails, hint: 'الدور، الشقة، علامة مميزة'),
      const SizedBox(height: 16),
      AppField(label: 'عنوان التسليم', controller: _dropoffLine, hint: 'مثال: شارع جامعة الدول، المهندسين'),
      const SizedBox(height: 8),
      AppField(label: 'تفاصيل التسليم', controller: _dropoffDetails, hint: 'الدور، الشقة، علامة مميزة'),
    ];
  }

  List<Widget> _details() {
    return [
      const Text('تفاصيل الطلب', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      const SizedBox(height: 14),
      AppField(label: 'اسم المستلم', controller: _recipientName),
      const SizedBox(height: 10),
      AppField(label: 'هاتف المستلم', controller: _recipientPhone, keyboardType: TextInputType.phone, onChanged: _suggest),
      if (_suggestions.isNotEmpty)
        ..._suggestions.take(3).map((item) {
          final row = Map<String, dynamic>.from(item as Map);
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(row['name'] as String? ?? ''),
            subtitle: Text(row['phone'] as String? ?? ''),
            onTap: () {
              _recipientName.text = row['name'] as String? ?? '';
              _recipientPhone.text = (row['phone'] as String? ?? '').replaceFirst('+20', '0');
              final line = row['line'] as String?;
              if (line != null && line.isNotEmpty && row['lat'] != null) {
                _dropoffLine.text = line;
                _dropoff = PlaceInput(name: 'التسليم', line: line, details: row['details'] as String?, lat: (row['lat'] as num).toDouble(), lng: (row['lng'] as num).toDouble());
              }
              setState(() => _suggestions = []);
            },
          );
        }),
      const SizedBox(height: 10),
      AppField(label: 'وصف الغرض', controller: _description, hint: 'مثال: كيس أوراق'),
      const SizedBox(height: 10),
      AppField(label: 'ملاحظات للمندوب', controller: _notes, maxLines: 2),
      const SizedBox(height: 14),
      const SectionLabel('نوع الغرض'),
      Wrap(
        spacing: 8,
        children: [
          for (final item in const [('PACKAGE', 'طرد'), ('DOCUMENTS', 'مستندات'), ('FOOD', 'طعام'), ('PERSONAL', 'شخصي'), ('OTHER', 'أخرى')])
            ChoiceChip(
              label: Text(item.$2),
              selected: _parcel == item.$1,
              onSelected: (_) => setState(() => _parcel = item.$1),
            ),
        ],
      ),
      const SizedBox(height: 12),
      const SectionLabel('الحجم'),
      Wrap(
        spacing: 8,
        children: [
          for (final item in const [('SMALL', 'صغير'), ('MEDIUM', 'متوسط'), ('LARGE', 'كبير')])
            ChoiceChip(
              label: Text(item.$2),
              selected: _size == item.$1,
              onSelected: (_) => setState(() => _size = item.$1),
            ),
        ],
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('الطلب قابل للكسر'),
        value: _fragile,
        activeThumbColor: AppColors.petrol,
        onChanged: (value) => setState(() => _fragile = value),
      ),
      if (ref.read(sessionProvider).user?.isBusiness == true)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('حفظ بيانات المستلم'),
          subtitle: const Text('بموافقتك، لإعادة الطلب لنفس العميل.'),
          value: _saveRecipient,
          activeThumbColor: AppColors.petrol,
          onChanged: (value) => setState(() => _saveRecipient = value),
        ),
    ];
  }

  List<Widget> _review() {
    final quote = _quote;
    return [
      const Text('تكلفة التوصيل', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      const Text('السعر محسوب على الخادم، والدفع نقدًا.', style: TextStyle(color: AppColors.muted)),
      const SizedBox(height: 14),
      const SectionLabel('المندوب'),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(_courierName ?? 'لم يتم الاختيار'),
        subtitle: const Text('من لديه طلب قيد التوصيل لا يظهر حتى يسلّمه.'),
        trailing: const Icon(Icons.chevron_left),
        onTap: _submitting ? null : _chooseCourier,
      ),
      const SizedBox(height: 8),
      AppButton(label: 'اختيار مندوب', secondary: true, onPressed: _submitting ? null : _chooseCourier),
      const SizedBox(height: 14),
      const SectionLabel('وسيلة النقل'),
      if (_vehicles.isEmpty && quote == null)
        const Text('بنراجع التوافر...')
      else
        Wrap(
          spacing: 8,
          children: [
            for (final item in _vehicles)
              ChoiceChip(
                label: Text(vehicleLabel((item as Map)['code'] as String)),
                selected: _vehicle == item['code'],
                onSelected: (_) {
                  setState(() => _vehicle = item['code'] as String);
                  _loadQuote();
                },
              ),
          ],
        ),
      const SizedBox(height: 14),
      if (quote != null)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
          child: Column(
            children: [
              if ((quote['distanceMeters'] as int? ?? 0) > 0) _line('المسافة', kmLabel(quote['distanceMeters'] as int)),
              _line('التوصيل', money(quote['feeMinor'] as int)),
              for (final extra in (quote['extras'] as List? ?? []))
                _line((extra as Map)['label'] as String, money(extra['amountMinor'] as int)),
              const Divider(),
              _line('الإجمالي', money(quote['totalMinor'] as int), strong: true),
              if ((quote['etaMinutes'] as int? ?? 0) > 0) _line('الوقت المتوقع', '${quote['etaMinutes']} دقيقة'),
              _line('الدفع', 'نقدًا'),
            ],
          ),
        ),
      const SizedBox(height: 18),
      const SectionLabel('تفاصيل الدفع والتحصيل'),
      AppField(label: 'قيمة المنتجات بالجنيه', controller: _goods, keyboardType: TextInputType.number, onChanged: (_) => _loadQuote()),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('قيمة المنتجات مدفوعة مسبقًا'),
        value: _goodsPrepaid,
        activeThumbColor: AppColors.petrol,
        onChanged: (value) => setState(() {
          _goodsPrepaid = value;
          if (value) _collectGoods = false;
          _loadQuote();
        }),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('المندوب يحصل قيمة المنتجات'),
        value: _goodsPrepaid ? false : _collectGoods,
        activeThumbColor: AppColors.petrol,
        onChanged: _goodsPrepaid ? null : (value) => setState(() {
          _collectGoods = value;
          _loadQuote();
        }),
      ),
      const Text('من يتحمل رسوم التوصيل؟', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: [
          ChoiceChip(label: const Text('العميل'), selected: _deliveryPayer == 'RECIPIENT', onSelected: (_) => setState(() { _deliveryPayer = 'RECIPIENT'; _loadQuote(); })),
          ChoiceChip(label: const Text('المحل'), selected: _deliveryPayer == 'BUSINESS', onSelected: (_) => setState(() { _deliveryPayer = 'BUSINESS'; _loadQuote(); })),
        ],
      ),
      if (quote != null && quote['collection'] is Map) ...[
        const SizedBox(height: 12),
        _line('المطلوب تحصيله', money((quote['collection'] as Map)['collectMinor'] as int), strong: true),
        _line('المستحق للمحل', money((quote['collection'] as Map)['businessDueMinor'] as int)),
        const Text('قيمة المنتجات كما أدخلتها، وليست مبلغًا موثقًا من المنصة. اكتمال التوصيل لا يعني وصول الأموال.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
      ],
    ];
  }

  Widget _line(String label, String value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: strong ? AppColors.ink : AppColors.muted, fontWeight: strong ? FontWeight.w800 : FontWeight.w500))),
          Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: strong ? 22 : 14, color: strong ? AppColors.petrol : AppColors.ink)),
        ],
      ),
    );
  }

  Future<void> _chooseSaved() async {
    if (_addresses.isEmpty) {
      setState(() => _error = 'لا توجد عناوين محفوظة. اكتب العنوان.');
      return;
    }
    final selected = await showModalBottomSheet<SavedAddress>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final address in _addresses)
              ListTile(
                title: Text(address.name),
                subtitle: Text(address.line),
                onTap: () => Navigator.pop(context, address),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    setState(() {
      _pickupLine.text = selected.line;
      _pickup = PlaceInput(name: selected.name, line: selected.line, details: selected.details, lat: selected.lat, lng: selected.lng);
      _pickupDetails.text = selected.details ?? _pickupDetails.text;
    });
  }
}

extension on PlaceInput {
  PlaceInput copyWith({String? name, String? details}) {
    return PlaceInput(
      name: name ?? this.name,
      line: line,
      details: details ?? this.details,
      lat: lat,
      lng: lng,
    );
  }
}
