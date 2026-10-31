import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/env.dart';
import '../core/formatters.dart';
import '../core/session.dart';
import '../core/supabase.dart';
import '../features/admin/student_import.dart';
import '../models/models.dart';

List<Map<String, dynamic>> _rows(Object? data) => (data as List).cast<Map<String, dynamic>>();

String? _blank(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

// ---------------------------------------------------------------------------
// Okuma sağlayıcıları (RLS sayesinde sadece kullanıcının yurdunun verisi gelir)
// ---------------------------------------------------------------------------

final modulesProvider = FutureProvider<List<DormModule>>((ref) async {
  final data = await db.from('modules').select().order('sort_order').order('name');
  return _rows(data).map(DormModule.fromJson).toList();
});

/// Kullanıcının öğretmeni olduğu grup türleri (gruba özel modülleri göstermek için).
final myGroupKindsProvider = FutureProvider<Set<GroupKind>>((ref) async {
  final data = await db.from('group_teachers').select('groups!inner(kind)').eq('teacher_id', currentUserId!);
  return _rows(data).map((r) => GroupKind.parse((r['groups'] as Map)['kind'] as String)).toSet();
});

final moduleStudentsProvider = FutureProvider.autoDispose.family<List<ModuleStudent>, String>((ref, moduleId) async {
  final data = await db.rpc('module_students', params: {'p_module': moduleId});
  return _rows(data).map(ModuleStudent.fromJson).toList();
});

typedef EntryKey = ({String moduleId, DateTime date});

final entriesProvider = FutureProvider.autoDispose.family<List<Entry>, EntryKey>((ref, key) async {
  final data = await db
      .from('entries')
      .select('id, student_id, session, value, choice, recorded_by, updated_at')
      .eq('module_id', key.moduleId)
      .eq('entry_date', isoDate(key.date));
  return _rows(data).map(Entry.fromJson).toList();
});

/// Yurdun yönetici ve öğretmenleri
final staffProvider = FutureProvider<List<Profile>>((ref) async {
  final data = await db
      .from('profiles')
      .select()
      .eq('tenant_id', session.ctx.tenantId)
      .order('role')
      .order('full_name');
  return _rows(data).map(Profile.fromJson).toList();
});

final studentsProvider = FutureProvider<List<Student>>((ref) async {
  final data = await db.from('students').select().order('first_name').order('last_name');
  return _rows(data).map(Student.fromJson).toList();
});

final groupsProvider = FutureProvider<List<Group>>((ref) async {
  final data = await db.from('groups').select().order('name');
  return _rows(data).map(Group.fromJson).toList();
});

/// Aktif grup üyelikleri
final membershipsProvider = FutureProvider<List<Membership>>((ref) async {
  final data = await db.from('group_students').select('group_id, student_id, kind').isFilter('end_date', null);
  return _rows(data).map(Membership.fromJson).toList();
});

/// groupId -> öğretmen id'leri
final groupTeachersProvider = FutureProvider<Map<String, Set<String>>>((ref) async {
  final data = await db.from('group_teachers').select('group_id, teacher_id');
  final map = <String, Set<String>>{};
  for (final r in _rows(data)) {
    map.putIfAbsent(r['group_id'] as String, () => {}).add(r['teacher_id'] as String);
  }
  return map;
});

final subjectsProvider = FutureProvider<List<Subject>>((ref) async {
  final data = await db
      .from('subjects')
      .select('id, name, sort_order, topics(id, subject_id, name, sort_order)')
      .order('sort_order')
      .order('name');
  return _rows(data).map(Subject.fromJson).toList();
});

// Superadmin
final tenantOverviewProvider = FutureProvider<List<TenantOverview>>((ref) async {
  final data = await db.rpc('tenant_overview');
  return _rows(data).map(TenantOverview.fromJson).toList();
});

final tenantAdminsProvider = FutureProvider.autoDispose.family<List<Profile>, String>((ref, tenantId) async {
  final data = await db.from('profiles').select().eq('tenant_id', tenantId).eq('role', 'admin').order('full_name');
  return _rows(data).map(Profile.fromJson).toList();
});

/// E-postaya gelen kodun amacı
enum CodePurpose { signup, recovery, invite }

// ---------------------------------------------------------------------------
// Yazma işlemleri
// ---------------------------------------------------------------------------

class Repo {
  static String get _tenantId => session.ctx.tenantId;

  // ---- Kimlik
  static Future<void> signIn(String email, String password) =>
      db.auth.signInWithPassword(email: email.trim(), password: password);

  /// "Hesap oluştur": yeni yurt kaydı. Kayıt olan kişi yurdun ilk yöneticisi olur.
  static Future<bool> registerTenant({
    required String email,
    required String password,
    required String fullName,
    required String tenantName,
    String? city,
    String? phone,
  }) async {
    final res = await db.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: Env.authRedirect,
      data: {
        'signup_type': 'tenant',
        'full_name': fullName.trim(),
        'tenant_name': tenantName.trim(),
        'city': _blank(city),
        'phone': _blank(phone),
      },
    );
    // E-posta doğrulaması açıksa oturum gelmez.
    return res.session != null;
  }

  /// E-postadaki doğrulama kodunu kontrol eder; başarılıysa oturum açılır.
  static Future<void> verifyEmailCode({required String email, required String code, required CodePurpose purpose}) async {
    final e = email.trim(), c = code.replaceAll(RegExp(r'\s'), '');
    switch (purpose) {
      case CodePurpose.signup:
        await db.auth.verifyOTP(email: e, token: c, type: OtpType.signup);
      case CodePurpose.recovery:
        session.beginRecovery();
        try {
          await db.auth.verifyOTP(email: e, token: c, type: OtpType.recovery);
        } catch (_) {
          session.cancelRecovery();
          rethrow;
        }
      case CodePurpose.invite:
        // "Daveti tekrar gönder" şifre sıfırlama e-postası yollar; o kod da kabul edilir.
        try {
          await db.auth.verifyOTP(email: e, token: c, type: OtpType.invite);
        } on AuthException {
          await db.auth.verifyOTP(email: e, token: c, type: OtpType.recovery);
        }
    }
  }

  static Future<void> resendSignupCode(String email) =>
      db.auth.resend(type: OtpType.signup, email: email.trim(), emailRedirectTo: Env.authRedirect);

  static Future<void> sendPasswordReset(String email) =>
      db.auth.resetPasswordForEmail(email.trim(), redirectTo: Env.authRedirect);

  static Future<void> updatePassword(String password) async {
    await db.auth.updateUser(UserAttributes(password: password));
  }

  // ---- Davet (Edge Function)
  static Future<void> invite({
    required String tenantId,
    required String email,
    required String fullName,
    String? phone,
    required UserRole role,
  }) async {
    await db.functions.invoke('invite-user', body: {
      'tenant_id': tenantId,
      'email': email.trim(),
      'full_name': fullName.trim(),
      'phone': _blank(phone),
      'role': role.name,
      'redirect_to': ?Env.authRedirect,
    });
  }

  static Future<void> updateProfile(String id, {required String fullName, String? phone}) async {
    await db.from('profiles').update({'full_name': fullName.trim(), 'phone': _blank(phone)}).eq('id', id);
  }

  static Future<void> setProfileStatus(String id, AccountStatus status) async {
    await db.from('profiles').update({'status': status.name}).eq('id', id);
  }

  // ---- Öğrenciler
  static Future<String> saveStudent({
    String? id,
    required String firstName,
    required String lastName,
    String? schoolGrade,
    String? roomNo,
    String? phone,
    String? guardianName,
    String? guardianPhone,
    String? notes,
    required StudentStatus status,
  }) async {
    final payload = {
      'tenant_id': _tenantId,
      'first_name': firstName.trim(),
      'last_name': lastName.trim(),
      'school_grade': _blank(schoolGrade),
      'room_no': _blank(roomNo),
      'phone': _blank(phone),
      'guardian_name': _blank(guardianName),
      'guardian_phone': _blank(guardianPhone),
      'notes': _blank(notes),
      'status': status.name,
    };
    if (id == null) {
      final row = await db.from('students').insert(payload).select('id').single();
      return row['id'] as String;
    }
    await db.from('students').update(payload).eq('id', id);
    return id;
  }

  static Future<void> deleteStudent(String id) => db.from('students').delete().eq('id', id);

  /// Excel'den toplu öğrenci ekler. Eklenen öğrenci sayısını döner.
  /// [createGroups]: plandaki eksik gruplar oluşturulsun mu (hayırsa o öğrenciler grupsuz eklenir).
  /// [includeSkipped]: "zaten kayıtlı / dosyada tekrar" diye atlanan satırlar da eklensin mi.
  static Future<int> importStudents(ImportPlan plan, {required bool createGroups, bool includeSkipped = false}) async {
    final rows = plan.rows.where((r) => r.isValid && (!r.skip || includeSkipped)).toList();
    if (rows.isEmpty) return 0;

    final groupIds = Map.of(plan.matchedGroups);
    if (createGroups && plan.newGroups.isNotEmpty) {
      final created = await db
          .from('groups')
          .insert([
            for (final g in plan.newGroups) {'tenant_id': _tenantId, 'kind': g.kind.name, 'name': g.name},
          ])
          .select('id, kind, name');
      for (final r in (created as List).cast<Map<String, dynamic>>()) {
        groupIds[(GroupKind.parse(r['kind'] as String), normalizeKey(r['name'] as String))] = r['id'] as String;
      }
    }

    final today = isoDate(session.ctx.today);
    var imported = 0;
    // Büyük dosyalarda istek boyutunu sınırlamak için parça parça
    for (var start = 0; start < rows.length; start += 100) {
      final chunk = rows.sublist(start, (start + 100).clamp(0, rows.length));
      final inserted = await db
          .from('students')
          .insert([
            for (final r in chunk)
              {
                'tenant_id': _tenantId,
                'first_name': r.firstName,
                'last_name': r.lastName,
                'school_grade': r.value(ImportField.schoolGrade),
                'room_no': r.value(ImportField.roomNo),
                'phone': r.value(ImportField.phone),
                'guardian_name': r.value(ImportField.guardianName),
                'guardian_phone': r.value(ImportField.guardianPhone),
                'notes': r.value(ImportField.notes),
                'status': StudentStatus.active.name,
              },
          ])
          .select('id');
      final ids = [for (final r in (inserted as List).cast<Map<String, dynamic>>()) r['id'] as String];

      // INSERT ... RETURNING satırları ekleme sırasıyla döner
      final memberships = <Map<String, dynamic>>[];
      for (var i = 0; i < chunk.length && i < ids.length; i++) {
        for (final kind in GroupKind.values) {
          final name = plan.groupNameOf(chunk[i], kind);
          final groupId = name == null ? null : groupIds[(kind, normalizeKey(name))];
          if (groupId == null) continue;
          memberships.add({
            'tenant_id': _tenantId,
            'group_id': groupId,
            'student_id': ids[i],
            'kind': kind.name,
            'start_date': today,
          });
        }
      }
      if (memberships.isNotEmpty) await db.from('group_students').insert(memberships);
      imported += ids.length;
    }
    return imported;
  }

  static Future<void> assignStudentGroup(String studentId, GroupKind kind, String? groupId) =>
      db.rpc('assign_student_group', params: {'p_student': studentId, 'p_kind': kind.name, 'p_group': groupId});

  // ---- Gruplar
  static Future<void> saveGroup({String? id, required GroupKind kind, required String name, String? description}) async {
    final payload = {'tenant_id': _tenantId, 'kind': kind.name, 'name': name.trim(), 'description': _blank(description)};
    if (id == null) {
      await db.from('groups').insert(payload);
    } else {
      await db.from('groups').update(payload).eq('id', id);
    }
  }

  static Future<void> deleteGroup(String id) => db.from('groups').delete().eq('id', id);

  static Future<void> setGroupArchived(String id, bool archived) =>
      db.from('groups').update({'is_archived': archived}).eq('id', id);

  static Future<void> setGroupTeachers(String groupId, Set<String> before, Set<String> after) async {
    final removed = before.difference(after);
    final added = after.difference(before);
    if (removed.isNotEmpty) {
      await db.from('group_teachers').delete().eq('group_id', groupId).inFilter('teacher_id', removed.toList());
    }
    if (added.isNotEmpty) {
      await db.from('group_teachers').insert([
        for (final t in added) {'tenant_id': _tenantId, 'group_id': groupId, 'teacher_id': t},
      ]);
    }
  }

  // ---- Dersler / konular
  static Future<void> saveSubject({String? id, required String name, int sortOrder = 0}) async {
    final payload = {'tenant_id': _tenantId, 'name': name.trim(), 'sort_order': sortOrder};
    if (id == null) {
      await db.from('subjects').insert(payload);
    } else {
      await db.from('subjects').update(payload).eq('id', id);
    }
  }

  static Future<void> deleteSubject(String id) => db.from('subjects').delete().eq('id', id);

  static Future<void> saveTopic({String? id, required String subjectId, required String name, int sortOrder = 0}) async {
    final payload = {'tenant_id': _tenantId, 'subject_id': subjectId, 'name': name.trim(), 'sort_order': sortOrder};
    if (id == null) {
      await db.from('topics').insert(payload);
    } else {
      await db.from('topics').update(payload).eq('id', id);
    }
  }

  static Future<void> deleteTopic(String id) => db.from('topics').delete().eq('id', id);

  // ---- Modüller
  static Future<void> saveModule({
    String? id,
    required String name,
    String? description,
    required String icon,
    required ModuleScope scope,
    required ModuleValueType valueType,
    int? minValue,
    int? maxValue,
    required List<String> sessions,
    required bool includeInReports,
    required double weight,
    bool? isActive,
  }) async {
    final payload = <String, dynamic>{
      'name': name.trim(),
      'description': _blank(description),
      'icon': icon,
      'sessions': sessions,
      'include_in_reports': includeInReports,
      'weight': weight,
      'is_active': ?isActive,
    };
    if (id == null) {
      await db.from('modules').insert({
        ...payload,
        'tenant_id': _tenantId,
        'scope': scope.dbValue,
        'value_type': valueType.dbValue,
        'min_value': valueType == ModuleValueType.score ? minValue : null,
        'max_value': valueType == ModuleValueType.score ? maxValue : null,
      });
    } else {
      await db.from('modules').update(payload).eq('id', id);
    }
  }

  static Future<void> setModuleActive(String id, bool active) =>
      db.from('modules').update({'is_active': active}).eq('id', id);

  static Future<void> deleteModule(String id) => db.from('modules').delete().eq('id', id);

  // ---- Girişler
  /// [changes]: öğrenci id -> yeni değer (null = kaydı sil)
  static Future<void> saveEntries({
    required DormModule module,
    required DateTime date,
    required int sessionIndex,
    required Map<String, Object?> changes,
  }) async {
    final upserts = <Map<String, dynamic>>[];
    final deletes = <String>[];
    changes.forEach((studentId, v) {
      if (v == null) {
        deletes.add(studentId);
        return;
      }
      upserts.add({
        'module_id': module.id,
        'student_id': studentId,
        'entry_date': isoDate(date),
        'session': sessionIndex,
        'value': v is num ? v : null,
        'choice': v is String ? v : null,
      });
    });
    if (upserts.isNotEmpty) {
      await db.from('entries').upsert(upserts, onConflict: 'module_id,student_id,entry_date,session');
    }
    if (deletes.isNotEmpty) {
      await db
          .from('entries')
          .delete()
          .eq('module_id', module.id)
          .eq('entry_date', isoDate(date))
          .eq('session', sessionIndex)
          .inFilter('student_id', deletes);
    }
  }

  // ---- Superadmin
  static Future<void> updateTenant(String id, Map<String, dynamic> values) =>
      db.from('tenants').update(values).eq('id', id);
}
