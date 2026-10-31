import '../../models/models.dart';

/// Excel'den toplu öğrenci yükleme: sütun eşleme, doğrulama ve grup eşleştirme.
/// Saf mantık; veritabanına yazmaz (bkz. Repo.importStudents).

enum ImportField {
  firstName('Ad', true),
  lastName('Soyad', true),
  schoolGrade('Okul Sınıfı', false),
  roomNo('Oda No', false),
  phone('Öğrenci Telefonu', false),
  guardianName('Veli Adı Soyadı', false),
  guardianPhone('Veli Telefonu', false),
  studyGroup('Etüt Grubu', false),
  internalGroup('Dahili Ders Grubu', false),
  notes('Notlar', false);

  const ImportField(this.label, this.required);
  final String label;
  final bool required;

  /// Şablondaki başlık ("Ad *")
  String get header => required ? '$label *' : label;
}

/// Başlık eşleştirmede kabul edilen diğer yazımlar (normalize edilmiş)
const _aliases = <ImportField, List<String>>{
  ImportField.firstName: ['ad', 'adi', 'isim', 'ogrenciadi'],
  ImportField.lastName: ['soyad', 'soyadi', 'ogrencisoyadi'],
  ImportField.schoolGrade: ['okulsinifi', 'sinif', 'sinifi', 'okul'],
  ImportField.roomNo: ['odano', 'oda', 'odanumarasi'],
  ImportField.phone: ['ogrencitelefonu', 'telefon', 'tel', 'ogrencitel', 'cep'],
  ImportField.guardianName: ['veliadisoyadi', 'veliadi', 'veli', 'veliadsoyad'],
  ImportField.guardianPhone: ['velitelefonu', 'velitel', 'velicep'],
  ImportField.studyGroup: ['etutgrubu', 'etut', 'etutsinifi'],
  ImportField.internalGroup: ['dahilidersgrubu', 'dahili', 'dahiligrup', 'dahiliders'],
  ImportField.notes: ['notlar', 'not', 'aciklama'],
};

/// Tek sütunda "Ad Soyad" yazan listeler için
const _fullNameAliases = ['adsoyad', 'adisoyadi', 'ogrenciadsoyad', 'ogrenciadisoyadi', 'isimsoyisim'];

