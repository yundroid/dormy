# Dormy – Öğrenci Yurdu Takip Uygulaması · Analiz ve Sentez Raporu

> Durum: Taslak v1 · Kod yazmadan önce gereksinimlerin netleştirilmesi için hazırlanmıştır.

---

## 1. Anladığım Şekliyle Sistem

Uygulama **çok kiracılı (multi-tenant) bir SaaS**: her yurt/okul kendi verisine sahip ayrı bir "kiracı", hepsinin üstünde de sen (Superadmin) varsın.

```
Superadmin (sen)
 └── Yurt / Okul (kiracı)  ── kayıt olunca PASİF, deneme kotası: 3 öğretmen + 3 öğrenci
      ├── Admin (okul yönetimi) = Öğretmen yetkileri + Yönetim Paneli
      ├── Öğretmen
      └── Öğrenci (veri kaydı – kullanıcı hesabı değil, bkz. 3.2)
```

**Kontrol modülleri** iki ana gruba ayrılıyor:

| Modül | Kim doldurur | Kapsam | Değerlendirme | Sıklık |
|---|---|---|---|---|
| Yoklama | Tüm öğretmenler | Yurt geneli | Var / Yok (+İzinli, Geç…) | Günlük, 5 vakit |
| Yatak-Dolap | Tüm öğretmenler | Yurt geneli | 1–5 puan | Günlük |
| Etüt Puanlama | Etüt öğretmeni | Kendi etüt grubu | 1–5 puan | Günlük |
| Dahili Ders Puanlama | Dahili ders öğretmeni | Kendi dahili grubu | 1–5 puan | Günlük |
| Yazılılar | Grup öğretmeni | Kendi grubu | 1–100 not, ders seçimi | Serbest tarih |
| Testler | Grup öğretmeni | Kendi grubu | D / Y (/B) → Net = D − Y/3 | Serbest tarih |
| Kitap Okuma | Etüt öğretmeni | Kendi etüt grubu | Atama → okunuyor → bitti | Süreç |
| **Özel modüller** | Admin tanımlar | Yurt geneli **veya** grup bazlı | Admin seçer | Admin seçer |

Raporlama: modül bazında en iyi / en zayıf öğrenciler, haftalık-aylık-tarih aralığı sıralamaları, öğrenci bazında yüzdelik özet (veliye paylaşılabilir).

---

## 2. Güçlü Yanlar (Olduğu Gibi Kalmalı)

- Pasif hesap + deneme kotası → kötüye kullanımı engeller, satış modeline zemin hazırlar.
- Admin = Öğretmen + Yönetim Paneli → küçük yurtlarda müdür de yoklama alabilir.
- Modül kapsamı ayrımı (yurt geneli / gruba özel) → doğru düşünülmüş, mimarinin kalbi bu olacak.
- Veliye paylaşılabilir ekranlar → ürünün en görünür "değer" noktası.

---

## 3. Netleşmesi Gereken / Değiştirmeyi Önerdiğim Noktalar

### 3.1 "Hesap oluştur" kimin için?
**Öneri:** Hesap oluştur = **yeni yurt kaydı**. Kaydı yapan kişi o yurdun ilk Admin'i olur, yurt PASİF başlar.
Öğretmenler kendileri kayıt olmaz; **Admin davet eder** (e-posta ile davet linki → kişi kendi şifresini belirler). Böylece biri rastgele bir yurda kendini öğretmen olarak ekleyemez.

### 3.2 Öğrenciler giriş yapacak mı?
Metinde öğrencinin uygulamayı kullandığı bir senaryo yok. **Öneri:** v1'de öğrenci = sadece **kayıt** (ad, soyad, sınıf, oda, veli telefonu vb.), hesap yok.
İleride "Veli/Öğrenci salt-okunur portalı" eklenebilir (Faz 4).

### 3.3 "Sınıf", "etüt", "dahili sınıf" kavramları
Metinde üç farklı gruplama geçiyor ve karışabilir:
- **Okul sınıfı** (9. sınıf, 10-A…) – öğrencinin okulda okuduğu sınıf, bilgi amaçlı / filtre
- **Etüt grubu** – öğretmenin sorumlu olduğu çalışma grubu (etüt puanı, kitap, test, yazılı)
- **Dahili ders grubu** – dahili ders öğretmeninin grubu (dahili puanlama)

