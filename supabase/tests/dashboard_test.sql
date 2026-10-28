-- Faz 4: kontrol paneli göstergeleri testleri.
\set ON_ERROR_STOP 1
set client_min_messages = warning;

insert into auth.users (email, raw_user_meta_data) values
  ('a1@a.com', '{"signup_type":"tenant","tenant_name":"A Yurdu","full_name":"Ali Admin"}'),
  ('b1@b.com', '{"signup_type":"tenant","tenant_name":"B Yurdu","full_name":"Berk Admin"}');
select tests.login('a1@a.com');
insert into invitations (tenant_id, email, full_name, role) select id, 't1@a.com', 'Tuba', 'teacher' from tenants;
select tests.logout();
insert into auth.users (email) values ('t1@a.com');

select tests.login('a1@a.com');
insert into students (tenant_id, first_name, last_name) select id, 'Ahmet', 'Y' from tenants;
insert into students (tenant_id, first_name, last_name) select id, 'Mehmet', 'K' from tenants;
insert into students (tenant_id, first_name, last_name) select id, 'Can', 'D' from tenants;
insert into groups (tenant_id, kind, name) select id, 'study', 'Etüt-1' from tenants;
insert into group_teachers (tenant_id, group_id, teacher_id)
  select g.tenant_id, g.id, p.id from groups g, profiles p where p.email = 't1@a.com';
select assign_student_group(s.id, 'study', (select id from groups)) from students s where first_name in ('Ahmet', 'Mehmet');
select tests.logout();

select id as att from modules where code = 'attendance' and tenant_id = (select id from tenants where name = 'A Yurdu') \gset
select id as st from modules where code = 'study_score' and tenant_id = (select id from tenants where name = 'A Yurdu') \gset
select id as s1 from students where first_name = 'Ahmet' \gset
select id as s2 from students where first_name = 'Mehmet' \gset
select id as s3 from students where first_name = 'Can' \gset

select tests.login('t1@a.com');
insert into entries (module_id, student_id, entry_date, session, choice) values
  (:'att', :'s1', current_date, 0, 'present'),
  (:'att', :'s2', current_date, 0, 'absent'),
  (:'att', :'s3', current_date, 0, 'present'),
  (:'att', :'s1', current_date, 1, 'present');
insert into entries (module_id, student_id, entry_date, value) values (:'st', :'s1', current_date, 5);

select tests.eq((select count(*) from today_progress() where module_id = :'att'), 5::bigint, 'yoklama: 5 vakit satırı');
select tests.eq((select filled from today_progress() where module_id = :'att' and session = 0), 3::bigint, 'sabah tamam');
select tests.eq((select total from today_progress() where module_id = :'att' and session = 0), 3::bigint, 'yoklama toplamı tüm öğrenciler');
select tests.eq((select filled from today_progress() where module_id = :'att' and session = 1), 1::bigint, 'öğle 1/3');
select tests.eq((select total from today_progress() where module_id = :'st'), 2::bigint, 'etüt: sadece kendi grubu');
select tests.eq((select filled from today_progress() where module_id = :'st'), 1::bigint, 'etüt 1/2');
select tests.logout();

-- Devamsızlık: Mehmet son 7 günde 3 kez yok, 10 gün önceki sayılmaz
select tests.login('a1@a.com');
insert into entries (module_id, student_id, entry_date, session, choice) values
  (:'att', :'s2', current_date - 1, 0, 'absent'),
  (:'att', :'s2', current_date - 6, 2, 'absent'),
  (:'att', :'s3', current_date - 1, 0, 'absent'),
  (:'att', :'s3', current_date - 10, 0, 'absent'),
  (:'att', :'s3', current_date - 11, 0, 'absent');
select tests.eq((select count(*) from attendance_alerts()), 1::bigint, 'tek uyarı');
select tests.eq((select absent_count from attendance_alerts() where student_id = :'s2'), 3::bigint, 'Mehmet 3 yok');
select tests.eq((select last_absent from attendance_alerts() where student_id = :'s2'), current_date, 'son yok tarihi');
select tests.eq((select count(*) from attendance_alerts(30, 3)), 2::bigint, '30 günde iki öğrenci');
update students set status = 'left' where id = :'s2';
select tests.eq((select count(*) from attendance_alerts()), 0::bigint, 'ayrılan öğrenci uyarı vermez');
select tests.logout();

select tests.login('b1@b.com');
select tests.eq((select count(*) from attendance_alerts(365, 1)), 0::bigint, 'B, A uyarılarını görmez');
select tests.eq((select count(*) from today_progress() where total > 0), 0::bigint, 'B, A ilerlemesini görmez');
select tests.logout();

\echo 'FAZ 4 TESTLERİ BAŞARILI'
