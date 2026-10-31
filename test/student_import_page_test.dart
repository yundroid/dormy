import 'package:dormy/core/session.dart';
import 'package:dormy/data/repository.dart';
import 'package:dormy/features/admin/student_import.dart';
import 'package:dormy/features/admin/student_import_page.dart';
import 'package:dormy/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void _login({int? maxStudents}) => session.debugSetContext(UserContext(
      profile: Profile(
        id: 'u1',
        tenantId: 't',
        role: UserRole.admin,
        fullName: 'Ali Admin',
        email: 'a@a.com',
        status: AccountStatus.active,
        passwordSet: true,
      ),
      tenant: Tenant(id: 't', name: 'A Yurdu', status: TenantStatus.active, maxStudents: maxStudents),
      today: DateTime(2026, 10, 31),
      backfillDays: 7,
    ));

ImportPlan _plan() => buildImportPlan(
      [
        ['Ad', 'Soyad', 'Etüt Grubu', 'Dahili Ders Grubu'],
        ['Ahmet', 'Yılmaz', 'Etüt-1', ''],
        ['Mehmet', 'Kaya', 'Etüt-3', 'Hafızlık Grubu Uzun İsimli'],
        ['', 'Soyadsız', '', ''],
        ['Ayşe', 'Ak', '', ''],
      ],
      existingStudents: [Student(id: 'x', tenantId: 't', firstName: 'Ayşe', lastName: 'Ak', status: StudentStatus.active)],
      groups: [Group(id: 'g1', tenantId: 't', kind: GroupKind.study, name: 'Etüt-1')],
    );

Widget _app(ImportPlan plan) => ProviderScope(
      overrides: [
        studentsProvider.overrideWith((ref) async => [
              Student(id: 'x', tenantId: 't', firstName: 'Ayşe', lastName: 'Ak', status: StudentStatus.active),
            ]),
      ],
      child: MaterialApp(home: StudentImportPage(plan: plan, fileName: 'liste.xlsx')),
    );

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(360 * 3, 780 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('önizleme: özet, yeni gruplar ve grup oluşturma seçeneği', (tester) async {
    await _phone(tester);
    _login();
    await tester.pumpWidget(_app(_plan()));
    await tester.pumpAndSettle();

    expect(find.text('2 eklenecek'), findsOneWidget);
    expect(find.text('1 atlanacak'), findsOneWidget);
    expect(find.text('1 hatalı'), findsOneWidget);
    expect(find.text('Etüt-3'), findsOneWidget);
    expect(find.text('2 öğrenciyi ekle'), findsOneWidget);

    await tester.tap(find.text('Bu grupları oluştur'));
    await tester.pumpAndSettle();
    expect(find.textContaining('öğrenci grupsuz eklenir'), findsOneWidget);

    // Atlananları da ekle
    await tester.ensureVisible(find.text('Bunları da ekle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bunları da ekle'));
    await tester.pumpAndSettle();
    expect(find.text('3 öğrenciyi ekle'), findsOneWidget);
  });

  testWidgets('kota yetmezse ekleme düğmesi kapalı ve açıklama gösterilir', (tester) async {
    await _phone(tester);
    _login(maxStudents: 2);
    await tester.pumpWidget(_app(_plan()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Öğrenci kotanız 2'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.ancestor(of: find.text('2 öğrenciyi ekle'), matching: find.byWidgetPredicate((w) => w is FilledButton)));
    expect(button.onPressed, isNull);
  });
}
