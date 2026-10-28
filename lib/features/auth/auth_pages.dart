import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/env.dart';
import '../../core/errors.dart';
import '../../core/session.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.apartment_rounded, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 8),
                  Text('Dormy', textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
                  Text(
                    'Yurt Takip Sistemi',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 32),
                  Text(title, style: theme.textTheme.titleLarge),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
                  ],
                  const SizedBox(height: 20),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({required this.controller, this.label = 'Şifre', this.validator, this.onSubmitted});

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String>? validator;
  final VoidCallback? onSubmitted;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      validator: widget.validator,
      autofillHints: const [AutofillHints.password],
      onFieldSubmitted: (_) => widget.onSubmitted?.call(),
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (session.linkError != null) {
      _error =
          'E-posta bağlantısı bu cihazda açılamadı veya süresi dolmuş. '
          'Hesabınız doğrulandıysa e-posta ve şifrenizle giriş yapabilirsiniz; '
          'değilse "Şifremi unuttum" ile yeni bağlantı isteyin.';
      session.linkError = null;
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Repo.signIn(_email.text, _password.text);
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Giriş Yap',
      child: Form(
        key: _form,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                validator: emailValidator,
                decoration: const InputDecoration(labelText: 'E-posta', prefixIcon: Icon(Icons.mail_outline)),
              ),
              const SizedBox(height: 12),
              _PasswordField(
                controller: _password,
                validator: (v) => (v == null || v.isEmpty) ? 'Şifre zorunlu' : null,
                onSubmitted: _submit,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.push('/forgot-password'),
                  child: const Text('Şifremi unuttum'),
                ),
              ),
              if (_error != null) ...[
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 12),
              ],
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Giriş Yap'),
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Yurdunuzu sisteme kaydetmek mi istiyorsunuz?',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              TextButton(onPressed: () => context.push('/register'), child: const Text('Hesap oluştur')),
              TextButton(
                onPressed: () => context.push('/verify?type=invite'),
                child: const Text('Davet e-postası aldım, kodu gireceğim'),
              ),
              Text(
                'Öğretmen hesapları yurt yöneticisinin daveti ile oluşturulur.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 24),
              Text(
                'Sunucu: ${Env.serverHost}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outlineVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _form = GlobalKey<FormState>();
  final _tenantName = TextEditingController();
  final _city = TextEditingController();
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  bool _kvkk = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!_kvkk) {
      setState(() => _error = 'Devam etmek için aydınlatma metnini onaylamalısınız.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final signedIn = await Repo.registerTenant(
        email: _email.text,
        password: _password.text,
        fullName: _fullName.text,
        tenantName: _tenantName.text,
        city: _city.text,
        phone: _phone.text,
      );
      if (!signedIn && mounted) {
        context.go(Uri(path: '/verify', queryParameters: {'type': 'signup', 'email': _email.text.trim()}).toString());
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Yurt Kaydı',
      subtitle: 'Yurdunuzu kaydedin; hesabı oluşturan kişi yurdun yöneticisi olur.',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _tenantName,
              validator: (v) => requiredValidator(v, 'Yurt adı zorunlu'),
              decoration: const InputDecoration(labelText: 'Yurt / okul adı', prefixIcon: Icon(Icons.apartment)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _city,
              decoration: const InputDecoration(labelText: 'Şehir', prefixIcon: Icon(Icons.location_city)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _fullName,
              validator: (v) => requiredValidator(v, 'Ad soyad zorunlu'),
              decoration: const InputDecoration(labelText: 'Yetkili ad soyad', prefixIcon: Icon(Icons.person_outline)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              validator: (v) => requiredValidator(v, 'Telefon zorunlu'),
              decoration: const InputDecoration(labelText: 'Telefon', prefixIcon: Icon(Icons.phone_outlined)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              validator: emailValidator,
              decoration: const InputDecoration(labelText: 'E-posta', prefixIcon: Icon(Icons.mail_outline)),
            ),
            const SizedBox(height: 12),
            _PasswordField(controller: _password, validator: passwordValidator),
            const SizedBox(height: 12),
            _PasswordField(
              controller: _password2,
              label: 'Şifre (tekrar)',
              validator: (v) => v != _password.text ? 'Şifreler eşleşmiyor' : null,
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _kvkk,
              onChanged: (v) => setState(() => _kvkk = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'Öğrenci verilerinin KVKK kapsamında yurdumuz sorumluluğunda işleneceğini '
                've gerekli açık rızaların tarafımızca alınacağını kabul ediyorum.',
                style: TextStyle(fontSize: 13),
              ),
            ),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 12),
            ],
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Kaydı Tamamla'),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: () => context.go('/login'), child: const Text('Zaten hesabım var')),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Repo.sendPasswordReset(_email.text);
      if (mounted) {
        context.go(Uri(path: '/verify', queryParameters: {'type': 'recovery', 'email': _email.text.trim()}).toString());
      }
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Şifremi Unuttum',
      subtitle: 'E-posta adresinize şifre sıfırlama kodu göndereceğiz.',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              validator: emailValidator,
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(labelText: 'E-posta', prefixIcon: Icon(Icons.mail_outline)),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 12),
            ],
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Kod Gönder'),
            ),
            TextButton(onPressed: () => context.go('/login'), child: const Text('Girişe dön')),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Davetle gelen kullanıcı veya şifre sıfırlama bağlantısı sonrası yeni şifre.
class SetPasswordPage extends StatefulWidget {
  const SetPasswordPage({super.key});

  @override
  State<SetPasswordPage> createState() => _SetPasswordPageState();
}

class _SetPasswordPageState extends State<SetPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Repo.updatePassword(_password.text);
      await session.passwordUpdated();
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = session.contextOrNull;
    final invited = c != null && !c.profile.passwordSet;
    return _AuthScaffold(
      title: invited ? 'Hoş geldiniz, ${c.profile.fullName}' : 'Yeni Şifre Belirle',
      subtitle: invited
          ? '${c.tenant?.name ?? ''} için hesabınız oluşturuldu. Devam etmek için bir şifre belirleyin.'
          : 'Hesabınız için yeni bir şifre belirleyin.',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PasswordField(controller: _password, label: 'Yeni şifre', validator: passwordValidator),
            const SizedBox(height: 12),
            _PasswordField(
              controller: _password2,
              label: 'Yeni şifre (tekrar)',
              validator: (v) => v != _password.text ? 'Şifreler eşleşmiyor' : null,
              onSubmitted: _submit,
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 12),
            ],
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Şifreyi Kaydet'),
            ),
            TextButton(onPressed: session.signOut, child: const Text('Çıkış yap')),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class BlockedPage extends StatelessWidget {
  const BlockedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isError = session.status == SessionStatus.error;
    return _AuthScaffold(
      title: isError ? 'Bağlantı hatası' : 'Erişim yok',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(isError ? friendlyError(session.error ?? 'Bilinmeyen hata') : session.blockedReason),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: session.refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Tekrar dene'),
          ),
          TextButton(onPressed: session.signOut, child: const Text('Çıkış yap')),
        ],
      ),
    );
  }
}

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

