import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repository.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

const _defaultSubjects = ['Türkçe', 'Matematik', 'Fizik', 'Kimya', 'Biyoloji', 'Tarih', 'Coğrafya', 'Din Kültürü', 'İngilizce'];

class SubjectsPage extends ConsumerWidget {
  const SubjectsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjectsAsync = ref.watch(subjectsProvider);

    Future<void> addSubject() async {
      final name = await _askName(context, title: 'Yeni ders', label: 'Ders adı');
      if (name == null || !context.mounted) return;
      final count = subjectsAsync.value?.length ?? 0;
      await runAction(context, () => Repo.saveSubject(name: name, sortOrder: count));
      ref.invalidate(subjectsProvider);
    }

    Future<void> addDefaults() async {
      await runAction(context, () async {
        for (var i = 0; i < _defaultSubjects.length; i++) {
          await Repo.saveSubject(name: _defaultSubjects[i], sortOrder: i);
        }
      }, success: 'Varsayılan dersler eklendi');
      ref.invalidate(subjectsProvider);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Dersler ve Konular')),
      floatingActionButton: FloatingActionButton.extended(onPressed: addSubject, icon: const Icon(Icons.add), label: const Text('Ders ekle')),
      body: AsyncView(
        value: subjectsAsync,
        onRetry: () => ref.invalidate(subjectsProvider),
        builder: (subjects) {
          if (subjects.isEmpty) {
            return EmptyState(
              icon: Icons.library_books_outlined,
              title: 'Henüz ders tanımlanmamış',
              message: 'Dersler ve konular yazılı ve test sonuçlarını girerken kullanılır.',
              action: OutlinedButton.icon(onPressed: addDefaults, icon: const Icon(Icons.auto_awesome), label: const Text('Varsayılan dersleri ekle')),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: subjects.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) => ContentWidth(child: _SubjectCard(subject: subjects[i])),
          );
        },
      ),
    );
  }
}

class _SubjectCard extends ConsumerWidget {
  const _SubjectCard({required this.subject});

  final Subject subject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void reload() => ref.invalidate(subjectsProvider);

    Future<void> menu(String action) async {
      switch (action) {
        case 'rename':
          final name = await _askName(context, title: 'Dersi düzenle', label: 'Ders adı', initial: subject.name);
          if (name == null || !context.mounted) return;
          await runAction(context, () => Repo.saveSubject(id: subject.id, name: name, sortOrder: subject.sortOrder));
          reload();
        case 'delete':
          final yes = await confirm(context,
              title: 'Dersi sil', message: '"${subject.name}" ve tüm konuları silinecek.', confirmLabel: 'Sil', destructive: true);
          if (!yes || !context.mounted) return;
          await runAction(context, () => Repo.deleteSubject(subject.id), success: 'Ders silindi');
          reload();
      }
    }

    Future<void> addTopic() async {
      final name = await _askName(context, title: '${subject.name} · yeni konu', label: 'Konu adı');
      if (name == null || !context.mounted) return;
      await runAction(context, () => Repo.saveTopic(subjectId: subject.id, name: name, sortOrder: subject.topics.length));
      reload();
    }

    Future<void> topicMenu(Topic t, String action) async {
      switch (action) {
        case 'rename':
          final name = await _askName(context, title: 'Konuyu düzenle', label: 'Konu adı', initial: t.name);
          if (name == null || !context.mounted) return;
          await runAction(context, () => Repo.saveTopic(id: t.id, subjectId: subject.id, name: name, sortOrder: t.sortOrder));
          reload();
        case 'delete':
          await runAction(context, () => Repo.deleteTopic(t.id), success: 'Konu silindi');
          reload();
      }
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(subject.name),
        subtitle: Text('${subject.topics.length} konu'),
        shape: const Border(),
        trailing: PopupMenuButton<String>(
          onSelected: menu,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('Düzenle')),
            PopupMenuItem(value: 'delete', child: Text('Sil')),
          ],
        ),
        children: [
          for (final t in subject.topics)
            ListTile(
              dense: true,
              leading: const Icon(Icons.subdirectory_arrow_right, size: 18),
              title: Text(t.name),
              trailing: PopupMenuButton<String>(
                onSelected: (a) => topicMenu(t, a),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Düzenle')),
                  PopupMenuItem(value: 'delete', child: Text('Sil')),
                ],
              ),
            ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.add, size: 18),
            title: const Text('Konu ekle'),
            onTap: addTopic,
          ),
        ],
      ),
    );
  }
}

Future<String?> _askName(BuildContext context, {required String title, required String label, String? initial}) {
  final controller = TextEditingController(text: initial);
  final form = GlobalKey<FormState>();
  void submit(BuildContext ctx) {
    if (form.currentState!.validate()) Navigator.pop(ctx, controller.text.trim());
  }

  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Form(
        key: form,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          validator: requiredValidator,
          onFieldSubmitted: (_) => submit(ctx),
          decoration: InputDecoration(labelText: label),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => submit(ctx), child: const Text('Kaydet')),
      ],
    ),
  );
}
