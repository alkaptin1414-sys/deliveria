import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../session/session_controller.dart';

const _sections = ['لوحة المعلومات', 'إدارة العملاء', 'إدارة المناديب', 'الطلبات', 'الأرباح والعمولات', 'التسويات والمدفوعات', 'البلاغات والشكاوى', 'إعدادات العمولة', 'سجل الإدارة'];

const _courierStatus = {
  'PENDING_REVIEW': 'قيد المراجعة',
  'NEEDS_INFO': 'يحتاج استكمال',
  'APPROVED': 'مقبول',
  'REJECTED': 'مرفوض',
  'SUSPENDED': 'موقوف',
};

const _orderStatus = {
  'SEARCHING': 'جديد',
  'ACCEPTED': 'مقبول',
  'EN_ROUTE_PICKUP': 'في الطريق للاستلام',
  'PICKED_UP': 'تم الاستلام',
  'EN_ROUTE_DROPOFF': 'في الطريق للتسليم',
  'DELIVERED': 'مكتمل',
  'CANCELLED': 'ملغى',
  'NO_COURIER': 'بلا مندوب',
};

const _vehicles = {
  'MOTORCYCLE': 'موتوسيكل',
  'CAR': 'سيارة',
  'BICYCLE': 'دراجة',
  'OTHER': 'أخرى',
};

const _docs = {
  'PORTRAIT': 'صورة شخصية',
  'NATIONAL_ID': 'بطاقة الرقم القومي',
  'LICENSE': 'رخصة القيادة',
  'VEHICLE_REGISTRATION': 'رخصة المركبة',
  'OTHER': 'مستند آخر',
};

const _settlementKind = {
  'WAGE_PAID': 'أجر مدفوع',
  'CASH_REMITTED': 'نقد مورّد',
  'ADJUSTMENT': 'تسوية',
};

String _show(dynamic value, [String fallback = 'غير متوفر']) {
  if (value == null || value is Map || value is List) return fallback;
  final text = value.toString().trim();
  if (text.isEmpty || text == 'null') return fallback;
  return text;
}

int _count(dynamic value) => value is num ? value.toInt() : 0;

const _ticketStatus = {
  'OPEN': 'جديدة',
  'IN_REVIEW': 'قيد المراجعة',
  'NEEDS_INFO': 'بانتظار الرد',
  'RESOLVED': 'تم الحل',
  'CLOSED': 'مغلقة',
};

class AdminHomePage extends ConsumerStatefulWidget {
  const AdminHomePage({super.key});

