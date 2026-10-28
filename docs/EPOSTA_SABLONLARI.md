# Supabase e-posta şablonları (Türkçe, kodlu)

Supabase → **Authentication → Emails → Templates** bölümünde aşağıdaki üç şablonu değiştirin.
Her şablonda e-postanın içinde 6 haneli bir kod (`{{ .Token }}`) bulunur; kullanıcı bu kodu uygulamaya yazar.
Bağlantı da yedek olarak durur (web sürümünde ya da bağlantıyı destekleyen e-posta uygulamalarında çalışır).

> Gmail gibi uygulamalar bağlantıyı kendi tarayıcılarında açıp uygulamaya geçişi engelleyebildiği için
> mobilde asıl yöntem **koddur**.

---

## 1. Confirm signup (Kayıt doğrulama)

**Subject:** `Dormy kayıt doğrulama kodunuz: {{ .Token }}`

```html
<h2>Dormy'ye hoş geldiniz</h2>
<p>Yurt kaydınızı tamamlamak için uygulamaya aşağıdaki kodu girin:</p>
<p style="font-size:28px;font-weight:bold;letter-spacing:6px">{{ .Token }}</p>
<p>Kod 1 saat geçerlidir.</p>
<p style="color:#666;font-size:13px">Bilgisayardan kayıt olduysanız bu bağlantıyı da kullanabilirsiniz:
<a href="{{ .ConfirmationURL }}">E-postamı doğrula</a></p>
<p style="color:#666;font-size:13px">Bu kaydı siz yapmadıysanız bu e-postayı dikkate almayın.</p>
```

## 2. Invite user (Öğretmen / yönetici daveti)

**Subject:** `Dormy davet kodunuz: {{ .Token }}`

```html
<h2>Dormy'ye davet edildiniz</h2>
<p>Yurdunuzun yöneticisi sizi Dormy yurt takip sistemine ekledi.</p>
<ol>
  <li>Dormy uygulamasını açın.</li>
  <li>Giriş ekranında <b>"Davet e-postası aldım, kodu gireceğim"</b> seçeneğine dokunun.</li>
  <li>E-posta adresinizi ve aşağıdaki kodu girin, ardından şifrenizi belirleyin.</li>
</ol>
<p style="font-size:28px;font-weight:bold;letter-spacing:6px">{{ .Token }}</p>
<p style="color:#666;font-size:13px">Web sürümünü kullanıyorsanız: <a href="{{ .ConfirmationURL }}">Daveti kabul et</a></p>
```

## 3. Reset password (Şifre sıfırlama)

**Subject:** `Dormy şifre sıfırlama kodunuz: {{ .Token }}`

```html
<h2>Şifre sıfırlama</h2>
<p>Yeni şifre belirlemek için uygulamaya aşağıdaki kodu girin:</p>
<p style="font-size:28px;font-weight:bold;letter-spacing:6px">{{ .Token }}</p>
<p>Kod 1 saat geçerlidir.</p>
<p style="color:#666;font-size:13px">Web sürümünü kullanıyorsanız: <a href="{{ .ConfirmationURL }}">Şifremi sıfırla</a></p>
<p style="color:#666;font-size:13px">Bu isteği siz yapmadıysanız bu e-postayı dikkate almayın; şifreniz değişmez.</p>
```

---

### Notlar
- Yöneticinin "Daveti tekrar gönder" düğmesi **şifre sıfırlama** e-postası gönderir; davet ekranı bu koddaki
  kodu da kabul eder.
- Kod uzunluğu Supabase'de **Authentication → Providers → Email → Email OTP Length** ayarındadır (varsayılan 6).
  Uygulama 6-10 hane kabul eder.
- Supabase'in ücretsiz e-posta servisi saatte birkaç e-postayla sınırlıdır. Çok sayıda öğretmen davet edilecekse
  **Authentication → Emails → SMTP Settings** bölümünden kendi e-posta servisinizi (ör. Gmail SMTP, Brevo, Resend)
  tanımlayın.
