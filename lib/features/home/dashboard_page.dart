import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/icons.dart';
import '../../core/session.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

/// Kullanıcının doldurabileceği kontrol modülleri.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctx = session.ctx;
    final modules = ref.watch(modulesProvider);
    final kinds = ref.watch(myGroupKindsProvider);

    Future<void> reload() async {
      ref.invalidate(modulesProvider);
      ref.invalidate(myGroupKindsProvider);
      await ref.read(modulesProvider.future);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(ctx.tenant?.name ?? 'Dormy'),
        actions: [IconButton(tooltip: 'Yenile', onPressed: reload, icon: const Icon(Icons.refresh))],
      ),
      body: RefreshIndicator(
        onRefresh: reload,
        child: AsyncView(
          value: modules,
          onRetry: reload,
          builder: (all) {
            final myKinds = kinds.value ?? const <GroupKind>{};
            final visible = all.where((m) {
              if (!m.isActive) return false;
              final kind = m.scope.groupKind;
              return kind == null || ctx.isAdmin || myKinds.contains(kind);
            }).toList();

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ContentWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (ctx.tenant?.status == TenantStatus.pending) const _TrialBanner(),
                      Text('Merhaba, ${ctx.profile.fullName}', style: Theme.of(context).textTheme.titleLarge),
                      Text('${formatWeekday(ctx.today)}, ${formatDay(ctx.today)}',
                          style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                      const SizedBox(height: 16),
                      if (visible.isEmpty)
                        const EmptyState(
                          icon: Icons.inbox_outlined,
                          title: 'Doldurabileceğiniz bir kontrol yok',
                          message: 'Etüt veya dahili ders grubu ataması için yöneticinizle görüşün.',
                        )
                      else
                        LayoutBuilder(builder: (context, c) {
                          final cols = c.maxWidth >= 700 ? 3 : (c.maxWidth >= 420 ? 2 : 1);
                          return GridView.count(
                            crossAxisCount: cols,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: cols == 1 ? 3.6 : 1.9,
                            children: [for (final m in visible) _ModuleCard(module: m)],
                          );
                        }),
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

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module});

  final DormModule module;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(module.route),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(moduleIcon(module.icon), color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(module.name, style: theme.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      module.sessions.length > 1 ? '${module.sessions.length} vakit · ${module.scaleLabel}' : module.scaleLabel,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrialBanner extends StatelessWidget {
  const _TrialBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = session.ctx.tenant!;
    String limit(int? v) => v == null ? 'sınırsız' : 'en fazla $v';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        color: scheme.tertiaryContainer,
        child: ListTile(
          leading: Icon(Icons.hourglass_top, color: scheme.onTertiaryContainer),
          title: Text('Deneme modundasınız', style: TextStyle(color: scheme.onTertiaryContainer)),
          subtitle: Text(
            'Hesabınız onay bekliyor. Bu sürede ${limit(t.maxTeachers)} öğretmen ve '
            '${limit(t.maxStudents)} öğrenci ekleyebilirsiniz.',
            style: TextStyle(color: scheme.onTertiaryContainer),
          ),
        ),
      ),
    );
  }
}
