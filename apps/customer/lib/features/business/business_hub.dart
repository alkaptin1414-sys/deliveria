import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ui.dart';

class CustomersPage extends ConsumerStatefulWidget {
  const CustomersPage({super.key});

  @override
  ConsumerState<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends ConsumerState<CustomersPage> {
  final _query = TextEditingController();
  List<dynamic> _items = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(apiProvider).recipients(q: _query.text.trim());
      if (mounted) setState(() => _items = items);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _add() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final line = TextEditingController();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppField(label: 'الاسم', controller: name),
            const SizedBox(height: 8),
            AppField(label: 'الهاتف', controller: phone, keyboardType: TextInputType.phone),
            const SizedBox(height: 8),
            AppField(label: 'العنوان', controller: line),
            const SizedBox(height: 12),
            AppButton(
              label: 'حفظ',
              onPressed: () async {
                await ref.read(apiProvider).saveRecipient({
                  'name': name.text.trim(),
                  'phone': phone.text.trim(),
                  'line': line.text.trim(),
                });
                if (context.mounted) Navigator.pop(context, true);
              },
            ),
          ],
        ),
      ),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('عملائي'), actions: [IconButton(onPressed: _add, icon: const Icon(Icons.add))]),
      body: Column(
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 0), child: AppField(label: 'بحث بالاسم أو الهاتف', controller: _query, onChanged: (_) => _load())),
          if (_error != null) Padding(padding: const EdgeInsets.all(20), child: Text(_error!)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                for (final item in _items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text((item as Map)['name'] as String? ?? ''),
                    subtitle: Text('${item['phone'] ?? ''}\n${item['line'] ?? ''}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await ref.read(apiProvider).deleteRecipient(item['id'] as String);
                        _load();
                      },
                    ),
                  ),
                if (_items.isEmpty) const EmptyView(title: 'لا يوجد عملاء', body: 'أضف عملاء المحل لإعادة استخدام بياناتهم عند الطلب.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FinancePage extends ConsumerStatefulWidget {
  const FinancePage({super.key});

  @override
  ConsumerState<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends ConsumerState<FinancePage> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ref.read(apiProvider).finance();
      if (mounted) setState(() => _data = data);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = Map<String, dynamic>.from(_data?['summary'] as Map? ?? {});
    final labels = Map<String, dynamic>.from(_data?['labels'] as Map? ?? {});
    final entries = (_data?['entries'] as List?) ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('الحسابات والتسويات')),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(_data?['note'] as String? ?? '', style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Stat('منتجات محصّلة', labels['goodsCollectedLabel'] as String? ?? money(summary['goodsCollectedMinor'] as int? ?? 0)),
                    _Stat('رسوم التوصيل', labels['deliveryLabel'] as String? ?? money(summary['deliveryMinor'] as int? ?? 0)),
                    _Stat('مستحق للمحل', labels['businessDueLabel'] as String? ?? money(summary['businessDueMinor'] as int? ?? 0)),
                    _Stat('تمت تسويته', labels['settledLabel'] as String? ?? money(summary['settledMinor'] as int? ?? 0)),
                    _Stat('معلق', labels['pendingLabel'] as String? ?? money(summary['pendingMinor'] as int? ?? 0)),
                    _Stat('نزاع', labels['disputedLabel'] as String? ?? money(summary['disputedMinor'] as int? ?? 0)),
                  ],
                ),
                const SizedBox(height: 18),
                const SectionLabel('سجل العمليات'),
                for (final entry in entries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text((entry as Map)['kind'] as String? ?? ''),
                    subtitle: Text((entry['order'] as Map?)?['publicNumber'] as String? ?? ''),
                    trailing: Text(money(entry['amountMinor'] as int? ?? 0)),
                  ),
              ],
            ),
    );
  }
}

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  String _range = 'today';
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    late DateTime from;
    if (_range == 'yesterday') {
      from = DateTime(now.year, now.month, now.day - 1);
    } else if (_range == '7') {
      from = now.subtract(const Duration(days: 7));
    } else if (_range == '30') {
      from = now.subtract(const Duration(days: 30));
    } else {
      from = DateTime(now.year, now.month, now.day);
    }
    try {
      final data = await ref.read(apiProvider).reports(from: from.toIso8601String(), to: now.toIso8601String());
      if (mounted) setState(() => _data = data);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data ?? {};
    return Scaffold(
      appBar: AppBar(title: const Text('التقارير')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final item in const [('today', 'اليوم'), ('yesterday', 'أمس'), ('7', '7 أيام'), ('30', '30 يومًا')])
                ChoiceChip(
                  label: Text(item.$2),
                  selected: _range == item.$1,
                  onSelected: (_) {
                    setState(() => _range = item.$1);
                    _load();
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_error != null) Text(_error!) else ...[
            _Stat('الطلبات', '${data['orders'] ?? 0}'),
            _Stat('مكتملة', '${data['completed'] ?? 0}'),
            _Stat('ملغاة', '${data['cancelled'] ?? 0}'),
            _Stat('جارية', '${data['active'] ?? 0}'),
            _Stat('تكاليف التوصيل', money(data['deliveryMinor'] as int? ?? 0)),
            _Stat('مستحقات المحل', money(data['businessDueMinor'] as int? ?? 0)),
            _Stat('تمت تسويته', money(data['settledMinor'] as int? ?? 0)),
          ],
        ],
      ),
    );
  }
}

