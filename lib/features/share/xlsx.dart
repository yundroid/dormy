import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Tek sayfalık basit bir Excel (.xlsx) dosyası üretir.
///
/// [numericFrom] ve sonrasındaki sütunlarda "32,67", "%75", "120" gibi değerler
/// Excel'e sayı olarak yazılır; diğer her şey metin olarak kalır.
Uint8List buildXlsx({
  required String sheetName,
  required List<String> header,
  required List<List<String>> rows,
  String? title,
  String? subtitle,
  int numericFrom = 2,
}) {
  final percentCols = <int>{
    for (var c = numericFrom; c < header.length; c++)
      if (rows.any((r) => c < r.length && r[c].startsWith('%'))) c,
  };

  final sheet = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
    ..write('<cols>');
  for (var c = 0; c < header.length; c++) {
    final longest = [header[c], for (final r in rows) if (c < r.length) r[c]].fold<int>(0, (a, s) => s.length > a ? s.length : a);
    final width = (longest + 2).clamp(6, 60);
    sheet.write('<col min="${c + 1}" max="${c + 1}" width="$width" customWidth="1"/>');
  }
  sheet.write('</cols><sheetData>');

  var rowNo = 0;
  void writeRow(List<String> cells, {bool bold = false, bool data = false}) {
    rowNo++;
    sheet.write('<row r="$rowNo">');
    for (var c = 0; c < cells.length; c++) {
      final ref = '${columnName(c)}$rowNo';
      final number = data && c >= numericFrom ? parseCellNumber(cells[c]) : null;
      if (number != null) {
        sheet.write('<c r="$ref"><v>$number</v></c>');
      } else if (cells[c].isNotEmpty) {
        sheet.write('<c r="$ref" t="inlineStr"${bold ? ' s="1"' : ''}><is><t xml:space="preserve">${_esc(cells[c])}</t></is></c>');
      }
    }
    sheet.write('</row>');
  }

  if (title != null) writeRow([title], bold: true);
  if (subtitle != null) writeRow([subtitle]);
  if (title != null || subtitle != null) rowNo++;
  writeRow([for (var c = 0; c < header.length; c++) percentCols.contains(c) ? '${header[c]} (%)' : header[c]], bold: true);
  for (final r in rows) {
    writeRow(r, data: true);
  }
  sheet.write('</sheetData></worksheet>');

  final name = _sheetName(sheetName);
  final files = <String, String>{
    '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '</Types>',
    '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>',
    'xl/workbook.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="${_esc(name)}" sheetId="1" r:id="rId1"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>',
    'xl/styles.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
        '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
        '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>'
        '</styleSheet>',
    'xl/worksheets/sheet1.xml': sheet.toString(),
  };

  final archive = Archive();
  files.forEach((path, content) => archive.addFile(ArchiveFile.bytes(path, utf8.encode(content))));
  return ZipEncoder().encodeBytes(archive);
}

/// 0 -> A, 25 -> Z, 26 -> AA
String columnName(int index) {
  var n = index + 1;
  final chars = <String>[];
  while (n > 0) {
    chars.insert(0, String.fromCharCode(65 + (n - 1) % 26));
    n = (n - 1) ~/ 26;
  }
  return chars.join();
}

/// "32,67" -> 32.67, "%75" -> 75, "1.250" -> 1250; sayı değilse null
num? parseCellNumber(String s) {
  var t = s.trim();
  if (t.startsWith('%')) t = t.substring(1);
  if (!RegExp(r'^-?[\d.]+(,\d+)?$').hasMatch(t)) return null;
  t = t.replaceAll('.', '').replaceAll(',', '.');
  return num.tryParse(t);
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

/// Excel sayfa adı: en fazla 31 karakter, []:*?/\ içermez
String _sheetName(String s) {
  final clean = s.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
  final name = clean.isEmpty ? 'Rapor' : clean;
  return name.length > 31 ? name.substring(0, 31) : name;
}
