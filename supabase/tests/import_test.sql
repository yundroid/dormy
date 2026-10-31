-- Excel'den toplu öğrenci yükleme: uygulamanın yaptığı toplu insert'lerin RLS ve kota altında çalışması.
\set ON_ERROR_STOP 1
set client_min_messages = warning;

insert into auth.users (email, raw_user_meta_data) values
  ('a1@a.com', '{"signup_type":"tenant","tenant_name":"A Yurdu","full_name":"Ali Admin"}'),
  ('b1@b.com', '{"signup_type":"tenant","tenant_name":"B Yurdu","full_name":"Berk Admin"}');
select id as ta from tenants where name = 'A Yurdu' \gset
update tenants set max_students = 5 where id = :'ta';

select tests.login('a1@a.com');
-- eksik grupları toplu oluştur
insert into groups (tenant_id, kind, name) values (:'ta', 'study', 'Etüt-3'), (:'ta', 'internal', 'Hafızlık');
-- öğrencileri tek seferde ekle
insert into students (tenant_id, first_name, last_name, room_no) values
  (:'ta', 'Ahmet', 'Yılmaz', '204'), (:'ta', 'Mehmet', 'Kaya', null), (:'ta', 'Can', 'Demir', null);
-- grup üyeliklerini tek seferde ekle
insert into group_students (tenant_id, group_id, student_id, kind, start_date)
  select :'ta', g.id, s.id, g.kind, current_date
  from students s, groups g
  where (g.name = 'Etüt-3' and s.first_name in ('Ahmet', 'Mehmet')) or (g.name = 'Hafızlık' and s.first_name = 'Can');
select tests.eq((select count(*) from group_students), 3::bigint, 'üyelikler eklendi');
select tests.eq((select count(*) from group_students where kind = 'internal'), 1::bigint, 'tür doğru');

-- kotayı aşan toplu ekleme tamamen geri alınır (yarım kayıt kalmaz)
select tests.expect_error(format($$insert into students (tenant_id, first_name, last_name) values
  (%1$L, 'D', '1'), (%1$L, 'D', '2'), (%1$L, 'D', '3')$$, :'ta'), 'kota');
select tests.eq((select count(*) from students), 3::bigint, 'kota aşımında hiç öğrenci eklenmez');
insert into students (tenant_id, first_name, last_name) values (:'ta', 'E', '1'), (:'ta', 'E', '2');
select tests.eq((select count(*) from students), 5::bigint, 'kota sınırına kadar eklenir');
select tests.logout();

-- başka yurdun grubuna üye eklenemez
select id as ga from groups where name = 'Etüt-3' \gset
select tests.login('b1@b.com');
insert into students (tenant_id, first_name, last_name) select id, 'B', 'Öğrenci' from tenants;
select tests.expect_error(format($$insert into group_students (tenant_id, group_id, student_id, kind)
  select tenant_id, %L, id, 'study' from students$$, :'ga'));
select tests.logout();

\echo 'TOPLU YÜKLEME TESTLERİ BAŞARILI'
