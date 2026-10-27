import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class AdminPanelPage extends ConsumerWidget {
  const AdminPanelPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = session.ctx.tenant!;
    final staff = ref.watch(staffProvider).value;
    final students = ref.watch(studentsProvider).value;
    final groups = ref.watch(groupsProvider).value;
    final subjects = ref.watch(subjectsProvider).value;
    final modules = ref.watch(modulesProvider).value;

    final teacherCount = staff?.where((p) => p.role == UserRole.teacher && p.isActive).length;
    final studentCount = students?.where((s) => s.status == StudentStatus.active).length;

    String count(int? n, [int? max]) => n == null ? '' : (max == null ? '$n' : quotaLabel(n, max));

    return Scaffold(
      appBar: AppBar(title: const Text('Yönetim Paneli')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.apartment),
                    title: Text(tenant.name),
                    subtitle: Text([tenant.city, tenant.phone].whereType<String>().join(' · ')),
                    trailing: StatusBadge(
                      label: tenant.status.label,
                      color: tenant.status == TenantStatus.active ? Colors.green : Colors.orange,
                    ),
                    onTap: () => context.push('/admin/tenant'),
                  ),
                ),
                const SizedBox(height: 16),
                _Tile(
                  icon: Icons.badge_outlined,
                  title: 'Öğretmenler ve Yöneticiler',
                  subtitle: 'Davet et, düzenle, pasifleştir',
                  trailing: count(teacherCount, tenant.maxTeachers),
                  path: '/admin/teachers',
                ),
                _Tile(
                  icon: Icons.groups_outlined,
                  title: 'Öğrenciler',
                  subtitle: 'Öğrenci kayıtları, oda ve grup bilgileri',
                  trailing: count(studentCount, tenant.maxStudents),
                  path: '/admin/students',
                ),
                _Tile(
                  icon: Icons.workspaces_outline,
                  title: 'Etüt ve Dahili Ders Grupları',
                  subtitle: 'Grup tanımla, öğretmen ve öğrenci ata',
                  trailing: count(groups?.where((g) => !g.isArchived).length),
                  path: '/admin/groups',
                ),
                _Tile(
                  icon: Icons.library_books_outlined,
                  title: 'Dersler ve Konular',
                  subtitle: 'Yazılı ve testlerde kullanılacak dersler',
                  trailing: count(subjects?.length),
                  path: '/admin/subjects',
                ),
                _Tile(
                  icon: Icons.tune,
                  title: 'Kontrol Modülleri',
                  subtitle: 'Varsayılan modülleri yönet, yurda özel modül ekle',
                  trailing: count(modules?.where((m) => m.isActive).length),
                  path: '/admin/modules',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, required this.subtitle, required this.trailing, required this.path});

  final IconData icon;
  final String title;
  final String subtitle;
  final String trailing;
  final String path;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (trailing.isNotEmpty) Text(trailing, style: Theme.of(context).textTheme.labelLarge),
              const Icon(Icons.chevron_right),
            ],
          ),
          onTap: () => context.push(path),
        ),
      ),
    );
  }
}

/// Yurt iletişim bilgilerini düzenleme
class TenantInfoPage extends StatefulWidget {
  const TenantInfoPage({super.key});

  @override
  State<TenantInfoPage> createState() => _TenantInfoPageState();
}

class _TenantInfoPageState extends State<TenantInfoPage> {
  final _form = GlobalKey<FormState>();
  late final Tenant _t = session.ctx.tenant!;
  late final _name = TextEditingController(text: _t.name);
  late final _city = TextEditingController(text: _t.city);
  late final _phone = TextEditingController(text: _t.phone);
  late final _email = TextEditingController(text: _t.email);
  late final _address = TextEditingController(text: _t.address);

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    String? v(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final ok = await runAction(
      context,
      () => Repo.updateTenant(_t.id, {
        'name': _name.text.trim(),
        'city': v(_city),
        'phone': v(_phone),
        'email': v(_email),
        'address': v(_address),
      }),
      success: 'Yurt bilgileri güncellendi',
    );
    if (ok) {
      await session.refresh();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    return Scaffold(
      appBar: AppBar(title: const Text('Yurt Bilgileri')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ContentWidth(
          maxWidth: 600,
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(controller: _name, validator: requiredValidator, decoration: const InputDecoration(labelText: 'Yurt adı')),
                const SizedBox(height: 12),
                TextFormField(controller: _city, decoration: const InputDecoration(labelText: 'Şehir')),
                const SizedBox(height: 12),
                TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Telefon')),
                const SizedBox(height: 12),
                TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-posta')),
                const SizedBox(height: 12),
                TextFormField(controller: _address, maxLines: 2, decoration: const InputDecoration(labelText: 'Adres')),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Durum: ${t.status.label}\n'
                      'Öğretmen kotası: ${t.maxTeachers ?? 'sınırsız'} · Öğrenci kotası: ${t.maxStudents ?? 'sınırsız'}\n'
                      'Kota ve durum değişiklikleri sistem yöneticisi tarafından yapılır.',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                BusyButton(onPressed: _save, label: 'Kaydet', icon: Icons.save),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
