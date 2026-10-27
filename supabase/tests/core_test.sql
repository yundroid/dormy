-- Faz 1 şeması için RLS / iş kuralı testleri.
-- Çalıştırma: supabase/tests/run_local.sh
\set ON_ERROR_STOP 1
set client_min_messages = warning;

-- GoTrue'nun kayıt sırasında yaptığı insert'ü taklit eder
insert into auth.users (email, raw_user_meta_data) values
  ('root@dormy.app', '{}'),
  ('a1@a.com', '{"signup_type":"tenant","tenant_name":"A Yurdu","city":"Ankara","full_name":"Ali Admin","phone":"555"}'),
  ('b1@b.com', '{"signup_type":"tenant","tenant_name":"B Yurdu","full_name":"Berk Admin"}'),
  ('random@x.com', '{}');
select public.promote_superadmin('root@dormy.app');

select tests.eq((select count(*) from tenants), 2::bigint, 'iki yurt oluştu');
select tests.eq((select status from tenants where name = 'A Yurdu'), 'pending'::tenant_status, 'yurt pasif başlar');
select tests.eq((select count(*) from modules m join tenants t on t.id = m.tenant_id where t.name = 'A Yurdu'), 8::bigint, 'varsayılan modüller');
select tests.eq((select role from profiles where email = 'a1@a.com'), 'admin'::user_role, 'kayıt olan admin olur');
select tests.eq((select count(*) from profiles where email = 'random@x.com'), 0::bigint, 'davetsiz kullanıcıya profil yok');

-- ---- Admin A
select tests.login('a1@a.com');
select tests.eq((select count(*) from tenants), 1::bigint, 'admin sadece kendi yurdunu görür');
select tests.expect_error($$update tenants set status = 'active'$$, 'sistem yöneticisi');
select tests.expect_error($$update tenants set max_students = 100$$, 'sistem yöneticisi');
update tenants set phone = '0312' where name = 'A Yurdu';
select tests.expect_error($$insert into invitations (tenant_id, email, full_name, role) select id, 'x@a.com', 'X', 'admin' from tenants$$);
insert into invitations (tenant_id, email, full_name, role) select id, 'T1@a.com', 'Tuba Öğretmen', 'teacher' from tenants;
insert into invitations (tenant_id, email, full_name, role) select id, 't2@a.com', 'Taner Öğretmen', 'teacher' from tenants;
insert into invitations (tenant_id, email, full_name, role) select id, 't3@a.com', 'Tülin Öğretmen', 'teacher' from tenants;
select tests.expect_error($$insert into invitations (tenant_id, email, full_name, role) select id, 't4@a.com', 'T4', 'teacher' from tenants$$, 'kota');
select tests.expect_error($$insert into invitations (tenant_id, email, full_name, role) select id, 'b1@b.com', 'B', 'teacher' from tenants$$);
insert into students (tenant_id, first_name, last_name, room_no) select id, 'Ahmet', 'Yılmaz', '101' from tenants;
insert into students (tenant_id, first_name, last_name, room_no) select id, 'Mehmet', 'Kaya', '101' from tenants;
insert into students (tenant_id, first_name, last_name, room_no) select id, 'Can', 'Demir', '102' from tenants;
select tests.expect_error($$insert into students (tenant_id, first_name, last_name) select id, 'Fazla', 'Öğrenci' from tenants$$, 'kota');
delete from modules where code = 'attendance'; -- RLS: sessizce 0 satır
select tests.eq((select count(*) from modules where code = 'attendance'), 1::bigint, 'sistem modülü silinmedi');
select tests.expect_error($$update modules set max_value = 10 where code = 'bed_locker'$$, 'değiştirilemez');
update modules set sessions = array['Sabah','Akşam','Yatsı'] where code = 'attendance';
update modules set is_active = false where code = 'internal_score';
update modules set is_active = true where code = 'internal_score';
insert into modules (tenant_id, name, scope, value_type) select id, 'Defter Kontrolü', 'study_group', 'yes_no' from tenants;
select tests.expect_error($$insert into modules (tenant_id, name, scope, value_type, is_system) select id, 'Hack', 'general', 'yes_no', true from tenants$$);
select tests.logout();

-- ---- Superadmin
select tests.login('root@dormy.app');
select tests.eq((select count(*) from tenant_overview()), 2::bigint, 'superadmin tüm yurtları görür');
select tests.eq((select student_count from tenant_overview() where name = 'A Yurdu'), 3::bigint, 'özet öğrenci sayısı');
select tests.eq((select pending_invites from tenant_overview() where name = 'A Yurdu'), 3::bigint, 'özet bekleyen davet');
select tests.eq((select count(*) from students), 0::bigint, 'superadmin öğrenci verisi görmez');
update tenants set status = 'active', max_teachers = 10, max_students = 50 where name = 'A Yurdu';
select tests.eq((select activated_at is not null from tenants where name = 'A Yurdu'), true, 'aktif tarihi');
insert into invitations (tenant_id, email, full_name, role) select id, 'a2@a.com', 'Ayşe Admin', 'admin' from tenants where name = 'A Yurdu';
select tests.logout();

