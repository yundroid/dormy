import '../core/formatters.dart';
import 'enums.dart';

export 'enums.dart';

DateTime? _ts(Object? v) => v == null ? null : DateTime.parse(v as String);

class Tenant {
  Tenant({
    required this.id,
    required this.name,
    required this.status,
    this.city,
    this.address,
    this.phone,
    this.email,
    this.maxTeachers,
    this.maxStudents,
    this.subscriptionEndsOn,
    this.createdAt,
    this.activatedAt,
  });

  final String id;
  final String name;
  final TenantStatus status;
  final String? city;
  final String? address;
  final String? phone;
  final String? email;
  final int? maxTeachers;
  final int? maxStudents;
  final DateTime? subscriptionEndsOn;
  final DateTime? createdAt;
  final DateTime? activatedAt;

  factory Tenant.fromJson(Map<String, dynamic> j) => Tenant(
        id: j['id'] as String,
        name: j['name'] as String,
        status: TenantStatus.parse(j['status'] as String),
        city: j['city'] as String?,
        address: j['address'] as String?,
        phone: j['phone'] as String?,
        email: j['email'] as String?,
        maxTeachers: j['max_teachers'] as int?,
        maxStudents: j['max_students'] as int?,
        subscriptionEndsOn: j['subscription_ends_on'] == null ? null : parseDate(j['subscription_ends_on'] as String),
        createdAt: _ts(j['created_at']),
        activatedAt: _ts(j['activated_at']),
      );
}

class Profile {
  Profile({
    required this.id,
    required this.role,
    required this.fullName,
    required this.email,
    required this.status,
    required this.passwordSet,
    this.tenantId,
    this.phone,
    this.lastSeenAt,
  });

  final String id;
  final String? tenantId;
  final UserRole role;
  final String fullName;
  final String email;
  final String? phone;
  final AccountStatus status;
  final bool passwordSet;
  final DateTime? lastSeenAt;

  bool get isActive => status == AccountStatus.active;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        tenantId: j['tenant_id'] as String?,
        role: UserRole.parse(j['role'] as String),
        fullName: j['full_name'] as String,
        email: j['email'] as String,
        phone: j['phone'] as String?,
        status: AccountStatus.parse(j['status'] as String),
        passwordSet: j['password_set'] as bool? ?? true,
        lastSeenAt: _ts(j['last_seen_at']),
      );
}

/// Oturum açan kullanıcının bağlamı (get_my_context RPC).
class UserContext {
  UserContext({required this.profile, required this.today, required this.backfillDays, this.tenant});

  final Profile profile;
  final Tenant? tenant;

  /// Yurdun yerel saatine göre bugün (sunucudan).
  final DateTime today;
  final int backfillDays;

  UserRole get role => profile.role;
  bool get isSuperadmin => role == UserRole.superadmin;
  bool get isAdmin => role == UserRole.admin;
  String get tenantId => tenant!.id;

  /// Öğretmenin veri girebileceği en eski tarih (admin için sınır yok).
  DateTime? get earliestEntryDate => isAdmin ? null : today.subtract(Duration(days: backfillDays));

  factory UserContext.fromJson(Map<String, dynamic> j) => UserContext(
        profile: Profile.fromJson(j['profile'] as Map<String, dynamic>),
        tenant: j['tenant'] == null ? null : Tenant.fromJson(j['tenant'] as Map<String, dynamic>),
        today: parseDate(j['today'] as String),
        backfillDays: j['backfill_days'] as int? ?? 7,
      );
}

class Student {
  Student({
    required this.id,
    required this.tenantId,
    required this.firstName,
    required this.lastName,
    required this.status,
    this.schoolGrade,
    this.roomNo,
    this.phone,
    this.guardianName,
    this.guardianPhone,
    this.notes,
  });

  final String id;
  final String tenantId;
  final String firstName;
  final String lastName;
  final StudentStatus status;
  final String? schoolGrade;
  final String? roomNo;
  final String? phone;
  final String? guardianName;
  final String? guardianPhone;
  final String? notes;

  String get fullName => '$firstName $lastName';

  factory Student.fromJson(Map<String, dynamic> j) => Student(
        id: j['id'] as String,
        tenantId: j['tenant_id'] as String,
        firstName: j['first_name'] as String,
        lastName: j['last_name'] as String,
        status: StudentStatus.parse(j['status'] as String),
        schoolGrade: j['school_grade'] as String?,
        roomNo: j['room_no'] as String?,
        phone: j['phone'] as String?,
        guardianName: j['guardian_name'] as String?,
        guardianPhone: j['guardian_phone'] as String?,
        notes: j['notes'] as String?,
      );
}

class Group {
  Group({
    required this.id,
    required this.tenantId,
    required this.kind,
    required this.name,
    this.description,
    this.isArchived = false,
  });

  final String id;
  final String tenantId;
  final GroupKind kind;
  final String name;
  final String? description;
  final bool isArchived;

  factory Group.fromJson(Map<String, dynamic> j) => Group(
        id: j['id'] as String,
        tenantId: j['tenant_id'] as String,
        kind: GroupKind.parse(j['kind'] as String),
        name: j['name'] as String,
        description: j['description'] as String?,
        isArchived: j['is_archived'] as bool? ?? false,
      );
}

class Membership {
  Membership({required this.groupId, required this.studentId, required this.kind});

  final String groupId;
  final String studentId;
  final GroupKind kind;

  factory Membership.fromJson(Map<String, dynamic> j) => Membership(
        groupId: j['group_id'] as String,
        studentId: j['student_id'] as String,
        kind: GroupKind.parse(j['kind'] as String),
      );
}

