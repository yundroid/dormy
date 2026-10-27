-- Faz 2: yazılı, test, deneme ve kitap takibi için RLS / iş kuralı testleri.
\set ON_ERROR_STOP 1
set client_min_messages = warning;

insert into auth.users (email, raw_user_meta_data) values
  ('a1@a.com', '{"signup_type":"tenant","tenant_name":"A Yurdu","full_name":"Ali Admin"}'),
  ('b1@b.com', '{"signup_type":"tenant","tenant_name":"B Yurdu","full_name":"Berk Admin"}');

select tests.login('a1@a.com');
insert into invitations (tenant_id, email, full_name, role) select id, 't1@a.com', 'Tuba', 'teacher' from tenants;
insert into invitations (tenant_id, email, full_name, role) select id, 't2@a.com', 'Taner', 'teacher' from tenants;
select tests.logout();
insert into auth.users (email) values ('t1@a.com'), ('t2@a.com');

select tests.login('a1@a.com');
select tests.eq((select count(*) from modules where value_type in ('exam', 'test', 'trial_exam', 'book')), 4::bigint, 'özel modüller');
insert into students (tenant_id, first_name, last_name) select id, 'Ahmet', 'Y' from tenants;
insert into students (tenant_id, first_name, last_name) select id, 'Mehmet', 'K' from tenants;
insert into students (tenant_id, first_name, last_name) select id, 'Can', 'D' from tenants;
insert into groups (tenant_id, kind, name) select id, 'study', 'Etüt-1' from tenants;
insert into groups (tenant_id, kind, name) select id, 'study', 'Etüt-2' from tenants;
insert into groups (tenant_id, kind, name) select id, 'internal', 'Dahili-1' from tenants;
insert into group_teachers (tenant_id, group_id, teacher_id)
  select g.tenant_id, g.id, p.id from groups g, profiles p where g.name = 'Etüt-1' and p.email = 't1@a.com';
insert into group_teachers (tenant_id, group_id, teacher_id)
  select g.tenant_id, g.id, p.id from groups g, profiles p where g.name in ('Etüt-2', 'Dahili-1') and p.email = 't2@a.com';
select assign_student_group(s.id, 'study', (select id from groups where name = 'Etüt-1')) from students s where first_name in ('Ahmet', 'Mehmet');
select assign_student_group(s.id, 'study', (select id from groups where name = 'Etüt-2')) from students s where first_name = 'Can';
insert into subjects (tenant_id, name) select id, 'Matematik' from tenants;
insert into subjects (tenant_id, name) select id, 'Fizik' from tenants;
insert into topics (tenant_id, subject_id, name) select tenant_id, id, 'Türev' from subjects where name = 'Matematik';
insert into topics (tenant_id, subject_id, name) select tenant_id, id, 'Kuvvet' from subjects where name = 'Fizik';
select tests.logout();

select g.id as g1, g.tenant_id as ta from groups g where name = 'Etüt-1' \gset
select id as g2 from groups where name = 'Etüt-2' \gset
select id as gi from groups where name = 'Dahili-1' \gset
select id as mat from subjects where name = 'Matematik' \gset
select id as fiz from subjects where name = 'Fizik' \gset
select id as turev from topics where name = 'Türev' \gset
select id as kuvvet from topics where name = 'Kuvvet' \gset
select id as s1 from students where first_name = 'Ahmet' \gset
select id as s2 from students where first_name = 'Mehmet' \gset
select id as s3 from students where first_name = 'Can' \gset

-- ---- Yazılılar
select tests.login('t1@a.com');
insert into exams (tenant_id, group_id, subject_id, topic_id, title, held_on)
  values (:'ta', :'g1', :'mat', :'turev', '1. Yazılı', current_date);
select tests.expect_error(format($$insert into exams (tenant_id, group_id, subject_id, held_on) values (%L, %L, %L, current_date)$$, :'ta', :'g2', :'mat'), 'row-level');
select tests.expect_error(format($$insert into exams (tenant_id, group_id, subject_id, held_on) values (%L, %L, %L, current_date)$$, :'ta', :'gi', :'mat'));
select tests.expect_error(format($$insert into exams (tenant_id, group_id, subject_id, topic_id, held_on) values (%L, %L, %L, %L, current_date)$$, :'ta', :'g1', :'mat', :'kuvvet'), 'foreign key');
select id as e1 from exams where title = '1. Yazılı' \gset
insert into exam_results (exam_id, student_id, score) values (:'e1', :'s1', 92.5), (:'e1', :'s2', 71);
select tests.expect_error(format($$insert into exam_results (exam_id, student_id, score) values (%L, %L, 101)$$, :'e1', :'s3'), 'check');
insert into exam_results (exam_id, student_id, score) values (:'e1', :'s2', 75)
  on conflict (exam_id, student_id) do update set score = excluded.score;
select tests.eq((select score from exam_results where student_id = :'s2'), 75.00::numeric, 'yazılı notu güncellendi');
select tests.logout();

select tests.login('t2@a.com');
select tests.eq((select count(*) from exam_results), 2::bigint, 'diğer öğretmen sonuçları görür');
update exam_results set score = 0 where exam_id = :'e1';
select tests.expect_error(format($$insert into exam_results (exam_id, student_id, score) values (%L, %L, 50)$$, :'e1', :'s3'), 'row-level');
select tests.logout();
select tests.eq((select min(score) from exam_results), 75.00::numeric, 't2, t1 sınavını değiştiremez');

-- ---- Testler
select tests.login('t1@a.com');
insert into assessments (tenant_id, kind, group_id, subject_id, topic_id, title, held_on)
  values (:'ta', 'test', :'g1', :'mat', :'turev', 'Türev testi', current_date);