select tests.login('a1@a.com');
select tests.expect_error($$select * from tenant_overview()$$, 'yetki');
select tests.logout();

-- Davetliler hesap açar
insert into auth.users (email) values ('t1@a.com'), ('t2@a.com'), ('t3@a.com'), ('a2@a.com');
select tests.eq((select role from profiles where email = 't1@a.com'), 'teacher'::user_role, 'davetli öğretmen');
select tests.eq((select password_set from profiles where email = 't1@a.com'), false, 'davetli şifre belirlemeli');
select tests.eq((select role from profiles where email = 'a2@a.com'), 'admin'::user_role, 'superadmin admin ekledi');
select tests.eq((select count(*) from invitations where accepted_at is null), 0::bigint, 'davetler kabul edildi');

-- ---- Gruplar
select tests.login('a1@a.com');
insert into groups (tenant_id, kind, name) select id, 'study', 'Etüt-1' from tenants;
insert into groups (tenant_id, kind, name) select id, 'study', 'Etüt-2' from tenants;
insert into groups (tenant_id, kind, name) select id, 'internal', 'Dahili-1' from tenants;
insert into group_teachers (tenant_id, group_id, teacher_id)
  select g.tenant_id, g.id, p.id from groups g, profiles p where g.name = 'Etüt-1' and p.email = 't1@a.com';
insert into group_teachers (tenant_id, group_id, teacher_id)
  select g.tenant_id, g.id, p.id from groups g, profiles p where g.name = 'Dahili-1' and p.email = 't2@a.com';
select assign_student_group(s.id, 'study', (select id from groups where name = 'Etüt-1')) from students s where first_name in ('Ahmet', 'Mehmet');
select assign_student_group(s.id, 'study', (select id from groups where name = 'Etüt-2')) from students s where first_name = 'Can';
select assign_student_group(s.id, 'internal', (select id from groups where name = 'Dahili-1')) from students s where first_name = 'Can';
-- aynı gün tekrar atama: eski üyelik silinir, tek aktif üyelik kalır
select assign_student_group(s.id, 'study', (select id from groups where name = 'Etüt-2')) from students s where first_name = 'Mehmet';
select assign_student_group(s.id, 'study', (select id from groups where name = 'Etüt-1')) from students s where first_name = 'Mehmet';
select tests.eq((select count(*) from group_students gs join students s on s.id = gs.student_id where s.first_name = 'Mehmet'), 1::bigint, 'tek aktif üyelik');
select tests.expect_error($$insert into group_students (tenant_id, group_id, student_id) select s.tenant_id, (select id from groups where name = 'Etüt-2'), s.id from students s where first_name = 'Ahmet'$$);
-- geriye dönük admin girişi
insert into entries (module_id, student_id, entry_date, value)
  select m.id, s.id, current_date - 30, 4 from modules m, students s where m.code = 'bed_locker' and s.first_name = 'Ahmet';
select tests.logout();

-- ---- Öğretmen t1 (Etüt-1)
select tests.login('t1@a.com');
select public.mark_password_set();
select tests.eq((select password_set from profiles where email = 't1@a.com'), true, 'şifre belirlendi');
select tests.eq((select count(*) from module_students((select id from modules where code = 'attendance'))), 3::bigint, 'yoklama: tüm öğrenciler');
select tests.eq((select count(*) from module_students((select id from modules where code = 'study_score'))), 2::bigint, 'etüt: kendi grubu');
insert into entries (module_id, student_id, entry_date, session, choice)
  select m.id, s.id, current_date, 0, 'present' from modules m, students s where m.code = 'attendance';
insert into entries (module_id, student_id, entry_date, session, choice)
  select m.id, s.id, current_date - 7, 2, 'excused' from modules m, students s where m.code = 'attendance' and s.first_name = 'Can';
select tests.expect_error($$insert into entries (module_id, student_id, entry_date, session, choice) select m.id, s.id, current_date - 8, 0, 'present' from modules m, students s where m.code = 'attendance' and s.first_name = 'Can'$$, 'row-level');
select tests.expect_error($$insert into entries (module_id, student_id, entry_date, session, choice) select m.id, s.id, current_date + 1, 0, 'present' from modules m, students s where m.code = 'attendance' and s.first_name = 'Can'$$, 'row-level');
select tests.expect_error($$insert into entries (module_id, student_id, entry_date, session, choice) select m.id, s.id, current_date, 3, 'present' from modules m, students s where m.code = 'attendance' and s.first_name = 'Can'$$, 'oturum');
select tests.expect_error($$insert into entries (module_id, student_id, entry_date, session, choice) select m.id, s.id, current_date, 1, 'late' from modules m, students s where m.code = 'attendance' and s.first_name = 'Can'$$, 'yoklama');
insert into entries (module_id, student_id, entry_date, value)
  select m.id, s.id, current_date, 5 from modules m, students s where m.code = 'study_score' and s.first_name = 'Ahmet';
