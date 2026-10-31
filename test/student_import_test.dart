import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dormy/features/admin/student_import.dart';
import 'package:dormy/features/share/xlsx.dart';
import 'package:dormy/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

Group _g(String id, GroupKind kind, String name, {bool archived = false}) =>
    Group(id: id, tenantId: 't', kind: kind, name: name, isArchived: archived);

Student _s(String first, String last) =>
    Student(id: '$first$last', tenantId: 't', firstName: first, lastName: last, status: StudentStatus.active);

/// Excel'in kendi kaydettiği biçimi taklit eder: paylaşılan metinler, sayılar, boş hücre atlamaları.
Uint8List _excelLikeFile() {
  const shared = '<?xml version="1.0" encoding="UTF-8"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<si><t>Ad</t></si><si><t>Soyad</t></si><si><t>Oda No</t></si><si><t>Etüt Grubu</t></si>'
      '<si><t>ahmet can</t></si><si><r><t>YIL</t></r><r><t>MAZ</t></r></si><si><t>Etut-1</t></si></sst>';
  const sheet = '<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'
      '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="s"><v>2</v></c><c r="D1" t="s"><v>3</v></c></row>'
      '<row r="3"><c r="A3" t="s"><v>4</v></c><c r="B3" t="s"><v>5</v></c><c r="C3"><v>204</v></c><c r="D3" t="s"><v>6</v></c></row>'
      '</sheetData></worksheet>';
  const wb = '<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Liste" sheetId="1" r:id="rId7"/></sheets></workbook>';
  const rels = '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId7" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/liste.xml"/></Relationships>';
  final a = Archive()
    ..addFile(ArchiveFile.bytes('xl/workbook.xml', utf8.encode(wb)))
    ..addFile(ArchiveFile.bytes('xl/_rels/workbook.xml.rels', utf8.encode(rels)))
    ..addFile(ArchiveFile.bytes('xl/sharedStrings.xml', utf8.encode(shared)))
    ..addFile(ArchiveFile.bytes('xl/worksheets/liste.xml', utf8.encode(sheet)));
  return ZipEncoder().encodeBytes(a);
}

