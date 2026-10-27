import 'package:dormy/core/env.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Supabase adresi kök adrese çevrilir', () {
    const root = 'https://abcd.supabase.co';
    for (final raw in [
      root,
      '$root/',
      '$root/rest/v1/',
      '$root/auth/v1',
      ' "$root" ',
      "'$root/'",
      'abcd.supabase.co',
    ]) {
      expect(normalizeSupabaseUrl(raw), root, reason: raw);
    }
    expect(normalizeSupabaseUrl('http://localhost:54321/'), 'http://localhost:54321');
  });

  test('yapılandırma hataları anlaşılır mesaj verir', () {
    expect(checkConfig(url: 'https://abcd.supabase.co', key: 'sb_publishable_x'), isNull);
    expect(checkConfig(url: '', key: 'x'), contains('SUPABASE_URL'));
    expect(checkConfig(url: 'https://abcd.supabase.co', key: ' "" '), contains('SUPABASE_PUBLISHABLE_KEY'));
    expect(checkConfig(url: 'https://supabase.com/dashboard/project/abcd', key: 'x'), contains('panelinin adresi'));
    expect(cleanValue(' "sb_publishable_x" '), 'sb_publishable_x');
  });
}
