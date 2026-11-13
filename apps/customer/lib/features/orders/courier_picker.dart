import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';

Future<Map<String, dynamic>?> pickCourier(BuildContext context, ApiClient api) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _CourierSheet(api: api),
  );
}

class _CourierSheet extends StatefulWidget {
  const _CourierSheet({required this.api});
  final ApiClient api;

  @override
  State<_CourierSheet> createState() => _CourierSheetState();
}

class _CourierSheetState extends State<_CourierSheet> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.api.selectableCouriers();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() { _error = error.message; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.7;
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(4)))),
            const SizedBox(height: 14),
            const Text('اختيار مندوب', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('يظهر المندوبون المسجّلون. من يوصل طلبًا الآن يختفي حتى يسلّمه.', style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(color: AppColors.petrol),
            if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.danger)),
            if (!_loading && _rows.isEmpty) const Text('لا يوجد مندوب متاح الآن.'),
            Expanded(
              child: ListView(
                children: [
                  for (final row in _rows)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(row['name'] as String? ?? 'مندوب'),
                      subtitle: Text('${row['area'] ?? ''} · ${_vehicle(row['vehicle'] as String? ?? '')}'),
                      enabled: row['selectable'] == true,
                      onTap: row['selectable'] == true ? () => Navigator.pop(context, row) : null,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _vehicle(String code) {
  if (code == 'CAR') return 'سيارة';
  if (code == 'BICYCLE') return 'دراجة — لا يستقبل طلبات الآن';
  if (code == 'OTHER') return 'وسيلة أخرى — لا تستقبل طلبات الآن';
  return 'موتوسيكل';
}
