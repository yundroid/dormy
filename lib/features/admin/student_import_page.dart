import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/session.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../share/xlsx.dart';
import 'student_import.dart';

const _xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Boş öğrenci şablonu (+ açıklama sayfası ve mevcut grup adları) üretip paylaşır.
Future<void> shareStudentTemplate(BuildContext context, List<Group> groups) async {
  final active = groups.where((g) => !g.isArchived).toList()..sort((a, b) => a.name.compareTo(b.name));
  String names(GroupKind k) {
    final list = active.where((g) => g.kind == k).map((g) => g.name).toList();
    return list.isEmpty ? '(henüz tanımlı değil)' : list.join(', ');
  }

  final bytes = buildWorkbook([
    XlsxSheet(
      name: 'Öğrenciler',
      header: [for (final f in ImportField.values) f.header],
      rows: const [],
      numericFrom: ImportField.values.length,
    ),
    XlsxSheet(
      name: 'Açıklama',
      header: const ['Sütun', 'Açıklama'],
      numericFrom: 2,
      rows: [
        ['Ad *', 'Zorunlu. Birden fazla adı varsa hepsini yazın (örn. Ahmet Can).'],
        ['Soyad *', 'Zorunlu.'],
        ['Okul Sınıfı', 'İsteğe bağlı, örn. 10-A'],
        ['Oda No', 'İsteğe bağlı, örn. 204'],
        ['Öğrenci Telefonu', 'İsteğe bağlı. Başındaki 0 kaybolmasın diye hücreyi metin biçiminde yazın.'],
        ['Veli Adı Soyadı', 'İsteğe bağlı'],
        ['Veli Telefonu', 'İsteğe bağlı'],
        ['Etüt Grubu', 'İsteğe bağlı. Mevcut gruplar: ${names(GroupKind.study)}'],
        ['Dahili Ders Grubu', 'İsteğe bağlı. Mevcut gruplar: ${names(GroupKind.internal)}'],
        ['Notlar', 'İsteğe bağlı'],
        ['', ''],
        ['Kurallar', 'Öğrenciler sayfasında ilk satır başlıktır, öğrenciler 2. satırdan itibaren yazılır.'],
        ['', 'Grup adları büyük/küçük harf ve Türkçe karakter farkı gözetilmeden eşleştirilir (Etut-1 = Etüt-1).'],
        ['', 'Sistemde olmayan grup adları yükleme öncesi listelenir; oluşturulup oluşturulmayacağını siz seçersiniz.'],
        ['', 'Aynı ad soyadla zaten kayıtlı öğrenciler varsayılan olarak atlanır.'],
        ['', 'Tek sütunda "Ad Soyad" yazan listeler de kabul edilir (son kelime soyad sayılır).'],
      ],
    ),
  ]);
  try {
    const name = 'dormy_ogrenci_sablonu.xlsx';
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: _xlsxMime, name: name)],
      fileNameOverrides: const [name],
      title: 'Öğrenci yükleme şablonu',
    ));
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// Excel dosyası seçtirir, okur ve önizleme ekranını açar.
Future<void> pickStudentExcel(BuildContext context, WidgetRef ref) async {
  try {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['xlsx']);
    if (files.isEmpty) return;
    final bytes = await files.first.readAsBytes();
    final students = await ref.read(studentsProvider.future);
    final groups = await ref.read(groupsProvider.future);
    final plan = buildImportPlan(readXlsxRows(bytes), existingStudents: students, groups: groups);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StudentImportPage(plan: plan, fileName: files.first.name),
    ));
  } on FormatException catch (e) {
    if (context.mounted) showMessage(context, e.message, error: true);
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

class StudentImportPage extends ConsumerStatefulWidget {
  const StudentImportPage({super.key, required this.plan, required this.fileName});

  final ImportPlan plan;
  final String fileName;

  @override
  ConsumerState<StudentImportPage> createState() => _StudentImportPageState();
}

class _StudentImportPageState extends ConsumerState<StudentImportPage> {
  bool _createGroups = true;
  bool _includeSkipped = false;
  bool _busy = false;

  ImportPlan get plan => widget.plan;

  int get _count => plan.rows.where((r) => r.isValid && (!r.skip || _includeSkipped)).length;

  /// Kota aşımı varsa açıklaması
  String? _quotaProblem(int activeCount) {
    final max = session.ctx.tenant?.maxStudents;
    if (max == null) return null;
    final left = max - activeCount;
    if (_count <= left) return null;
    return 'Öğrenci kotanız $max. Şu an $activeCount aktif öğrenci var; en fazla ${left < 0 ? 0 : left} öğrenci '
        'eklenebilir ama dosyada $_count öğrenci var. Fazla satırları silin veya kota artırımı isteyin.';
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final n = await Repo.importStudents(plan, createGroups: _createGroups, includeSkipped: _includeSkipped);
      ref.invalidate(studentsProvider);
      ref.invalidate(groupsProvider);
      ref.invalidate(membershipsProvider);
      if (!mounted) return;
      showMessage(context, '$n öğrenci eklendi');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final students = ref.watch(studentsProvider).value ?? const <Student>[];
    final activeCount = students.where((s) => s.status == StudentStatus.active).length;
    final quota = _quotaProblem(activeCount);
    final ungrouped = _createGroups ? 0 : plan.newGroups.fold<int>(0, (a, g) => a + g.studentCount);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Excel\'den Yükle')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _busy || _count == 0 || quota != null ? null : _import,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload),
            label: Text('$_count öğrenciyi ekle'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.fileName, style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Pill(icon: Icons.check_circle_outline, color: Colors.green, text: '${plan.toImport.length} eklenecek'),
                    if (plan.skipped.isNotEmpty)
                      _Pill(icon: Icons.skip_next_outlined, color: Colors.orange, text: '${plan.skipped.length} atlanacak'),
                    if (plan.invalid.isNotEmpty)
                      _Pill(icon: Icons.error_outline, color: theme.colorScheme.error, text: '${plan.invalid.length} hatalı'),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Tanınan sütunlar: ${ImportField.values.where(plan.columns.contains).map((f) => f.label).join(', ')}',
                  style: theme.textTheme.bodySmall,
                ),
                if (quota != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: theme.colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(quota, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                    ),
                  ),
                ],
                if (plan.newGroups.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Sistemde olmayan gruplar', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Card(
                    child: Column(
                      children: [
                        for (final g in plan.newGroups)
                          ListTile(
                            dense: true,
                            leading: Icon(_createGroups ? Icons.add_circle_outline : Icons.block, size: 20),
                            title: Text(g.name),
                            subtitle: Text('${g.kind.label} · ${g.studentCount} öğrenci'),
                          ),
                        const Divider(height: 1),
                        SwitchListTile(
                          value: _createGroups,
                          onChanged: (v) => setState(() => _createGroups = v),
                          title: const Text('Bu grupları oluştur'),
                          subtitle: Text(_createGroups
                              ? 'Gruplar oluşturulur ve öğrenciler bu gruplara atanır. Öğretmen atamasını sonra yaparsınız.'
                              : '$ungrouped öğrenci grupsuz eklenir; sonra elle atayabilirsiniz.'),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'Yazım hatası varsa (örn. mevcut bir grubu farklı yazdıysanız) Excel\'i düzeltip tekrar yükleyin.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (plan.skipped.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Atlanacaklar', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Card(
                    child: Column(
                      children: [
                        for (final r in plan.skipped)
                          ListTile(
                            dense: true,
                            title: Text('${r.rowNumber}. satır · ${r.fullName}'),
                            subtitle: Text(r.warnings.join(' · ')),
                          ),
                        const Divider(height: 1),
                        CheckboxListTile(
                          value: _includeSkipped,
                          onChanged: (v) => setState(() => _includeSkipped = v ?? false),
                          title: const Text('Bunları da ekle'),
                          subtitle: const Text('Aynı isimli farklı öğrenciler varsa işaretleyin'),
                        ),
                      ],
                    ),
                  ),
                ],
                if (plan.invalid.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Hatalı satırlar (eklenmeyecek)', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Card(
                    child: Column(
                      children: [
                        for (final r in plan.invalid)
                          ListTile(
                            dense: true,
                            leading: Icon(Icons.error_outline, color: theme.colorScheme.error, size: 20),
                            title: Text('${r.rowNumber}. satır${r.fullName.isEmpty ? '' : ' · ${r.fullName}'}'),
                            subtitle: Text(r.errors.join(' · ')),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text('Eklenecek öğrenciler', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                if (plan.toImport.isEmpty)
                  const Card(child: ListTile(title: Text('Eklenecek öğrenci yok')))
                else
                  Card(
                    child: Column(
                      children: [
                        for (final r in plan.toImport)
                          ListTile(
                            dense: true,
                            title: Text(r.fullName),
                            subtitle: Text([
                              if (r.value(ImportField.roomNo) != null) 'Oda ${r.value(ImportField.roomNo)}',
                              if (r.value(ImportField.schoolGrade) != null) r.value(ImportField.schoolGrade)!,
                              if (plan.groupNameOf(r, GroupKind.study) != null) 'Etüt: ${plan.groupNameOf(r, GroupKind.study)}',
                              if (plan.groupNameOf(r, GroupKind.internal) != null)
                                'Dahili: ${plan.groupNameOf(r, GroupKind.internal)}',
                            ].join(' · ')),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
