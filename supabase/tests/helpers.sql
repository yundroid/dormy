-- Test yardımcıları (her test dosyasından önce yüklenir)
set client_min_messages = warning;

create schema tests;
grant usage on schema tests to authenticated;

create function tests.login(p_email text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', (select id::text from auth.users where email = p_email), false);
  set role authenticated;
end $$;

create function tests.logout() returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claim.sub', '', false);
end $$;

create function tests.expect_error(p_sql text, p_like text default null) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if p_like is not null and sqlerrm not ilike '%' || p_like || '%' then
      raise exception 'Beklenmeyen hata: % (beklenen: %) <- %', sqlerrm, p_like, p_sql;
    end if;
    return;
  end;
  raise exception 'Hata bekleniyordu ama gelmedi: %', p_sql;
end $$;

create function tests.eq(p_actual anyelement, p_expected anyelement, p_msg text) returns void language plpgsql as $$
begin
  if p_actual is distinct from p_expected then
    raise exception 'FAIL %: beklenen %, gelen %', p_msg, p_expected, p_actual;
  end if;
end $$;
grant execute on all functions in schema tests to authenticated;
