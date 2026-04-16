import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppSupabaseConfig {
  const AppSupabaseConfig._();

  static const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: _readRequiredEnv('SUPABASE_URL'),
      anonKey: _readRequiredEnv('SUPABASE_ANON_KEY'),
    );
  }

  static String _readRequiredEnv(String key) {
    final compileTimeValue = switch (key) {
      'SUPABASE_URL' => _supabaseUrl.trim(),
      'SUPABASE_ANON_KEY' => _supabaseAnonKey.trim(),
      _ => '',
    };

    if (compileTimeValue.isNotEmpty) {
      return compileTimeValue;
    }

    final value = dotenv.env[key]?.trim();
    if (value == null || value.isEmpty) {
      throw StateError('Missing required environment variable: $key');
    }

    return value;
  }
}
