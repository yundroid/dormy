import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/formatters.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/person_dialogs.dart';

Color tenantStatusColor(TenantStatus s) => switch (s) {
      TenantStatus.pending => Colors.orange,
      TenantStatus.active => Colors.green,
      TenantStatus.suspended => Colors.red,
    };

class TenantsPage extends ConsumerStatefulWidget {
  const TenantsPage({super.key});

  @override
  ConsumerState<TenantsPage> createState() => _TenantsPageState();
}

class _TenantsPageState extends ConsumerState<TenantsPage> {
  TenantStatus? _filter;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(tenantOverviewProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yurtlar'),
        actions: [IconButton(onPressed: () => ref.invalidate(tenantOverviewProvider), icon: const Icon(Icons.refresh))],
      ),
      body: AsyncView(
        value: overview,
        onRetry: () => ref.invalidate(tenantOverviewProvider),
        builder: (all) {
          final q = _search.trim().toLowerCase();
          final list = all.where((o) {
            if (_filter != null && o.tenant.status != _filter) return false;
            if (q.isEmpty) return true;
            final t = o.tenant;
            return t.name.toLowerCase().contains(q) ||
                (t.city?.toLowerCase().contains(q) ?? false) ||
                (t.email?.toLowerCase().contains(q) ?? false);
          }).toList();
          int countOf(TenantStatus s) => all.where((o) => o.tenant.status == s).length;
          final totalStudents = all.fold<int>(0, (a, o) => a + o.studentCount);
          final newThisWeek = all.where((o) => o.tenant.createdAt != null && DateTime.now().difference(o.tenant.createdAt!).inDays < 7).length;

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(tenantOverviewProvider),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ContentWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _Stat(label: 'Toplam yurt', value: '${all.length}'),
                          _Stat(label: 'Onay bekleyen', value: '${countOf(TenantStatus.pending)}', color: Colors.orange),
                          _Stat(label: 'Aktif', value: '${countOf(TenantStatus.active)}', color: Colors.green),
                          _Stat(label: 'Toplam öğrenci', value: '$totalStudents'),
                          _Stat(label: 'Bu hafta kayıt', value: '$newThisWeek'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        onChanged: (v) => setState(() => _search = v),
                        decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search), hintText: 'Yurt, şehir veya e-posta ara'),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        children: [
                          ChoiceChip(label: const Text('Tümü'), selected: _filter == null, onSelected: (_) => setState(() => _filter = null)),
                          for (final s in TenantStatus.values)
                            ChoiceChip(
                              label: Text('${s.label} (${countOf(s)})'),
                              selected: _filter == s,
                              onSelected: (_) => setState(() => _filter = s),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (list.isEmpty)
                        const EmptyState(icon: Icons.apartment_outlined, title: 'Yurt bulunamadı')
                      else
                        for (final o in list) ...[_TenantCard(o: o), const SizedBox(height: 8)],
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

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 150,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: theme.textTheme.headlineSmall?.copyWith(color: color, fontWeight: FontWeight.w600)),
              Text(label, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _TenantCard extends StatelessWidget {
  const _TenantCard({required this.o});

  final TenantOverview o;

  @override
  Widget build(BuildContext context) {
    final t = o.tenant;
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/tenants/${t.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(t.name, style: theme.textTheme.titleMedium)),
                  StatusBadge(label: t.status.label, color: tenantStatusColor(t.status)),
                ],
              ),
              const SizedBox(height: 4),
              Text([t.city, t.phone, t.email].whereType<String>().join(' · '), style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _Mini(icon: Icons.badge_outlined, text: 'Öğretmen ${quotaLabel(o.teacherCount, t.maxTeachers)}'),
                  _Mini(icon: Icons.groups_outlined, text: 'Öğrenci ${quotaLabel(o.studentCount, t.maxStudents)}'),
                  _Mini(icon: Icons.edit_note, text: '30 günde ${o.entriesLast30d} giriş'),
                  _Mini(icon: Icons.access_time, text: 'Son aktivite: ${formatLastActivity(o.lastSeenAt)}'),
                  if (t.createdAt != null) _Mini(icon: Icons.event, text: 'Kayıt: ${formatDay(t.createdAt!.toLocal())}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 4),
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class TenantDetailPage extends ConsumerWidget {
  const TenantDetailPage({super.key, required this.tenantId});

  final String tenantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(tenantOverviewProvider);
    final admins = ref.watch(tenantAdminsProvider(tenantId));

    void reload() {
      ref.invalidate(tenantOverviewProvider);
      ref.invalidate(tenantAdminsProvider(tenantId));
    }

    return AsyncView(
      value: overview,
      onRetry: reload,
      builder: (all) {
        final o = all.where((x) => x.tenant.id == tenantId).firstOrNull;
        if (o == null) {
          return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.search_off, title: 'Yurt bulunamadı'));
        }
        final t = o.tenant;

        Future<void> setStatus(TenantStatus s) async {
          final message = switch (s) {
            TenantStatus.active => '${t.name} aktifleştirilecek. Kotaları ayrıca belirleyebilirsiniz.',
            TenantStatus.suspended => '${t.name} askıya alınacak; yurt kullanıcıları uygulamaya erişemeyecek. Veriler korunur.',
            TenantStatus.pending => '${t.name} tekrar deneme (pasif) durumuna alınacak.',
          };
          if (!await confirm(context, title: 'Durumu değiştir', message: message, destructive: s == TenantStatus.suspended)) return;
          if (!context.mounted) return;
          await runAction(context, () => Repo.updateTenant(t.id, {'status': s.name}), success: 'Durum: ${s.label}');
          reload();
        }

        Future<void> editQuota() async {
          final changed = await showDialog<bool>(context: context, builder: (_) => _QuotaDialog(tenant: t));
          if (changed == true) reload();
        }

        Future<void> addAdmin() async {
          if (await showInviteDialog(context, tenantId: t.id, role: UserRole.admin)) reload();
        }

        return Scaffold(
          appBar: AppBar(title: Text(t.name)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        StatusBadge(label: t.status.label, color: tenantStatusColor(t.status)),
                        const Spacer(),
                        if (t.status != TenantStatus.active)
                          FilledButton.icon(
                            onPressed: () => setStatus(TenantStatus.active),
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Aktifleştir'),
                          ),
                        const SizedBox(width: 8),
                        PopupMenuButton<TenantStatus>(
                          tooltip: 'Durumu değiştir',
                          onSelected: setStatus,
                          itemBuilder: (_) => [
                            for (final s in TenantStatus.values.where((s) => s != t.status))
                              PopupMenuItem(value: s, child: Text('${s.label} yap')),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _SectionTitle('İletişim'),
                    Card(
                      child: Column(
                        children: [
                          _ContactTile(icon: Icons.phone, label: 'Telefon', value: t.phone, uri: t.phone == null ? null : Uri(scheme: 'tel', path: t.phone)),
                          if (t.phone != null)
                            _ContactTile(
                              icon: Icons.chat_outlined,
                              label: 'WhatsApp',
                              value: t.phone,
                              uri: Uri.parse('https://wa.me/${_waNumber(t.phone!)}'),
                            ),
                          _ContactTile(icon: Icons.mail_outline, label: 'E-posta', value: t.email, uri: t.email == null ? null : Uri(scheme: 'mailto', path: t.email)),
                          _ContactTile(icon: Icons.location_on_outlined, label: 'Şehir / Adres', value: [t.city, t.address].whereType<String>().join(' · ')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionTitle('Özet', action: TextButton.icon(onPressed: editQuota, icon: const Icon(Icons.tune, size: 18), label: const Text('Kota / abonelik'))),
                    Card(
                      child: Column(
                        children: [
                          _InfoTile('Öğretmen', quotaLabel(o.teacherCount, t.maxTeachers)),
                          _InfoTile('Öğrenci', quotaLabel(o.studentCount, t.maxStudents)),
                          _InfoTile('Yönetici', '${o.adminCount}'),
                          _InfoTile('Bekleyen davet', '${o.pendingInvites}'),
                          _InfoTile('Son 30 günde veri girişi', '${o.entriesLast30d}'),
                          _InfoTile('Son veri girişi', formatLastActivity(o.lastEntryAt)),
                          _InfoTile('Son kullanıcı aktivitesi', formatLastActivity(o.lastSeenAt)),
                          _InfoTile('Kayıt tarihi', t.createdAt == null ? '-' : formatDateTime(t.createdAt!)),
                          _InfoTile('Aktifleştirme', t.activatedAt == null ? '-' : formatDateTime(t.activatedAt!)),
                          _InfoTile('Abonelik bitişi', t.subscriptionEndsOn == null ? 'Belirtilmemiş' : formatDay(t.subscriptionEndsOn!)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionTitle('Yöneticiler', action: TextButton.icon(onPressed: addAdmin, icon: const Icon(Icons.person_add_alt, size: 18), label: const Text('Yönetici ekle'))),
                    AsyncView(
                      value: admins,
                      builder: (list) => Card(
                        child: Column(
                          children: [
                            if (list.isEmpty) const ListTile(title: Text('Yönetici yok')),
                            for (final p in list) _AdminTile(person: p, onChanged: reload),
                          ],
                        ),
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

/// Türkiye numaralarını wa.me biçimine çevirir: 0532... -> 90532...
String _waNumber(String phone) {
  var digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('0')) digits = '9$digits';
  if (digits.length == 10) digits = '90$digits';
  return digits;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [Text(title, style: Theme.of(context).textTheme.titleMedium), const Spacer(), ?action]),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(dense: true, title: Text(label), trailing: Text(value, style: Theme.of(context).textTheme.labelLarge));
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.icon, required this.label, required this.value, this.uri});

  final IconData icon;
  final String label;
  final String? value;
  final Uri? uri;

  @override
  Widget build(BuildContext context) {
    final has = value != null && value!.isNotEmpty;
    return ListTile(
      leading: Icon(icon),
      title: Text(has ? value! : '-'),
      subtitle: Text(label),
      onTap: has && uri != null ? () => launchUrl(uri!, mode: LaunchMode.externalApplication) : null,
      trailing: has
          ? IconButton(
              tooltip: 'Kopyala',
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value!));
                showMessage(context, 'Kopyalandı');
              },
            )
          : null,
    );
  }
}

class _AdminTile extends StatelessWidget {
  const _AdminTile({required this.person, required this.onChanged});

  final Profile person;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    Future<void> act(String a) async {
      switch (a) {
        case 'call':
          await launchUrl(Uri(scheme: 'tel', path: person.phone));
        case 'mail':
          await launchUrl(Uri(scheme: 'mailto', path: person.email));
        case 'resend':
          await runAction(context, () => Repo.sendPasswordReset(person.email), success: 'Şifre belirleme bağlantısı gönderildi');
        case 'toggle':
          await runAction(
            context,
            () => Repo.setProfileStatus(person.id, person.isActive ? AccountStatus.disabled : AccountStatus.active),
            success: person.isActive ? 'Yönetici pasifleştirildi' : 'Yönetici aktifleştirildi',
          );
          onChanged();
      }
    }

    return ListTile(
      leading: const Icon(Icons.admin_panel_settings_outlined),
      title: Row(
        children: [
          Flexible(child: Text(person.fullName)),
          if (!person.isActive) const Padding(padding: EdgeInsets.only(left: 6), child: StatusBadge(label: 'Pasif', color: Colors.grey)),
          if (person.isActive && !person.passwordSet)
            const Padding(padding: EdgeInsets.only(left: 6), child: StatusBadge(label: 'Davet bekliyor', color: Colors.orange)),
        ],
      ),
      subtitle: Text([person.email, if (person.phone != null) person.phone!, 'Son giriş: ${formatLastActivity(person.lastSeenAt)}'].join('\n')),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        onSelected: act,
        itemBuilder: (_) => [
          if (person.phone != null) const PopupMenuItem(value: 'call', child: Text('Ara')),
          const PopupMenuItem(value: 'mail', child: Text('E-posta gönder')),
          if (!person.passwordSet) const PopupMenuItem(value: 'resend', child: Text('Daveti tekrar gönder')),
          PopupMenuItem(value: 'toggle', child: Text(person.isActive ? 'Pasifleştir' : 'Aktifleştir')),
        ],
      ),
    );
  }
}

class _QuotaDialog extends StatefulWidget {
  const _QuotaDialog({required this.tenant});

  final Tenant tenant;

  @override
  State<_QuotaDialog> createState() => _QuotaDialogState();
}

class _QuotaDialogState extends State<_QuotaDialog> {
  late final _teachers = TextEditingController(text: widget.tenant.maxTeachers?.toString() ?? '');
  late final _students = TextEditingController(text: widget.tenant.maxStudents?.toString() ?? '');
  late DateTime? _ends = widget.tenant.subscriptionEndsOn;

  int? _parse(TextEditingController c) => c.text.trim().isEmpty ? null : int.tryParse(c.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Kota ve abonelik'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _teachers,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'En fazla öğretmen', helperText: 'Boş bırakırsanız sınırsız'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _students,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'En fazla öğrenci', helperText: 'Boş bırakırsanız sınırsız'),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(_ends == null ? 'Abonelik bitişi yok' : 'Bitiş: ${formatDay(_ends!)}'),
              trailing: _ends == null ? null : IconButton(onPressed: () => setState(() => _ends = null), icon: const Icon(Icons.clear)),
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _ends ?? DateTime(now.year + 1, now.month, now.day),
                  firstDate: DateTime(now.year - 1),
                  lastDate: DateTime(now.year + 10),
                );
                if (picked != null) setState(() => _ends = picked);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
        BusyButton(
          label: 'Kaydet',
          onPressed: () async {
            final ok = await runAction(
              context,
              () => Repo.updateTenant(widget.tenant.id, {
                'max_teachers': _parse(_teachers),
                'max_students': _parse(_students),
                'subscription_ends_on': _ends == null ? null : isoDate(_ends!),
              }),
              success: 'Kotalar güncellendi',
            );
            if (ok && context.mounted) Navigator.pop(context, true);
          },
        ),
      ],
    );
  }
}