**Öneri:** Tek bir genel **"Grup"** varlığı olsun, tipi olsun (`etut`, `dahili`, ileride admin'in tanımlayacağı tipler). Öğretmen bir veya birden fazla gruba atanır, öğrenci her tipte bir gruba üye olur.
❓ *Yazılı ve testler "kendi sınıfı" derken etüt grubunu mu kastediyorsun?*

### 3.4 Kota kodda sabit olmamalı
"3 öğretmen + 3 öğrenci" değerini yurt bazında **ayarlanabilir kota** olarak tutalım (`maxTeachers`, `maxStudents`). Aktif ettiğinde kotayı sınırsız ya da paket büyüklüğüne göre ayarlarsın. İleride ücretli paketlere geçişi kolaylaştırır.
Ek olarak yurt durumları: `pasif → aktif → askıya alınmış`, opsiyonel **abonelik bitiş tarihi**.

### 3.5 Modül motoru (en kritik mimari karar)
Özel modül eklenebilmesi için **varsayılan modüller de aynı motor üzerine** kurulmalı; aksi halde her yeni modül için kod yazmak gerekir.

Admin modül eklerken seçecekleri:
| Ayar | Seçenekler |
|---|---|
| Ad, ikon, açıklama | serbest |
| Kapsam | Yurt geneli (tüm öğretmenler) / Grup bazlı (hangi grup tipi: etüt, dahili…) |
| Değerlendirme tipi | Puan (min–max: 1–5, 1–10, 1–100) / Var-Yok / Evet-Hayır / Seçenek listesi |
| Sıklık | Günlük / Haftalık / Serbest tarih |
| Günlük oturum sayısı | 1 veya çoklu (yoklamadaki 5 vakit gibi, isimleri düzenlenebilir) |
| Raporlara dahil | Evet/Hayır, opsiyonel ağırlık |
| Durum | Aktif / Pasif (silmek yerine – geçmiş veri kaybolmasın) |

Yazılı, Test ve Kitap yapıları farklı olduğu için (ders/konu, D-Y, süreç takibi) bunlar **özel tablolu sabit modüller** olur; puanlama/yoklama türü modüller ise genel motoru kullanır.
Varsayılan modüller de okul bazında **kapatılabilmeli** (örn. dahili ders yapmayan bir yurt).

### 3.6 Yoklama detayları
- Durumlar sadece Var/Yok değil: **Var, Yok, İzinli, Raporlu, Geç** önerilir; aksi halde evci/izinli öğrenciler yüzdeyi haksız düşürür.
- Vakit isimleri ve sayısı yurt bazında düzenlenebilir olmalı (5 vakit default).
- Aynı vakit için ikinci öğretmen girerse: önceki kaydı **"X öğretmen saat 07:15'te aldı"** şeklinde göster, düzenlemeye izin ver, değişikliği logla.
- Ekranda "hepsini Var işaretle, sadece yokları seç" hızlı akışı – 100+ öğrencide kritik.

### 3.7 Testler
- Girdi: Doğru, Yanlış, **Boş** (soru sayısı biliniyorsa D+Y+B = N kontrolü yapılır).
- Net = D − (Y / 3). Negatif net mümkün; gösterimde virgülden sonra 2 hane.
- Ders → **Konu** hiyerarşisi tanımlanmalı (Yönetim Paneli'ndeki "ders tanımlama" ekranına konu ekleme de eklenmeli).
- ❓ Ders bazlı karma testler (TYT denemesi gibi her dersten ayrı D/Y) gerekli mi? Gerekirse "Deneme sınavı" ayrı yapı olur.

### 3.8 Yüzdelik hesaplama kuralları (Öğrencilerim & raporlar)
Farklı ölçekleri tek ekranda göstermek için normalizasyon tanımlı olmalı:
- Puan modülleri: ortalama puan / maksimum puan × 100
- Yoklama: Var / (Toplam − İzinli − Raporlu) × 100
- Test: ortalama net / soru sayısı × 100
- Yazılı: ortalama not (zaten 100'lük)
- Kitap: bitirilen kitap sayısı ve okunan sayfa (yüzde değil, sayı)
- **Genel başarı puanı**: modül yüzdelerinin (admin'in belirleyeceği ağırlıklarla) ortalaması – opsiyonel.

Sıralamalarda **minimum veri şartı** olmalı (örn. dönemde 1 kez puanlanıp 5 alan öğrenci birinci çıkmasın – "en az %X veri girilmiş olanlar").

### 3.9 Veliye paylaşım ve KVKK ⚠️
"Sıralı listeyi veliye ekran görüntüsü olarak paylaşma", bir velinin **diğer çocukların notlarını görmesi** demek. Öğrenciler büyük ihtimalle reşit değil; bu KVKK açısından riskli.
**Öneriler:**
- Paylaşım ekranında seçenek: **Tam isim / Baş harfler (A. Y.) / Sadece ilk N kişi / Sadece bu öğrenci**
- Bireysel öğrenci karnesi (Öğrencilerim ekranı) zaten tek öğrenci – en güvenli paylaşım bu.
- Görüntü (PNG) + **PDF** çıktısı, WhatsApp vb. ile `share` menüsünden paylaşım.
- Uygulama içi aydınlatma metni / KVKK onayı (yurt kaydında admin onaylar).
- Sunucu konumu: Firebase/Supabase Cloud verileri yurt dışında tutar → KVKK "yurt dışına aktarım" konusu. Başlangıç için kabul edilebilir, ileride Türkiye'de self-host seçeneği düşünülmeli.

### 3.10 Eksik olduğunu düşündüğüm temel kavramlar
- **Eğitim-öğretim yılı / dönem**: Yıl sonunda veriler arşivlenir, yeni yıl temiz başlar, raporlar döneme göre filtrelenir.
- **Öğrenci durumu**: Aktif / Ayrıldı / Mezun – silme yerine pasifleştirme (geçmiş raporlar bozulmasın).
- **Grup üyelik geçmişi**: Öğrenci Mart'ta etüt değiştirirse, eski öğretmenin raporu bozulmamalı (üyelikte başlangıç–bitiş tarihi).
- **Oda / yatak numarası**: Yatak-dolap kontrolünü oda oda yapmak çok daha hızlı (oda bazlı filtre).
- **Düzenleme kuralları ve log**: Öğretmen kendi girdiğini X gün içinde düzeltebilir, admin her zaman; her değişiklik "kim/ne zaman" loglanır.
- **Çevrimdışı çalışma**: Yurt koridorlarında internet zayıf olabilir; yoklama çevrimdışı alınıp sonra senkronlanmalı.
- **Öğretmen nöbet/izin**: v1'de gerek yok, not olarak dursun.

### 3.11 Superadmin ekranları – önerilen içerik
- Yurt listesi: ad, şehir, admin adı, telefon, e-posta, kayıt tarihi, durum rozeti, filtre (pasif/aktif/askıda)
- Yurt detay: iletişim bilgileri, öğretmen/öğrenci sayısı vs kota, aktif modül sayısı, **son aktivite tarihi**, son 30 gün veri girişi sayısı (yurt gerçekten kullanıyor mu?)
- Aksiyonlar: aktif et, askıya al, kotayı değiştir, abonelik bitişi ver, admin'e e-posta/telefon (tek dokunuşla arama/WhatsApp)
- Genel panel: toplam yurt, toplam öğrenci, bu hafta kaydolanlar, onay bekleyenler

### 3.12 Çıkarmayı / ertelemeyi önerdiklerim
- **Öğrenci hesabı** (v1'de yok)
- **Kodda sabit 3+3 kota** (ayarlanabilir kota ile değiştir)
- **Sadece ekran görüntüsü paylaşımı** → PNG + PDF + KVKK seçenekleri
- Bildirimler, veli portalı, Excel dışa aktarım, izin (evci) modülü → **sonraki fazlar**

---

## 4. Teknik Öneri

| Katman | Öneri | Neden |
|---|---|---|
| Uygulama | **Flutter** – Android, iOS + **Web** (yönetim paneli ve raporlar için) | Tek kod tabanı; büyük tablolar web'de rahat |
| Backend | **Supabase** (PostgreSQL + Auth + Row Level Security + Edge Functions) | Rapor/sıralama/tarih aralığı sorguları SQL ile çok kolay ve ucuz; RLS ile yurtlar arası veri izolasyonu veritabanı seviyesinde garanti; ileride Türkiye'de self-host edilebilir |
| Alternatif | Firebase (Firestore) | Çevrimdışı desteği daha olgun, fakat çapraz modül/tarih aralığı raporlamada hem zor hem maliyetli |
| Durum yönetimi | Riverpod | Test edilebilir, yaygın |
| Yönlendirme | go_router | Rol bazlı yönlendirme (guard) |
| Grafik | fl_chart | Rapor ekranları |
| Paylaşım | screenshot + share_plus, pdf + printing | PNG ve PDF |
| Yerelleştirme | Türkçe öncelikli, intl ile çok dil altyapısı | |

### 4.1 Taslak veri modeli
```
tenants            (id, ad, şehir, telefon, e-posta, durum, max_ogretmen, max_ogrenci, abonelik_bitis)
profiles           (id=auth.uid, tenant_id, ad_soyad, telefon, rol[superadmin|admin|ogretmen], durum)
academic_terms     (id, tenant_id, ad, baslangic, bitis, aktif)
students           (id, tenant_id, ad, soyad, okul_sinifi, oda_no, veli_ad, veli_tel, durum)
group_types        (id, tenant_id|null, kod[etut|dahili|...], ad)
groups             (id, tenant_id, group_type_id, ad)
group_teachers     (group_id, teacher_id)
group_students     (group_id, student_id, baslangic, bitis)
subjects           (id, tenant_id, ad)            topics (id, subject_id, ad)
modules            (id, tenant_id|null(=varsayılan), kod, ad, kapsam[genel|grup], group_type_id,
                    deger_tipi[puan|var_yok|evet_hayir|secenek], min, max, secenekler,
                    siklik, oturumlar[], rapora_dahil, agirlik, aktif)
tenant_module_settings (tenant_id, module_id, aktif, oturum_isimleri)  -- varsayılanları açıp kapamak için
entries            (id, tenant_id, module_id, student_id, tarih, oturum, deger, not, giren_ogretmen, guncelleme)
                    UNIQUE(module_id, student_id, tarih, oturum)
exams              (id, tenant_id, group_id, subject_id, baslik, tarih, ogretmen)   exam_results (exam_id, student_id, not)
tests              (id, tenant_id, group_id, subject_id, topic_id, tarih, soru_sayisi) test_results (test_id, student_id, d, y, b, net)
books              (id, tenant_id, ad, yazar, sayfa)
book_assignments   (id, book_id, student_id, atayan, atama, baslama, bitis, okunan_sayfa, durum)
audit_logs         (id, tenant_id, kullanici, tablo, kayit_id, eylem, eski, yeni, zaman)
```

---

## 5. Önerilen Geliştirme Fazları

**Faz 1 – Temel (MVP)**
Giriş / şifremi unuttum / yurt kaydı · Superadmin: yurt listesi, aktif etme, iletişim, kota · Admin paneli: öğretmen (davet), öğrenci, grup, ders/konu CRUD · **Modül motoru** + Yoklama, Yatak-Dolap, Etüt, Dahili puanlama ekranları

**Faz 2 – Akademik**
Yazılılar · Testler (net) · Kitap takibi · Sıralı sonuç listeleri + PNG/PDF paylaşım (KVKK seçenekleriyle)

**Faz 3 – Raporlama ve Özelleştirme**
Öğrencilerim (yüzdelik karne) · Admin yurt geneli raporları, en iyi/en zayıf, tarih aralığı · Admin'in özel modül tanımlaması · Superadmin özet ekranları

**Faz 4 – Gelişmiş**
Bildirimler (yoklama hatırlatma, devamsızlık uyarısı) · İzin/evci modülü · Excel dışa aktarım · Veli portalı · Dönem arşivleme

---

## 6. Senden Cevap Beklediğim Sorular

1. **Hesap oluştur** = yeni yurt kaydı, öğretmenler admin daveti ile mi gelsin? (öneri: evet)
2. **Öğrenciler** v1'de giriş yapmasın, sadece kayıt olsun – uygun mu?
3. Yazılı / test / kitap için "kendi sınıfı" = **etüt grubu** mu? Bir öğretmenin birden fazla etüt grubu olabilir mi?
4. Bir yurtta **birden fazla admin** olabilir mi? (öneri: evet)
5. Yoklama durumları: **Var / Yok / İzinli / Raporlu / Geç** yeterli mi?
6. Testlerde **Boş** ve **soru sayısı** girilsin mi? Çok dersli deneme sınavı gerekli mi?
7. Veliye paylaşımda **isim gizleme** seçeneği eklememe onay veriyor musun?
8. Backend olarak **Supabase** ile ilerleyelim mi, yoksa Firebase'i mi tercih edersin?
9. Platformlar: Android + iOS + Web (yönetim paneli) – hepsi mi?
10. Aktif etmede kota: sınırsız mı, yoksa paket bazlı (örn. 50/100/250 öğrenci) mı düşünüyorsun?
11. Geçmişe dönük veri girişi: öğretmen dünü / geçen haftayı doldurabilsin mi? Kaç güne kadar?
