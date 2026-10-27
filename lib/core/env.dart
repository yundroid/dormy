/// Derleme zamanı yapılandırması:
/// flutter run --dart-define-from-file=env.json  (bkz. env.example.json)
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Publishable key (sb_publishable_...) ya da eski "anon" key
  static const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// Davet ve şifre sıfırlama e-postalarındaki bağlantının açılacağı adres
  /// (yayınlanan web uygulamasının adresi). Boşsa Supabase "Site URL" kullanılır.
  static const authRedirectUrl = String.fromEnvironment('AUTH_REDIRECT_URL');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
