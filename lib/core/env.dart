/// Derleme zamanı yapılandırması:
/// flutter run --dart-define-from-file=env.json  (bkz. env.example.json)
class Env {
  static const _rawUrl = String.fromEnvironment('SUPABASE_URL');
  static const _rawKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const _rawRedirect = String.fromEnvironment('AUTH_REDIRECT_URL');

  static String get supabaseUrl => normalizeSupabaseUrl(_rawUrl);

  /// Publishable key (sb_publishable_...) ya da eski "anon" key
  static String get supabaseKey => cleanValue(_rawKey);

  /// Davet ve şifre sıfırlama e-postalarındaki bağlantının açılacağı adres
  /// (yayınlanan web uygulamasının adresi). Boşsa Supabase "Site URL" kullanılır.
  static String get authRedirectUrl => cleanValue(_rawRedirect);

  static bool get isConfigured => configError == null;

  /// Teşhis için ekranda gösterilen sunucu adı
  static String get serverHost => Uri.tryParse(supabaseUrl)?.host ?? supabaseUrl;

  /// Yapılandırma hatası varsa açıklaması, yoksa null
  static String? get configError => checkConfig(url: _rawUrl, key: _rawKey);
}

/// CI arayüzlerine yapıştırılan değerlerdeki boşluk ve tırnakları temizler.
String cleanValue(String v) => v.trim().replaceAll(RegExp(r'''^["']+|["']+$'''), '').trim();

/// "https://ref.supabase.co/rest/v1/" gibi değerleri kök adrese çevirir.
String normalizeSupabaseUrl(String raw) {
  var url = cleanValue(raw);
  if (url.isEmpty) return url;
  if (!url.contains('://')) url = 'https://$url';
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return url;
  // Supabase API kökü yol içermez (/rest/v1, /auth/v1 vb. istemci tarafından eklenir).
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host}$port';
}

String? checkConfig({required String url, required String key}) {
  final u = normalizeSupabaseUrl(url);
  if (u.isEmpty) return 'SUPABASE_URL tanımlı değil.';
  if (cleanValue(key).isEmpty) return 'SUPABASE_PUBLISHABLE_KEY tanımlı değil.';
  final host = Uri.tryParse(u)?.host ?? '';
  if (host == 'supabase.com' || host.endsWith('.supabase.com')) {
    return 'SUPABASE_URL olarak Supabase panelinin adresi girilmiş ($u). '
        'Project Settings → API sayfasındaki "Project URL" değerini (https://xxxx.supabase.co) kullanın.';
  }
  return null;
}
