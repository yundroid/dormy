-- Günlük program: yönetici yazar, öğretmen sadece okur, yurtlar ayrık.
\set ON_ERROR_STOP 1
set client_min_messages = warning;

insert into auth.users (email, raw_user_meta_data) values
  ('a1@a.com', '{"signup_type":"tenant","tenant_name":"A Yurdu","full_name":"Ali Admin"}'),
  ('b1@b.com', '{"signup_type":"tenant","tenant_name":"B Yurdu","full_name":"Berk Admin"}');
select id as ta from tenants where name = 'A Yurdu' \gset
insert into invitations (tenant_id, email, full_name, role) values (:'ta', 't1@a.com', 'Tuba', 'teacher');
insert into auth.users (email) values ('t1@a.com');

select tests.login('a1@a.com');
insert into schedule_items (tenant_id, starts_at, ends_at, title) values
  (:'ta', '06:30', '07:00', 'Kalkış ve sabah yoklaması'),
  (:'ta', '19:00', '21:00', 'Akşam etüdü');
insert into schedule_items (tenant_id, starts_at, ends_at, title, days) values
  (:'ta', '09:00', '12:00', 'Hafta sonu etüdü', '{6,7}');
select tests.expect_error(format($$insert into schedule_items (tenant_id, starts_at, ends_at, title) values (%L, '10:00', '09:00', 'Ters')$$, :'ta'), 'check');
select tests.expect_error(format($$insert into schedule_items (tenant_id, starts_at, ends_at, title, days) values (%L, '10:00', '11:00', 'Geçersiz gün', '{8}')$$, :'ta'), 'check');
update schedule_items set title = 'Akşam etüdü (2 saat)' where title = 'Akşam etüdü';
select tests.logout();

select tests.login('t1@a.com');
select tests.eq((select count(*) from schedule_items), 3::bigint, 'öğretmen programı görür');
select tests.eq((select count(*) from schedule_items where 6 = any(days)), 3::bigint, 'cumartesi 3 satır');
select tests.eq((select count(*) from schedule_items where 1 = any(days)), 2::bigint, 'pazartesi 2 satır');
select tests.expect_error(format($$insert into schedule_items (tenant_id, starts_at, ends_at, title) values (%L, '08:00', '09:00', 'Hack')$$, :'ta'), 'row-level');
update schedule_items set title = 'Değişti';
delete from schedule_items;
select tests.logout();
select tests.eq((select count(*) from schedule_items where title = 'Değişti'), 0::bigint, 'öğretmen değiştiremez');
select tests.eq((select count(*) from schedule_items), 3::bigint, 'öğretmen silemez');

select tests.login('b1@b.com');
select tests.eq((select count(*) from schedule_items), 0::bigint, 'B, A programını görmez');
select tests.logout();

\echo 'GÜNLÜK PROGRAM TESTLERİ BAŞARILI'
