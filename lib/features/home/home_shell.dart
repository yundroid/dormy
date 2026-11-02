import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/session.dart';
import '../../models/models.dart';

class NavDest {
  const NavDest(this.path, this.label, this.icon, this.selectedIcon, {this.alsoMatches = const []});

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// Bu sekmeyi seçili gösteren diğer adresler (ör. Ayarlar → /admin)
  final List<String> alsoMatches;

  bool matches(String location) => [path, ...alsoMatches].any(location.startsWith);
}

const _home = NavDest('/home', 'Kontroller', Icons.dashboard_outlined, Icons.dashboard);
const _students = NavDest('/my-students', 'Öğrencilerim', Icons.groups_outlined, Icons.groups);
const _program = NavDest('/program', 'Program', Icons.event_note_outlined, Icons.event_note);
const _reports = NavDest('/reports', 'Raporlar', Icons.insights_outlined, Icons.insights);
const _settings = NavDest('/settings', 'Ayarlar', Icons.settings_outlined, Icons.settings, alsoMatches: ['/admin']);
const _tenants = NavDest('/tenants', 'Yurtlar', Icons.apartment_outlined, Icons.apartment);

/// Alt çubuk düzeni: sol sekmeler, (varsa) ortadaki Program düğmesi, sağ sekmeler.
({List<NavDest> left, NavDest? center, List<NavDest> right}) navLayoutFor(UserRole role) => switch (role) {
      UserRole.superadmin => (left: const [_tenants], center: null, right: const [_settings]),
      UserRole.admin => (left: const [_home, _students], center: _program, right: const [_reports, _settings]),
      UserRole.teacher => (left: const [_home, _students], center: _program, right: const [_settings]),
    };

String homePathFor(UserRole role) => role == UserRole.superadmin ? '/tenants' : '/home';

/// Role göre alt gezinme çubuğu (dar ekran) ya da yan menü (geniş ekran).
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final layout = navLayoutFor(session.ctx.role);
    final all = [...layout.left, ?layout.center, ...layout.right];
    final selected = all.where((d) => d.matches(location)).firstOrNull ?? all.first;

    final wide = MediaQuery.sizeOf(context).width >= 800;
    if (wide) {
      final index = all.indexOf(selected);
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: index,
              onDestinationSelected: (i) => context.go(all[i].path),
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Icon(Icons.apartment_rounded, color: Theme.of(context).colorScheme.primary, size: 32),
              ),
              destinations: [
                for (final d in all)
                  NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(d.label)),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }

    Widget side(List<NavDest> items) => Expanded(
          child: Row(
            children: [
              for (final d in items)
                Expanded(child: _NavItem(dest: d, selected: d == selected, onTap: () => context.go(d.path))),
            ],
          ),
        );

    return Scaffold(
      body: child,
      bottomNavigationBar: BottomAppBar(
        height: 72,
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            side(layout.left),
            if (layout.center != null)
              _CenterButton(
                dest: layout.center!,
                selected: layout.center == selected,
                onTap: () => context.go(layout.center!.path),
              ),
            side(layout.right),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.dest, required this.selected, required this.onTap});

  final NavDest dest;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      label: dest.label,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 56,
              height: 30,
              decoration: BoxDecoration(
                color: selected ? scheme.secondaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(selected ? dest.selectedIcon : dest.icon, color: color, size: 22),
            ),
            const SizedBox(height: 4),
            Text(
              dest.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ortadaki öne çıkan Günlük Program düğmesi
class _CenterButton extends StatelessWidget {
  const _CenterButton({required this.dest, required this.selected, required this.onTap});

  final NavDest dest;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      label: 'Günlük ${dest.label.toLowerCase()}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? scheme.primary : scheme.primaryContainer,
                  boxShadow: [BoxShadow(color: scheme.shadow.withValues(alpha: 0.15), blurRadius: 6, offset: const Offset(0, 2))],
                ),
                child: Icon(selected ? dest.selectedIcon : dest.icon,
                    color: selected ? scheme.onPrimary : scheme.onPrimaryContainer),
              ),
              const SizedBox(height: 2),
              Text(
                dest.label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: selected ? scheme.primary : scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
