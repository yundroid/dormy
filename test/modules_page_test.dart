import 'package:dormy/data/repository.dart';
import 'package:dormy/features/admin/modules_page.dart';
import 'package:dormy/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DormModule _m(int order, String code, String name, ModuleValueType t, {bool system = true}) => DormModule(
      id: code,
      tenantId: 't',
      code: system ? code : null,
      name: name,
      icon: 'checklist',
      scope: ModuleScope.general,
      valueType: t,
      minValue: t == ModuleValueType.score ? 1 : null,
      maxValue: t == ModuleValueType.score ? 5 : null,
      sessions: code == 'attendance' ? const ['Sabah', 'Öğle', 'İkindi', 'Akşam', 'Yatsı'] : const ['Günlük'],
      isSystem: system,
      isActive: true,
      includeInReports: true,
      weight: 1,
      sortOrder: order,
    );

void main() {
  testWidgets('modüller sırasıyla, tutamaçlarla listelenir', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final modules = [
      _m(10, 'attendance', 'Yoklama', ModuleValueType.attendance),
      _m(20, 'bed_locker', 'Yatak-Dolap Düzeni', ModuleValueType.score),
      _m(30, 'study_score', 'Etüt Puanlama', ModuleValueType.score),
      _m(40, 'internal_score', 'Dahili Ders Puanlama', ModuleValueType.score),
      _m(50, 'exams', 'Yazılılar', ModuleValueType.exam),
      _m(60, 'tests', 'Testler', ModuleValueType.test),
      _m(70, 'books', 'Kitap Takibi', ModuleValueType.book),
      _m(80, 'trial_exams', 'Deneme Sınavları', ModuleValueType.trialExam),
      _m(90, 'defter', 'Defter Kontrolü', ModuleValueType.yesNo, system: false),
    ];
    await tester.pumpWidget(ProviderScope(
      overrides: [modulesProvider.overrideWith((ref) async => modules)],
      child: const MaterialApp(home: ModulesPage()),
    ));
    await tester.pumpAndSettle();

    final names = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();
    expect(names.indexOf('Yoklama'), lessThan(names.indexOf('Yatak-Dolap Düzeni')));
    expect(names.indexOf('Kitap Takibi'), lessThan(names.indexOf('Deneme Sınavları')));
    expect(find.byIcon(Icons.drag_handle), findsWidgets);
    await tester.scrollUntilVisible(find.text('Yurda özel'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Yurda özel'), findsOneWidget);
  });
}
