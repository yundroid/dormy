import 'package:dormy/core/session.dart';
import 'package:dormy/data/reports_repository.dart';
import 'package:dormy/data/repository.dart';
import 'package:dormy/features/reports/my_students_page.dart';
import 'package:dormy/features/reports/report_logic.dart';
import 'package:dormy/features/reports/reports_page.dart';
import 'package:dormy/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

DormModule _m(String id, String name, ModuleValueType type, {int? max}) => DormModule(
      id: id,
      tenantId: 't',
      code: id,
      name: name,
      icon: 'checklist',
      scope: ModuleScope.general,
      valueType: type,
      minValue: max == null ? null : 1,
      maxValue: max,
      sessions: const ['Günlük'],
      isSystem: true,
      isActive: true,
      includeInReports: true,
      weight: 1,
      sortOrder: 0,
    );

final _modules = [
  _m('attendance', 'Yoklama', ModuleValueType.attendance),
  _m('bed_locker', 'Yatak-Dolap Düzeni', ModuleValueType.score, max: 5),
  _m('exams', 'Yazılılar', ModuleValueType.exam),
  _m('books', 'Kitap Takibi', ModuleValueType.book),
];

final _students = [
  for (final (i, n) in ['Ahmet Yılmaz', 'İsmail Şahin', 'Çağrı Öztürk', 'Gülşen Ünal', 'Irmak Doğan', 'Mehmet Kaya', 'Zeynep Ak'].indexed)
    Student(
      id: 's$i',
      tenantId: 't',
      firstName: n.split(' ').first,
      lastName: n.split(' ').last,
      status: StudentStatus.active,
      roomNo: '10$i',
      guardianName: 'Veli $i',
    ),
];

StudentReport _report() => groupReport([
      for (final (i, s) in _students.indexed) ...[
        ReportCell(studentId: s.id, moduleId: 'attendance', count: 20, percent: 100 - i * 6.5, raw: i.toDouble(), extra: 1),
        ReportCell(studentId: s.id, moduleId: 'bed_locker', count: i == 6 ? 1 : 10, percent: 95 - i * 9, raw: 4.75 - i * 0.45),
        if (i < 5) ReportCell(studentId: s.id, moduleId: 'exams', count: 2, percent: 88 - i * 7, raw: 88 - i * 7),
        if (i.isEven) ReportCell(studentId: s.id, moduleId: 'books', count: i, extra: i * 250),
      ],
    ]);

Widget _app(Widget child) => ProviderScope(
      overrides: [
        modulesProvider.overrideWith((ref) async => _modules),
        studentsProvider.overrideWith((ref) async => _students),
        groupsProvider.overrideWith((ref) async => [Group(id: 'g1', tenantId: 't', kind: GroupKind.study, name: '9. Sınıf Etüdü')]),
        groupTeachersProvider.overrideWith((ref) async => {'g1': {'u1'}}),
        membershipsProvider.overrideWith((ref) async => [
              for (final s in _students) Membership(groupId: 'g1', studentId: s.id, kind: GroupKind.study),
            ]),
        reportProvider.overrideWith((ref, range) async => _report()),
      ],
      child: MaterialApp(
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: child,
      ),
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    session.debugSetContext(UserContext(
      profile: Profile(
        id: 'u1',
        tenantId: 't',
        role: UserRole.admin,
        fullName: 'Ali Admin',
        email: 'a@a.com',
        status: AccountStatus.active,
        passwordSet: true,
      ),
      tenant: Tenant(id: 't', name: 'A Yurdu', status: TenantStatus.active),
      today: DateTime(2026, 10, 29),
      backfillDays: 7,
    ));
  });

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('Öğrencilerim listesi ve karne', (tester) async {
    await phone(tester);
    await tester.pumpWidget(_app(const MyStudentsPage()));
    await tester.pumpAndSettle();

    expect(find.text('Ahmet Yılmaz'), findsOneWidget);
    expect(find.text('7 öğrenci'), findsOneWidget);

    await tester.tap(find.text('Ahmet Yılmaz'));
    await tester.pumpAndSettle();
    expect(find.text('Genel başarı'), findsOneWidget);
    expect(find.text('20 yoklama · 0 yok · 1 izinli'), findsOneWidget);
    // (100 + 95 + 88) / 3 = 94,3 -> %94
    expect(find.text('%94'), findsWidgets);

    await tester.tap(find.text('Veliye paylaş'));
    await tester.pumpAndSettle();
    // Karnede isim gizleme seçenekleri gösterilmez
    expect(find.text('İsim gösterimi'), findsNothing);
    expect(find.text('Ahmet Yılmaz · Gelişim Raporu'), findsOneWidget);
  });

  testWidgets('Yönetici raporları ve sıralama', (tester) async {
    await phone(tester);
    await tester.pumpWidget(_app(const ReportsPage()));
    await tester.pumpAndSettle();

    expect(find.text('Genel Başarı'), findsOneWidget);
    expect(find.text('En iyiler'), findsWidgets);
    // Genel başarı tam sıralaması
    await tester.tap(find.text('Tümü').first);
    await tester.pumpAndSettle();
    expect(find.text('Ahmet Yılmaz'), findsOneWidget);
    expect(find.byIcon(Icons.share), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();

    // Zeynep'in tek yatak-dolap kaydı var: sıralamaya alınmaz
    final vertical = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
    await tester.scrollUntilVisible(find.textContaining('az kayıt nedeniyle'), 300, scrollable: vertical);
    expect(find.textContaining('1 öğrenci az kayıt nedeniyle'), findsOneWidget);
  });
}
