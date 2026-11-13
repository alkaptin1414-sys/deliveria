import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ui.dart';

class BusinessSetupPage extends ConsumerStatefulWidget {
  const BusinessSetupPage({super.key});

  @override
  ConsumerState<BusinessSetupPage> createState() => _BusinessSetupPageState();
}

class _BusinessSetupPageState extends ConsumerState<BusinessSetupPage> {
  final _name = TextEditingController();
  final _manager = TextEditingController();
  final _phone = TextEditingController();
  final _line = TextEditingController();
  final _details = TextEditingController();
  List<dynamic> _categories = [];
  String _category = 'PHARMACY';
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(apiProvider).categories().then((value) {
      if (mounted) setState(() => _categories = value);
    });
  }

  Future<void> _save() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).createBusiness({
        'name': _name.text.trim(),
        'category': _category,
        'managerName': _manager.text.trim(),
        'phone': _phone.text.trim(),
        'addressLine': _line.text.trim(),
        'details': _details.text.trim(),
        'lat': 0,
        'lng': 0,
      });
      if (mounted) context.go('/home');
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('بيانات النشاط')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const Text('عنوان المحل هيتحفظ كمكان الاستلام الافتراضي.', style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 16),
          AppField(label: 'اسم النشاط', controller: _name),
          const SizedBox(height: 10),
          AppField(label: 'اسم المسؤول', controller: _manager),
          const SizedBox(height: 10),
          AppField(label: 'هاتف النشاط', controller: _phone, keyboardType: TextInputType.phone),
          const SizedBox(height: 10),
          AppField(label: 'العنوان', controller: _line),
          const SizedBox(height: 10),
          AppField(label: 'تفاصيل', controller: _details, hint: 'الدور أو علامة مميزة'),
          const SizedBox(height: 16),
          const SectionLabel('نوع النشاط'),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _categories.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisExtent: 72, crossAxisSpacing: 8, mainAxisSpacing: 8),
            itemBuilder: (context, index) {
              final item = _categories[index] as Map;
              final selected = _category == item['code'];
              return Pressable(
                onTap: () => setState(() => _category = item['code'] as String),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: selected ? AppColors.petrol : AppColors.line, width: selected ? 1.4 : 1),
                  ),
                  child: Text(item['label'] as String, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              );
            },
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: AppColors.danger))),
          const SizedBox(height: 16),
          AppButton(label: 'حفظ وبدء الاستخدام', loading: _loading, onPressed: _loading ? null : _save),
        ],
      ),
    );
  }
}
