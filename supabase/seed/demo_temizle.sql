-- Dormy · demo verilerini kaldırır (demo_data.sql ile oluşturulan yurt ve hesaplar).
-- Supabase → SQL Editor'de çalıştırın. Gerçek verilerinize dokunmaz.
do $$
declare
  v_tenant uuid;
begin
  select tenant_id into v_tenant from public.profiles where email = 'demo.yonetici@example.com';
  if v_tenant is not null then
    -- yurt silinince öğrenciler, gruplar, kayıtlar, sınavlar ve kitaplar da silinir
    delete from public.tenants where id = v_tenant;
  end if;
  delete from auth.users where email in (
    'demo.yonetici@example.com', 'demo.ogretmen1@example.com', 'demo.ogretmen2@example.com', 'demo.ogretmen3@example.com');
  raise notice 'Demo veriler kaldırıldı.';
end;
$$;
