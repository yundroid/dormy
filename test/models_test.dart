import 'package:dormy/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('get_my_context yanıtı çözümlenir', () {
    final ctx = UserContext.fromJson({
      'profile': {
        'id': 'u1',
        'tenant_id': 't1',
        'role': 'teacher',
        'full_name': 'Tuba Öğretmen',
        'email': 't@a.com',
        'phone': null,
        'status': 'active',
        'password_set': false,
        'created_at': '2026-10-27T08:00:00.123456+00:00',
        'last_seen_at': null,
      },
      'tenant': {
        'id': 't1',
        'name': 'A Yurdu',
        'status': 'pending',
        'max_teachers': 3,
        'max_students': null,
        'subscription_ends_on': '2027-06-30',
        'created_at': '2026-10-27T08:00:00+00:00',
      },
      'today': '2026-10-27',
      'backfill_days': 7,
    });
    expect(ctx.role, UserRole.teacher);
    expect(ctx.profile.passwordSet, isFalse);
    expect(ctx.tenant!.status, TenantStatus.pending);
    expect(ctx.tenant!.maxStudents, isNull);
    expect(ctx.tenant!.subscriptionEndsOn, DateTime(2027, 6, 30));
    expect(ctx.earliestEntryDate, DateTime(2026, 10, 20));
  });

  test('admin için geriye dönük sınır yok', () {
    final ctx = UserContext(
      profile: Profile(
        id: 'a',
        role: UserRole.admin,
        fullName: 'A',
        email: 'a@a.com',
        status: AccountStatus.active,
        passwordSet: true,
        tenantId: 't',
      ),
      today: DateTime(2026, 10, 27),
      backfillDays: 7,
    );
    expect(ctx.earliestEntryDate, isNull);
  });

  test('modül çözümlenir', () {
    final m = DormModule.fromJson({
      'id': 'm',
      'tenant_id': 't',
      'code': 'attendance',
      'name': 'Yoklama',
      'icon': 'fact_check',
      'scope': 'general',
      'value_type': 'attendance',
      'min_value': null,
      'max_value': null,
      'sessions': ['Sabah', 'Öğle', 'İkindi', 'Akşam', 'Yatsı'],
      'is_system': true,
      'is_active': true,
      'include_in_reports': true,
      'weight': 1,
      'sort_order': 10,
    });
    expect(m.scope, ModuleScope.general);
    expect(m.sessions, hasLength(5));
    expect(m.scaleLabel, 'Var / Yok / İzinli');
    expect(ModuleScope.parse('study_group').groupKind, GroupKind.study);
  });
}