class QuickOrderPage extends ConsumerStatefulWidget {
  const QuickOrderPage({super.key});

  @override
  ConsumerState<QuickOrderPage> createState() => _QuickOrderPageState();
}

class _QuickOrderPageState extends ConsumerState<QuickOrderPage> {
  final _phone = TextEditingController();
  final _name = TextEditingController();
  final _goods = TextEditingController();
  final _notes = TextEditingController();
  final _dropLine = TextEditingController();
  PlaceInput? _pickup;
  PlaceInput? _dropoff;
  bool _prepaid = false;
  String _payer = 'RECIPIENT';
  Map<String, dynamic>? _quote;
  String? _error;
  bool _busy = false;
  final _key = DateTime.now().microsecondsSinceEpoch.toString();

  @override
  void initState() {
    super.initState();
    _loadShop();
  }

  Future<void> _loadShop() async {
    try {
      final business = await ref.read(apiProvider).business();
      _pickup = PlaceInput(
        name: business['name'] as String? ?? 'المحل',
        line: business['addressLine'] as String? ?? '',
        lat: (business['lat'] as num).toDouble(),
        lng: (business['lng'] as num).toDouble(),
      );
      if (mounted) setState(() {});
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Map<String, dynamic> _collection() {
    final pounds = double.tryParse(_goods.text.replaceAll(',', '.')) ?? 0;
    return {
      'goodsMinor': (pounds * 100).round(),
      'goodsPrepaid': _prepaid,
      'collectGoods': !_prepaid,
      'deliveryPayer': _payer,
    };
  }

  Future<void> _price() async {
    final line = _dropLine.text.trim();
    if (_pickup == null || line.length < 3) {
      setState(() => _error = 'اكتب عنوان التسليم.');
      return;
    }
    _dropoff = PlaceInput(name: 'التسليم', line: line, lat: 0, lng: 0);
    setState(() => _busy = true);
    try {
      final quote = await ref.read(apiProvider).quote({
        'pickup': _pickup!.toJson(),
        'dropoff': _dropoff!.toJson(),
        'size': 'SMALL',
        'fragile': false,
        'vehicle': 'MOTORCYCLE',
        ..._collection(),
      });
      setState(() {
        _quote = quote;
        _error = null;
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_quote == null || _busy) return;
    setState(() => _busy = true);
    try {
      final order = await ref.read(apiProvider).createOrder({
        'pickup': _pickup!.toJson(),
        'dropoff': _dropoff!.toJson(),
        'size': 'SMALL',
        'fragile': false,
        'vehicle': 'MOTORCYCLE',
        'recipientName': _name.text.trim(),
        'recipientPhone': _phone.text.trim(),
        'parcelType': 'PACKAGE',
        'parcelDescription': 'طلب سريع من المحل',
        'notes': _notes.text.trim(),
        ..._collection(),
      }, _key);
      if (mounted) context.go('/orders/${order.id}');
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final collection = _quote?['collection'] as Map?;
    return Scaffold(
      appBar: AppBar(title: const Text('طلب سريع')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('الاستلام: ${_pickup?.line ?? 'عنوان المحل'}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          AppField(label: 'هاتف المستلم', controller: _phone, keyboardType: TextInputType.phone),
          const SizedBox(height: 8),
          AppField(label: 'اسم المستلم', controller: _name),
          const SizedBox(height: 8),
          AppField(label: 'عنوان التسليم', controller: _dropLine, hint: 'الشارع، المنطقة، والمدينة'),
          const SizedBox(height: 8),
          AppField(label: 'قيمة المنتجات بالجنيه', controller: _goods, keyboardType: TextInputType.number),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('المنتجات مدفوعة مسبقًا'), value: _prepaid, activeThumbColor: AppColors.petrol, onChanged: (value) => setState(() => _prepaid = value)),
          const Text('من يتحمل التوصيل؟'),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(label: const Text('العميل'), selected: _payer == 'RECIPIENT', onSelected: (_) => setState(() => _payer = 'RECIPIENT')),
              ChoiceChip(label: const Text('المحل'), selected: _payer == 'BUSINESS', onSelected: (_) => setState(() => _payer = 'BUSINESS')),
            ],
          ),
          AppField(label: 'ملاحظات', controller: _notes),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: AppColors.danger))),
          if (collection != null) ...[
            const SizedBox(height: 8),
            Text('تكلفة التوصيل ${money(_quote!['totalMinor'] as int)}'),
            Text('المطلوب تحصيله ${money(collection['collectMinor'] as int)}'),
          ],
          const SizedBox(height: 16),
          AppButton(label: _quote == null ? 'عرض تكلفة التوصيل' : 'تأكيد الطلب', loading: _busy, onPressed: _quote == null ? _price : _submit),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ],
      ),
    );
  }
}
