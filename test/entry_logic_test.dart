import 'package:dormy/core/router.dart';
import 'package:dormy/core/session.dart';
import 'package:dormy/features/entries/entry_logic.dart';
import 'package:dormy/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

DormModule _module({
  ModuleValueType type = ModuleValueType.score,
  int? min = 1,
  int? max = 5,
  List<String> sessions = const ['Günlük'],
}) =>
    DormModule(
      id: 'm',
      tenantId: 't',
      name: 'Test',
      icon: 'checklist',
      scope: ModuleScope.general,
      valueType: type,
      minValue: min,
      maxValue: max,
      sessions: sessions,
      isSystem: false,
      isActive: true,
      includeInReports: true,
      weight: 1,
      sortOrder: 0,
    );

Entry _entry(String student, int session, {num? value, String? choice}) =>
    Entry(id: '$student-$session', studentId: student, session: session, value: value, choice: choice);

void main() {
  group('oturum seçimi', () {
    test('vakit başına giriş sayısı', () {
      final entries = [_entry('a', 0), _entry('b', 0), _entry('a', 2)];
      expect(sessionCounts(5, entries), [2, 0, 1, 0, 0]);
    });

    test('tamamlanmamış ilk vakit seçilir', () {
      final entries = [_entry('a', 0), _entry('b', 0), _entry('a', 1)];
      expect(firstIncompleteSession(5, entries, 2), 1);
    });

    test('hepsi tamamsa son vakit seçilir', () {
      final entries = [for (var s = 0; s < 3; s++) _entry('a', s)];
      expect(firstIncompleteSession(3, entries, 1), 2);
    });
  });

  group('özet', () {
    test('yoklama sayımları', () {
      final m = _module(type: ModuleValueType.attendance, min: null, max: null);
      final s = summarize(m, ['present', 'present', 'absent', 'excused', null]);
      expect(s.filled, 4);
      expect(s.attendance![AttendanceChoice.present], 2);
      expect(s.attendance![AttendanceChoice.absent], 1);
      expect(s.attendance![AttendanceChoice.excused], 1);
    });

    test('puan ortalaması boşları saymaz', () {
      final s = summarize(_module(), [5, 4, null, 3]);
      expect(s.filled, 3);
      expect(s.average, 4);
    });

    test('toplu doldurma seçenekleri yüksekten düşüğe', () {
      expect(valueOptions(_module()).map((o) => o.value), [5, 4, 3, 2, 1]);
      expect(valueOptions(_module(min: 1, max: 100)).map((o) => o.value), [100]);
    });
  });

  group('yönlendirme', () {
    test('çıkış yapmış kullanıcı girişe yönlenir', () {
      expect(resolveRedirect(status: SessionStatus.signedOut, role: null, location: '/home'), '/login');
      expect(resolveRedirect(status: SessionStatus.signedOut, role: null, location: '/register'), isNull);
    });

    test('davetli kullanıcı şifre belirlemeye yönlenir', () {
      expect(resolveRedirect(status: SessionStatus.needsPassword, role: UserRole.teacher, location: '/home'), '/set-password');
    });

    test('öğretmen yönetim paneline giremez', () {
      expect(resolveRedirect(status: SessionStatus.ready, role: UserRole.teacher, location: '/admin/students'), '/home');
      expect(resolveRedirect(status: SessionStatus.ready, role: UserRole.teacher, location: '/tenants'), '/home');
      expect(resolveRedirect(status: SessionStatus.ready, role: UserRole.teacher, location: '/module/x'), isNull);
    });

    test('admin yönetim paneline girer, superadmin ekranına giremez', () {
      expect(resolveRedirect(status: SessionStatus.ready, role: UserRole.admin, location: '/admin/students'), isNull);
      expect(resolveRedirect(status: SessionStatus.ready, role: UserRole.admin, location: '/tenants/1'), '/home');
    });

    test('superadmin yurtlar ekranına yönlenir', () {
      expect(resolveRedirect(status: SessionStatus.ready, role: UserRole.superadmin, location: '/login'), '/tenants');
      expect(resolveRedirect(status: SessionStatus.ready, role: UserRole.superadmin, location: '/home'), '/tenants');
      expect(resolveRedirect(status: SessionStatus.ready, role: UserRole.superadmin, location: '/admin'), '/tenants');
      expect(resolveRedirect(status: SessionStatus.ready, role: UserRole.superadmin, location: '/exams/1'), '/tenants');
      expect(resolveRedirect(status: SessionStatus.ready, role: UserRole.superadmin, location: '/profile'), isNull);
    });

    test('öğretmen akademik modüllere girer', () {
      for (final path in ['/exams', '/tests/1', '/trials/new', '/books']) {
        expect(resolveRedirect(status: SessionStatus.ready, role: UserRole.teacher, location: path), isNull);
      }
    });
  });
}
