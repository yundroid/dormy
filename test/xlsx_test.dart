import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:dormy/features/share/xlsx.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sütun adları', () {
    expect(columnName(0), 'A');
    expect(columnName(25), 'Z');
    expect(columnName(26), 'AA');
    expect(columnName(27), 'AB');
    expect(columnName(701), 'ZZ');
  });

  test('Türkçe sayılar Excel sayısına çevrilir', () {
    expect(parseCellNumber('32,67'), 32.67);
    expect(parseCellNumber('%75'), 75);
    expect(parseCellNumber('-1,5'), -1.5);
    expect(parseCellNumber('1.250'), 1250);
    expect(parseCellNumber('120'), 120);
    expect(parseCellNumber('-'), isNull);
    expect(parseCellNumber('3 kitap'), isNull);
    expect(parseCellNumber('A. Y.'), isNull);
  });

  test('geçerli bir xlsx paketi üretir', () {
    final bytes = buildXlsx(
      sheetName: 'TYT: Deneme/3',
      title: 'A Yurdu · TYT',
      subtitle: '27 Ekim 2026',
      header: ['Sıra', 'Öğrenci', 'Türkçe', 'Toplam'],
      rows: [
        ['1', 'Çağrı Öztürk <&>', '32,67', '%88'],
        ['2', 'İsmail Şahin', '-', '%81'],
      ],
    );
    final zip = ZipDecoder().decodeBytes(bytes);
    expect(zip.files.map((f) => f.name), containsAll(['[Content_Types].xml', 'xl/workbook.xml', 'xl/worksheets/sheet1.xml']));
    final sheet = utf8.decode(zip.findFile('xl/worksheets/sheet1.xml')!.content as List<int>);
    expect(sheet, contains('Çağrı Öztürk &lt;&amp;&gt;'));
    expect(sheet, contains('<v>32.67</v>'));
    expect(sheet, contains('Toplam (%)'));
    expect(sheet, contains('<c r="D5"><v>88</v></c>'));
    final wb = utf8.decode(zip.findFile('xl/workbook.xml')!.content as List<int>);
    expect(wb, contains('name="TYT  Deneme 3"'));
  });
}
