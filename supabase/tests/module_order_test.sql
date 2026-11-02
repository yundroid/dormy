-- Modül sıralaması testleri.
\set ON_ERROR_STOP 1
set client_min_messages = warning;

insert into auth.users (email, raw_user_meta_data) values
  ('a1@a.com', '{"signup_type":"tenant","tenant_name":"A Yurdu","full_name":"Ali Admin"}'),
  ('b1@b.com', '{"signup_type":"tenant","tenant_name":"B Yurdu","full_name":"Berk Admin"}');
select id as ta from tenants where name = 'A Yurdu' \gset
insert into invitations (tenant_id, email, full_name, role) values (:'ta', 't1@a.com', 'Tuba', 'teacher');
insert into auth.users (email) values ('t1@a.com');

select tests.eq(
  (select string_agg(code, ',' order by sort_order) from modules where tenant_id = :'ta'),
  'attendance,bed_locker,study_score,internal_score,exams,tests,books,trial_exams',
  'varsayılan sıra');

select tests.login('a1@a.com');
insert into modules (tenant_id, name, scope, value_type, sort_order) values (:'ta', 'Defter', 'general', 'yes_no', 90);
-- Defter en üste, Yoklama en alta
select reorder_modules(array(
  select id from modules
  order by case when name = 'Defter' then 0 when code = 'attendance' then 99 else sort_order end));
select tests.eq((select name from modules order by sort_order limit 1), 'Defter', 'yönetici sıralar');
select tests.eq((select code from modules order by sort_order desc limit 1), 'attendance', 'yoklama en altta');
select tests.logout();

select tests.login('t1@a.com');
select reorder_modules(array(select id from modules order by sort_order desc));
select tests.logout();
select tests.eq((select name from modules where tenant_id = :'ta' order by sort_order limit 1), 'Defter', 'öğretmen sıralayamaz');

select array_agg(id order by sort_order desc)::text as aids from modules where tenant_id = :'ta' \gset
select tests.login('b1@b.com');
select reorder_modules(:'aids'::uuid[]);
select tests.logout();
select tests.eq((select name from modules where tenant_id = :'ta' order by sort_order limit 1), 'Defter', 'başka yurt sıralayamaz');

\echo 'MODÜL SIRALAMA TESTLERİ BAŞARILI'
