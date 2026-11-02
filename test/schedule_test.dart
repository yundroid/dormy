import 'package:dormy/core/session.dart';
import 'package:dormy/data/schedule_repository.dart';
import 'package:dormy/features/home/home_shell.dart';
import 'package:dormy/features/schedule/schedule_page.dart';
import 'package:dormy/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ScheduleItem _i(String start, String end, String title, [Set<int> days = const {1, 2, 3, 4, 5, 6, 7}]) =>
    ScheduleItem(id: title, start: parseTimeOfDay(start), end: parseTimeOfDay(end), title: title, days: days);

void _login(UserRole role) => session.debugSetContext(UserContext(
      profile: Profile(
        id: 'u',
        tenantId: 't',
        role: role,
        fullName: 'Kişi',
        email: 'k@a.com',
        status: AccountStatus.active,
        passwordSet: true,
      ),
      tenant: Tenant(id: 't', name: 'A Yurdu', status: TenantStatus.active),
      today: DateTime(2026, 11, 4),
      backfillDays: 7,
    ));

final _items = [
  _i('19:15', '21:30', 'Akşam etüdü'),
  _i('06:30', '07:00', 'Kalkış'),
  _i('09:30', '12:00', 'Hafta sonu etüdü', {6}),
  _i('07:00', '07:30', 'Kahvaltı', {1, 2, 3, 4, 5}),
];

void main() {
  group('program mantığı', () {
    test('saat dönüşümleri', () {
      expect(parseTimeOfDay('06:30:00'), 390);
      expect(formatMinutes(390), '06:30');
      expect(formatMinutes(0), '00:00');
    });

    test('gün etiketleri', () {
      expect(daysLabel({1, 2, 3, 4, 5, 6, 7}), 'Her gün');
      expect(daysLabel({1, 2, 3, 4, 5}), 'Hafta içi');
      expect(daysLabel({6, 7}), 'Hafta sonu');
      expect(daysLabel({1, 3, 5}), 'Pzt, Çar, Cum');
    });

    test('güne göre filtre ve saat sırası', () {
      expect(itemsForDay(_items, 1).map((i) => i.title), ['Kalkış', 'Kahvaltı', 'Akşam etüdü']);
      expect(itemsForDay(_items, 6).map((i) => i.title), ['Kalkış', 'Hafta sonu etüdü', 'Akşam etüdü']);
    });

    test('şimdi ve sıradaki', () {
      final day = itemsForDay(_items, 1);
      expect(statesFor(day, parseTimeOfDay('06:45')),
          [ScheduleState.now, ScheduleState.next, ScheduleState.later]);
      expect(statesFor(day, parseTimeOfDay('12:00')),
          [ScheduleState.past, ScheduleState.past, ScheduleState.next]);
      expect(statesFor(day, parseTimeOfDay('23:00')),
          [ScheduleState.past, ScheduleState.past, ScheduleState.past]);
    });
  });

  group('alt çubuk', () {
    test('Program ortada; Yönetim Ayarlar altında', () {
      final admin = navLayoutFor(UserRole.admin);
      expect(admin.left.map((d) => d.label), ['Kontroller', 'Öğrencilerim']);
      expect(admin.center?.label, 'Program');
      expect(admin.right.map((d) => d.label), ['Raporlar', 'Ayarlar']);
      expect(admin.right.last.matches('/admin/students'), isTrue);
      expect(navLayoutFor(UserRole.teacher).right.map((d) => d.label), ['Ayarlar']);
      expect(navLayoutFor(UserRole.superadmin).center, isNull);
    });
  });

  group('program ekranı', () {
    Widget app() => ProviderScope(
          overrides: [scheduleProvider.overrideWith((ref) async => _items)],
          child: const MaterialApp(home: SchedulePage()),
        );

    testWidgets('öğretmen sadece görüntüler', (tester) async {
      _login(UserRole.teacher);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('Başlangıç'), findsOneWidget);
      expect(find.text('Kalkış'), findsOneWidget);
      expect(find.text('Ekle'), findsNothing);
      await tester.tap(find.text('Kalkış'));
      await tester.pumpAndSettle();
      expect(find.text('Düzenle'), findsNothing);
      // başka güne geçiş
      await tester.tap(find.textContaining('Cmt'));
      await tester.pumpAndSettle();
      expect(find.text('Hafta sonu etüdü'), findsOneWidget);
    });

    testWidgets('yönetici ekler ve düzenler', (tester) async {
      _login(UserRole.admin);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('Ekle'), findsOneWidget);
      await tester.tap(find.text('Kalkış'));
      await tester.pumpAndSettle();
      expect(find.text('Düzenle'), findsOneWidget);
      expect(find.text('Sil'), findsOneWidget);
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ekle'));
      await tester.pumpAndSettle();
      expect(find.text('Programa ekle'), findsOneWidget);
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();
      expect(find.text('Bu alan zorunlu'), findsOneWidget);
    });
  });
}
