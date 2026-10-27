import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'supabase.dart';

enum SessionStatus {
  /// Açılış, bağlam yükleniyor
  loading,
  signedOut,

  /// Şifre sıfırlama bağlantısından ya da davetten geldi: yeni şifre belirlemeli
  needsPassword,

  /// Giriş yapıldı ama yurt/rol tanımı yok, hesap pasif veya yurt askıda
  blocked,

  /// Bağlam yüklenemedi (ağ hatası vb.)
  error,
  ready,
}

/// Uygulama genelindeki oturum durumu. Router bunu dinleyerek yönlendirir.
class SessionController extends ChangeNotifier {
  SessionController._();

  static final instance = SessionController._();

  SessionStatus status = SessionStatus.loading;
  UserContext? _context;
  Object? error;
  bool _recovering = false;
  StreamSubscription<AuthState>? _sub;

  UserContext get ctx => _context!;
  UserContext? get contextOrNull => _context;

  /// Kullanıcı değişince Riverpod önbelleğini sıfırlamak için anahtar.
  String get userKey => _context?.profile.id ?? 'anon';

  String get blockedReason {
    final c = _context;
    if (c == null) {
      return 'Hesabınız herhangi bir yurda tanımlı değil. Yöneticinizden davet isteyin.';
    }
    if (!c.profile.isActive) return 'Hesabınız pasif durumda. Yurt yöneticinizle iletişime geçin.';
    if (c.tenant?.status == TenantStatus.suspended) {
      return '"${c.tenant!.name}" hesabı askıya alınmış. Sistem yöneticisiyle iletişime geçin.';
    }
    return 'Hesabınıza erişilemiyor.';
  }

  void start() {
    _sub ??= db.auth.onAuthStateChange.listen(_onAuthChange, onError: (Object e) {
      error = e;
      _set(SessionStatus.error);
    });
  }

  Future<void> _onAuthChange(AuthState state) async {
    switch (state.event) {
      case AuthChangeEvent.passwordRecovery:
        _recovering = true;
        await refresh();
      case AuthChangeEvent.signedOut:
        _recovering = false;
        _context = null;
        _set(SessionStatus.signedOut);
      case AuthChangeEvent.initialSession:
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.userUpdated:
        await refresh();
      default:
        break;
    }
  }

  Future<void> refresh() async {
    if (db.auth.currentSession == null) {
      _context = null;
      _set(SessionStatus.signedOut);
      return;
    }
    try {
      final res = await db.rpc('get_my_context');
      _context = res == null ? null : UserContext.fromJson(Map<String, dynamic>.from(res as Map));
      error = null;
      _set(_resolve());
    } catch (e) {
      error = e;
      _set(SessionStatus.error);
    }
  }

  SessionStatus _resolve() {
    final c = _context;
    if (_recovering || (c != null && !c.profile.passwordSet)) return SessionStatus.needsPassword;
    if (c == null || !c.profile.isActive) return SessionStatus.blocked;
    if (!c.isSuperadmin && c.tenant?.status == TenantStatus.suspended) return SessionStatus.blocked;
    return SessionStatus.ready;
  }

  /// Yeni şifre kaydedildikten sonra
  Future<void> passwordUpdated() async {
    _recovering = false;
    if (_context != null && !_context!.profile.passwordSet) {
      await db.rpc('mark_password_set');
    }
    await refresh();
  }

  Future<void> signOut() async {
    _recovering = false;
    await db.auth.signOut();
  }

  void _set(SessionStatus s) {
    status = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

SessionController get session => SessionController.instance;
