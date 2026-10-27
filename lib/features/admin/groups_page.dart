import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class GroupsPage extends ConsumerWidget {
  const GroupsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: GroupKind.values.length,
      child: Builder(builder: (context) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Gruplar'),
            bottom: TabBar(tabs: [for (final k in GroupKind.values) Tab(text: k.pluralLabel)]),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () async {
              final kind = GroupKind.values[DefaultTabController.of(context).index];
              final ok = await showGroupDialog(context, kind: kind);
              if (ok) ref.invalidate(groupsProvider);
            },
            icon: const Icon(Icons.add),
            label: const Text('Grup ekle'),
          ),
          body: TabBarView(children: [for (final k in GroupKind.values) _GroupList(kind: k)]),
        );
      }),
    );
  }
}

class _GroupList extends ConsumerWidget {
  const _GroupList({required this.kind});

  final GroupKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(groupsProvider);
    final memberships = ref.watch(membershipsProvider).value ?? const <Membership>[];
    final groupTeachers = ref.watch(groupTeachersProvider).value ?? const <String, Set<String>>{};
    final staff = {for (final p in ref.watch(staffProvider).value ?? const <Profile>[]) p.id: p};

    return AsyncView(
      value: groupsAsync,
      onRetry: () => ref.invalidate(groupsProvider),
      builder: (all) {
        final groups = all.where((g) => g.kind == kind).toList()
          ..sort((a, b) => a.isArchived == b.isArchived ? a.name.compareTo(b.name) : (a.isArchived ? 1 : -1));
        if (groups.isEmpty) {
          return EmptyState(
            icon: Icons.workspaces_outline,
            title: 'Henüz ${kind.label.toLowerCase()} yok',
            message: kind == GroupKind.study
                ? 'Etüt grupları; etüt puanlama, yazılı, test ve kitap takibi için kullanılır.'
                : 'Dahili ders grupları, dahili ders puanlaması için kullanılır.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: groups.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final g = groups[i];
            final studentCount = memberships.where((m) => m.groupId == g.id).length;
            final teachers = (groupTeachers[g.id] ?? const <String>{}).map((id) => staff[id]?.fullName ?? '?').toList();
            return ContentWidth(
              child: Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text('$studentCount')),
                  title: Row(
                    children: [
                      Flexible(child: Text(g.name)),
                      if (g.isArchived) ...[
                        const SizedBox(width: 6),
                        const StatusBadge(label: 'Arşiv', color: Colors.grey),
                      ],
                    ],
                  ),
                  subtitle: Text(teachers.isEmpty ? 'Öğretmen atanmamış' : teachers.join(', ')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/admin/groups/${g.id}'),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

Future<bool> showGroupDialog(BuildContext context, {required GroupKind kind, Group? group}) async {
  final name = TextEditingController(text: group?.name);
  final desc = TextEditingController(text: group?.description);
  final form = GlobalKey<FormState>();
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(group == null ? 'Yeni ${kind.label}' : 'Grubu düzenle'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                autofocus: true,
                validator: requiredValidator,
                decoration: InputDecoration(labelText: 'Grup adı', hintText: kind == GroupKind.study ? 'örn. 9. Sınıf Etüdü' : 'örn. Dahili-1'),
              ),
              const SizedBox(height: 12),
              TextFormField(controller: desc, decoration: const InputDecoration(labelText: 'Açıklama (isteğe bağlı)')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
        BusyButton(
          label: 'Kaydet',
          onPressed: () async {
            if (!form.currentState!.validate()) return;
            final ok = await runAction(
              ctx,
              () => Repo.saveGroup(id: group?.id, kind: kind, name: name.text, description: desc.text),
            );
            if (ok && ctx.mounted) Navigator.pop(ctx, true);
          },
        ),
      ],
    ),
  );
  return result ?? false;
}

// ---------------------------------------------------------------------------

class GroupDetailPage extends ConsumerWidget {
  const GroupDetailPage({super.key, required this.groupId});

  final String groupId;

  void _refresh(WidgetRef ref) {
    ref.invalidate(groupsProvider);
    ref.invalidate(membershipsProvider);
    ref.invalidate(groupTeachersProvider);
    ref.invalidate(myGroupKindsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsProvider);
    final students = ref.watch(studentsProvider).value ?? const <Student>[];
    final memberships = ref.watch(membershipsProvider).value ?? const <Membership>[];
    final teachersMap = ref.watch(groupTeachersProvider).value ?? const <String, Set<String>>{};
    final staff = ref.watch(staffProvider).value ?? const <Profile>[];

    return AsyncView(
      value: groups,
      builder: (all) {
        final g = all.where((x) => x.id == groupId).firstOrNull;
        if (g == null) {
          return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.search_off, title: 'Grup bulunamadı'));
        }
        final teacherIds = teachersMap[g.id] ?? const <String>{};
        final memberIds = memberships.where((m) => m.groupId == g.id).map((m) => m.studentId).toSet();
        final members = students.where((s) => memberIds.contains(s.id)).toList();
        final otherGroupOf = {
          for (final m in memberships.where((m) => m.kind == g.kind && m.groupId != g.id)) m.studentId: m.groupId,
        };
        final groupNames = {for (final x in all) x.id: x.name};
        final eligibleTeachers = staff.where((p) => p.isActive).toList();

        Future<void> editTeachers() async {
          final selected = await showDialog<Set<String>>(
            context: context,
            builder: (_) => _MultiSelectDialog(
              title: 'Grubun öğretmenleri',
              options: {for (final p in eligibleTeachers) p.id: '${p.fullName}${p.role == UserRole.admin ? ' (Yönetici)' : ''}'},
              selected: teacherIds,
            ),
          );
          if (selected == null || !context.mounted) return;
          await runAction(context, () => Repo.setGroupTeachers(g.id, teacherIds, selected), success: 'Öğretmenler güncellendi');
          _refresh(ref);
        }

        Future<void> addStudents() async {
          final candidates = students.where((s) => s.status == StudentStatus.active && !memberIds.contains(s.id)).toList();
          final selected = await showDialog<Set<String>>(
            context: context,
            builder: (_) => _MultiSelectDialog(
              title: 'Gruba öğrenci ekle',
              searchable: true,
              options: {
                for (final s in candidates)
                  s.id: otherGroupOf.containsKey(s.id) ? '${s.fullName}  (şu an: ${groupNames[otherGroupOf[s.id]]})' : s.fullName,
              },
              selected: const {},
            ),
          );
          if (selected == null || selected.isEmpty || !context.mounted) return;
          await runAction(context, () async {
            for (final id in selected) {
              await Repo.assignStudentGroup(id, g.kind, g.id);
            }
          }, success: '${selected.length} öğrenci eklendi');
          _refresh(ref);
        }

        Future<void> removeStudent(Student s) async {
          await runAction(context, () => Repo.assignStudentGroup(s.id, g.kind, null), success: '${s.fullName} gruptan çıkarıldı');
          _refresh(ref);
        }

        Future<void> menu(String action) async {
          switch (action) {
            case 'edit':
              if (await showGroupDialog(context, kind: g.kind, group: g)) _refresh(ref);
            case 'archive':
              await runAction(context, () => Repo.setGroupArchived(g.id, !g.isArchived),
                  success: g.isArchived ? 'Grup arşivden çıkarıldı' : 'Grup arşivlendi');
              _refresh(ref);
            case 'delete':
              final yes = await confirm(
                context,
                title: 'Grubu sil',
                message: '"${g.name}" grubu ve üyelik geçmişi silinecek. Öğrencilerin girilmiş puanları korunur.',
                confirmLabel: 'Sil',
                destructive: true,
              );
              if (!yes || !context.mounted) return;
              final ok = await runAction(context, () => Repo.deleteGroup(g.id), success: 'Grup silindi');
              _refresh(ref);
              if (ok && context.mounted) context.pop();
          }
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(g.name),
            actions: [
              PopupMenuButton<String>(
                onSelected: menu,
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                  PopupMenuItem(value: 'archive', child: Text(g.isArchived ? 'Arşivden çıkar' : 'Arşivle')),
                  const PopupMenuItem(value: 'delete', child: Text('Sil')),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(g.kind.label, style: Theme.of(context).textTheme.labelLarge),
                    if (g.description != null) Text(g.description!),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text('Öğretmenler', style: Theme.of(context).textTheme.titleMedium),
                        const Spacer(),
                        TextButton.icon(onPressed: editTeachers, icon: const Icon(Icons.edit, size: 18), label: const Text('Düzenle')),
                      ],
                    ),
                    Card(
                      child: teacherIds.isEmpty
                          ? const ListTile(title: Text('Öğretmen atanmamış'))
                          : Column(
                              children: [
                                for (final p in staff.where((p) => teacherIds.contains(p.id)))
                                  ListTile(leading: const Icon(Icons.badge_outlined), title: Text(p.fullName), subtitle: Text(p.email)),
                              ],
                            ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text('Öğrenciler (${members.length})', style: Theme.of(context).textTheme.titleMedium),
                        const Spacer(),
                        if (!g.isArchived)
                          TextButton.icon(onPressed: addStudents, icon: const Icon(Icons.person_add_alt, size: 18), label: const Text('Ekle')),
                      ],
                    ),
                    Card(
                      child: members.isEmpty
                          ? const ListTile(title: Text('Grupta öğrenci yok'))
                          : Column(
                              children: [
                                for (final s in members)
                                  ListTile(
                                    title: Text(s.fullName),
                                    subtitle: s.roomNo == null ? null : Text('Oda ${s.roomNo}'),
                                    trailing: IconButton(
                                      tooltip: 'Gruptan çıkar',
                                      icon: const Icon(Icons.remove_circle_outline),
                                      onPressed: () => removeStudent(s),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Bir öğrenci aynı anda yalnızca bir ${g.kind.label.toLowerCase()} üyesi olabilir. '
                      'Başka gruba eklenen öğrenci önceki gruptan otomatik çıkarılır; geçmiş kayıtları korunur.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MultiSelectDialog extends StatefulWidget {
  const _MultiSelectDialog({required this.title, required this.options, required this.selected, this.searchable = false});

  final String title;
  final Map<String, String> options;
  final Set<String> selected;
  final bool searchable;

  @override
  State<_MultiSelectDialog> createState() => _MultiSelectDialogState();
}

class _MultiSelectDialogState extends State<_MultiSelectDialog> {
  late final Set<String> _selected = {...widget.selected};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final entries = widget.options.entries.where((e) => e.value.toLowerCase().contains(_q.toLowerCase())).toList();
    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            if (widget.searchable)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  onChanged: (v) => setState(() => _q = v),
                  decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search), hintText: 'Ara'),
                ),
              ),
            Expanded(
              child: entries.isEmpty
                  ? const Center(child: Text('Seçilebilecek kayıt yok'))
                  : ListView(
                      children: [
                        for (final e in entries)
                          CheckboxListTile(
                            value: _selected.contains(e.key),
                            title: Text(e.value),
                            onChanged: (v) => setState(() => v == true ? _selected.add(e.key) : _selected.remove(e.key)),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(context, _selected), child: Text('Tamam (${_selected.length})')),
      ],
    );
  }
}
