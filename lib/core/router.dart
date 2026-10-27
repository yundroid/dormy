import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/academics/assessments_page.dart';
import '../features/academics/books_page.dart';
import '../features/academics/exams_page.dart';
import '../features/admin/admin_panel_page.dart';
import '../features/admin/groups_page.dart';
import '../features/admin/modules_page.dart';
import '../features/admin/students_page.dart';
import '../features/admin/subjects_page.dart';
import '../features/admin/teachers_page.dart';
import '../features/auth/auth_pages.dart';
import '../features/entries/entry_page.dart';
import '../features/home/dashboard_page.dart';
import '../features/home/home_shell.dart';
import '../features/profile/profile_page.dart';
import '../features/reports/my_students_page.dart';
import '../features/reports/reports_page.dart';
import '../features/superadmin/tenants_page.dart';
import '../models/models.dart';
import 'session.dart';

final _rootKey = GlobalKey<NavigatorState>();

const _publicPaths = {'/login', '/register', '/forgot-password'};

/// Oturum durumuna ve role göre yönlendirme kuralı (test edilebilir saf fonksiyon).
String? resolveRedirect({required SessionStatus status, required UserRole? role, required String location}) {
  switch (status) {
    case SessionStatus.loading:
      return location == '/splash' ? null : '/splash';
    case SessionStatus.signedOut:
      return _publicPaths.contains(location) ? null : '/login';
    case SessionStatus.needsPassword:
      return location == '/set-password' ? null : '/set-password';
    case SessionStatus.blocked:
    case SessionStatus.error:
      return location == '/blocked' ? null : '/blocked';
    case SessionStatus.ready:
      final home = homePathFor(role!);
      if (_publicPaths.contains(location) || const {'/splash', '/set-password', '/blocked', '/'}.contains(location)) {
        return home;
      }
      if (location.startsWith('/tenants') && role != UserRole.superadmin) return home;
      if ((location.startsWith('/admin') || location.startsWith('/reports')) && role != UserRole.admin) return home;
      // Sistem yöneticisi yurt verisine erişmez: sadece yurtlar ve profil
      if (role == UserRole.superadmin && !location.startsWith('/tenants') && !location.startsWith('/profile')) return home;
      return null;
  }
}

GoRouter buildRouter() {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    refreshListenable: session,
    redirect: (context, state) => resolveRedirect(
      status: session.status,
      role: session.contextOrNull?.role,
      location: state.matchedLocation,
    ),
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashPage()),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterPage()),
      GoRoute(path: '/forgot-password', builder: (_, _) => const ForgotPasswordPage()),
      GoRoute(path: '/set-password', builder: (_, _) => const SetPasswordPage()),
      GoRoute(path: '/blocked', builder: (_, _) => const BlockedPage()),
      GoRoute(path: '/module/:id', builder: (_, s) => EntryPage(moduleId: s.pathParameters['id']!)),
      GoRoute(path: '/exams', builder: (_, _) => const ExamsPage(), routes: [
        GoRoute(path: ':id', builder: (_, s) => ExamDetailPage(examId: s.pathParameters['id']!)),
      ]),
      GoRoute(path: '/tests', builder: (_, _) => const AssessmentsPage(kind: AssessmentKind.test), routes: [
        GoRoute(path: ':id', builder: (_, s) => AssessmentDetailPage(kind: AssessmentKind.test, assessmentId: s.pathParameters['id']!)),
      ]),
      GoRoute(path: '/trials', builder: (_, _) => const AssessmentsPage(kind: AssessmentKind.trial), routes: [
        GoRoute(path: 'new', builder: (_, _) => const TrialFormPage()),
        GoRoute(path: ':id', builder: (_, s) => AssessmentDetailPage(kind: AssessmentKind.trial, assessmentId: s.pathParameters['id']!)),
      ]),
      GoRoute(path: '/books', builder: (_, _) => const BooksPage()),
      ShellRoute(
        builder: (context, state, child) => HomeShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, _) => const DashboardPage()),
          GoRoute(path: '/my-students', builder: (_, _) => const MyStudentsPage()),
          GoRoute(path: '/reports', builder: (_, _) => const ReportsPage()),
          GoRoute(
            path: '/admin',
            builder: (_, _) => const AdminPanelPage(),
            routes: [
              GoRoute(parentNavigatorKey: _rootKey, path: 'tenant', builder: (_, _) => const TenantInfoPage()),
              GoRoute(parentNavigatorKey: _rootKey, path: 'teachers', builder: (_, _) => const TeachersPage()),
              GoRoute(
                parentNavigatorKey: _rootKey,
                path: 'students',
                builder: (_, _) => const StudentsPage(),
                routes: [
                  GoRoute(parentNavigatorKey: _rootKey, path: 'new', builder: (_, _) => const StudentFormPage()),
                  GoRoute(parentNavigatorKey: _rootKey, path: ':id', builder: (_, s) => StudentFormPage(studentId: s.pathParameters['id'])),
                ],
              ),
              GoRoute(
                parentNavigatorKey: _rootKey,
                path: 'groups',
                builder: (_, _) => const GroupsPage(),
                routes: [
                  GoRoute(parentNavigatorKey: _rootKey, path: ':id', builder: (_, s) => GroupDetailPage(groupId: s.pathParameters['id']!)),
                ],
              ),
              GoRoute(parentNavigatorKey: _rootKey, path: 'subjects', builder: (_, _) => const SubjectsPage()),
              GoRoute(
                parentNavigatorKey: _rootKey,
                path: 'modules',
                builder: (_, _) => const ModulesPage(),
                routes: [
                  GoRoute(parentNavigatorKey: _rootKey, path: 'new', builder: (_, _) => const ModuleFormPage()),
                  GoRoute(parentNavigatorKey: _rootKey, path: ':id', builder: (_, s) => ModuleFormPage(moduleId: s.pathParameters['id'])),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/tenants',
            builder: (_, _) => const TenantsPage(),
            routes: [
              GoRoute(parentNavigatorKey: _rootKey, path: ':id', builder: (_, s) => TenantDetailPage(tenantId: s.pathParameters['id']!)),
            ],
          ),
          GoRoute(path: '/profile', builder: (_, _) => const ProfilePage()),
        ],
      ),
    ],
  );
}