// ---------------------------------------------------------------------------

/// E-postaya gelen doğrulama / şifre sıfırlama / davet kodunu girme ekranı.
/// E-postadaki bağlantının uygulamayı açamadığı durumlar (Gmail'in kendi
/// tarayıcısı, farklı cihaz) için asıl yöntem budur.
class VerifyCodePage extends StatefulWidget {
  const VerifyCodePage({super.key, required this.purpose, this.email});

  final CodePurpose purpose;
  final String? email;

  @override
  State<VerifyCodePage> createState() => _VerifyCodePageState();
}

class _VerifyCodePageState extends State<VerifyCodePage> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.email);
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _info;

  bool get _emailKnown => widget.email != null && widget.email!.isNotEmpty;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Başarılıysa oturum açılır; yönlendirmeyi router yapar.
      await Repo.verifyEmailCode(email: _email.text, code: _code.text, purpose: widget.purpose);
    } catch (e) {
      setState(() => _error = _codeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _codeError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('expired') || msg.contains('invalid') || msg.contains('otp')) {
      return 'Kod hatalı veya süresi dolmuş. Yeni kod isteyip tekrar deneyin.';
    }
    return friendlyError(e);
  }

  Future<void> _resend() async {
    setState(() {
      _error = null;
      _info = null;
    });
    try {
      if (widget.purpose == CodePurpose.signup) {
        await Repo.resendSignupCode(_email.text);
      } else {
        await Repo.sendPasswordReset(_email.text);
      }
      setState(() => _info = 'Yeni kod gönderildi. En son gelen e-postadaki kodu kullanın.');
    } catch (e) {
      setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = switch (widget.purpose) {
      CodePurpose.signup => (
          'E-postanızı doğrulayın',
          'Kayıt tamamlandı. E-postanıza gelen doğrulama kodunu girin. '
              'Hesabınız deneme modunda açılır; sistem yöneticisi onayladıktan sonra kotanız genişletilir.',
        ),
      CodePurpose.recovery => (
          'Şifre sıfırlama kodu',
          'Adres kayıtlıysa e-postanıza bir kod gönderdik. Kodu girdikten sonra yeni şifrenizi belirleyeceksiniz.',
        ),
      CodePurpose.invite => (
          'Davet kodu',
          'Yöneticinizin gönderdiği davet e-postasındaki kodu ve e-posta adresinizi girin. '
              'Ardından kendi şifrenizi belirleyeceksiniz.',
        ),
    };
    return _AuthScaffold(
      title: title,
      subtitle: subtitle,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _email,
              readOnly: _emailKnown,
              keyboardType: TextInputType.emailAddress,
              validator: emailValidator,
              decoration: const InputDecoration(labelText: 'E-posta', prefixIcon: Icon(Icons.mail_outline)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _code,
              autofocus: _emailKnown,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.w600),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
              autofillHints: const [AutofillHints.oneTimeCode],
              validator: (v) => (v == null || v.length < 6) ? 'E-postadaki kodu girin' : null,
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(labelText: 'Kod', hintText: '••••••'),
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 12),
            ],
            if (_info != null) ...[Text(_info!), const SizedBox(height: 12)],
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Doğrula'),
            ),
            if (widget.purpose != CodePurpose.invite)
              TextButton(onPressed: _resend, child: const Text('Kodu tekrar gönder'))
            else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Kod gelmediyse veya süresi dolduysa yöneticinizden daveti tekrar göndermesini isteyin.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            TextButton(onPressed: () => context.go('/login'), child: const Text('Girişe dön')),
          ],
        ),
      ),
    );
  }
}
