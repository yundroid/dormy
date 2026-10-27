import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../models/models.dart';
import 'common.dart';

/// Öğretmen (admin tarafından) ya da yönetici (superadmin tarafından) davet eder.
Future<bool> showInviteDialog(BuildContext context, {required String tenantId, required UserRole role}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => _InviteDialog(tenantId: tenantId, role: role),
  );
  return result ?? false;
}

class _InviteDialog extends StatefulWidget {
  const _InviteDialog({required this.tenantId, required this.role});

  final String tenantId;
  final UserRole role;

  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final ok = await runAction(
      context,
      () => Repo.invite(
        tenantId: widget.tenantId,
        email: _email.text,
        fullName: _name.text,
        phone: _phone.text,
        role: widget.role,
      ),
      success: '${_email.text.trim()} adresine davet gönderildi',
    );
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.role.label} davet et'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                validator: requiredValidator,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Ad soyad'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                validator: emailValidator,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-posta'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Telefon (isteğe bağlı)'),
              ),
              const SizedBox(height: 12),
              Text(
                'Davet edilen kişiye e-posta ile bir bağlantı gönderilir; kişi bağlantıya tıklayıp kendi şifresini belirler.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
        BusyButton(onPressed: _submit, label: 'Davet gönder'),
      ],
    );
  }
}

Future<bool> showEditPersonDialog(BuildContext context, Profile person) async {
  final result = await showDialog<bool>(context: context, builder: (_) => _EditPersonDialog(person: person));
  return result ?? false;
}

class _EditPersonDialog extends StatefulWidget {
  const _EditPersonDialog({required this.person});

  final Profile person;

  @override
  State<_EditPersonDialog> createState() => _EditPersonDialogState();
}

class _EditPersonDialogState extends State<_EditPersonDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.person.fullName);
  late final _phone = TextEditingController(text: widget.person.phone);

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final ok = await runAction(
      context,
      () => Repo.updateProfile(widget.person.id, fullName: _name.text, phone: _phone.text),
      success: 'Bilgiler güncellendi',
    );
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Bilgileri düzenle'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(controller: _name, validator: requiredValidator, decoration: const InputDecoration(labelText: 'Ad soyad')),
              const SizedBox(height: 12),
              TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Telefon')),
              const SizedBox(height: 12),
              Text('E-posta: ${widget.person.email}', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
        BusyButton(onPressed: _submit, label: 'Kaydet'),
      ],
    );
  }
}
