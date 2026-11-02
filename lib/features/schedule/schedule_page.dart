import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session.dart';
import '../../data/schedule_repository.dart';
import '../../widgets/common.dart';
import '../share/share_table.dart';

/// Yönetimin oluşturduğu günlük program. Öğretmenler sadece görüntüler.
class SchedulePage extends ConsumerStatefulWidget {
  const SchedulePage({super.key});

  @override
  ConsumerState<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends ConsumerState<SchedulePage> {
  late int _day = DateTime.now().weekday;
  late DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // "Şimdi" vurgusu dakikada bir güncellenir
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _isAdmin => session.ctx.isAdmin;

  Future<void> _edit([ScheduleItem? item]) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ItemDialog(item: item, defaultDay: _day),
    );
    if (changed == true) ref.invalidate(scheduleProvider);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(scheduleProvider);
    final isToday = _day == _now.weekday;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Günlük Program'),
        actions: [
          if (async.hasValue && itemsForDay(async.value!, _day).isNotEmpty)
            IconButton(
              tooltip: 'Paylaş',
              icon: const Icon(Icons.share),
              onPressed: () => openSharePreview(context, _table(itemsForDay(async.value!, _day))),
            ),
        ],
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              heroTag: 'schedule-add',
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('Ekle'),
            )
          : null,
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                for (var d = 1; d <= 7; d++) ...[
                  ChoiceChip(
                    label: Text(d == _now.weekday ? '${weekdayShort[d - 1]} · Bugün' : weekdayShort[d - 1]),
                    selected: _day == d,
                    onSelected: (_) => setState(() => _day = d),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          Expanded(
            child: AsyncView(
              value: async,
              onRetry: () => ref.invalidate(scheduleProvider),
              builder: (all) {
                final day = itemsForDay(all, _day);
                if (day.isEmpty) {
                  return EmptyState(
                    icon: Icons.event_note_outlined,
                    title: all.isEmpty ? 'Henüz günlük program yok' : '${weekdayLong[_day - 1]} için program yok',
                    message: _isAdmin
                        ? '"Ekle" ile başlangıç ve bitiş saatini, yapılacak programı girin.'
                        : 'Günlük program yurt yönetimi tarafından oluşturulur.',
                  );
                }
                final states = isToday
                    ? statesFor(day, _now.hour * 60 + _now.minute)
                    : List.filled(day.length, ScheduleState.later);
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(scheduleProvider),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    children: [
                      ContentWidth(
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              const _HeaderRow(),
                              for (var i = 0; i < day.length; i++)
                                _ItemRow(
                                  item: day[i],
                                  state: states[i],
                                  onTap: _isAdmin ? () => _edit(day[i]) : null,
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (_isAdmin)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: ContentWidth(
                            child: Text('Düzenlemek veya silmek için satıra dokunun.',
                                style: Theme.of(context).textTheme.bodySmall),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  ShareTable _table(List<ScheduleItem> day) => ShareTable(
        title: 'Günlük Program',
        subtitle: weekdayLong[_day - 1],
        columns: const ['Başlangıç', 'Bitiş', 'Program'],
        nameColumn: -1,
        numericFrom: 3,
        rows: [
          for (final i in day)
            ShareRow(cells: [formatMinutes(i.start), formatMinutes(i.end), i.note == null ? i.title : '${i.title} (${i.note})']),
        ],
      );
}

const _timeColWidth = 78.0;

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary);
    return Container(
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(width: _timeColWidth, child: Text('Başlangıç', style: style)),
          SizedBox(width: _timeColWidth, child: Text('Bitiş', style: style)),
          Expanded(child: Text('Program', style: style)),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.state, this.onTap});

  final ScheduleItem item;
  final ScheduleState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final past = state == ScheduleState.past;
    final now = state == ScheduleState.now;
    final textColor = past ? scheme.outline : null;
    final timeStyle = TextStyle(fontFeatures: const [FontFeature.tabularFigures()], color: textColor, fontWeight: now ? FontWeight.w700 : null);

    return Material(
      color: now ? scheme.primaryContainer : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)))),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: _timeColWidth, child: Text(formatMinutes(item.start), style: timeStyle)),
              SizedBox(width: _timeColWidth, child: Text(formatMinutes(item.end), style: timeStyle)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(item.title, style: TextStyle(color: textColor, fontWeight: now ? FontWeight.w700 : FontWeight.w500)),
                        if (now) StatusBadge(label: 'Şimdi', color: scheme.primary),
                        if (state == ScheduleState.next) const StatusBadge(label: 'Sıradaki', color: Colors.orange),
                      ],
                    ),
                    if (item.note != null)
                      Text(item.note!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.outline)),
                    if (item.days.length < 7)
                      Text(daysLabel(item.days), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.outline)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ItemDialog extends StatefulWidget {
  const _ItemDialog({this.item, required this.defaultDay});

  final ScheduleItem? item;
  final int defaultDay;

  @override
  State<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<_ItemDialog> {
  final _form = GlobalKey<FormState>();
  late int? _start = widget.item?.start;
  late int? _end = widget.item?.end;
  late final _title = TextEditingController(text: widget.item?.title);
  late final _note = TextEditingController(text: widget.item?.note);
  late final Set<int> _days = {...?widget.item?.days};
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_days.isEmpty) _days.addAll(const [1, 2, 3, 4, 5, 6, 7]);
  }

  Future<void> _pickTime(bool start) async {
    final initial = (start ? _start : _end) ?? (start ? 8 * 60 : (_start ?? 8 * 60) + 30);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (initial ~/ 60) % 24, minute: initial % 60),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      final m = picked.hour * 60 + picked.minute;
      if (start) {
        _start = m;
        // bitiş boşsa ya da başlangıçtan önceyse 30 dk sonrasını öner
        if (_end == null || _end! <= m) _end = (m + 30).clamp(0, 23 * 60 + 59);
      } else {
        _end = m;
      }
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_start == null || _end == null) return setState(() => _error = 'Başlangıç ve bitiş saatini seçin');
    if (_end! <= _start!) return setState(() => _error = 'Bitiş saati başlangıçtan sonra olmalı');
    if (_days.isEmpty) return setState(() => _error = 'En az bir gün seçin');
    final ok = await runAction(
      context,
      () => ScheduleRepo.save(id: widget.item?.id, start: _start!, end: _end!, title: _title.text, note: _note.text, days: _days),
    );
    if (ok && mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final yes = await confirm(context,
        title: 'Programdan kaldır', message: '"${widget.item!.title}" silinecek.', confirmLabel: 'Sil', destructive: true);
    if (!yes || !mounted) return;
    final ok = await runAction(context, () => ScheduleRepo.delete(widget.item!.id), success: 'Silindi');
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    Widget timeField(String label, int? value, bool start) => Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pickTime(start),
            icon: const Icon(Icons.schedule, size: 18),
            label: Text(value == null ? label : '$label  ${formatMinutes(value)}'),
          ),
        );

    void preset(List<int> days) => setState(() => _days
      ..clear()
      ..addAll(days));

    return AlertDialog(
      title: Text(widget.item == null ? 'Programa ekle' : 'Düzenle'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [timeField('Başlangıç', _start, true), const SizedBox(width: 8), timeField('Bitiş', _end, false)]),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _title,
                  validator: requiredValidator,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Program', hintText: 'örn. Akşam etüdü'),
                ),
                const SizedBox(height: 12),
                TextFormField(controller: _note, decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)')),
                const SizedBox(height: 16),
                Text('Geçerli günler', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ActionChip(label: const Text('Her gün'), onPressed: () => preset(const [1, 2, 3, 4, 5, 6, 7])),
                    ActionChip(label: const Text('Hafta içi'), onPressed: () => preset(const [1, 2, 3, 4, 5])),
                    ActionChip(label: const Text('Hafta sonu'), onPressed: () => preset(const [6, 7])),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (var d = 1; d <= 7; d++)
                      FilterChip(
                        label: Text(weekdayShort[d - 1]),
                        selected: _days.contains(d),
                        onSelected: (v) => setState(() => v ? _days.add(d) : _days.remove(d)),
                      ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (widget.item != null)
          TextButton(
            onPressed: _delete,
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Sil'),
          ),
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
        BusyButton(onPressed: _save, label: 'Kaydet'),
      ],
    );
  }
}