select tests.expect_error($$insert into entries (module_id, student_id, entry_date, value) select m.id, s.id, current_date, 6 from modules m, students s where m.code = 'study_score' and s.first_name = 'Mehmet'$$, 'arasında');
select tests.expect_error($$insert into entries (module_id, student_id, entry_date, value) select m.id, s.id, current_date, 3 from modules m, students s where m.code = 'study_score' and s.first_name = 'Can'$$, 'row-level');
select tests.expect_error($$insert into entries (module_id, student_id, entry_date, value) select m.id, s.id, current_date, 3 from modules m, students s where m.code = 'internal_score' and s.first_name = 'Can'$$, 'row-level');
-- upsert (başka öğretmenin girdiğini güncelleme)
insert into entries (module_id, student_id, entry_date, session, choice)
  select m.id, s.id, current_date, 0, 'absent' from modules m, students s where m.code = 'attendance' and s.first_name = 'Can'
  on conflict (module_id, student_id, entry_date, session) do update set choice = excluded.choice;
select tests.eq((select choice from entries e join students s on s.id = e.student_id join modules m on m.id = e.module_id where m.code = 'attendance' and s.first_name = 'Can' and e.entry_date = current_date and session = 0), 'absent', 'upsert');
update profiles set full_name = 'Hack' where email = 't2@a.com'; -- RLS: sessizce 0 satır
select tests.eq((select full_name from profiles where email = 't2@a.com'), 'Taner Öğretmen', 'başka profili değiştiremez');
select tests.expect_error($$update profiles set role = 'admin' where email = 't1@a.com'$$, 'değiştirilemez');
select tests.expect_error($$insert into students (tenant_id, first_name, last_name) select id, 'X', 'Y' from tenants$$, 'row-level');
-- admin girişi 30 gün öncesini düzenleyemez
update entries set value = 1 where entry_date = current_date - 30;
select tests.eq((select value from entries where entry_date = current_date - 30), 4::numeric, 'öğretmen eski kaydı değiştiremez');
select tests.logout();

-- ---- Öğretmen t2 (Dahili-1)
select tests.login('t2@a.com');
insert into entries (module_id, student_id, entry_date, value)
  select m.id, s.id, current_date, 2 from modules m, students s where m.code = 'internal_score' and s.first_name = 'Can';
select tests.eq((select count(*) from module_students((select id from modules where code = 'study_score'))), 0::bigint, 't2 etüt grubu yok');
select tests.logout();

-- ---- B yurdu izolasyonu
select m.id as a_att, s.id as a_student, s.tenant_id as a_tenant
  from modules m join students s on s.tenant_id = m.tenant_id
  where m.code = 'attendance' and s.first_name = 'Ahmet' \gset
select tests.login('b1@b.com');
select tests.eq((select count(*) from students), 0::bigint, 'B, A öğrencilerini görmez');
select tests.eq((select count(*) from entries), 0::bigint, 'B, A girişlerini görmez');
select tests.eq((select count(*) from profiles), 1::bigint, 'B sadece kendini görür');
select tests.eq((select count(*) from module_students(:'a_att')), 0::bigint, 'B, A modülü öğrencilerini göremez');
select tests.expect_error(format($$insert into entries (module_id, student_id, entry_date, choice) values (%L, %L, current_date, 'present')$$, :'a_att', :'a_student'), 'row-level');
select tests.expect_error(format($$insert into students (tenant_id, first_name, last_name) values (%L, 'X', 'Y')$$, :'a_tenant'), 'row-level');
update students set first_name = 'Hack' where id = :'a_student';
select tests.logout();
select tests.eq((select first_name from students where id = :'a_student'), 'Ahmet', 'B, A öğrencisini değiştiremez');

-- ---- Admin pasifleştirme ve öğrenci ayrılışı
select tests.login('a1@a.com');
select tests.expect_error($$update profiles set status = 'disabled' where email = 'a2@a.com'$$, 'sistem yöneticisi');
update profiles set status = 'disabled' where email = 't3@a.com';
update students set status = 'left' where first_name = 'Can';
select tests.eq((select count(*) from group_students gs join students s on s.id = gs.student_id where s.first_name = 'Can' and gs.end_date is null), 0::bigint, 'ayrılan öğrencinin üyelikleri kapanır');
select tests.logout();

select tests.login('t3@a.com');
select tests.eq((select count(*) from students), 0::bigint, 'pasif öğretmen veri görmez');
select tests.logout();

-- ---- Askıya alma
select tests.login('root@dormy.app');
update tenants set status = 'suspended' where name = 'A Yurdu';
select tests.logout();
select tests.login('t1@a.com');
select tests.eq((select count(*) from students), 0::bigint, 'askıdaki yurt veri göremez');
select tests.eq((get_my_context() -> 'tenant' ->> 'status'), 'suspended', 'bağlam askı durumunu döner');
select tests.logout();

\echo 'FAZ 1 TESTLERİ BAŞARILI'