/// Türkçe duyarsız karşılaştırma anahtarı: "Etüt-1 " -> "etut1", "İSMAİL" -> "ismail"
String normalizeKey(String s) {
  final lower = s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
  const map = {'ç': 'c', 'ğ': 'g', 'ı': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u', 'â': 'a', 'î': 'i', 'û': 'u'};
  final folded = lower.split('').map((c) => map[c] ?? c).join();
  return folded.replaceAll(RegExp(r'[^a-z0-9]'), '');
}

/// "  ahmet   CAN " -> "Ahmet Can" (Türkçe büyük/küçük harf)
String titleCaseTr(String s) => s
    .trim()
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .map((w) {
      final first = w.substring(0, 1).replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();
      final rest = w.substring(1).replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
      return '$first$rest';
    })
    .join(' ');

class ImportRow {
  ImportRow({required this.rowNumber, required this.values});

  /// Excel'deki satır numarası (1'den başlar)
  final int rowNumber;
  final Map<ImportField, String> values;
  final List<String> errors = [];
  final List<String> warnings = [];

  /// Atlanacak (hatalı değil ama eklenmeyecek): zaten kayıtlı / dosyada tekrar
  bool skip = false;

  String get firstName => values[ImportField.firstName] ?? '';
  String get lastName => values[ImportField.lastName] ?? '';
  String get fullName => '$firstName $lastName'.trim();
  bool get isValid => errors.isEmpty;
  bool get willImport => isValid && !skip;

  String? value(ImportField f) {
    final v = values[f]?.trim();
    return v == null || v.isEmpty ? null : v;
  }
}

/// Mevcut olmayan, oluşturulması önerilen grup
class NewGroup {
  NewGroup(this.kind, this.name);

  final GroupKind kind;

  /// Excel'de ilk görülen yazım
  final String name;
  int studentCount = 0;

  String get key => normalizeKey(name);
}

class ImportPlan {
  ImportPlan({required this.rows, required this.newGroups, required this.matchedGroups, required this.columns});

  final List<ImportRow> rows;

  /// Excel'deki ama yurtta olmayan gruplar
  final List<NewGroup> newGroups;

  /// (tür, normalize ad) -> mevcut grup id
  final Map<(GroupKind, String), String> matchedGroups;

  /// Tanınan sütunlar
  final Set<ImportField> columns;

  List<ImportRow> get toImport => rows.where((r) => r.willImport).toList();
  List<ImportRow> get invalid => rows.where((r) => !r.isValid).toList();
  List<ImportRow> get skipped => rows.where((r) => r.isValid && r.skip).toList();

  /// Bir satırın verilen türdeki grup adı
  String? groupNameOf(ImportRow r, GroupKind kind) =>
      r.value(kind == GroupKind.study ? ImportField.studyGroup : ImportField.internalGroup);
}

/// [table]: Excel'in satırları. [existingStudents]: yurttaki öğrenciler (tekrarları atlamak için).
ImportPlan buildImportPlan(
  List<List<String>> table, {
  required List<Student> existingStudents,
  required List<Group> groups,
}) {
  // Başlık satırını bul (ilk 10 satır içinde "Ad" veya "Ad Soyad" içeren)
  var headerIndex = -1;
  final columnOf = <ImportField, int>{};
  int? fullNameCol;
  for (var i = 0; i < table.length && i < 10; i++) {
    final keys = table[i].map(normalizeKey).toList();
    final found = <ImportField, int>{};
    int? full;
    for (var c = 0; c < keys.length; c++) {
      final k = keys[c];
      if (k.isEmpty) continue;
      if (_fullNameAliases.contains(k)) {
        full ??= c;
        continue;
      }
      for (final f in ImportField.values) {
        if (!found.containsKey(f) && (k == normalizeKey(f.label) || (_aliases[f]?.contains(k) ?? false))) {
          found[f] = c;
          break;
        }
      }
    }
    if (found.containsKey(ImportField.firstName) || full != null) {
      headerIndex = i;
      columnOf.addAll(found);
      fullNameCol = found.containsKey(ImportField.firstName) ? null : full;
      break;
    }
  }
  if (headerIndex < 0) {
    throw const FormatException(
      'Başlık satırı bulunamadı. İlk satırda en az "Ad" ve "Soyad" (veya "Ad Soyad") sütunları olmalı. '
      'Şablonu indirip onu doldurmanızı öneririz.',
    );
  }
  if (fullNameCol == null && !columnOf.containsKey(ImportField.lastName)) {
    throw const FormatException('"Soyad" sütunu bulunamadı.');
  }

  final activeGroups = groups.where((g) => !g.isArchived).toList();
  final matched = <(GroupKind, String), String>{};
  for (final g in activeGroups) {
    matched.putIfAbsent((g.kind, normalizeKey(g.name)), () => g.id);
  }

  final existingNames = {
    for (final s in existingStudents)
      if (s.status == StudentStatus.active) normalizeKey(s.fullName),
  };
  final seenInFile = <String, int>{};
  final newGroups = <(GroupKind, String), NewGroup>{};
  final rows = <ImportRow>[];

  for (var i = headerIndex + 1; i < table.length; i++) {
    final cells = table[i];
    if (cells.every((c) => c.trim().isEmpty)) continue;
    String cell(int? c) => c == null || c >= cells.length ? '' : cells[c].trim();

    final values = <ImportField, String>{
      for (final e in columnOf.entries) e.key: cell(e.value),
    };
    if (fullNameCol != null) {
      final parts = cell(fullNameCol).split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
      if (parts.length >= 2) {
        values[ImportField.firstName] = parts.sublist(0, parts.length - 1).join(' ');
        values[ImportField.lastName] = parts.last;
      } else {
        values[ImportField.firstName] = parts.join();
        values[ImportField.lastName] = '';
      }
    }
    values[ImportField.firstName] = titleCaseTr(values[ImportField.firstName] ?? '');
    values[ImportField.lastName] = titleCaseTr(values[ImportField.lastName] ?? '');

    final row = ImportRow(rowNumber: i + 1, values: values);
    if (row.firstName.isEmpty) row.errors.add('Ad boş');
    if (row.lastName.isEmpty) row.errors.add('Soyad boş');
    for (final f in ImportField.values) {
      if ((row.value(f)?.length ?? 0) > 200) row.errors.add('${f.label} çok uzun');
    }

    if (row.isValid) {
      final key = normalizeKey(row.fullName);
      if (existingNames.contains(key)) {
        row.skip = true;
        row.warnings.add('Bu isimde kayıtlı bir öğrenci zaten var');
      } else if (seenInFile.containsKey(key)) {
        row.skip = true;
        row.warnings.add('Dosyada tekrar ediyor (${seenInFile[key]}. satır)');
      } else {
        seenInFile[key] = row.rowNumber;
      }
    }

    for (final kind in GroupKind.values) {
      final name = row.value(kind == GroupKind.study ? ImportField.studyGroup : ImportField.internalGroup);
      if (name == null) continue;
      final key = (kind, normalizeKey(name));
      if (key.$2.isEmpty || matched.containsKey(key)) continue;
      final ng = newGroups.putIfAbsent(key, () => NewGroup(kind, name.trim()));
      if (row.willImport) ng.studentCount++;
    }
    rows.add(row);
  }

  return ImportPlan(
    rows: rows,
    newGroups: newGroups.values.toList(),
    matchedGroups: matched,
    columns: {...columnOf.keys, if (fullNameCol != null) ...[ImportField.firstName, ImportField.lastName]},
  );
}
