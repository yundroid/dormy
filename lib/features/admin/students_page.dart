import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class StudentsPage extends ConsumerStatefulWidget {
  const StudentsPage({super.key});

  @override
  ConsumerState<StudentsPage> createState() => _StudentsPageState();
}

class _StudentsPageState extends ConsumerState<StudentsPage> {
  String _search = '';
  StudentStatus _status = StudentStatus.active;

  @override
  Widget build(BuildContext context) {
    final studentsAsync = ref.watch(studentsProvider);
    final groups = {for (final g in ref.watch(groupsProvider).value ?? const <Group>[]) g.id: g};
    final memberships = ref.watch(membershipsProvider).value ?? const <Membership>[];
    final tenant = session.ctx.tenant!;

    final byStudent = <String, List<String>>{};
    for (final m in memberships) {
      final g = groups[m.groupId];
      if (g != null) byStudent.putIfAbsent(m.studentId, () => []).add(g.name);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Öğrenciler')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/admin/students/new'),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Öğrenci ekle'),
      ),
      body: AsyncView(
        value: studentsAsync,
        onRetry: () => ref.invalidate(studentsProvider),
        builder: (all) {
          final activeCount = all.where((s) => s.status == StudentStatus.active).length;
          final q = _search.trim().toLowerCase();
          final list = all.where((s) {
            if (s.status != _status) return false;
            if (q.isEmpty) return true;
            return s.fullName.toLowerCase().contains(q) ||
                (s.roomNo?.toLowerCase().contains(q) ?? false) ||
                (s.schoolGrade?.toLowerCase().contains(q) ?? false);
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: ContentWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        onChanged: (v) => setState(() => _search = v),
                        decoration: const InputDecoration(
                          isDense: true,
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Ad, oda veya sınıf ara',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          for (final s in StudentStatus.values) ...[
                            ChoiceChip(
                              label: Text(s.label),
                              selected: _status == s,
                              onSelected: (_) => setState(() => _status = s),
                            ),
                            const SizedBox(width: 6),
                          ],
                          const Spacer(),
                          Text('Kota: ${quotaLabel(activeCount, tenant.maxStudents)}',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? EmptyState(
                        icon: Icons.groups_outlined,
                        title: all.isEmpty ? 'Henüz öğrenci eklenmemiş' : 'Eşleşen öğrenci yok',
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          ref.invalidate(studentsProvider);
                          ref.invalidate(membershipsProvider);
                        },
                        child: ListView.separated(
                          padding: const EdgeInsets.only(bottom: 96),
                          itemCount: list.length,
                          separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                          itemBuilder: (context, i) {
                            final s = list[i];
                            final info = [
                              if (s.roomNo != null) 'Oda ${s.roomNo}',
                              if (s.schoolGrade != null) s.schoolGrade!,
                              ...?byStudent[s.id],
                            ].join(' · ');
                            return ContentWidth(
                              child: ListTile(
                                leading: CircleAvatar(child: Text(s.firstName.characters.first.toUpperCase())),
                                title: Text(s.fullName),
                                subtitle: info.isEmpty ? null : Text(info),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => context.push('/admin/students/${s.id}'),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class StudentFormPage extends ConsumerStatefulWidget {
  const StudentFormPage({super.key, this.studentId});

  final String? studentId;

  @override
  ConsumerState<StudentFormPage> createState() => _StudentFormPageState();
}

class _StudentFormPageState extends ConsumerState<StudentFormPage> {
  final _form = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _grade = TextEditingController();
  final _room = TextEditingController();
  final _phone = TextEditingController();
  final _guardian = TextEditingController();
  final _guardianPhone = TextEditingController();
  final _notes = TextEditingController();
  StudentStatus _status = StudentStatus.active;
  final Map<GroupKind, String?> _groups = {};
  final Map<GroupKind, String?> _initialGroups = {};
  bool _loaded = false;

  bool get _isNew => widget.studentId == null;

  void _load(Student? s, List<Membership> memberships) {
    if (_loaded) return;
    _loaded = true;
    if (s != null) {
      _first.text = s.firstName;
      _last.text = s.lastName;
      _grade.text = s.schoolGrade ?? '';
      _room.text = s.roomNo ?? '';
      _phone.text = s.phone ?? '';
      _guardian.text = s.guardianName ?? '';
      _guardianPhone.text = s.guardianPhone ?? '';
      _notes.text = s.notes ?? '';
      _status = s.status;
    }
    for (final kind in GroupKind.values) {
      final m = memberships.where((m) => m.studentId == widget.studentId && m.kind == kind).firstOrNull;
      _groups[kind] = m?.groupId;
      _initialGroups[kind] = m?.groupId;
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final ok = await runAction(context, () async {
      final id = await Repo.saveStudent(
        id: widget.studentId,
        firstName: _first.text,
        lastName: _last.text,
        schoolGrade: _grade.text,
        roomNo: _room.text,
        phone: _phone.text,
        guardianName: _guardian.text,
        guardianPhone: _guardianPhone.text,
        notes: _notes.text,
        status: _status,
      );
      if (_status == StudentStatus.active) {
        for (final kind in GroupKind.values) {
          if (_groups[kind] != _initialGroups[kind]) {
            await Repo.assignStudentGroup(id, kind, _groups[kind]);
          }
        }
      }
    }, success: _isNew ? 'Öğrenci eklendi' : 'Öğrenci güncellendi');
    ref.invalidate(studentsProvider);
    ref.invalidate(membershipsProvider);
    if (ok && mounted) context.pop();
  }

  Future<void> _delete(Student s) async {
    final yes = await confirm(
      context,
      title: 'Öğrenciyi sil',
      message: '${s.fullName} ve öğrenciye ait TÜM kontrol kayıtları kalıcı olarak silinecek. '
          'Geçmiş raporları korumak için "Ayrıldı" veya "Mezun" durumuna almanız önerilir.',
      confirmLabel: 'Kalıcı olarak sil',
      destructive: true,
    );
    if (!yes || !mounted) return;
    final ok = await runAction(context, () => Repo.deleteStudent(s.id), success: 'Öğrenci silindi');
    ref.invalidate(studentsProvider);
    ref.invalidate(membershipsProvider);
    if (ok && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final students = ref.watch(studentsProvider);
    final memberships = ref.watch(membershipsProvider);
    final groups = ref.watch(groupsProvider);

    if (!students.hasValue || !memberships.hasValue || !groups.hasValue) {
      final err = students.error ?? memberships.error ?? groups.error;
      return Scaffold(
        appBar: AppBar(),
        body: err != null ? ErrorView(message: err.toString()) : const Center(child: CircularProgressIndicator()),
      );
    }
    final student = _isNew ? null : students.value!.where((s) => s.id == widget.studentId).firstOrNull;
    if (!_isNew && student == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.search_off, title: 'Öğrenci bulunamadı'));
    }
    _load(student, memberships.value!);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Yeni Öğrenci' : student!.fullName),
        actions: [
          if (!_isNew)
            IconButton(tooltip: 'Sil', onPressed: () => _delete(student!), icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ContentWidth(
          maxWidth: 640,
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _first,
                        validator: requiredValidator,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Ad'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _last,
                        validator: requiredValidator,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Soyad'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(controller: _grade, decoration: const InputDecoration(labelText: 'Okul sınıfı (örn. 10-A)')),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: TextFormField(controller: _room, decoration: const InputDecoration(labelText: 'Oda no'))),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Öğrenci telefonu')),
                const SizedBox(height: 20),
                Text('Veli', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                TextFormField(controller: _guardian, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Veli ad soyad')),
                const SizedBox(height: 12),
                TextFormField(controller: _guardianPhone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Veli telefonu')),
                const SizedBox(height: 20),
                Text('Gruplar', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                for (final kind in GroupKind.values) ...[
                  DropdownButtonFormField<String?>(
                    initialValue: _groups[kind],
                    decoration: InputDecoration(labelText: kind.label),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('— Atanmamış —')),
                      for (final g in groups.value!.where((g) => g.kind == kind && (!g.isArchived || g.id == _groups[kind])))
                        DropdownMenuItem<String?>(value: g.id, child: Text(g.name)),
                    ],
                    onChanged: _status == StudentStatus.active ? (v) => setState(() => _groups[kind] = v) : null,
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 8),
                Text('Durum', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<StudentStatus>(
                  segments: [for (final s in StudentStatus.values) ButtonSegment(value: s, label: Text(s.label))],
                  selected: {_status},
                  onSelectionChanged: (s) => setState(() => _status = s.first),
                ),
                if (_status != StudentStatus.active)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Aktif olmayan öğrenciler kontrol listelerinde görünmez; geçmiş kayıtları korunur.',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                const SizedBox(height: 12),
                TextFormField(controller: _notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Notlar')),
                const SizedBox(height: 20),
                BusyButton(onPressed: _save, label: 'Kaydet', icon: Icons.save),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
