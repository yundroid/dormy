import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get db => Supabase.instance.client;

String? get currentUserId => db.auth.currentUser?.id;
