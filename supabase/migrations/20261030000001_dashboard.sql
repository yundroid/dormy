-- =====================================================================
-- Dormy · Faz 4: kontrol paneli göstergeleri
-- =====================================================================

-- Bugün, kullanıcının doldurabileceği her günlük giriş modülü için
-- oturum (vakit) başına kaç öğrencinin girildiği.
create function public.today_progress()
returns table (module_id uuid, session smallint, filled bigint, total bigint)
language plpgsql stable security definer set search_path = public as $$
declare
  v_tenant uuid := app_tenant();
  v_today date;
  m modules;
begin
  if v_tenant is null then
    return;
  end if;
  v_today := tenant_today(v_tenant);
  for m in
    select * from modules
    where tenant_id = v_tenant and is_active and value_type in ('attendance', 'score', 'yes_no')
  loop
    return query
      with st as (select ms.student_id from module_students(m.id) ms),
      tot as (select count(*) as n from st)
      select m.id, s.i::smallint,
             (select count(*) from entries e
               where e.module_id = m.id and e.entry_date = v_today and e.session = s.i
                 and e.student_id in (select student_id from st)),
             (select n from tot)
      from generate_series(0, cardinality(m.sessions) - 1) as s(i);
  end loop;
end;
$$;

-- Son [p_days] günde en az [p_min] kez "yok" yazılan aktif öğrenciler.
create function public.attendance_alerts(p_days int default 7, p_min int default 3)
returns table (student_id uuid, absent_count bigint, last_absent date)
language sql stable set search_path = public as $$
  select e.student_id, count(*), max(e.entry_date)
  from entries e
  join modules m on m.id = e.module_id
  join students s on s.id = e.student_id
  where e.tenant_id = app_tenant()
    and m.code = 'attendance' and m.is_active
    and s.status = 'active'
    and e.choice = 'absent'
    and e.entry_date > tenant_today(e.tenant_id) - greatest(p_days, 1)
  group by e.student_id
  having count(*) >= greatest(p_min, 1)
  order by count(*) desc
$$;
