import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner_app/core/diagnostics/diagnostic_log.dart';
import 'package:trip_planner_app/core/diagnostics/diagnostic_screen.dart';
import 'package:trip_planner_app/main.dart';
import 'package:trip_planner_app/core/theme/app_theme.dart';

void main() {
  testWidgets('startup failure exposes diagnostics without raw configuration',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(StartupFailureApp(
        error:
            StateError('Missing required environment variable: SUPABASE_URL')));
    expect(find.text('暫時無法啟動'), findsOneWidget);
    expect(find.textContaining('SUPABASE_URL'), findsNothing);
    await tester.tap(find.text('操作紀錄'));
    await tester.pumpAndSettle();
    expect(find.byType(DiagnosticScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('diagnostic page renders with long content at mobile width',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final log = DiagnosticLog();
    await log.trace('儲存地點與照片', () async {
      log.event(DiagnosticKind.operation, '登入刷新後重試');
      log.error(
          '照片處理',
          StateError('new row violates row-level security 42501'),
          StackTrace.fromString(
              '#0 upload (package:trip_planner_app/features/trip_detail/data/stop_photo_service.dart:52:10)'));
      await log.trace('還原地點變更', () async => true);
      log.markFailed();
    });
    final key = GlobalKey();
    final preview =
        const bool.fromEnvironment('DIAGNOSTICS_PREVIEW') && Platform.isWindows;
    if (preview) {
      await tester.runAsync(() async {
        final font = FontLoader('DiagnosticPreview')
          ..addFont(File('C:/Windows/Fonts/msjh.ttc')
              .readAsBytes()
              .then(ByteData.sublistView));
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await font.load();
        await icons.load();
      });
    }
    await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: preview
                ? buildAppTheme().copyWith(
                    textTheme: buildAppTheme()
                        .textTheme
                        .apply(fontFamily: 'DiagnosticPreview'))
                : buildAppTheme(),
            home: DiagnosticScreen(log: log))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('DIAGNOSTICS_PREVIEW')) {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build').create(recursive: true);
        await File('build/diagnostics_preview.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox.shrink());
    log.dispose();
  });
}
