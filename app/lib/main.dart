import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trip_planner_app/app.dart';
import 'package:trip_planner_app/core/supabase/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  await AppSupabaseConfig.initialize();
  runApp(const ProviderScope(child: TripPlannerApp()));
}
