import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/session.dart';
import '../../data/academics_repository.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

/// Birden fazla etüt grubu varsa filtre çipleri gösterir.
class GroupFilter extends StatelessWidget {
  const GroupFilter({super.key, required this.groups, required this.selected, required this.onChanged});

  final List<Group> groups;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (groups.length < 2) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          ChoiceChip(label: const Text('Tüm gruplar'), selected: selected == null, onSelected: (_) => onChanged(null)),
          for (final g in groups) ...[
            const SizedBox(width: 6),
            ChoiceChip(label: Text(g.name), selected: selected == g.id, onSelected: (_) => onChanged(g.id)),
          ],
        ],
      ),
    );
  }
}

/// Etüt grubu olmayan öğretmen için bilgi ekranı
class NoStudyGroup extends StatelessWidget {
  const NoStudyGroup({super.key});

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.workspaces_outline,
        title: 'Etüt grubunuz yok',
        message: session.ctx.isAdmin
            ? 'Yönetim panelinden önce bir etüt grubu oluşturun.'
            : 'Bu modülü kullanmak için yöneticinizin sizi bir etüt grubuna ataması gerekir.',
      );
}

/// "Matematik · Türev" gibi ders/konu etiketi
String subjectLabel(List<Subject> subjects, String? subjectId, [String? topicId]) {
  final s = subjects.where((s) => s.id == subjectId).firstOrNull;
  if (s == null) return '';
  final t = s.topics.where((t) => t.id == topicId).firstOrNull;
  return t == null ? s.name : '${s.name} · ${t.name}';
}

enum HeaderMode { exam, test }

/// Yazılı / test oluşturma ve düzenleme formu sonucu
typedef HeaderResult = ({
  String groupId,
  String subjectId,
  String? topicId,
  String? title,
  DateTime heldOn,
  int? questionCount,
});

Future<HeaderResult?> showHeaderDialog(
  BuildContext context, {
  required HeaderMode mode,
  String? groupId,
  String? subjectId,
  String? topicId,
  String? title,
  DateTime? heldOn,
  int? questionCount,
  bool editing = false,
}) =>
    showDialog<HeaderResult>(
      context: context,
      builder: (_) => _HeaderDialog(
        mode: mode,
        groupId: groupId,
        subjectId: subjectId,
        topicId: topicId,
        title: title,
        heldOn: heldOn,
        questionCount: questionCount,
        editing: editing,
      ),
    );

class _HeaderDialog extends ConsumerStatefulWidget {
  const _HeaderDialog({
    required this.mode,
    required this.editing,
    this.groupId,
    this.subjectId,
    this.topicId,
    this.title,
    this.heldOn,
    this.questionCount,
  });

  final HeaderMode mode;
  final bool editing;
  final String? groupId;
  final String? subjectId;
  final String? topicId;
  final String? title;
  final DateTime? heldOn;
  final int? questionCount;

  @override
  ConsumerState<_HeaderDialog> createState() => _HeaderDialogState();
}

class _HeaderDialogState extends ConsumerState<_HeaderDialog> {
  final _form = GlobalKey<FormState>();
  late String? _group = widget.groupId;
  late String? _subject = widget.subjectId;
  late String? _topic = widget.topicId;
  late DateTime _date = widget.heldOn ?? session.ctx.today;
  late final _title = TextEditingController(text: widget.title);
  late final _count = TextEditingController(text: widget.questionCount?.toString() ?? '');

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(myStudyGroupsProvider).value ?? const <Group>[];
    final subjects = ref.watch(subjectsProvider).value ?? const <Subject>[];
    _group ??= groups.length == 1 ? groups.first.id : null;
    final topics = subjects.where((s) => s.id == _subject).firstOrNull?.topics ?? const <Topic>[];
    final isTest = widget.mode == HeaderMode.test;