select id as t1test from assessments where title = 'Türev testi' \gset
insert into assessment_sections (assessment_id, name, subject_id, question_count) values (:'t1test', 'Matematik', :'mat', 20);
select id as sec from assessment_sections where assessment_id = :'t1test' \gset
select tests.expect_error(format($$insert into assessment_results (section_id, student_id, correct, wrong) values (%L, %L, 15, 6)$$, :'sec', :'s1'), 'geçemez');
insert into assessment_results (section_id, student_id, correct, wrong) values (:'sec', :'s1', 12, 6), (:'sec', :'s2', 18, 2);
select tests.eq((select net from assessment_results where student_id = :'s1'), 10::numeric, 'net = D - Y/3');
select tests.eq((select assessment_id from assessment_results where student_id = :'s1'), :'t1test'::uuid, 'assessment_id tetikleyiciyle dolar');
select tests.expect_error(format($$update assessment_sections set question_count = 19 where id = %L$$, :'sec'), 'soru sayısı');
update assessment_sections set question_count = 25 where id = :'sec';
select tests.expect_error(format($$insert into assessments (tenant_id, kind, group_id, held_on) values (%L, 'test', %L, current_date)$$, :'ta', :'g1'), 'check');

-- ---- Deneme
insert into assessments (tenant_id, kind, group_id, title, held_on) values (:'ta', 'trial', :'g1', 'TYT-1', current_date);
select id as tr from assessments where title = 'TYT-1' \gset
insert into assessment_sections (assessment_id, name, subject_id, question_count, sort_order)
  values (:'tr', 'Matematik', :'mat', 40, 0), (:'tr', 'Fen', :'fiz', 20, 1);
insert into assessment_results (section_id, student_id, correct, wrong)
  select s.id, :'s1', 30, 9 from assessment_sections s where s.assessment_id = :'tr' and s.name = 'Matematik';
insert into assessment_results (section_id, student_id, correct, wrong)
  select s.id, :'s1', 10, 3 from assessment_sections s where s.assessment_id = :'tr' and s.name = 'Fen';
select tests.eq((select sum(net) from assessment_results where assessment_id = :'tr' and student_id = :'s1'), 36::numeric, 'deneme toplam net');
select tests.logout();

select tests.login('t2@a.com');
select tests.expect_error(format($$insert into assessment_sections (assessment_id, name, question_count) values (%L, 'Hack', 10)$$, :'tr'), 'row-level');
delete from assessments where id = :'tr';
select tests.logout();
select tests.eq((select count(*) from assessments where id = :'tr'), 1::bigint, 't2, t1 denemesini silemez');

-- ---- Grup silme koruması
select tests.login('a1@a.com');
select tests.expect_error(format($$delete from groups where id = %L$$, :'g1'), 'foreign key');
select tests.logout();

-- ---- Kitaplar
select tests.login('t1@a.com');
insert into books (tenant_id, title, author, page_count) values (:'ta', 'Sefiller', 'Victor Hugo', 300);
select id as book from books where title = 'Sefiller' \gset
insert into book_assignments (book_id, student_id) values (:'book', :'s1');
select tests.expect_error(format($$insert into book_assignments (book_id, student_id) values (%L, %L)$$, :'book', :'s3'), 'row-level');
update book_assignments set pages_read = 120 where student_id = :'s1';
select tests.eq((select status from book_assignments where student_id = :'s1'), 'reading'::book_status, 'okuma başladı');
select tests.eq((select started_on from book_assignments where student_id = :'s1'), current_date, 'başlama tarihi');
update book_assignments set pages_read = 999 where student_id = :'s1';
select tests.eq((select pages_read from book_assignments where student_id = :'s1'), 300, 'sayfa sayısı sınırlanır');
update book_assignments set status = 'finished' where student_id = :'s1';
select tests.eq((select finished_on from book_assignments where student_id = :'s1'), current_date, 'bitirme tarihi');
select tests.logout();

select tests.login('t2@a.com');
update books set title = 'Hack' where id = :'book';
insert into books (tenant_id, title) values (:'ta', 'Nutuk');
insert into book_assignments (book_id, student_id) values (:'book', :'s3');
select tests.logout();
select tests.eq((select title from books where id = :'book'), 'Sefiller', 'başkasının kitabı değiştirilemez');

-- ---- Modül kapatılınca yazma engellenir
select tests.login('a1@a.com');
update modules set is_active = false where code = 'exams';
select tests.expect_error($$insert into modules (tenant_id, name, scope, value_type) select id, 'Sahte', 'general', 'exam' from tenants$$, 'sistem');
select tests.expect_error(format($$insert into entries (module_id, student_id, entry_date, value) select id, %L, current_date, 1 from modules where code = 'tests'$$, :'s1'));
select tests.logout();
select tests.login('t1@a.com');
select tests.expect_error(format($$insert into exams (tenant_id, group_id, subject_id, held_on) values (%L, %L, %L, current_date)$$, :'ta', :'g1', :'mat'), 'row-level');
select tests.logout();

-- ---- Yurt izolasyonu
select tests.login('b1@b.com');
select tests.eq((select count(*) from exams) + (select count(*) from assessment_results) + (select count(*) from books), 0::bigint, 'B, A verisini görmez');
select tests.expect_error(format($$insert into exam_results (exam_id, student_id, score) values (%L, %L, 10)$$, :'e1', :'s3'), 'row-level');
select tests.logout();

\echo 'FAZ 2 TESTLERİ BAŞARILI'