  @override
  ConsumerState<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends ConsumerState<AdminHomePage> {
  int _section = 0;
  Map<String, dynamic>? _home;
  dynamic _extra;
  String? _error;
  bool _loading = true;
  final _search = TextEditingController();
  final _from = TextEditingController();
  final _to = TextEditingController();
  String _statusFilter = 'ALL';

  @override
  void dispose() {
    _search.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiProvider);
      final q = Uri.encodeQueryComponent(_search.text.trim());
      final query = _search.text.trim().isEmpty ? '' : '&q=$q';
      final dates = '${_from.text.trim().isEmpty ? '' : '&from=${Uri.encodeQueryComponent(_from.text.trim())}'}${_to.text.trim().isEmpty ? '' : '&to=${Uri.encodeQueryComponent(_to.text.trim())}'}';
      final dynamic data = switch (_section) {
        0 => await api.adminHome(),
        1 => await api.adminGet('/admin/users?role=CUSTOMER&take=30$query$dates${_statusFilter == 'SUSPENDED' || _statusFilter == 'ACTIVE' ? '&status=$_statusFilter' : ''}'),
        2 => await api.adminGet('/admin/users?role=COURIER&take=30$query$dates${_statusFilter == 'ALL' ? '' : '&status=$_statusFilter'}'),
        3 => await api.adminGet('/admin/orders'),
        4 => await api.adminGet('/admin/earnings?take=30'),
        5 || 7 => await api.adminGet('/admin/finance'),
        6 => await api.adminGet('/admin/tickets?take=30$query$dates'),
        8 => await api.adminGet('/admin/audits?take=40'),
        _ => await api.adminHome(),
      };
      if (!mounted) return;
      setState(() {
        if (_section == 0) {
          _home = Map<String, dynamic>.from(data as Map);
        } else {
          _extra = data;
        }
        _error = null;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<String?> _reason(String title) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: note, decoration: const InputDecoration(labelText: 'السبب')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('تأكيد')),
        ],
      ),
    );
    if (ok != true || note.text.trim().isEmpty) return null;
    return note.text.trim();
  }

  Future<void> _act(Future<dynamic> Function() action) async {
    try {
      await action();
      await _load();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _review(String id, String status) async {
    String? note;
    if (status != 'APPROVED' && status != 'PENDING_REVIEW') {
      note = await _reason(_courierStatus[status] ?? status);
      if (note == null) return;
    }
    await _act(() => ref.read(apiProvider).adminReviewCourier(id, status, note));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.petrol,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            children: [
              Row(
                children: [
                  const Expanded(child: Text('إدارة دليفريه', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.ink))),
                  TextButton(
                    onPressed: () async {
                      await ref.read(sessionProvider.notifier).logout();
                      if (context.mounted) context.go('/welcome');
                    },
                    child: const Text('خروج'),
                  ),
                ],
              ),
              const Text('قيمة الطلبات ليست إيراد المنصة. النقد الذي يحمله المندوب ليس أجره.', style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < _sections.length; i++)
                    ChoiceChip(
                      label: Text(_sections[i]),
                      selected: _section == i,
                      selectedColor: AppColors.petrol,
                      labelStyle: TextStyle(color: _section == i ? Colors.white : AppColors.ink),
                      onSelected: (_) {
                        setState(() {
                          _section = i;
                          if (i == 1 && !['ALL', 'ACTIVE', 'SUSPENDED'].contains(_statusFilter)) _statusFilter = 'ALL';
                        });
                        _load();
                      },
                    ),
                ],
              ),
              if (_loading) const Padding(padding: EdgeInsets.only(top: 24), child: Center(child: CircularProgressIndicator(color: AppColors.petrol))),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: AppColors.danger))),
              if (!_loading) ..._body(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body() {
    if (_section == 0 && _home != null) return _dashboard(_home!);
    if (_section == 1 || _section == 2) return _accounts(_asMaps(_extra), courier: _section == 2);
    if (_section == 3) return _orders(_asMaps(_extra));
    if (_section == 4) return _earnings(_asMaps(_extra));
    if ((_section == 5 || _section == 7) && _extra is Map) return _finance(Map<String, dynamic>.from(_extra as Map));
    if (_section == 6 && _extra is Map) return _tickets(Map<String, dynamic>.from(_extra as Map));
    if (_section == 8) return _audits(_asMaps(_extra));
    return const [SizedBox.shrink()];
  }

  List<Map<String, dynamic>> _asMaps(dynamic value) {
    if (value is! List) return [];
    return value.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Widget _card(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  List<Widget> _dashboard(Map<String, dynamic> home) {
    final today = home['ordersToday'] is Map ? Map<String, dynamic>.from(home['ordersToday'] as Map) : <String, dynamic>{};
    final finance = home['finance'] is Map ? Map<String, dynamic>.from(home['finance'] as Map) : <String, dynamic>{};
    final audits = _asMaps(home['audits']);
    final recent = _asMaps(home['recentOrders']);
    return [
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _metric('العملاء', '${_count(home['customers'])}'),
          _metric('المندوبون', '${_count(home['couriers'])}'),
          _metric('المطاعم', '${_count(home['restaurants'])}'),
          _metric('بانتظار المراجعة', '${_count(home['pendingCouriers'])}'),
          _metric('معتمدون', '${_count(home['approvedCouriers'])}'),
          _metric('موقوفون', '${_count(home['suspendedCouriers'])}'),
          _metric('متاحون الآن', '${_count(home['availableCouriers'])}'),
        ],
      ),
      const SizedBox(height: 16),
      _card([
        const Text('طلبات اليوم', style: TextStyle(fontWeight: FontWeight.w700)),
        Text('جديدة ${_count(today['new'])} · جارية ${_count(today['active'])} · مكتملة ${_count(today['delivered'])} · ملغاة ${_count(today['cancelled'])}'),
        Text('قيمة الطلبات: ${_show(today['orderValueLabel'], money(0))}'),
        Text('رسوم التوصيل: ${_show(today['deliveryFeesLabel'], money(0))}'),
        Text('إيراد المنصة: ${_show(today['platformRevenueLabel'], money(0))}', style: const TextStyle(fontWeight: FontWeight.w700)),
        Text('أجور غير مسوّاة: ${_show(finance['unsettledWagesLabel'], money(0))}'),
        Text('نقد غير مورّد: ${_show(finance['unsettledCashLabel'], money(0))}'),
      ]),
      const SizedBox(height: 16),
      const Text('آخر الطلبات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      if (recent.isEmpty) const Text('لا توجد طلبات اليوم.', style: TextStyle(color: AppColors.muted)),
      for (final row in recent.take(8))
        _card([
          Text(_show(row['publicNumber']), style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('${_orderStatus[row['status']] ?? 'غير متوفر'} · ${_show(row['parcelType'])}'),
          Text(money(_count(row['totalMinor']))),
        ]),
      const SizedBox(height: 16),
      const Text('آخر العمليات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      if (audits.isEmpty) const Text('لا توجد عمليات إدارية مسجّلة بعد.', style: TextStyle(color: AppColors.muted)),
      for (final row in audits) _card([Text(_show(row['action'])), Text(_show(row['reason']))]),
    ];
  }

  Widget _metric(String label, String value) {
    return Container(
      width: 148,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: AppColors.ink)),
      ]),
    );
  }


  Future<void> _detail(String id) async {
    try {
      final data = Map<String, dynamic>.from(await ref.read(apiProvider).adminGet('/admin/couriers/$id') as Map);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          final documents = _asMaps(data['documents']);
          final orders = _asMaps(data['orders']);
          final reviews = _asMaps(data['reviews']);
          final settlements = _asMaps(data['settlements']);
          final audits = _asMaps(data['audits']);
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(_show(data['fullName'], 'بدون اسم'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                Text(_show(data['phone'])),
                Text('${_show(data['governorate'])} · ${_show(data['area'])} · ${_vehicles[data['vehicle']] ?? 'وسيلة غير محددة'}'),
                Text('الحالة: ${_courierStatus[data['status']] ?? 'غير متوفر'}'),
                if (data['reviewNote'] != null) Text('ملاحظة المراجعة: ${_show(data['reviewNote'])}'),
                Text('مكتمل: ${_count(data['completed'])} · أجر التوصيل: ${_show(data['payoutLabel'], money(0))}'),
                const SizedBox(height: 12),
                const Text('المستندات', style: TextStyle(fontWeight: FontWeight.w700)),
                if (documents.isEmpty) const Text('لا توجد مستندات مرفوعة.', style: TextStyle(color: AppColors.muted)),
                for (final doc in documents) Text(_docs[doc['kind']] ?? 'مستند'),
                const SizedBox(height: 12),
                const Text('الطلبات', style: TextStyle(fontWeight: FontWeight.w700)),
                if (orders.isEmpty) const Text('لا توجد طلبات.', style: TextStyle(color: AppColors.muted)),
                for (final order in orders)
                  Text('${_show(order['publicNumber'])} · ${_orderStatus[order['status']] ?? 'غير متوفر'} · توصيل ${_show(order['feeLabel'])}'),
                const SizedBox(height: 12),
                const Text('التقييمات', style: TextStyle(fontWeight: FontWeight.w700)),
                if (reviews.isEmpty) const Text('لا توجد تقييمات.', style: TextStyle(color: AppColors.muted)),
                for (final review in reviews) Text('${_count(review['rating'])} نجوم · ${_show(review['comment'], 'بدون تعليق')}'),
                const SizedBox(height: 12),
                const Text('التسويات', style: TextStyle(fontWeight: FontWeight.w700)),
                if (settlements.isEmpty) const Text('لا توجد تسويات.', style: TextStyle(color: AppColors.muted)),
                for (final row in settlements) Text('${_settlementKind[row['kind']] ?? 'تسوية'} · ${_show(row['amountLabel'])} · ${_show(row['reason'])}'),
                const SizedBox(height: 12),
                const Text('سجل الإدارة', style: TextStyle(fontWeight: FontWeight.w700)),
                if (audits.isEmpty) const Text('لا توجد إجراءات مسجّلة.', style: TextStyle(color: AppColors.muted)),
                for (final row in audits) Text('${_show(row['action'])} · ${_show(row['reason'])}'),
              ],
            ),
          );
        },
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }


  List<Widget> _orders(List<Map<String, dynamic>> rows) {
    return [
      const SizedBox(height: 12),
      for (final row in rows)
        _card([
          Text('${row['publicNumber'] ?? ''} · ${row['parcelType'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('${_orderStatus[row['status']] ?? 'غير متوفر'} · ${_show(row['paymentMethod'])} · ${_show(row['paymentState'])}'),
          Text('قيمة الطلب ${money(row['totalMinor'] as int? ?? 0)} · توصيل ${money(row['feeMinor'] as int? ?? 0)} · عمولة ${money(row['platformMinor'] as int? ?? 0)}'),
          Text('${row['pickupLine'] ?? ''} ← ${row['dropoffLine'] ?? ''}'),
          if (['SEARCHING', 'NO_COURIER', 'ACCEPTED', 'EN_ROUTE_PICKUP'].contains(row['status']))
            TextButton(
              onPressed: () async {
                final reason = await _reason('إلغاء الطلب');
                if (reason == null) return;
                await _act(() => ref.read(apiProvider).adminPost('/admin/orders/${row['id']}/cancel', {'reason': reason}));
              },
              child: const Text('إلغاء'),
            ),
        ]),
    ];
  }

  List<Widget> _finance(Map<String, dynamic> data) {
    final settlements = _asMaps(data['settlements']);
    return [
      const SizedBox(height: 12),
      Text('قيمة الطلبات المكتملة: ${data['orderValueLabel'] ?? ''}'),
      Text('رسوم التوصيل: ${data['deliveryFeesLabel'] ?? ''}'),
      Text('إيراد المنصة: ${data['platformRevenueLabel'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
      Text('أجور المندوبين: ${data['courierWagesLabel'] ?? ''}'),
      Text('نقد حصّله المندوبون: ${data['cashCollectedLabel'] ?? ''}'),
      Text('قيمة الطعام: ${data['goodsLabel'] ?? ''}'),
      Text('عمولة التوصيل الحالية: ${(data['commissionBps'] ?? 0) / 100}% · رسم الخدمة ${money(data['serviceFeeMinor'] as int? ?? 0)}'),
      TextButton(
        onPressed: () async {
          final bps = TextEditingController(text: '${data['commissionBps'] ?? 0}');
          final fee = TextEditingController(text: '${data['serviceFeeMinor'] ?? 0}');
          final reason = TextEditingController();
          final ok = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('تسعير المنصة'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: bps, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'عمولة التوصيل بنقطة أساس (100 = 1%)')),
                  TextField(controller: fee, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'رسم الخدمة بالقرش')),
                  TextField(controller: reason, decoration: const InputDecoration(labelText: 'سبب التعديل')),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
              ],
            ),
          );
          if (ok != true || reason.text.trim().isEmpty) return;
          await _act(() => ref.read(apiProvider).adminPost('/admin/pricing', {
                'deliveryPlatformBps': int.tryParse(bps.text.trim()) ?? 0,
                'serviceFeeMinor': int.tryParse(fee.text.trim()) ?? 0,
                'reason': reason.text.trim(),
              }));
        },
        child: const Text('تعديل العمولة ورسم الخدمة'),
      ),
      const SizedBox(height: 8),
      const Text('آخر التسويات', style: TextStyle(fontWeight: FontWeight.w700)),
      for (final row in settlements) Text('${_show(row['courier'], 'مندوب')} · ${_settlementKind[row['kind']] ?? 'تسوية'} · ${_show(row['amountLabel'])} · ${_show(row['reason'])}'),
    ];
  }


  List<Widget> _accounts(List<Map<String, dynamic>> rows, {required bool courier}) {
    return [
      const SizedBox(height: 12),
      TextField(controller: _search, decoration: const InputDecoration(labelText: 'بحث بالاسم أو الهاتف أو البريد'), onSubmitted: (_) => _load()),
      TextField(controller: _from, decoration: const InputDecoration(labelText: 'من تاريخ 2026-10-01'), onSubmitted: (_) => _load()),
      TextField(controller: _to, decoration: const InputDecoration(labelText: 'إلى تاريخ 2026-10-18'), onSubmitted: (_) => _load()),
      const SizedBox(height: 8),
      Wrap(spacing: 6, children: [
        for (final item in courier ? ['ALL', 'ACTIVE', 'SUSPENDED', 'PENDING_REVIEW', 'NEEDS_INFO', 'APPROVED', 'REJECTED'] : ['ALL', 'ACTIVE', 'SUSPENDED'])
          ChoiceChip(
            label: Text(item == 'ALL' ? 'الكل' : item == 'ACTIVE' ? 'نشط' : item == 'SUSPENDED' ? 'محظور' : _courierStatus[item] ?? item),
            selected: _statusFilter == item,
            onSelected: (_) {
              setState(() => _statusFilter = item);
              _load();
            },
          ),
      ]),
      const SizedBox(height: 8),
      if (rows.isEmpty) const Text('لا توجد حسابات مطابقة.', style: TextStyle(color: AppColors.muted)),
      for (final row in rows)
        _card([
          Text(_show(row['name'], 'بدون اسم'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          Text('${_show(row['phone'])} · ${_show(row['email'])}'),
          Text('${row['role'] == 'COURIER' ? 'مندوب' : 'عميل'} · ${_show(row['accountType'], 'شخصي')}'),
          Text('التسجيل: ${_show(row['createdAt'])}'),
          Text('الحالة: ${row['suspendedAt'] != null ? 'محظور' : _courierStatus[row['status']] ?? 'نشط'}'),
          Text('الطلبات: ${_count(row['orders'])}'),
          if (courier) Text('التقييم: ${_show(row['rating'], 'بدون تقييم')} · ${_count(row['ratingCount'])} تقييم'),
          if (courier) Text('أرباح التوصيل: ${_show(row['payoutLabel'], money(0))}'),
          if (row['banHistory'] is List && (row['banHistory'] as List).isNotEmpty)
            Text('سجل الحظر: ${(row['banHistory'] as List).length} عملية'),
          if (courier && row['commissionBps'] != null) Text('نسبة خاصة: ${(row['commissionBps'] as num) / 100}%'),
          Wrap(spacing: 4, children: [
            TextButton(
              onPressed: () async {
                final reason = await _reason(row['suspendedAt'] == null ? 'حظر الحساب' : 'فك الحظر');
                if (reason == null) return;
                final result = await ref.read(apiProvider).adminPost('/admin/users/${row['id']}/suspension', {'suspended': row['suspendedAt'] == null, 'reason': reason});
                final warning = result is Map ? result['warning'] : null;
                if (warning != null && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(warning.toString())));
                }
                await _load();
              },
              child: Text(row['suspendedAt'] == null ? 'حظر الحساب' : 'فك الحظر'),
            ),
            if (courier && row['profileId'] != null) ...[
              TextButton(onPressed: () => _detail(row['profileId'] as String), child: const Text('الملف')),
              TextButton(onPressed: () => _commission(row['profileId'] as String), child: const Text('نسبة خاصة')),
              TextButton(onPressed: () => _review(row['profileId'] as String, 'APPROVED'), child: const Text('قبول')),
              TextButton(onPressed: () => _review(row['profileId'] as String, 'NEEDS_INFO'), child: const Text('استكمال')),
              TextButton(onPressed: () => _review(row['profileId'] as String, 'REJECTED'), child: const Text('رفض')),
            ],
          ]),
        ]),
    ];
  }

  Future<void> _commission(String profileId) async {
    final bps = TextEditingController();
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('نسبة خاصة بالمندوب'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('اترك النسبة فارغة للعودة إلى النسبة العامة. 1000 نقطة أساس = 10% من أجرة التوصيل فقط.'),
          TextField(controller: bps, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'نقطة الأساس')),
          TextField(controller: reason, decoration: const InputDecoration(labelText: 'سبب التعديل')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true || reason.text.trim().length < 8) return;
    final parsed = int.tryParse(bps.text.trim());
    await _act(() => ref.read(apiProvider).adminPost('/admin/couriers/$profileId/commission', {'bps': bps.text.trim().isEmpty ? null : parsed, 'reason': reason.text.trim()}));
  }

  List<Widget> _earnings(List<Map<String, dynamic>> rows) {
    final csv = [
      'الاسم,الهاتف,المكتمل,أجرة التوصيل,حصة الشركة,صافي المندوب,غير المدفوع,المصروف',
      for (final row in rows) '${row['name'] ?? ''},${row['phone'] ?? ''},${row['completed'] ?? 0},${row['feeLabel'] ?? ''},${row['platformLabel'] ?? ''},${row['payoutLabel'] ?? ''},${row['unsettledLabel'] ?? ''},${row['paidLabel'] ?? ''}',
    ].join('\n');
    return [
      const SizedBox(height: 12),
      TextButton(onPressed: () async { await Clipboard.setData(ClipboardData(text: csv)); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ تقرير CSV.'))); }, child: const Text('نسخ CSV')),
      for (final row in rows)
        _card([
          Text(_show(row['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(_show(row['phone'])),
          Text('مكتمل ${_count(row['completed'])} · أجرة ${_show(row['feeLabel'])}'),
          Text('حصة الشركة ${_show(row['platformLabel'])} · صافي ${_show(row['payoutLabel'])}'),
          Text('غير مدفوع ${_show(row['unsettledLabel'])} · مصروف ${_show(row['paidLabel'])}'),
          Text('آخر نشاط ${_show(row['lastActivity'])}'),
          TextButton(onPressed: () => _earningDetail(row['id'] as String), child: const Text('التفاصيل')),
        ]),
    ];
  }

  Future<void> _earningDetail(String id) async {
    try {
      final data = Map<String, dynamic>.from(await ref.read(apiProvider).adminGet('/admin/earnings/$id') as Map);
      if (!mounted) return;
      final orders = _asMaps(data['orders']);
      final settlements = _asMaps(data['settlements']);
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(_show(data['name']), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              Text('اليوم ${_show(data['todayLabel'])} · الأسبوع ${_show(data['weekLabel'])}'),
              Text('الشهر ${_show(data['monthLabel'])} · الإجمالي ${_show(data['totalLabel'])}'),
              Text('المستحق ${_show(data['unsettledLabel'])} · المصروف ${_show(data['paidLabel'])}'),
              Text(data['commissionBps'] == null ? 'يستخدم النسبة العامة' : 'نسبة خاصة ${(data['commissionBps'] as num) / 100}%'),
              const SizedBox(height: 12),
              const Text('طلبات محتسبة', style: TextStyle(fontWeight: FontWeight.w700)),
              for (final order in orders) Text('${_show(order['publicNumber'])} · أجرة ${_show(order['feeLabel'])} · شركة ${_show(order['platformLabel'])} · صافي ${_show(order['payoutLabel'])}'),
              const SizedBox(height: 12),
              const Text('التسويات والمدفوعات', style: TextStyle(fontWeight: FontWeight.w700)),
              if (settlements.isEmpty) const Text('لا توجد تسويات. هذا لا يعني أن المستحق صفر.'),
              for (final row in settlements) Text('${_settlementKind[row['kind']] ?? 'تسوية'} · ${_show(row['amountLabel'])} · ${_show(row['reason'])}'),
            ],
          ),
        ),
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  List<Widget> _audits(List<Map<String, dynamic>> rows) {
    return [
      const SizedBox(height: 12),
      if (rows.isEmpty) const Text('لا توجد عمليات.', style: TextStyle(color: AppColors.muted)),
      for (final row in rows)
        _card([
          Text(_show(row['action']), style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('${_show(row['actorName'])} · ${_show(row['createdAt'])}'),
          Text(_show(row['reason'])),
        ]),
    ];
  }

  List<Widget> _tickets(Map<String, dynamic> data) {
    final rows = _asMaps(data['items']);
    return [
      const SizedBox(height: 12),
      Text('بلاغات غير مقروءة: ${_count(data['unread'])}', style: const TextStyle(fontWeight: FontWeight.w700)),
      TextField(controller: _search, decoration: const InputDecoration(labelText: 'بحث برقم البلاغ أو الاسم أو الهاتف'), onSubmitted: (_) => _load()),
      TextField(controller: _from, decoration: const InputDecoration(labelText: 'من تاريخ 2026-10-01'), onSubmitted: (_) => _load()),
      TextField(controller: _to, decoration: const InputDecoration(labelText: 'إلى تاريخ 2026-10-18'), onSubmitted: (_) => _load()),
      for (final row in rows)
        _card([
          Text('${_show(row['publicNumber'])} · ${_show(row['subject'])}', style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('${_show(row['name'])} · ${_show(row['phone'])} · ${_show(row['email'])}'),
          Text('${row['role'] == 'COURIER' ? 'مندوب' : 'عميل'} · طلب ${_show(row['orderNumber'], 'بدون طلب')}'),
          Text('${_ticketStatus[row['status']] ?? 'غير متوفر'} · ${_show(row['kind'])} · ${_show(row['createdAt'])}'),
          Text(row['message'] as String? ?? ''),
          Wrap(spacing: 4, children: [
            for (final status in _ticketStatus.keys)
              TextButton(
                onPressed: () async {
                  final note = await _reason(_ticketStatus[status] ?? status);
                  if (note == null) return;
                  await _act(() => ref.read(apiProvider).adminPost('/admin/tickets/${row['id']}', {'status': status, 'note': note, 'internal': false}));
                },
                child: Text(_ticketStatus[status]!),
              ),
            TextButton(
              onPressed: () async {
                final note = await _reason('ملاحظة داخلية');
                if (note == null) return;
                await _act(() => ref.read(apiProvider).adminPost('/admin/tickets/${row['id']}', {'status': row['status'], 'note': note, 'internal': true}));
              },
              child: const Text('ملاحظة داخلية'),
            ),
          ]),
        ]),
    ];
  }
}