    return AlertDialog(
      title: Text(widget.editing ? 'Düzenle' : (isTest ? 'Yeni test' : 'Yeni yazılı')),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _group,
                  decoration: const InputDecoration(labelText: 'Etüt grubu'),
                  validator: (v) => v == null ? 'Grup seçin' : null,
                  items: [for (final g in groups) DropdownMenuItem(value: g.id, child: Text(g.name))],
                  onChanged: widget.editing ? null : (v) => setState(() => _group = v),
                ),
                const SizedBox(height: 12),
                if (subjects.isEmpty)
                  const Text('Önce yönetim panelinden ders tanımlanmalı.')
                else
                  DropdownButtonFormField<String>(
                    initialValue: _subject,
                    decoration: const InputDecoration(labelText: 'Ders'),
                    validator: (v) => v == null ? 'Ders seçin' : null,
                    items: [for (final s in subjects) DropdownMenuItem(value: s.id, child: Text(s.name))],
                    onChanged: widget.editing
                        ? null
                        : (v) => setState(() {
                              _subject = v;
                              _topic = null;
                            }),
                  ),
                if (topics.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    key: ValueKey(_subject),
                    initialValue: _topic,
                    decoration: const InputDecoration(labelText: 'Konu (isteğe bağlı)'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('— Genel —')),
                      for (final t in topics) DropdownMenuItem<String?>(value: t.id, child: Text(t.name)),
                    ],
                    onChanged: (v) => setState(() => _topic = v),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _title,
                  decoration: InputDecoration(
                    labelText: 'Başlık (isteğe bağlı)',
                    hintText: isTest ? 'örn. Türev Tarama Testi' : 'örn. 1. Dönem 1. Yazılı',
                  ),
                ),
                if (isTest) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _count,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return n == null || n < 1 || n > 500 ? '1-500 arası' : null;
                    },
                    decoration: const InputDecoration(labelText: 'Soru sayısı'),
                  ),
                ],
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event),
                  title: Text(formatDay(_date)),
                  subtitle: const Text('Sınav tarihi'),
                  onTap: () async {
                    final today = session.ctx.today;
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(today.year - 2),
                      lastDate: today,
                    );
                    if (picked != null) setState(() => _date = picked);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: subjects.isEmpty
              ? null
              : () {
                  if (!_form.currentState!.validate()) return;
                  Navigator.pop<HeaderResult>(context, (
                    groupId: _group!,
                    subjectId: _subject!,
                    topicId: _topic,
                    title: _title.text,
                    heldOn: _date,
                    questionCount: int.tryParse(_count.text),
                  ));
                },
          child: Text(widget.editing ? 'Kaydet' : 'Oluştur'),
        ),
      ],
    );
  }
}

/// Liste kartı: tarih kutusu + başlık + özet
class AcademicCard extends StatelessWidget {
  const AcademicCard({super.key, required this.date, required this.title, required this.subtitle, this.trailing, required this.onTap});

  final DateTime date;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 52,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
                child: Column(
                  children: [
                    Text('${date.day}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer)),
                    Text(formatDayShort(date).split(' ').last, style: TextStyle(fontSize: 11, color: scheme.onPrimaryContainer)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              ?trailing,
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// Küçük sayı giriş kutusu (not, doğru, yanlış)
class NumberBox extends StatelessWidget {
  const NumberBox({
    super.key,
    required this.initial,
    required this.onChanged,
    required this.label,
    this.max,
    this.width = 64,
    this.decimal = false,
    this.error = false,
  });

  final String initial;
  final ValueChanged<String> onChanged;
  final String label;
  final int? max;
  final double width;
  final bool decimal;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextFormField(
        initialValue: initial,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [
          decimal ? FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')) : FilteringTextInputFormatter.digitsOnly,
        ],
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          enabledBorder: error ? OutlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.error)) : null,
          focusedBorder: error ? OutlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.error, width: 2)) : null,
        ),
        onChanged: onChanged,
      ),
    );
  }
}

/// Özet istatistik satırı
class StatsBar extends StatelessWidget {
  const StatsBar({super.key, required this.items});

  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (label, value) in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Text(label, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
      ],
    );
  }
}

/// "#1" sıra rozeti
class RankBadge extends StatelessWidget {
  const RankBadge(this.rank, {super.key});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final medal = switch (rank) {
      1 => const Color(0xFFD4A017),
      2 => const Color(0xFF9E9E9E),
      3 => const Color(0xFFB0773C),
      _ => null,
    };
    return CircleAvatar(
      radius: 16,
      backgroundColor: medal ?? Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Text('$rank', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: medal != null ? Colors.white : null)),
    );
  }
}

/// Bir grubun not/sonuç giriş listesindeki öğrenciler: güncel üyeler + sonucu olan eski üyeler.
List<Student> rosterWithResults(List<Student> allStudents, List<Membership> memberships, String groupId, Set<String> withResults) {
  final members = memberships.where((m) => m.groupId == groupId).map((m) => m.studentId).toSet();
  return allStudents
      .where((s) => withResults.contains(s.id) || (members.contains(s.id) && s.status == StudentStatus.active))
      .toList()
    ..sort((a, b) => a.fullName.compareTo(b.fullName));
}
