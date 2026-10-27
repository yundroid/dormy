import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/session.dart';
import '../../core/supabase.dart';
import '../../data/academics_repository.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../share/share_table.dart';
import 'academic_widgets.dart';

Color bookStatusColor(BookStatus s) => switch (s) {
      BookStatus.assigned => Colors.blueGrey,
      BookStatus.reading => Colors.blue,
      BookStatus.finished => Colors.green,
      BookStatus.dropped => Colors.grey,
    };

class BooksPage extends ConsumerStatefulWidget {
  const BooksPage({super.key});

  @override
  ConsumerState<BooksPage> createState() => _BooksPageState();
}

class _BooksPageState extends ConsumerState<BooksPage> {
  String? _group;

  void _reload() {
    ref.invalidate(booksProvider);
    ref.invalidate(bookAssignmentsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(myStudyGroupsProvider);
    final students = ref.watch(studentsProvider).value ?? const <Student>[];
    final memberships = ref.watch(membershipsProvider).value ?? const <Membership>[];

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kitap Takibi'),
          bottom: const TabBar(tabs: [Tab(text: 'Okumalar'), Tab(text: 'Bitirilenler'), Tab(text: 'Kitaplar')]),
        ),
        body: AsyncView(
          value: groupsAsync,
          builder: (groups) {
            if (groups.isEmpty) return const NoStudyGroup();
            final groupIds = (_group == null ? groups.map((g) => g.id) : [_group!]).toSet();
            final myStudentIds = memberships.where((m) => groupIds.contains(m.groupId)).map((m) => m.studentId).toSet();
            final myStudents = students.where((s) => myStudentIds.contains(s.id) && s.status == StudentStatus.active).toList()
              ..sort((a, b) => a.fullName.compareTo(b.fullName));
            return Column(
              children: [
                GroupFilter(groups: groups, selected: _group, onChanged: (g) => setState(() => _group = g)),
                Expanded(
                  child: TabBarView(
                    children: [
                      _ReadingTab(students: myStudents, onChanged: _reload),
                      _FinishedTab(students: myStudents, groupName: _group == null ? null : groups.firstWhere((g) => g.id == _group).name),
                      _CatalogTab(onChanged: _reload),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ReadingTab extends ConsumerWidget {
  const _ReadingTab({required this.students, required this.onChanged});

  final List<Student> students;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignments = ref.watch(bookAssignmentsProvider);
    final books = {for (final b in ref.watch(booksProvider).value ?? const <Book>[]) b.id: b};

    Future<void> assign() async {
      final ok = await showDialog<bool>(context: context, builder: (_) => _AssignDialog(students: students));
      if (ok == true) onChanged();
    }

    return Scaffold(
      floatingActionButton: students.isEmpty
          ? null
          : FloatingActionButton.extended(onPressed: assign, icon: const Icon(Icons.add), label: const Text('Kitap ata')),
      body: AsyncView(
        value: assignments,
        onRetry: onChanged,
        builder: (all) {
          if (students.isEmpty) return const EmptyState(icon: Icons.groups_outlined, title: 'Grupta öğrenci yok');
          final byStudent = <String, List<BookAssignment>>{};
          for (final a in all) {
            byStudent.putIfAbsent(a.studentId, () => []).add(a);
          }
          return RefreshIndicator(
            onRefresh: () async => onChanged(),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: students.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final s = students[i];
                final list = byStudent[s.id] ?? const <BookAssignment>[];
                final open = list.where((a) => a.isOpen).toList();
                final finished = list.where((a) => a.status == BookStatus.finished).length;
                return ContentWidth(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ListTile(
                            title: Text(s.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                            trailing: StatusBadge(label: '$finished kitap bitirdi', color: Colors.green),
                          ),
                          if (open.isEmpty)
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Text('Okuduğu kitap yok', style: TextStyle(color: Colors.grey)),
                            ),
                          for (final a in open)
                            _AssignmentTile(assignment: a, book: books[a.bookId], onChanged: onChanged),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _AssignmentTile extends StatelessWidget {
  const _AssignmentTile({required this.assignment, required this.book, required this.onChanged});

  final BookAssignment assignment;
  final Book? book;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final a = assignment;
    final pages = book?.pageCount;
    final progress = pages == null || pages == 0 ? null : (a.pagesRead / pages).clamp(0.0, 1.0);
    return ListTile(
      dense: true,
      leading: const Icon(Icons.menu_book_outlined),
      title: Text(book?.title ?? '?'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text([
            a.status.label,
            if (pages != null) '${a.pagesRead}/$pages sayfa' else if (a.pagesRead > 0) '${a.pagesRead} sayfa',
            'Atandı: ${formatDayShort(a.assignedOn)}',
          ].join(' · ')),
          if (progress != null) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(value: progress, minHeight: 4, borderRadius: BorderRadius.circular(2)),
          ],
        ],
      ),
      trailing: const Icon(Icons.edit_outlined, size: 18),
      onTap: () async {
        final ok = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          builder: (_) => _ProgressSheet(assignment: a, book: book),
        );
        if (ok == true) onChanged();
      },
    );
  }
}

class _ProgressSheet extends StatefulWidget {
  const _ProgressSheet({required this.assignment, required this.book});

  final BookAssignment assignment;
  final Book? book;

  @override
  State<_ProgressSheet> createState() => _ProgressSheetState();
}

class _ProgressSheetState extends State<_ProgressSheet> {
  late BookStatus _status = widget.assignment.status;
  late final _pages = TextEditingController(text: '${widget.assignment.pagesRead}');
  late final _note = TextEditingController(text: widget.assignment.note);

  @override
  Widget build(BuildContext context) {
    final pageCount = widget.book?.pageCount;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.book?.title ?? '', style: Theme.of(context).textTheme.titleLarge),
          if (widget.book?.author != null) Text(widget.book!.author!),
          const SizedBox(height: 16),
          SegmentedButton<BookStatus>(
            segments: [for (final s in BookStatus.values) ButtonSegment(value: s, label: Text(s.label))],
            selected: {_status},
            onSelectionChanged: (s) => setState(() => _status = s.first),
          ),
          const SizedBox(height: 12),
          if (_status != BookStatus.finished)
            TextField(
              controller: _pages,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: 'Okunan sayfa', suffixText: pageCount == null ? null : '/ $pageCount'),
            ),
          const SizedBox(height: 12),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)')),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton.icon(
                onPressed: () async {
                  final yes = await confirm(context, title: 'Atamayı kaldır', message: 'Bu kitap ataması silinecek.', destructive: true, confirmLabel: 'Kaldır');
                  if (!yes || !context.mounted) return;
                  final ok = await runAction(context, () => AcademicsRepo.deleteAssignment(widget.assignment.id));
                  if (ok && context.mounted) Navigator.pop(context, true);
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Kaldır'),
              ),
              const Spacer(),
              BusyButton(
                label: 'Kaydet',
                onPressed: () async {
                  final ok = await runAction(
                    context,
                    () => AcademicsRepo.updateAssignment(
                      widget.assignment.id,
                      status: _status,
                      pagesRead: int.tryParse(_pages.text) ?? 0,
                      note: _note.text,
                    ),
                    success: 'Güncellendi',
                  );
                  if (ok && context.mounted) Navigator.pop(context, true);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AssignDialog extends ConsumerStatefulWidget {
  const _AssignDialog({required this.students});

  final List<Student> students;

  @override
  ConsumerState<_AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends ConsumerState<_AssignDialog> {
  String? _book;
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final books = ref.watch(booksProvider).value ?? const <Book>[];
    final assignments = ref.watch(bookAssignmentsProvider).value ?? const <BookAssignment>[];
    final already = {for (final a in assignments) if (a.bookId == _book) a.studentId};

    return AlertDialog(
      title: const Text('Kitap ata'),
      contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      content: SizedBox(
        width: 440,
        height: 480,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _book,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Kitap'),
                      items: [for (final b in books) DropdownMenuItem(value: b.id, child: Text(b.display, overflow: TextOverflow.ellipsis))],
                      onChanged: (v) => setState(() {
                        _book = v;
                        _selected.clear();
                      }),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Yeni kitap',
                    icon: const Icon(Icons.add),
                    onPressed: () async {
                      final id = await showBookDialog(context);
                      if (id != null) {
                        ref.invalidate(booksProvider);
                        setState(() => _book = id);
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              title: const Text('Tümünü seç'),
              value: _selected.length == widget.students.where((s) => !already.contains(s.id)).length && _selected.isNotEmpty,
              onChanged: _book == null
                  ? null
                  : (v) => setState(() {
                        _selected.clear();
                        if (v == true) _selected.addAll(widget.students.map((s) => s.id).where((id) => !already.contains(id)));
                      }),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: [
                  for (final s in widget.students)
                    CheckboxListTile(
                      title: Text(s.fullName),
                      subtitle: already.contains(s.id) ? const Text('Bu kitap zaten atanmış') : null,
                      value: already.contains(s.id) || _selected.contains(s.id),
                      onChanged: _book == null || already.contains(s.id)
                          ? null
                          : (v) => setState(() => v == true ? _selected.add(s.id) : _selected.remove(s.id)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
        BusyButton(
          label: 'Ata (${_selected.length})',
          onPressed: _book == null || _selected.isEmpty
              ? null
              : () async {
                  final ok = await runAction(context, () => AcademicsRepo.assignBook(_book!, _selected),
                      success: '${_selected.length} öğrenciye atandı');
                  if (ok && context.mounted) Navigator.pop(context, true);
                },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _FinishedTab extends ConsumerStatefulWidget {
  const _FinishedTab({required this.students, this.groupName});

  final List<Student> students;
  final String? groupName;

  @override
  ConsumerState<_FinishedTab> createState() => _FinishedTabState();
}

class _FinishedTabState extends ConsumerState<_FinishedTab> {
  DateTimeRange? _range;

  @override
  Widget build(BuildContext context) {
    final assignments = ref.watch(bookAssignmentsProvider).value ?? const <BookAssignment>[];
    final books = {for (final b in ref.watch(booksProvider).value ?? const <Book>[]) b.id: b};
    final ids = widget.students.map((s) => s.id).toSet();
    final finished = assignments.where((a) {
      if (a.status != BookStatus.finished || !ids.contains(a.studentId) || a.finishedOn == null) return false;
      if (_range == null) return true;
      return !a.finishedOn!.isBefore(_range!.start) && !a.finishedOn!.isAfter(_range!.end);
    }).toList();

    final byStudent = <String, List<BookAssignment>>{};
    for (final a in finished) {
      byStudent.putIfAbsent(a.studentId, () => []).add(a);
    }
    final rows = widget.students.map((s) {
      final list = byStudent[s.id] ?? const <BookAssignment>[];
      final pages = list.fold<int>(0, (t, a) => t + (books[a.bookId]?.pageCount ?? a.pagesRead));
      return (student: s, list: list, pages: pages);
    }).toList()
      ..sort((a, b) => b.list.length != a.list.length ? b.list.length.compareTo(a.list.length) : b.pages.compareTo(a.pages));

    final rangeLabel = _range == null ? 'Tüm zamanlar' : '${formatDay(_range!.start)} – ${formatDay(_range!.end)}';

    ShareTable table() => ShareTable(
          title: 'Okunan Kitaplar',
          subtitle: [if (widget.groupName != null) widget.groupName!, rangeLabel].join(' · '),
          columns: const ['Sıra', 'Öğrenci', 'Kitaplar', 'Kitap', 'Sayfa'],
          numericFrom: 3,
          rows: [
            for (final (i, r) in rows.indexed)
              ShareRow(studentId: r.student.id, cells: [
                '${i + 1}',
                r.student.fullName,
                r.list.map((a) => books[a.bookId]?.title ?? '?').join(', '),
                '${r.list.length}',
                '${r.pages}',
              ]),
          ],
        );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.date_range, size: 18),
                    label: Text(rangeLabel),
                    onPressed: () async {
                      final today = session.ctx.today;
                      final r = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(today.year - 3),
                        lastDate: today,
                        initialDateRange: _range,
                      );
                      if (r != null) setState(() => _range = r);
                    },
                  ),
                  if (_range != null) ActionChip(label: const Text('Temizle'), onPressed: () => setState(() => _range = null)),
                  FilledButton.tonalIcon(
                    onPressed: rows.isEmpty ? null : () => openSharePreview(context, table()),
                    icon: const Icon(Icons.share),
                    label: const Text('Paylaş'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('${finished.length} kitap bitirildi', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    for (final r in rows)
                      ExpansionTile(
                        shape: const Border(),
                        title: Text(r.student.fullName),
                        subtitle: Text('${r.list.length} kitap · ${r.pages} sayfa'),
                        children: [
                          for (final a in r.list)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.check_circle, color: Colors.green, size: 20),
                              title: Text(books[a.bookId]?.display ?? '?'),
                              trailing: Text(formatDayShort(a.finishedOn!)),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _CatalogTab extends ConsumerWidget {
  const _CatalogTab({required this.onChanged});

  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(booksProvider);
    final assignments = ref.watch(bookAssignmentsProvider).value ?? const <BookAssignment>[];
    final canEdit = session.ctx.isAdmin;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'book-add',
        onPressed: () async {
          if (await showBookDialog(context) != null) onChanged();
        },
        icon: const Icon(Icons.add),
        label: const Text('Kitap ekle'),
      ),
      body: AsyncView(
        value: books,
        onRetry: onChanged,
        builder: (list) {
          if (list.isEmpty) {
            return const EmptyState(icon: Icons.local_library_outlined, title: 'Kitap listesi boş', message: 'Yurt geneli ortak kitap listesine kitap ekleyin.');
          }
          return ListView.separated(
            padding: const EdgeInsets.only(top: 8, bottom: 96),
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
            itemBuilder: (context, i) {
              final b = list[i];
              final readers = assignments.where((a) => a.bookId == b.id).length;
              final mine = canEdit || b.createdBy == currentUserId;
              return ContentWidth(
                child: ListTile(
                  title: Text(b.title),
                  subtitle: Text([if (b.author != null) b.author!, if (b.pageCount != null) '${b.pageCount} sayfa', '$readers atama'].join(' · ')),
                  trailing: mine
                      ? PopupMenuButton<String>(
                          onSelected: (a) async {
                            if (a == 'edit') {
                              if (await showBookDialog(context, book: b) != null) onChanged();
                            } else {
                              final yes = await confirm(context, title: 'Kitabı sil', message: '"${b.title}" silinecek.', destructive: true, confirmLabel: 'Sil');
                              if (!yes || !context.mounted) return;
                              await runAction(context, () => AcademicsRepo.deleteBook(b.id), success: 'Kitap silindi');
                              onChanged();
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                            if (readers == 0) const PopupMenuItem(value: 'delete', child: Text('Sil')),
                          ],
                        )
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Kitap ekle / düzenle. Kaydedilen kitabın id'sini döner.
Future<String?> showBookDialog(BuildContext context, {Book? book}) {
  final form = GlobalKey<FormState>();
  final title = TextEditingController(text: book?.title);
  final author = TextEditingController(text: book?.author);
  final pages = TextEditingController(text: book?.pageCount?.toString());
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(book == null ? 'Yeni kitap' : 'Kitabı düzenle'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(controller: title, autofocus: true, validator: requiredValidator, decoration: const InputDecoration(labelText: 'Kitap adı')),
              const SizedBox(height: 12),
              TextFormField(controller: author, decoration: const InputDecoration(labelText: 'Yazar')),
              const SizedBox(height: 12),
              TextFormField(
                controller: pages,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Sayfa sayısı'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
        BusyButton(
          label: 'Kaydet',
          onPressed: () async {
            if (!form.currentState!.validate()) return;
            String? id;
            final ok = await runAction(ctx, () async {
              id = await AcademicsRepo.saveBook(
                id: book?.id,
                title: title.text,
                author: author.text,
                pageCount: int.tryParse(pages.text) == 0 ? null : int.tryParse(pages.text),
              );
            });
            if (ok && ctx.mounted) Navigator.pop(ctx, id);
          },
        ),
      ],
    ),
  );
}
