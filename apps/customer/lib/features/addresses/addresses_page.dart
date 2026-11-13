import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ui.dart';
import '../session/session_controller.dart';

class AddressesPage extends ConsumerStatefulWidget {
  const AddressesPage({super.key});

  @override
  ConsumerState<AddressesPage> createState() => _AddressesPageState();
}

class _AddressesPageState extends ConsumerState<AddressesPage> {
  List<SavedAddress> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (ref.read(sessionProvider).user == null) {
      if (!mounted) return;
      setState(() {
        _items = [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final items = await ref.read(apiProvider).addresses();
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
          _error = null;
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

  Future<void> _open([SavedAddress? address]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddressFormPage(existing: address)),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('العناوين'), actions: [
        IconButton(onPressed: () => _open(), icon: const Icon(Icons.add)),
      ]),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(20), child: SkeletonBox(height: 72))
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _items.isEmpty
                  ? EmptyView(title: 'لا توجد عناوين', body: 'احفظ المنزل أو العمل لتسريع الطلب.', action: 'إضافة عنوان', onAction: () => _open())
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return SurfaceGroup(children: [
                          NavRow(
                            icon: Icons.place_outlined,
                            title: item.name,
                            subtitle: '${item.line}${item.isDefault ? ' · افتراضي' : ''}',
                            onTap: () => _open(item),
                            showDivider: false,
                          ),
                        ]);
                      },
                    ),
    );
  }
}

class AddressFormPage extends ConsumerStatefulWidget {
  const AddressFormPage({super.key, this.existing});
  final SavedAddress? existing;

  @override
  ConsumerState<AddressFormPage> createState() => _AddressFormPageState();
}

class _AddressFormPageState extends ConsumerState<AddressFormPage> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _gov = TextEditingController(text: widget.existing?.governorate ?? '');
  late final _city = TextEditingController(text: widget.existing?.city ?? '');
  late final _area = TextEditingController(text: widget.existing?.area ?? '');
  late final _line = TextEditingController(text: widget.existing?.line ?? '');
  late final _details = TextEditingController(text: widget.existing?.details ?? '');
  late String _label = widget.existing?.label ?? 'HOME';
  bool _loading = false;
  String? _error;

  Future<void> _save() async {
    if (_name.text.trim().length < 2 || _line.text.trim().length < 3) {
      setState(() => _error = 'اكتب الاسم والعنوان.');
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(apiProvider).saveAddress({
        'label': _label,
        'name': _name.text.trim(),
        'governorate': _gov.text.trim().isEmpty ? 'غير محدد' : _gov.text.trim(),
        'city': _city.text.trim().isEmpty ? 'غير محدد' : _city.text.trim(),
        'area': _area.text.trim().isEmpty ? 'غير محدد' : _area.text.trim(),
        'line': _line.text.trim(),
        'details': _details.text.trim(),
        'lat': 0,
        'lng': 0,
        'isDefault': widget.existing?.isDefault ?? false,
      }, id: widget.existing?.id);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete() async {
    await ref.read(apiProvider).deleteAddress(widget.existing!.id);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'عنوان جديد' : 'تعديل العنوان')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final item in const [('HOME', 'المنزل'), ('WORK', 'العمل'), ('SHOP', 'المحل'), ('OTHER', 'أخرى')])
                ChoiceChip(label: Text(item.$2), selected: _label == item.$1, onSelected: (_) => setState(() => _label = item.$1)),
            ],
          ),
          const SizedBox(height: 12),
          AppField(label: 'اسم العنوان', controller: _name),
          const SizedBox(height: 10),
          AppField(label: 'المحافظة', controller: _gov),
          const SizedBox(height: 10),
          AppField(label: 'المدينة', controller: _city),
          const SizedBox(height: 10),
          AppField(label: 'المنطقة', controller: _area),
          const SizedBox(height: 10),
          AppField(label: 'العنوان', controller: _line),
          const SizedBox(height: 10),
          AppField(label: 'وصف إضافي', controller: _details),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: AppColors.danger))),
          const SizedBox(height: 16),
          AppButton(label: 'حفظ', loading: _loading, onPressed: _save),
          if (widget.existing != null) TextButton(onPressed: _delete, child: const Text('حذف العنوان', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
  }
}
