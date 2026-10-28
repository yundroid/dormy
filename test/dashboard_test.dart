import 'package:dormy/data/dashboard_repository.dart';
import 'package:dormy/features/home/dashboard_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('telefonda da en az 2 sütun', () {
    expect(DashboardPage.columnsFor(320), 2);
    expect(DashboardPage.columnsFor(400), 2);
    expect(DashboardPage.columnsFor(700), 3);
    expect(DashboardPage.columnsFor(1200), 4);
  });

  test('bugünkü doluluk etiketi', () {
    const att = ModuleProgress([
      (session: 0, filled: 30, total: 30),
      (session: 1, filled: 12, total: 30),
      (session: 2, filled: 0, total: 30),
    ]);
    expect(att.label, 'Bugün 1/3 vakit');
    expect(att.complete, isFalse);
    expect(att.ratio, closeTo(42 / 90, 1e-9));

    const bed = ModuleProgress([(session: 0, filled: 30, total: 30)]);
    expect(bed.label, 'Bugün 30/30');
    expect(bed.complete, isTrue);

    const empty = ModuleProgress([(session: 0, filled: 0, total: 0)]);
    expect(empty.label, 'Listede öğrenci yok');
    expect(empty.ratio, 0);
  });
}
