-- Silme senaryoları: veri girmiş öğretmenin hesabı ve tüm yurt silinebilmeli.
\set ON_ERROR_STOP 1
set client_min_messages = warning;

insert into auth.users (email, raw_user_meta_data) values
  ('root@dormy.app', '{}'),
  ('a1@a.com', '{"signup_type":"tenant","tenant_name":"A Yurdu","full_name":"Ali Admin"}'),
  ('b1@b.com', '{"signup_type":"tenant","tenant_name":"B Yurdu","full_name":"Berk Admin"}');
select public.promote_superadmin('root@dormy.app');
select id as ta from tenants where name = 'A Yurdu' \gset
insert into invitations (tenant_id, email, full_name, role) values (:'ta', 't1@a.com', 'Tuba', 'teacher');
insert into auth.users (email) values ('t1@a.com');
select id as t1 from profiles where email = 't1@a.com' \gset

select tests.login('a1@a.com');
insert into students (tenant_id, first_name, last_name) values (:'ta', 'Ahmet', 'Y');
insert into groups (tenant_id, kind, name) values (:'ta', 'study', 'Etüt-1');
insert into group_teachers (tenant_id, group_id, teacher_id) select :'ta', id, :'t1' from groups;
select assign_student_group(s.id, 'study', (select id from groups)) from students s;
insert into subjects (tenant_id, name) values (:'ta', 'Matematik');
select tests.logout();

select tests.login('t1@a.com');
insert into entries (module_id, student_id, entry_date, session, choice)
  select m.id, s.id, current_date, 0, 'present' from modules m, students s where m.code = 'attendance';
insert into exams (tenant_id, group_id, subject_id, held_on) select :'ta', g.id, sb.id, current_date from groups g, subjects sb;
insert into exam_results (exam_id, student_id, score) select e.id, s.id, 80 from exams e, students s;
insert into assessments (tenant_id, kind, group_id, subject_id, held_on) select :'ta', 'test', g.id, sb.id, current_date from groups g, subjects sb;
insert into assessment_sections (assessment_id, name, subject_id, question_count) select a.id, 'Mat', sb.id, 10 from assessments a, subjects sb;
insert into assessment_results (section_id, student_id, correct, wrong) select sec.id, s.id, 5, 2 from assessment_sections sec, students s;
insert into books (tenant_id, title, page_count) values (:'ta', 'Sefiller', 100);
insert into book_assignments (book_id, student_id) select b.id, s.id from books b, students s;
select tests.logout();

-- Öğretmen hesabı silinir; girdiği kayıtlar kalır, "giren" alanı boşalır
delete from auth.users where email = 't1@a.com';
select tests.eq((select count(*) from entries where recorded_by is null), 1::bigint, 'yoklama kaydı korunur');
select tests.eq((select count(*) from exam_results where updated_by is null), 1::bigint, 'yazılı notu korunur');
select tests.eq((select count(*) from assessment_results where updated_by is null), 1::bigint, 'test sonucu korunur');
select tests.eq((select count(*) from book_assignments where assigned_by is null), 1::bigint, 'kitap ataması korunur');

-- Normal güncelleme hâlâ doğrulanır
select tests.login('a1@a.com');
select tests.expect_error($$update entries set choice = 'late'$$, 'yoklama');
select tests.expect_error($$update assessment_results set correct = 9$$, 'geçemez');
select tests.logout();

-- Kullanılan ders, grup ve kitap tek başına silinemez (koruma sürer)
select tests.login('a1@a.com');
select tests.expect_error($$delete from subjects$$, 'foreign key');
select tests.expect_error($$delete from groups$$, 'foreign key');
select tests.expect_error($$delete from books$$, 'foreign key');
select tests.logout();
select tests.eq((select count(*) from subjects) + (select count(*) from groups) + (select count(*) from books), 3::bigint, 'ders/grup/kitap duruyor');

-- Superadmin tüm yurdu silebilir
select tests.login('root@dormy.app');
delete from tenants where id = :'ta';
select tests.logout();
select tests.eq((select count(*) from tenants where id = :'ta'), 0::bigint, 'yurt silindi');
select tests.eq((select count(*) from students) + (select count(*) from entries) + (select count(*) from exams), 0::bigint, 'yurt verisi silindi');
select tests.eq((select count(*) from tenants where name = 'B Yurdu'), 1::bigint, 'diğer yurt duruyor');

\echo 'SİLME TESTLERİ BAŞARILI'
