import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppSupabaseConfig {
  const AppSupabaseConfig._();

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: _readRequiredEnv('SUPABASE_URL'),
      anonKey: _readRequiredEnv('SUPABASE_ANON_KEY'),
    );
  }

  static String _readRequiredEnv(String key) {
    final value = dotenv.env[key]?.trim();
    if (value == null || value.isEmpty) {
      throw StateError('Missing required environment variable: $key');
    }

    return value;
  }
}