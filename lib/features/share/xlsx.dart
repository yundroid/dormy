import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Excel çalışma kitabındaki bir sayfa.
class XlsxSheet {
  const XlsxSheet({
    required this.name,
    required this.header,
    required this.rows,
    this.title,
    this.subtitle,
    this.numericFrom = 2,
  });

  final String name;
  final List<String> header;
  final List<List<String>> rows;
  final String? title;
  final String? subtitle;

  /// Bu sütundan itibaren "32,67", "%75", "120" gibi değerler sayı olarak yazılır.
  /// Hepsi metin kalsın diye `header.length` verilebilir.
  final int numericFrom;
}

/// Tek sayfalık basit bir Excel (.xlsx) dosyası üretir.
Uint8List buildXlsx({
  required String sheetName,
  required List<String> header,
  required List<List<String>> rows,
  String? title,
  String? subtitle,
  int numericFrom = 2,
}) =>
    buildWorkbook([
      XlsxSheet(name: sheetName, header: header, rows: rows, title: title, subtitle: subtitle, numericFrom: numericFrom),
    ]);

/// Birden fazla sayfalı Excel (.xlsx) dosyası üretir.
Uint8List buildWorkbook(List<XlsxSheet> sheets) {
  final names = <String>[];
  for (final s in sheets) {
    var n = _sheetName(s.name);
    for (var i = 2; names.contains(n); i++) {
      n = _sheetName('${s.name} $i');
    }
    names.add(n);
  }

  final files = <String, String>{
    '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '${[for (var i = 1; i <= sheets.length; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '</Types>',
    '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>',
    'xl/workbook.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
        '${[for (var i = 0; i < sheets.length; i++) '<sheet name="${_esc(names[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
        '</sheets></workbook>',
    'xl/_rels/workbook.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '${[for (var i = 1; i <= sheets.length; i++) '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>'].join()}'
        '<Relationship Id="rId${sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
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
    for (var i = 0; i < sheets.length; i++) 'xl/worksheets/sheet${i + 1}.xml': _sheetXml(sheets[i]),
  };

  final archive = Archive();
  files.forEach((path, content) => archive.addFile(ArchiveFile.bytes(path, utf8.encode(content))));
  return ZipEncoder().encodeBytes(archive);
}

String _sheetXml(XlsxSheet s) {
  final header = s.header, rows = s.rows, numericFrom = s.numericFrom;
  final percentCols = <int>{
    for (var c = numericFrom; c < header.length; c++)
      if (rows.any((r) => c < r.length && r[c].startsWith('%'))) c,
  };
  final colCount = [header.length, for (final r in rows) r.length].fold<int>(0, (a, b) => b > a ? b : a);

  final sheet = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
  if (colCount > 0) {
    sheet.write('<cols>');
    for (var c = 0; c < colCount; c++) {
      final longest = [if (c < header.length) header[c], for (final r in rows) if (c < r.length) r[c]]
          .fold<int>(0, (a, v) => v.length > a ? v.length : a);
      sheet.write('<col min="${c + 1}" max="${c + 1}" width="${(longest + 2).clamp(6, 80)}" customWidth="1"/>');
    }
    sheet.write('</cols>');
  }
  sheet.write('<sheetData>');

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

  if (s.title != null) writeRow([s.title!], bold: true);
  if (s.subtitle != null) writeRow([s.subtitle!]);
  if (s.title != null || s.subtitle != null) rowNo++;
  if (header.isNotEmpty) {
    writeRow([for (var c = 0; c < header.length; c++) percentCols.contains(c) ? '${header[c]} (%)' : header[c]], bold: true);
  }
  for (final r in rows) {
    writeRow(r, data: true);
  }
  sheet.write('</sheetData></worksheet>');
  return sheet.toString();
}

/// Bir .xlsx dosyasının ilk sayfasını satır satır metin olarak okur.
/// Boş hücreler "" olur; satır sonundaki boşluklar kırpılır, tamamen boş satırlar atlanmaz.
List<List<String>> readXlsxRows(Uint8List bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException('Dosya okunamadı. Lütfen .xlsx biçiminde bir Excel dosyası seçin.');
  }
  String? text(String path) {
    final f = zip.findFile(path);
    return f == null ? null : utf8.decode(f.content as List<int>, allowMalformed: true);
  }

  // İlk sayfanın yolu: workbook.xml -> ilk <sheet r:id> -> workbook.xml.rels hedefi
  var sheetPath = 'xl/worksheets/sheet1.xml';
  final wb = text('xl/workbook.xml');
  final rels = text('xl/_rels/workbook.xml.rels');
  if (wb != null && rels != null) {
    final first = XmlDocument.parse(wb).findAllElements('sheet').firstOrNull;
    final rid = first?.attributes.where((a) => a.name.local == 'id').firstOrNull?.value;
    final target = XmlDocument.parse(rels)
        .findAllElements('Relationship')
        .where((r) => r.getAttribute('Id') == rid)
        .firstOrNull
        ?.getAttribute('Target');
    if (target != null) {
      sheetPath = target.startsWith('/') ? target.substring(1) : 'xl/${target.replaceFirst(RegExp(r'^\./'), '')}';
    }
  }
  final sheetXml = text(sheetPath);
  if (sheetXml == null) throw const FormatException('Excel dosyasında sayfa bulunamadı.');

  final shared = <String>[];
  final sst = text('xl/sharedStrings.xml');
  if (sst != null) {
    for (final si in XmlDocument.parse(sst).findAllElements('si')) {
      shared.add(si.findAllElements('t').map((t) => t.innerText).join());
    }
  }

  final out = <List<String>>[];
  for (final row in XmlDocument.parse(sheetXml).findAllElements('row')) {
    final rowIndex = (int.tryParse(row.getAttribute('r') ?? '') ?? out.length + 1) - 1;
    while (out.length < rowIndex) {
      out.add(const []);
    }
    final cells = <String>[];
    for (final c in row.findElements('c')) {
      final ref = c.getAttribute('r');
      final col = ref == null ? cells.length : columnIndex(ref);
      while (cells.length < col) {
        cells.add('');
      }
      final type = c.getAttribute('t');
      final v = c.getElement('v')?.innerText ?? '';
      final value = switch (type) {
        's' => (int.tryParse(v) != null && int.parse(v) < shared.length) ? shared[int.parse(v)] : '',
        'inlineStr' => c.findAllElements('t').map((t) => t.innerText).join(),
        'b' => v == '1' ? 'DOĞRU' : 'YANLIŞ',
        _ => _numberText(v),
      };
      if (cells.length == col) {
        cells.add(value.trim());
      } else {
        cells[col] = value.trim();
      }
    }
    while (cells.isNotEmpty && cells.last.isEmpty) {
      cells.removeLast();
    }
    out.add(cells);
  }
  return out;
}

/// Excel sayıları: "5321234567" olduğu gibi, "12.0" -> "12"
String _numberText(String v) {
  final n = num.tryParse(v);
  if (n == null) return v;
  if (n == n.roundToDouble() && n.abs() < 1e15) return n.toInt().toString();
  return v;
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

/// "B12" -> 1, "AA3" -> 26
int columnIndex(String cellRef) {
  final letters = RegExp(r'^[A-Za-z]+').stringMatch(cellRef) ?? 'A';
  var n = 0;
  for (final ch in letters.toUpperCase().codeUnits) {
    n = n * 26 + (ch - 64);
  }
  return n - 1;
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
