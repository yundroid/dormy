import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/formatters.dart';
import '../../core/session.dart';
import '../../widgets/common.dart';
import '../academics/ranking.dart';

/// Veliye paylaşılabilir tablo (sıralı sonuç listesi, öğrenci karnesi vb.).
class ShareTable {
  const ShareTable({
    required this.title,
    required this.columns,
    required this.rows,
    this.subtitle,
    this.nameColumn = 1,
    this.footer,
    this.numericFrom = 2,
  });

  final String title;
  final String? subtitle;
  final List<String> columns;
  final List<ShareRow> rows;

  /// Öğrenci adının bulunduğu sütun (isim gizlemede kullanılır)
  final int nameColumn;

  /// Bu sütundan itibaren sağa yaslı (sayısal) sütunlar
  final int numericFrom;
  final String? footer;

  List<List<String>> cells(NameMode mode, String? highlightId) => [
        for (final r in rows)
          [
            for (var i = 0; i < r.cells.length; i++)
              i == nameColumn ? maskName(r.cells[i], mode, studentId: r.studentId, highlightId: highlightId) : r.cells[i],
          ],
      ];
}

class ShareRow {
  const ShareRow({required this.cells, this.studentId});

  final List<String> cells;
  final String? studentId;
}

Future<void> openSharePreview(BuildContext context, ShareTable table) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => SharePreviewPage(table: table)));

class SharePreviewPage extends StatefulWidget {
  const SharePreviewPage({super.key, required this.table});

  final ShareTable table;

  @override
  State<SharePreviewPage> createState() => _SharePreviewPageState();
}

class _SharePreviewPageState extends State<SharePreviewPage> {
  final _boundary = GlobalKey();
  NameMode _mode = NameMode.full;
  String? _highlight;
  bool _busy = false;

  ShareTable get t => widget.table;

  String get _fileBase {
    final safe = t.title.replaceAll(RegExp(r'[^\wçğıöşüÇĞİÖŞÜ]+'), '_');
    return '${safe}_${isoDate(DateTime.now())}';
  }