class Subject {
  Subject({required this.id, required this.name, required this.sortOrder, required this.topics});

  final String id;
  final String name;
  final int sortOrder;
  final List<Topic> topics;

  factory Subject.fromJson(Map<String, dynamic> j) => Subject(
        id: j['id'] as String,
        name: j['name'] as String,
        sortOrder: j['sort_order'] as int? ?? 0,
        topics: ((j['topics'] as List?) ?? const [])
            .map((t) => Topic.fromJson(t as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.sortOrder != b.sortOrder ? a.sortOrder.compareTo(b.sortOrder) : a.name.compareTo(b.name)),
      );
}

class Topic {
  Topic({required this.id, required this.subjectId, required this.name, required this.sortOrder});

  final String id;
  final String subjectId;
  final String name;
  final int sortOrder;

  factory Topic.fromJson(Map<String, dynamic> j) => Topic(
        id: j['id'] as String,
        subjectId: j['subject_id'] as String,
        name: j['name'] as String,
        sortOrder: j['sort_order'] as int? ?? 0,
      );
}

class DormModule {
  DormModule({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.icon,
    required this.scope,
    required this.valueType,
    required this.sessions,
    required this.isSystem,
    required this.isActive,
    required this.includeInReports,
    required this.weight,
    required this.sortOrder,
    this.code,
    this.description,
    this.minValue,
    this.maxValue,
  });

  final String id;
  final String tenantId;
  final String? code;
  final String name;
  final String? description;
  final String icon;
  final ModuleScope scope;
  final ModuleValueType valueType;
  final int? minValue;
  final int? maxValue;
  final List<String> sessions;
  final bool isSystem;
  final bool isActive;
  final bool includeInReports;
  final double weight;
  final int sortOrder;

  String get scaleLabel => switch (valueType) {
        ModuleValueType.attendance => 'Var / Yok / İzinli',
        ModuleValueType.score => '$minValue – $maxValue puan',
        ModuleValueType.yesNo => 'Evet / Hayır',
      };

  factory DormModule.fromJson(Map<String, dynamic> j) => DormModule(
        id: j['id'] as String,
        tenantId: j['tenant_id'] as String,
        code: j['code'] as String?,
        name: j['name'] as String,
        description: j['description'] as String?,
        icon: j['icon'] as String? ?? 'checklist',
        scope: ModuleScope.parse(j['scope'] as String),
        valueType: ModuleValueType.parse(j['value_type'] as String),
        minValue: j['min_value'] as int?,
        maxValue: j['max_value'] as int?,
        sessions: (j['sessions'] as List).cast<String>(),
        isSystem: j['is_system'] as bool? ?? false,
        isActive: j['is_active'] as bool? ?? true,
        includeInReports: j['include_in_reports'] as bool? ?? true,
        weight: (j['weight'] as num?)?.toDouble() ?? 1,
        sortOrder: j['sort_order'] as int? ?? 100,
      );
}

/// Bir modül ekranında listelenen öğrenci (module_students RPC).
class ModuleStudent {
  ModuleStudent({
    required this.studentId,
    required this.firstName,
    required this.lastName,
    this.roomNo,
    this.schoolGrade,
    this.groupId,
    this.groupName,
  });

  final String studentId;
  final String firstName;
  final String lastName;
  final String? roomNo;
  final String? schoolGrade;
  final String? groupId;
  final String? groupName;

  String get fullName => '$firstName $lastName';

  factory ModuleStudent.fromJson(Map<String, dynamic> j) => ModuleStudent(
        studentId: j['student_id'] as String,
        firstName: j['first_name'] as String,
        lastName: j['last_name'] as String,
        roomNo: j['room_no'] as String?,
        schoolGrade: j['school_grade'] as String?,
        groupId: j['group_id'] as String?,
        groupName: j['group_name'] as String?,
      );
}

class Entry {
  Entry({
    required this.id,
    required this.studentId,
    required this.session,
    this.value,
    this.choice,
    this.recordedBy,
    this.updatedAt,
  });

  final String id;
  final String studentId;
  final int session;
  final num? value;
  final String? choice;
  final String? recordedBy;
  final DateTime? updatedAt;

  factory Entry.fromJson(Map<String, dynamic> j) => Entry(
        id: j['id'] as String,
        studentId: j['student_id'] as String,
        session: j['session'] as int,
        value: j['value'] as num?,
        choice: j['choice'] as String?,
        recordedBy: j['recorded_by'] as String?,
        updatedAt: _ts(j['updated_at']),
      );
}

/// Superadmin yurt özeti (tenant_overview RPC).
class TenantOverview {
  TenantOverview({
    required this.tenant,
    required this.adminCount,
    required this.teacherCount,
    required this.studentCount,
    required this.pendingInvites,
    required this.entriesLast30d,
    this.lastEntryAt,
    this.lastSeenAt,
  });

  final Tenant tenant;
  final int adminCount;
  final int teacherCount;
  final int studentCount;
  final int pendingInvites;
  final int entriesLast30d;
  final DateTime? lastEntryAt;
  final DateTime? lastSeenAt;

  factory TenantOverview.fromJson(Map<String, dynamic> j) => TenantOverview(
        tenant: Tenant.fromJson(j),
        adminCount: j['admin_count'] as int,
        teacherCount: j['teacher_count'] as int,
        studentCount: j['student_count'] as int,
        pendingInvites: j['pending_invites'] as int,
        entriesLast30d: j['entries_last_30d'] as int,
        lastEntryAt: _ts(j['last_entry_at']),
        lastSeenAt: _ts(j['last_seen_at']),
      );
}
