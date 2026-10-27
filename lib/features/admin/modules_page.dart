import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/icons.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class ModulesPage extends ConsumerWidget {
  const ModulesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modulesAsync = ref.watch(modulesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Kontrol Modülleri')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/admin/modules/new'),
        icon: const Icon(Icons.add),
        label: const Text('Yeni modül'),
      ),
      body: AsyncView(
        value: modulesAsync,
        onRetry: () => ref.invalidate(modulesProvider),
        builder: (modules) {
          final system = modules.where((m) => m.isSystem).toList();
          final custom = modules.where((m) => !m.isSystem).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              ContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Varsayılan modüller', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Card(child: Column(children: [for (final m in system) _ModuleTile(module: m)])),
                    const SizedBox(height: 20),
                    Text('Yurdunuza özel modüller', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('Örn. defter kontrolü, temizlik kontrolü. Sadece sizin yurdunuzda görünür.',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    if (custom.isEmpty)
                      const Card(child: ListTile(title: Text('Henüz özel modül eklenmemiş')))
                    else
                      Card(child: Column(children: [for (final m in custom) _ModuleTile(module: m)])),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ModuleTile extends ConsumerWidget {
  const _ModuleTile({required this.module});

  final DormModule module;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: Icon(moduleIcon(module.icon)),
      title: Text(module.name),
      subtitle: Text('${module.scope.label}\n${module.scaleLabel}'
          '${module.sessions.length > 1 ? ' · ${module.sessions.join(', ')}' : ''}'),
      isThreeLine: true,
      onTap: () => context.push('/admin/modules/${module.id}'),
      trailing: Switch(
        value: module.isActive,
        onChanged: (v) async {
          await runAction(context, () => Repo.setModuleActive(module.id, v),
              success: v ? '${module.name} açıldı' : '${module.name} kapatıldı');
          ref.invalidate(modulesProvider);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class ModuleFormPage extends ConsumerStatefulWidget {
  const ModuleFormPage({super.key, this.moduleId});

  final String? moduleId;

  @override
  ConsumerState<ModuleFormPage> createState() => _ModuleFormPageState();
}

class _ModuleFormPageState extends ConsumerState<ModuleFormPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _min = TextEditingController(text: '1');
  final _max = TextEditingController(text: '5');
  final _weight = TextEditingController(text: '1');
  String _icon = 'checklist';
  ModuleScope _scope = ModuleScope.general;
  ModuleValueType _type = ModuleValueType.score;
  List<TextEditingController> _sessions = [TextEditingController(text: 'Günlük')];
  bool _reports = true;
  DormModule? _module;
  bool _loaded = false;

  bool get _isNew => widget.moduleId == null;

  /// Yapı alanları (kapsam, tip, ölçek) sadece yeni özel modülde düzenlenebilir.
  bool get _structureEditable => _isNew;

  void _load(List<DormModule> modules) {
    if (_loaded || _isNew) return;
    _loaded = true;
    final m = modules.where((m) => m.id == widget.moduleId).firstOrNull;
    if (m == null) return;
    _module = m;
    _name.text = m.name;
    _desc.text = m.description ?? '';
    _min.text = '${m.minValue ?? 1}';
    _max.text = '${m.maxValue ?? 5}';
    _weight.text = m.weight.toString().replaceAll(RegExp(r'\.0$'), '');
    _icon = m.icon;
    _scope = m.scope;
    _type = m.valueType;
    _sessions = [for (final s in m.sessions) TextEditingController(text: s)];
    _reports = m.includeInReports;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final sessions = [for (final c in _sessions) c.text.trim()].where((s) => s.isNotEmpty).toList();
    final ok = await runAction(
      context,
      () => Repo.saveModule(
        id: widget.moduleId,
        name: _name.text,
        description: _desc.text,
        icon: _icon,
        scope: _scope,
        valueType: _type,
        minValue: int.tryParse(_min.text),
        maxValue: int.tryParse(_max.text),
        sessions: sessions.isEmpty ? ['Günlük'] : sessions,
        includeInReports: _reports,
        weight: double.tryParse(_weight.text.replaceAll(',', '.')) ?? 1,
      ),
      success: _isNew ? 'Modül oluşturuldu' : 'Modül güncellendi',
    );
    ref.invalidate(modulesProvider);
    if (ok && mounted) context.pop();
  }

  Future<void> _delete() async {
    final yes = await confirm(
      context,
      title: 'Modülü sil',
      message: '"${_module!.name}" modülü ve bu modüle girilmiş TÜM veriler silinecek. '
          'Verileri korumak için modülü kapatmanız önerilir.',
      confirmLabel: 'Kalıcı olarak sil',
      destructive: true,
    );
    if (!yes || !mounted) return;
    final ok = await runAction(context, () => Repo.deleteModule(_module!.id), success: 'Modül silindi');
    ref.invalidate(modulesProvider);
    if (ok && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final modules = ref.watch(modulesProvider);
    if (!modules.hasValue) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    _load(modules.value!);
    if (!_isNew && _module == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.search_off, title: 'Modül bulunamadı'));
    }
    final isSystem = _module?.isSystem ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Yeni Modül' : _module!.name),
        actions: [
          if (!_isNew && !isSystem) IconButton(tooltip: 'Sil', onPressed: _delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ContentWidth(
          maxWidth: 640,
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(controller: _name, validator: requiredValidator, decoration: const InputDecoration(labelText: 'Modül adı', hintText: 'örn. Defter Kontrolü')),
                const SizedBox(height: 12),
                TextFormField(controller: _desc, decoration: const InputDecoration(labelText: 'Açıklama')),
                const SizedBox(height: 16),
                Text('İkon', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final e in moduleIcons.entries)
                      ChoiceChip(
                        label: Icon(e.value, size: 20),
                        selected: _icon == e.key,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _icon = e.key),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Kim doldurur?', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                RadioGroup<ModuleScope>(
                  groupValue: _scope,
                  onChanged: (v) {
                    if (_structureEditable && v != null) setState(() => _scope = v);
                  },
                  child: Column(
                    children: [
                      for (final s in ModuleScope.values)
                        RadioListTile<ModuleScope>(
                          value: s,
                          enabled: _structureEditable,
                          contentPadding: EdgeInsets.zero,
                          title: Text(s.label),
                          subtitle: Text(switch (s) {
                            ModuleScope.general => 'Tüm öğretmenler tüm öğrenciler için doldurabilir (yoklama, yatak-dolap gibi)',
                            ModuleScope.studyGroup => 'Sadece etüt öğretmeni kendi etüt grubu için doldurur (etüt puanlama gibi)',
                            ModuleScope.internalGroup => 'Sadece dahili ders öğretmeni kendi grubu için doldurur',
                          }),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text('Değerlendirme', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                DropdownButtonFormField<ModuleValueType>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Değerlendirme tipi'),
                  items: [for (final t in ModuleValueType.values) DropdownMenuItem(value: t, child: Text(t.label))],
                  onChanged: _structureEditable ? (v) => setState(() => _type = v!) : null,
                ),
                if (_type == ModuleValueType.score) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _min,
                          enabled: _structureEditable,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          validator: (v) => int.tryParse(v ?? '') == null ? 'Sayı girin' : null,
                          decoration: const InputDecoration(labelText: 'En düşük puan'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _max,
                          enabled: _structureEditable,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          validator: (v) {
                            final max = int.tryParse(v ?? '');
                            final min = int.tryParse(_min.text);
                            if (max == null) return 'Sayı girin';
                            if (min != null && max <= min) return 'En düşükten büyük olmalı';
                            if (max > 1000) return 'En fazla 1000';
                            return null;
                          },
                          decoration: const InputDecoration(labelText: 'En yüksek puan'),
                        ),
                      ),
                    ],
                  ),
                ],
                if (!_structureEditable)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      isSystem
                          ? 'Varsayılan modüllerin kapsamı ve ölçeği değiştirilemez.'
                          : 'Raporların tutarlı kalması için modül oluşturulduktan sonra kapsam ve ölçek değiştirilemez.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text('Günlük oturumlar', style: Theme.of(context).textTheme.titleSmall),
                    const Spacer(),
                    if (_sessions.length < 10)
                      TextButton.icon(
                        onPressed: () => setState(() => _sessions.add(TextEditingController())),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Oturum ekle'),
                      ),
                  ],
                ),
                Text('Gün içinde birden fazla kez doldurulacaksa (örn. yoklamada 5 vakit) oturum ekleyin.',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                for (var i = 0; i < _sessions.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _sessions[i],
                            validator: requiredValidator,
                            decoration: InputDecoration(labelText: '${i + 1}. oturum', isDense: true),
                          ),
                        ),
                        // Mevcut oturumlar silinemez (girilmiş veriler kaybolmasın), sadece yeni eklenenler.
                        if (_sessions.length > 1 && i >= (_module?.sessions.length ?? 1))
                          IconButton(
                            onPressed: () => setState(() => _sessions.removeAt(i)),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _reports,
                  onChanged: (v) => setState(() => _reports = v),
                  title: const Text('Raporlara dahil et'),
                  subtitle: const Text('Öğrenci başarı yüzdesi ve sıralamalarda kullanılır'),
                ),
                if (_reports)
                  TextFormField(
                    controller: _weight,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      final w = double.tryParse((v ?? '').replaceAll(',', '.'));
                      return w == null || w < 0 ? 'Geçerli bir ağırlık girin' : null;
                    },
                    decoration: const InputDecoration(labelText: 'Genel puandaki ağırlığı', helperText: 'Varsayılan 1. Daha önemli modüller için 2, 3...'),
                  ),
                const SizedBox(height: 24),
                BusyButton(onPressed: _save, label: 'Kaydet', icon: Icons.save),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
