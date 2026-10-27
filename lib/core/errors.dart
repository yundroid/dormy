import 'package:supabase_flutter/supabase_flutter.dart';

/// Sunucu hatalarını kullanıcıya gösterilecek Türkçe mesaja çevirir.
String friendlyError(Object error) {
  if (error is AuthException) {
    final msg = error.message.toLowerCase();
    if (msg.contains('invalid login credentials')) return 'E-posta veya şifre hatalı.';
    if (msg.contains('email not confirmed')) return 'E-posta adresiniz henüz doğrulanmadı. Gelen kutunuzu kontrol edin.';
    if (msg.contains('already registered')) return 'Bu e-posta ile kayıtlı bir hesap zaten var.';
    if (msg.contains('password should be')) return 'Şifre en az 6 karakter olmalı.';
    if (msg.contains('rate limit') || error.statusCode == '429') {
      return 'Çok fazla deneme yapıldı. Lütfen biraz sonra tekrar deneyin.';
    }
    return error.message;
  }
  if (error is PostgrestException) {
    switch (error.hint) {
      case 'quota_teachers':
        return 'Öğretmen kotanız dolu. Kota artırımı için sistem yöneticisiyle iletişime geçin.';
      case 'quota_students':
        return 'Öğrenci kotanız dolu. Kota artırımı için sistem yöneticisiyle iletişime geçin.';
      case 'email_exists':
        return 'Bu e-posta ile kayıtlı bir kullanıcı zaten var.';
      case 'tenant_suspended':
        return 'Yurt hesabı askıya alınmış.';
      case 'module_has_entries':
        return 'Bu modüle veri girilmiş; ölçeği değiştirilemez.';
    }
    if (error.code == '23505') return 'Bu kayıt zaten mevcut (aynı isim kullanılıyor olabilir).';
    if (error.code == '23503') return 'Bu kayıt başka kayıtlarla ilişkili olduğu için işlem yapılamadı.';
    if (error.code == '42501' && error.message.contains('row-level security')) {
      return 'Bu işlem için yetkiniz yok (geriye dönük süre dolmuş olabilir).';
    }
    return error.message;
  }
  if (error is FunctionException) {
    final details = error.details;
    if (details is Map) {
      final code = details['code'];
      const codes = {
        'quota_teachers': 'Öğretmen kotanız dolu. Kota artırımı için sistem yöneticisiyle iletişime geçin.',
        'email_exists': 'Bu e-posta ile kayıtlı bir kullanıcı zaten var.',
        'tenant_suspended': 'Yurt hesabı askıya alınmış.',
        '23505': 'Bu e-postaya zaten bekleyen bir davet var.',
        '42501': 'Bu işlem için yetkiniz yok.',
      };
      if (codes.containsKey(code)) return codes[code]!;
      if (details['error'] != null) return details['error'].toString();
    }
    return 'İşlem başarısız (${error.status}).';
  }
  final text = error.toString();
  if (text.contains('SocketException') || text.contains('ClientException')) {
    return 'İnternet bağlantısı kurulamadı.';
  }
  return text;
}
