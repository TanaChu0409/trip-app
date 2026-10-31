import 'package:trip_planner_app/core/diagnostics/diagnostic_log.dart';
import 'package:trip_planner_app/core/diagnostics/diagnostic_screen.dart';
import 'package:trip_planner_app/core/diagnostics/diagnostic_errors.dart';
import 'package:trip_planner_app/core/diagnostics/diagnostic_observer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trip_planner_app/app.dart';
import 'package:trip_planner_app/core/supabase/supabase_config.dart';
import 'package:trip_planner_app/core/supabase/supabase_error_formatter.dart';
import 'package:trip_planner_app/core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DiagnosticErrors.install();

  try {
    await DiagnosticLog.instance.trace('啟動', AppSupabaseConfig.initialize);
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
    runApp(StartupFailureApp(error: error));
  }
}

class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final message = SupabaseErrorFormatter.userMessage(error);

    return MaterialApp(
      title: '旅遊規劃 APP',
      theme: buildAppTheme(),
      navigatorObservers: [DiagnosticObserver()],
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
                        Text('暫時無法啟動',
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 12),
                        Text(message),
                        const SizedBox(height: 16),
                        const Text('請稍後重新開啟應用程式。'),
                        const DiagnosticButton(),
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