  Future<void> _sharePng() async {
    setState(() => _busy = true);
    try {
      final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'image/png', name: '$_fileBase.png')],
        fileNameOverrides: ['$_fileBase.png'],
        title: t.title,
      ));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sharePdf() async {
    setState(() => _busy = true);
    try {
      final bytes = await buildPdf(t, _mode, _highlight);
      await Printing.sharePdf(bytes: bytes, filename: '$_fileBase.pdf');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final students = [
      if (t.nameColumn >= 0)
        for (final r in t.rows)
          if (r.studentId != null) (id: r.studentId!, name: r.cells[t.nameColumn]),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Paylaş')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _sharePdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('PDF'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy || (_mode == NameMode.single && _highlight == null) ? null : _sharePng,
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.image_outlined),
                  label: const Text('Görsel'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ContentWidth(
            maxWidth: 700,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (students.isNotEmpty) ...[
                Text('İsim gösterimi', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<NameMode>(
                  segments: [for (final m in NameMode.values) ButtonSegment(value: m, label: Text(m.label))],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
                if (_mode == NameMode.single) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _highlight,
                    decoration: const InputDecoration(labelText: 'Adı görünecek öğrenci', helperText: 'Diğer öğrencilerin adları gizlenir'),
                    items: [for (final s in students) DropdownMenuItem(value: s.id, child: Text(s.name))],
                    onChanged: (v) => setState(() => _highlight = v),
                  ),
                ],
                const SizedBox(height: 16),
                ],
                Text('Önizleme', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                // Görsel her cihazda aynı (okunabilir) genişlikte çizilir, önizlemede ekrana sığdırılır.
                DecoratedBox(
                  decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topLeft,
                    child: RepaintBoundary(
                      key: _boundary,
                      child: SizedBox(
                        width: shareImageWidth(t),
                        child: ShareTableView(table: t, mode: _mode, highlightId: _highlight),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Paylaşılan görselin genişliği: isim sütunu + sütun başına yer.
double shareImageWidth(ShareTable t) => (190 + (t.columns.length - 2) * 62 + 48).clamp(400, 1400).toDouble();

/// Paylaşılan görselin kendisi. Tema ne olursa olsun beyaz zeminde çizilir.
class ShareTableView extends StatelessWidget {
  const ShareTableView({super.key, required this.table, required this.mode, this.highlightId});

  final ShareTable table;
  final NameMode mode;
  final String? highlightId;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF1B1B1F);
    const muted = Color(0xFF5F6368);
    const accent = Color(0xFF2E5E8C);
    final cells = table.cells(mode, highlightId);
    final tenant = session.contextOrNull?.tenant?.name;

    TextStyle cell({bool bold = false, Color color = ink}) =>
        TextStyle(fontSize: 13, color: color, fontWeight: bold ? FontWeight.w600 : FontWeight.normal);

    return Theme(
      data: ThemeData.light(useMaterial3: true),
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tenant != null) Text(tenant, style: const TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w600)),
            Text(table.title, style: const TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w700)),
            if (table.subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(table.subtitle!, style: const TextStyle(color: muted, fontSize: 12)),
              ),
            const SizedBox(height: 12),
            Table(
              columnWidths: {
                0: const IntrinsicColumnWidth(),
                table.nameColumn: const FlexColumnWidth(),
                // Kitap listesi gibi uzun metin sütunları da esnek
                for (var i = 0; i < table.numericFrom; i++)
                  if (i != 0 && i != table.nameColumn) i: const FlexColumnWidth(1.4),
              },
              defaultColumnWidth: const IntrinsicColumnWidth(),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  decoration: const BoxDecoration(color: Color(0xFFE8EEF5)),
                  children: [
                    for (var i = 0; i < table.columns.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Text(
                          table.columns[i],
                          textAlign: i >= table.numericFrom ? TextAlign.right : TextAlign.left,
                          style: cell(bold: true, color: accent),
                        ),
                      ),
                  ],
                ),
                for (var r = 0; r < cells.length; r++)
                  TableRow(
                    decoration: BoxDecoration(
                      color: table.rows[r].studentId != null && table.rows[r].studentId == highlightId
                          ? const Color(0xFFFFF4D6)
                          : (r.isOdd ? const Color(0xFFF7F8FA) : Colors.white),
                    ),
                    children: [
                      for (var i = 0; i < cells[r].length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                          child: Text(
                            cells[r][i],
                            textAlign: i >= table.numericFrom ? TextAlign.right : TextAlign.left,
                            style: cell(bold: i == table.columns.length - 1),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              [if (table.footer != null) table.footer!, 'Oluşturulma: ${formatDateTime(DateTime.now())}'].join(' · '),
              style: const TextStyle(color: muted, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

Future<Uint8List> buildPdf(ShareTable t, NameMode mode, String? highlightId) async {
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
  final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));
  final cells = t.cells(mode, highlightId);
  final accent = PdfColor.fromHex('#2E5E8C');
  final tenant = session.contextOrNull?.tenant?.name;

  final highlightRow = highlightId == null ? -1 : t.rows.indexWhere((r) => r.studentId == highlightId);

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    build: (_) => [
      if (tenant != null) pw.Text(tenant, style: pw.TextStyle(color: accent, fontSize: 10, fontWeight: pw.FontWeight.bold)),
      pw.Text(t.title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      if (t.subtitle != null) pw.Text(t.subtitle!, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
      pw.SizedBox(height: 12),
      pw.TableHelper.fromTextArray(
        headers: t.columns,
        data: cells,
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: accent, fontSize: 10),
        headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE8EEF5)),
        cellStyle: const pw.TextStyle(fontSize: 10),
        cellAlignments: {
          for (var i = 0; i < t.columns.length; i++) i: i >= t.numericFrom ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
        },
        headerAlignments: {
          for (var i = 0; i < t.columns.length; i++) i: i >= t.numericFrom ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
        },
        oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF7F8FA)),
        rowDecoration: const pw.BoxDecoration(),
        border: null,
        cellDecoration: (index, data, rowNum) => rowNum - 1 == highlightRow
            ? const pw.BoxDecoration(color: PdfColor.fromInt(0xFFFFF4D6))
            : const pw.BoxDecoration(),
      ),
      pw.SizedBox(height: 8),
      pw.Text(
        [if (t.footer != null) t.footer!, 'Oluşturulma: ${formatDateTime(DateTime.now())}'].join(' · '),
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),
    ],
  ));
  return doc.save();
}
