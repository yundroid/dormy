import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/session.dart';
import '../../models/models.dart';

class _Dest {
  const _Dest(this.path, this.label, this.icon, this.selectedIcon);

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

List<_Dest> _destinationsFor(UserRole role) => switch (role) {
      UserRole.superadmin => const [
          _Dest('/tenants', 'Yurtlar', Icons.apartment_outlined, Icons.apartment),
          _Dest('/profile', 'Profil', Icons.person_outline, Icons.person),
        ],
      UserRole.admin => const [
          _Dest('/home', 'Kontroller', Icons.dashboard_outlined, Icons.dashboard),
          _Dest('/admin', 'Yönetim', Icons.admin_panel_settings_outlined, Icons.admin_panel_settings),
          _Dest('/profile', 'Profil', Icons.person_outline, Icons.person),
        ],
      UserRole.teacher => const [
          _Dest('/home', 'Kontroller', Icons.dashboard_outlined, Icons.dashboard),
          _Dest('/profile', 'Profil', Icons.person_outline, Icons.person),
        ],
    };

String homePathFor(UserRole role) => role == UserRole.superadmin ? '/tenants' : '/home';

/// Role göre alt gezinme çubuğu (dar ekran) ya da yan menü (geniş ekran).
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dests = _destinationsFor(session.ctx.role);
    var index = dests.indexWhere((d) => location.startsWith(d.path));
    if (index < 0) index = 0;
    void go(int i) => context.go(dests[i].path);

    final wide = MediaQuery.sizeOf(context).width >= 800;
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: index,
              onDestinationSelected: go,
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Icon(Icons.apartment_rounded, color: Theme.of(context).colorScheme.primary, size: 32),
              ),
              destinations: [
                for (final d in dests)
                  NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(d.label)),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: go,
        destinations: [
          for (final d in dests) NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
        ],
      ),
    );
  }
}
