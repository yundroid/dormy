# Dormy – Yurt Takip Sistemi

Öğrenci yurtları için çok kullanıcılı (çok kiracılı) takip uygulaması.
Flutter (Android, iOS, Web) + Supabase (PostgreSQL, Auth, Row Level Security, Edge Functions).

Gereksinim analizi: [`docs/ANALIZ_RAPORU.md`](docs/ANALIZ_RAPORU.md)

## Roller

| Rol | Yetkiler |
|---|---|
| **Sistem yöneticisi (superadmin)** | Tüm yurtları listeler, aktifleştirir / askıya alır, kota ve abonelik belirler, yurtlara yönetici ekler, iletişim bilgilerini ve kullanım özetini görür. Öğrenci verisini görmez. |
| **Yönetici (admin)** | Öğretmenin yapabildiği her şey + yönetim paneli: öğretmen daveti, öğrenci, grup, ders/konu ve modül yönetimi. Geçmiş tarihlere sınırsız veri girebilir. |
| **Öğretmen** | Yurt geneli modülleri (yoklama, yatak-dolap…) tüm öğrenciler için; gruba özel modülleri (etüt, dahili ders…) sadece kendi grubu için doldurur. En fazla **7 gün** geriye veri girebilir. |

Öğrenciler ve veliler uygulamaya giriş yapmaz.

## Faz durumu

- [x] **Faz 1 – Temel:** giriş / şifremi unuttum / yurt kaydı, davetle öğretmen, superadmin paneli, yönetim paneli (öğretmen, öğrenci, etüt & dahili gruplar, ders/konu, modüller), modül motoru ve veri giriş ekranı (yoklama 5 vakit, yatak-dolap, etüt, dahili ders, yurda özel modüller)
- [x] **Faz 2 – Akademik:** yazılılar (0-100), testler (soru sayısı + D/Y, boş otomatik, net = D − Y/3), deneme sınavları
  (çok bölümlü; TYT / AYT / LGS şablonları), kitap takibi (ortak kitap listesi, atama, sayfa ilerlemesi, bitirilenler),
  veliye paylaşılabilir sıralı listeler (PNG görsel / PDF; tam isim, baş harfler veya tek öğrenci seçenekleri)
- [ ] **Faz 3 – Raporlar:** Öğrencilerim (yüzdelik karne), yurt geneli raporlar ve sıralamalar
- [ ] **Faz 4:** bildirimler, Excel dışa aktarım, dönem arşivi

## Kurulum

### 1. Supabase projesi

1. [supabase.com](https://supabase.com) üzerinde bir proje oluşturun.
2. Şemayı yükleyin (Supabase CLI ile):
   ```bash
   supabase link --project-ref PROJE-REF
   supabase db push
   ```
   CLI yoksa `supabase/migrations/*.sql` dosyalarını sırayla **SQL Editor**'de çalıştırın.
3. Davet fonksiyonunu yayınlayın:
   ```bash
   supabase functions deploy invite-user
   supabase secrets set APP_URL=https://yurt-uygulamaniz.example.com
   ```
4. **Authentication → URL Configuration**: *Site URL* olarak web uygulamanızın adresini,
   *Redirect URLs* listesine aynı adresi ekleyin. Davet ve şifre sıfırlama bağlantıları bu adrese yönlenir.
5. **Authentication → Email Templates**: davet / şifre sıfırlama e-postalarını Türkçeleştirebilirsiniz.

### 2. Sistem yöneticisi hesabı

**Authentication → Users → Add user** ile kendi kullanıcınızı oluşturun, sonra SQL Editor'de:

```sql
select public.promote_superadmin('siz@ornek.com');
```

### 3. Uygulamayı çalıştırma

```bash
cp env.example.json env.json   # değerleri doldurun (Project Settings → API)
flutter pub get
flutter run --dart-define-from-file=env.json            # mobil
flutter run -d chrome --dart-define-from-file=env.json  # web
flutter build web --dart-define-from-file=env.json      # web yayını
```

## Akışlar

- **Hesap oluştur** = yeni yurt kaydı. Kaydı yapan kişi yurdun yöneticisi olur; yurt **pasif (deneme)** başlar ve
  varsayılan olarak 3 öğretmen + 3 öğrenci ekleyebilir. Superadmin yurdu aktifleştirip kotaları belirler.
- **Öğretmen daveti:** yönetici e-posta ile davet eder (`invite-user` Edge Function). Davetli kişi bağlantıya
  tıklar, şifresini belirler ve doğrudan yurduna öğretmen olarak girer. Yöneticiler yalnızca superadmin tarafından eklenir.
- **Askıya alınan** yurdun kullanıcıları hiçbir veriye erişemez (veritabanı seviyesinde).

## Mimari notlar

- **Kiracı izolasyonu** tamamen PostgreSQL RLS ile sağlanır; istemci kodu yetki kontrolü için güvenilir kabul edilmez.
  Tablolar arası bileşik yabancı anahtarlar (`tenant_id, id`) farklı yurtların kayıtlarının birbirine bağlanmasını engeller.
- **Modül motoru:** yoklama, yatak-dolap, etüt ve dahili ders puanlaması dahil tüm "günlük giriş" modülleri
  `modules` + `entries` tabloları üzerinde çalışır. Varsayılan modüller her yeni yurda kopyalanır; yönetici kapatabilir,
  vakit isimlerini düzenleyebilir veya yurda özel yeni modül ekleyebilir (kapsam: yurt geneli / etüt grubu / dahili grup;
  tip: yoklama / puan aralığı / evet-hayır; günlük oturum sayısı; rapor ağırlığı).
- **Grup üyelik geçmişi** tutulur: öğrenci grup değiştirdiğinde eski üyelik `end_date` ile kapanır.
- **Akademik modüller** (yazılı, test, deneme, kitap) etüt grubuna özeldir; yazma yetkisi `can_manage_group()` /
  `can_manage_student_books()` ile, modülün açık olması `feature_enabled()` ile sunucuda kontrol edilir.
  Test, tek bölümlü bir "ölçme"dir; deneme sınavı ile aynı tabloları (`assessments`, `assessment_sections`,
  `assessment_results`) kullanır. Net, veritabanında hesaplanan bir sütundur.
- **7 gün kuralı** ve yurt yerel tarihi (`Europe/Istanbul`) sunucuda `can_write_entry()` içinde uygulanır.

## Testler

```bash
flutter test                      # Dart birim testleri
# Veritabanı (RLS ve iş kuralları) testleri – yerel PostgreSQL 15+ gerekir:
PGHOST=localhost PGUSER=postgres supabase/tests/run_local.sh
```

## Proje yapısı

```
lib/
  core/        env, oturum, yönlendirme, tema, hata mesajları
  models/      veri modelleri
  data/        Supabase sorguları ve Riverpod sağlayıcıları
  features/
    auth/        giriş, yurt kaydı, şifremi unuttum, şifre belirleme
    home/        rol bazlı kabuk ve kontrol paneli
    entries/     ortak modül veri giriş ekranı
    academics/   yazılılar, testler, denemeler, kitap takibi
    share/       veliye paylaşım (PNG / PDF, isim gizleme)
    admin/       yönetim paneli ekranları
    superadmin/  yurt listesi ve detayı
    profile/     profil, şifre değiştirme
supabase/
  migrations/  şema, RLS, tetikleyiciler, RPC'ler
  functions/   invite-user Edge Function
  tests/       yerel RLS test betiği
```
