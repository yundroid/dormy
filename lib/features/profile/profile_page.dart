import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';
import '../../widgets/person_dialogs.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final c = session.contextOrNull;
        if (c == null) return const Scaffold(body: SizedBox.shrink());
        final p = c.profile;
        return Scaffold(
          appBar: AppBar(title: const Text('Profil')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ContentWidth(
                maxWidth: 600,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Text(p.fullName.characters.first.toUpperCase())),
                        title: Text(p.fullName),
                        subtitle: Text('${p.role.label}${c.tenant != null ? ' · ${c.tenant!.name}' : ''}\n${p.email}'
                            '${p.phone != null ? '\n${p.phone}' : ''}'),
                        isThreeLine: true,
                        trailing: IconButton(
                          tooltip: 'Düzenle',
                          icon: const Icon(Icons.edit),
                          onPressed: () async {
                            if (await showEditPersonDialog(context, p)) await session.refresh();
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.lock_reset),
                            title: const Text('Şifre değiştir'),
                            onTap: () => showDialog<void>(context: context, builder: (_) => const _ChangePasswordDialog()),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
                            title: Text('Çıkış yap', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                            onTap: () async {
                              if (await confirm(context, title: 'Çıkış', message: 'Oturumunuz kapatılacak.', confirmLabel: 'Çıkış yap')) {
                                await session.signOut();
                              }
                            },
                          ),
                        ],
                      ),
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

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Şifre değiştir'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(controller: _p1, obscureText: true, validator: passwordValidator, decoration: const InputDecoration(labelText: 'Yeni şifre')),
              const SizedBox(height: 12),
              TextFormField(
                controller: _p2,
                obscureText: true,
                validator: (v) => v != _p1.text ? 'Şifreler eşleşmiyor' : null,
                decoration: const InputDecoration(labelText: 'Yeni şifre (tekrar)'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        BusyButton(
          label: 'Kaydet',
          onPressed: () async {
            if (!_form.currentState!.validate()) return;
            final ok = await runAction(context, () => Repo.updatePassword(_p1.text), success: 'Şifreniz değiştirildi');
            if (ok && context.mounted) Navigator.pop(context);
          },
        ),
      ],
    );
  }
}
