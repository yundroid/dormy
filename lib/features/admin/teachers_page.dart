import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/session.dart';
import '../../core/supabase.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/person_dialogs.dart';

class TeachersPage extends ConsumerWidget {
  const TeachersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(staffProvider);
    final groups = ref.watch(groupsProvider).value ?? const <Group>[];
    final groupTeachers = ref.watch(groupTeachersProvider).value ?? const <String, Set<String>>{};
    final tenant = session.ctx.tenant!;

    Future<void> invite() async {
      final ok = await showInviteDialog(context, tenantId: tenant.id, role: UserRole.teacher);
      if (ok) ref.invalidate(staffProvider);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Öğretmenler')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: invite,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Öğretmen davet et'),
      ),
      body: AsyncView(
        value: staffAsync,
        onRetry: () => ref.invalidate(staffProvider),
        builder: (staff) {
          final teachers = staff.where((p) => p.role == UserRole.teacher).toList();
          final admins = staff.where((p) => p.role == UserRole.admin).toList();
          final activeTeachers = teachers.where((p) => p.isActive).length;

          List<String> groupsOf(String id) => [
                for (final g in groups)
                  if (groupTeachers[g.id]?.contains(id) ?? false) g.name,
              ];

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(staffProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                ContentWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Öğretmen kotası: ${quotaLabel(activeTeachers, tenant.maxTeachers)}',
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 12),
                      _Section(title: 'Yöneticiler', people: admins, groupsOf: groupsOf),
                      const SizedBox(height: 16),
                      if (teachers.isEmpty)
                        const EmptyState(
                          icon: Icons.badge_outlined,
                          title: 'Henüz öğretmen yok',
                          message: 'Öğretmenlerinizi e-posta ile davet edin. Davet edilen kişi kendi şifresini belirler.',
                        )
                      else
                        _Section(title: 'Öğretmenler', people: teachers, groupsOf: groupsOf),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.people, required this.groupsOf});

  final String title;
  final List<Profile> people;
  final List<String> Function(String id) groupsOf;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < people.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _PersonTile(person: people[i], groups: groupsOf(people[i].id)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PersonTile extends ConsumerWidget {
  const _PersonTile({required this.person, required this.groups});

  final Profile person;
  final List<String> groups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMe = person.id == currentUserId;
    final canManage = person.role == UserRole.teacher && !isMe;
    final badges = <Widget>[
      if (!person.isActive) const StatusBadge(label: 'Pasif', color: Colors.grey),
      if (person.isActive && !person.passwordSet) const StatusBadge(label: 'Davet bekliyor', color: Colors.orange),
      if (isMe) const StatusBadge(label: 'Siz', color: Colors.blue),
    ];

    Future<void> act(String action) async {
      switch (action) {
        case 'edit':
          final ok = await showEditPersonDialog(context, person);
          if (ok) ref.invalidate(staffProvider);
        case 'resend':
          await runAction(context, () => Repo.sendPasswordReset(person.email),
              success: '${person.email} adresine şifre belirleme bağlantısı gönderildi');
        case 'toggle':
          final disable = person.isActive;
          if (disable &&
              !await confirm(context,
                  title: 'Öğretmeni pasifleştir',
                  message: '${person.fullName} artık giriş yapamayacak. Girdiği veriler korunur.',
                  confirmLabel: 'Pasifleştir',
                  destructive: true)) {
            return;
          }
          if (!context.mounted) return;
          final ok = await runAction(
            context,
            () => Repo.setProfileStatus(person.id, disable ? AccountStatus.disabled : AccountStatus.active),
            success: disable ? 'Öğretmen pasifleştirildi' : 'Öğretmen aktifleştirildi',
          );
          if (ok) ref.invalidate(staffProvider);
      }
    }

    return ListTile(
      leading: CircleAvatar(child: Text(person.fullName.characters.first.toUpperCase())),
      title: Row(
        children: [
          Flexible(child: Text(person.fullName, overflow: TextOverflow.ellipsis)),
          for (final b in badges) Padding(padding: const EdgeInsets.only(left: 6), child: b),
        ],
      ),
      subtitle: Text([
        person.email,
        if (person.phone != null) person.phone!,
        if (groups.isNotEmpty) 'Gruplar: ${groups.join(', ')}',
        'Son giriş: ${formatLastActivity(person.lastSeenAt)}',
      ].join('\n')),
      isThreeLine: true,
      trailing: canManage
          ? PopupMenuButton<String>(
              onSelected: act,
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                if (!person.passwordSet && person.isActive)
                  const PopupMenuItem(value: 'resend', child: Text('Daveti tekrar gönder')),
                PopupMenuItem(value: 'toggle', child: Text(person.isActive ? 'Pasifleştir' : 'Aktifleştir')),
              ],
            )
          : null,
    );
  }
}
