import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/icons.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../data/dashboard_repository.dart';
import '../../data/repository.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../reports/my_students_page.dart';
import '../reports/report_logic.dart';

/// Kullanıcının doldurabileceği kontrol modülleri.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  /// Ekran genişliğine göre sütun sayısı; telefonda da en az 2.
  static int columnsFor(double width) => width >= 900 ? 4 : (width >= 600 ? 3 : 2);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctx = session.ctx;
    final modules = ref.watch(modulesProvider);
    final kinds = ref.watch(myGroupKindsProvider);
    final progress = ref.watch(todayProgressProvider).value ?? const <String, ModuleProgress>{};
    final alerts = ref.watch(attendanceAlertsProvider).value ?? const <AbsenceAlert>[];

    Future<void> reload() async {
      ref.invalidate(modulesProvider);
      ref.invalidate(myGroupKindsProvider);
      ref.invalidate(todayProgressProvider);
      ref.invalidate(attendanceAlertsProvider);
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
                      if (alerts.isNotEmpty) ...[_AbsenceAlertCard(alerts: alerts), const SizedBox(height: 16)],
                      if (visible.isEmpty)
                        const EmptyState(
                          icon: Icons.inbox_outlined,
                          title: 'Doldurabileceğiniz bir kontrol yok',
                          message: 'Etüt veya dahili ders grubu ataması için yöneticinizle görüşün.',
                        )
                      else
                        LayoutBuilder(builder: (context, c) {
                          return GridView(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columnsFor(c.maxWidth),
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              mainAxisExtent: 128,
                            ),
                            children: [for (final m in visible) ModuleCard(module: m, progress: progress[m.id])],
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

class ModuleCard extends StatelessWidget {
  const ModuleCard({super.key, required this.module, this.progress});

  final DormModule module;
  final ModuleProgress? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = progress;
    final done = p?.complete ?? false;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(module.route),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(moduleIcon(module.icon), size: 20, color: theme.colorScheme.onPrimaryContainer),
                  ),
                  const Spacer(),
                  if (done) const Icon(Icons.check_circle, color: StatusColors.present, size: 20),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                module.name,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              if (p != null) ...[
                Text(p.label, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: p.ratio,
                    minHeight: 4,
                    color: done ? StatusColors.present : theme.colorScheme.primary,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              ] else
                Text(
                  module.scaleLabel,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AbsenceAlertCard extends ConsumerWidget {
  const _AbsenceAlertCard({required this.alerts});

  final List<AbsenceAlert> alerts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final students = {for (final s in ref.watch(studentsProvider).value ?? const <Student>[]) s.id: s};
    final today = session.ctx.today;
    return Card(
      color: scheme.errorContainer,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        leading: Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
        iconColor: scheme.onErrorContainer,
        collapsedIconColor: scheme.onErrorContainer,
        title: Text('Devamsızlık uyarısı', style: TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${alerts.length} öğrenci son 7 günde 3 veya daha fazla yoklamada "yok"',
          style: TextStyle(color: scheme.onErrorContainer),
        ),
        children: [
          for (final a in alerts)
            if (students[a.studentId] case final s?)
              ListTile(
                dense: true,
                title: Text(s.fullName, style: TextStyle(color: scheme.onErrorContainer)),
                subtitle: Text(
                  '${a.absentCount} kez yok · son: ${relativeDayLabel(a.lastAbsent, today)}'
                  '${s.guardianPhone != null ? ' · Veli: ${s.guardianPhone}' : ''}',
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
                trailing: Icon(Icons.chevron_right, color: scheme.onErrorContainer),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => StudentReportPage(student: s, range: rangeFor(RangePreset.last30, today)),
                )),
              ),
        ],
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