void main() {
  group('Excel okuma', () {
    test('Excel biçimi: paylaşılan metin, sayı, boş satır ve sütun boşlukları', () {
      final rows = readXlsxRows(_excelLikeFile());
      expect(rows[0], ['Ad', 'Soyad', 'Oda No', 'Etüt Grubu']);
      expect(rows[1], isEmpty);
      expect(rows[2], ['ahmet can', 'YILMAZ', '204', 'Etut-1']);
    });

    test('kendi şablonumuz geri okunabilir', () {
      final bytes = buildWorkbook([
        XlsxSheet(name: 'Öğrenciler', header: [for (final f in ImportField.values) f.header], rows: const [], numericFrom: 99),
        const XlsxSheet(name: 'Açıklama', header: ['Sütun'], rows: [['x']]),
      ]);
      final rows = readXlsxRows(bytes);
      expect(rows.first.first, 'Ad *');
      expect(rows.first, hasLength(ImportField.values.length));
      final zip = ZipDecoder().decodeBytes(bytes);
      expect(zip.findFile('xl/worksheets/sheet2.xml'), isNotNull);
    });

    test('xlsx olmayan dosya anlaşılır hata verir', () {
      expect(() => readXlsxRows(Uint8List.fromList(utf8.encode('ad;soyad'))), throwsFormatException);
    });

    test('hücre adresi', () {
      expect(columnIndex('A1'), 0);
      expect(columnIndex('D3'), 3);
      expect(columnIndex('AA10'), 26);
    });
  });

  group('içe aktarma planı', () {
    final groups = [
      _g('e1', GroupKind.study, 'Etüt-1'),
      _g('d1', GroupKind.internal, 'Dahili A'),
      _g('old', GroupKind.study, 'Eski Etüt', archived: true),
    ];

    test('Türkçe duyarsız anahtar', () {
      expect(normalizeKey(' Etüt-1 '), normalizeKey('ETUT 1'));
      expect(normalizeKey('İSMAİL'), 'ismail');
      expect(normalizeKey('IRMAK'), 'irmak');
      expect(titleCaseTr('  ahmet   CAN '), 'Ahmet Can');
      expect(titleCaseTr('İSMAİL ırmak'), 'İsmail Irmak');
    });

    test('grup eşleştirme, yeni gruplar, tekrarlar ve hatalar', () {
      final plan = buildImportPlan(
        [
          ['Ad *', 'Soyad *', 'Oda No', 'Etüt Grubu', 'Dahili Ders Grubu'],
          ['ahmet', 'YILMAZ', '204', 'etut 1', ''],
          ['Mehmet', 'Kaya', '', 'Etüt-3', 'dahili a'],
          ['Can', 'Demir', '', 'etüt-3', 'Hafızlık'],
          ['', 'Soyadsız', '', '', ''],
          ['', '', '', '', ''],
          ['Ayşe', 'Ak', '', '', ''],
          ['Ahmet', 'Yılmaz', '', '', ''],
          ['Eski', 'Grup', '', 'Eski Etüt', ''],
        ],
        existingStudents: [_s('Ayşe', 'Ak')],
        groups: groups,
      );

      expect(plan.toImport.map((r) => r.fullName), ['Ahmet Yılmaz', 'Mehmet Kaya', 'Can Demir', 'Eski Grup']);
      expect(plan.invalid.single.rowNumber, 5);
      expect(plan.invalid.single.errors, contains('Ad boş'));
      expect(plan.skipped.map((r) => r.rowNumber), [7, 8]);
      expect(plan.skipped.first.warnings.single, contains('zaten var'));
      expect(plan.skipped.last.warnings.single, contains('2. satır'));

      // "etut 1" mevcut Etüt-1'e bağlanır; Etüt-3 iki yazımla da tek yeni grup
      expect(plan.matchedGroups[(GroupKind.study, normalizeKey('etut 1'))], 'e1');
      expect(plan.matchedGroups[(GroupKind.internal, normalizeKey('dahili a'))], 'd1');
      final names = {for (final g in plan.newGroups) '${g.kind.name}:${g.name}': g.studentCount};
      // arşivdeki grup eşleşmez, yeni grup olarak önerilir
      expect(names, {'study:Etüt-3': 2, 'internal:Hafızlık': 1, 'study:Eski Etüt': 1});
    });

    test('tek sütunda "Ad Soyad" ve farklı başlık yazımları', () {
      final plan = buildImportPlan(
        [
          ['Sıra', 'Adı Soyadı', 'Sınıf', 'Veli Tel', 'Etüt'],
          ['1', 'ahmet can yılmaz', '10-A', '05321112233', 'Etüt-1'],
          ['2', 'Tekisim', '', '', ''],
        ],
        existingStudents: const [],
        groups: groups,
      );
      final r = plan.rows.first;
      expect(r.firstName, 'Ahmet Can');
      expect(r.lastName, 'Yılmaz');
      expect(r.value(ImportField.schoolGrade), '10-A');
      expect(r.value(ImportField.guardianPhone), '05321112233');
      expect(plan.groupNameOf(r, GroupKind.study), 'Etüt-1');
      expect(plan.newGroups, isEmpty);
      expect(plan.rows.last.errors, contains('Soyad boş'));
    });

    test('başlık bulunamazsa anlaşılır hata', () {
      expect(
        () => buildImportPlan([['x', 'y'], ['1', '2']], existingStudents: const [], groups: const []),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('Başlık satırı'))),
      );
      expect(
        () => buildImportPlan([['Ad', 'Oda']], existingStudents: const [], groups: const []),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('Soyad'))),
      );
    });
  });
}
