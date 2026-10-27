enum UserRole {
  superadmin('Sistem Yöneticisi'),
  admin('Yönetici'),
  teacher('Öğretmen');

  const UserRole(this.label);
  final String label;

  static UserRole parse(String v) => UserRole.values.byName(v);
}

enum TenantStatus {
  pending('Pasif'),
  active('Aktif'),
  suspended('Askıda');

  const TenantStatus(this.label);
  final String label;

  static TenantStatus parse(String v) => TenantStatus.values.byName(v);
}

enum AccountStatus {
  active('Aktif'),
  disabled('Pasif');

  const AccountStatus(this.label);
  final String label;

  static AccountStatus parse(String v) => AccountStatus.values.byName(v);
}

enum StudentStatus {
  active('Aktif'),
  left('Ayrıldı'),
  graduated('Mezun');

  const StudentStatus(this.label);
  final String label;

  static StudentStatus parse(String v) => StudentStatus.values.byName(v);
}

enum GroupKind {
  study('Etüt Grubu', 'Etüt Grupları'),
  internal('Dahili Ders Grubu', 'Dahili Ders Grupları');

  const GroupKind(this.label, this.pluralLabel);
  final String label;
  final String pluralLabel;

  static GroupKind parse(String v) => GroupKind.values.byName(v);
}

enum ModuleScope {
  general('Yurt geneli (tüm öğretmenler)', null),
  studyGroup('Etüt grubuna özel', GroupKind.study),
  internalGroup('Dahili ders grubuna özel', GroupKind.internal);

  const ModuleScope(this.label, this.groupKind);
  final String label;
  final GroupKind? groupKind;

  String get dbValue => switch (this) {
        general => 'general',
        studyGroup => 'study_group',
        internalGroup => 'internal_group',
      };

  static ModuleScope parse(String v) => switch (v) {
        'general' => general,
        'study_group' => studyGroup,
        'internal_group' => internalGroup,
        _ => throw ArgumentError(v),
      };
}

enum ModuleValueType {
  attendance('Yoklama (Var / Yok / İzinli)'),
  score('Puan'),
  yesNo('Evet / Hayır'),
  // Kendi ekranı olan özel modüller (günlük giriş almaz)
  exam('Yazılı'),
  test('Test'),
  trialExam('Deneme sınavı'),
  book('Kitap takibi');

  const ModuleValueType(this.label);
  final String label;

  /// Günlük giriş ekranını kullanan tipler (yurda özel modüllerde seçilebilir)
  bool get isEntryType => this == attendance || this == score || this == yesNo;

  /// Özel modülün ekran adresi
  String? get route => switch (this) {
        exam => '/exams',
        test => '/tests',
        trialExam => '/trials',
        book => '/books',
        _ => null,
      };

  String get dbValue => switch (this) {
        attendance => 'attendance',
        score => 'score',
        yesNo => 'yes_no',
        exam => 'exam',
        test => 'test',
        trialExam => 'trial_exam',
        book => 'book',
      };

  static ModuleValueType parse(String v) => values.firstWhere((t) => t.dbValue == v, orElse: () => throw ArgumentError(v));
}

enum AttendanceChoice {
  present('Var'),
  absent('Yok'),
  excused('İzinli');

  const AttendanceChoice(this.label);
  final String label;

  static AttendanceChoice parse(String v) => AttendanceChoice.values.byName(v);
}
