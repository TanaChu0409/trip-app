import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trip_planner_app/app.dart';
import 'package:trip_planner_app/core/supabase/supabase_config.dart';
import 'package:trip_planner_app/core/supabase/supabase_error_formatter.dart';
import 'package:trip_planner_app/core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    try {
      await dotenv.load();
    } on Exception {
      // GitHub Pages builds inject Supabase config through --dart-define.
    }

    await AppSupabaseConfig.initialize();
    runApp(const ProviderScope(child: TripPlannerApp()));
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'main',
        informationCollector: () => [
          DiagnosticsNode.message(
              'Supabase initialization failed during app startup.'),
        ],
      ),
    );
    runApp(_StartupFailureApp(error: error));
  }
}

class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final message = SupabaseErrorFormatter.userMessage(error);
    final details = SupabaseErrorFormatter.diagnosticDetails(error);

    return MaterialApp(
      title: '旅遊規劃APP',
      theme: buildAppTheme(),
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Supabase 初始化失敗',
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 12),
                        Text(message),
                        const SizedBox(height: 16),
                        const Text('建議檢查：'),
                        const SizedBox(height: 8),
                        const Text(
                            '1. app/.env 是否存在，或 build 時是否透過 --dart-define 提供 SUPABASE_URL、SUPABASE_ANON_KEY'),
                        const Text('2. Supabase SQL migrations 是否已完整執行'),
                        const Text('3. 本機網路是否能連到 Supabase 專案'),
                        const SizedBox(height: 16),
                        SelectableText('診斷資訊: $details'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
