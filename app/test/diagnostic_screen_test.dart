import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner_app/core/diagnostics/diagnostic_log.dart';
import 'package:trip_planner_app/core/diagnostics/diagnostic_screen.dart';
import 'package:trip_planner_app/features/auth/presentation/auth_screen.dart';
import 'package:trip_planner_app/features/trips/presentation/trips_list_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trip_planner_app/app.dart';
import 'package:trip_planner_app/core/router/app_router.dart';
import 'package:trip_planner_app/features/auth/data/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trip_planner_app/core/router/invite_link_controller.dart';

void main() {
  testWidgets('diagnostic route is accessible before authentication',
      (tester) async {
    final auth = AuthStateListenable(const Stream.empty(), false);
    SharedPreferences.setMockInitialValues({});
    final invites = InviteLinkController(await SharedPreferences.getInstance());
    final container = ProviderContainer(overrides: [
      authStateListenableProvider.overrideWithValue(auth),
      inviteLinkControllerProvider.overrideWithValue(invites),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const TripPlannerApp()));
    await tester.pumpAndSettle();
    container.read(appRouterProvider).go('/diagnostics');
    await tester.pumpAndSettle();
    expect(find.byType(DiagnosticScreen), findsOneWidget);
    expect(find.byType(AuthScreen), findsNothing);
    await invites.remember('a' * 64);
    await tester.pumpAndSettle();
    expect(find.byType(DiagnosticScreen), findsOneWidget);
    expect(invites.pendingRoute, '/invite/${'a' * 64}');
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    auth.dispose();
    invites.dispose();
  });
  testWidgets('login entry works without a session', (tester) async {
    await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: AuthScreen())));
    await tester.tap(find.text('操作紀錄'));
    await tester.pumpAndSettle();
    expect(find.byType(DiagnosticScreen), findsOneWidget);
    expect(find.text('記錄操作'), findsOneWidget);
  });

  testWidgets('trip list exposes diagnostics without hiding the sync actions',
      (tester) async {
    await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: TripsListScreen())));
    await tester.pumpAndSettle();
    expect(find.byType(DiagnosticButton), findsOneWidget);
    expect(find.byTooltip('重新從雲端同步'), findsOneWidget);
  });

  testWidgets(
      'narrow screen supports search, filters, details, copy and toggles',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final log = DiagnosticLog();
    log.event(DiagnosticKind.operation, '建立旅程',
        outcome: DiagnosticOutcome.success);
    log.error('照片失敗', StateError('private@example.com secret-token'));
    String? clipboard;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(MaterialApp(home: DiagnosticScreen(log: log)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextField), '照片失敗');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, '照片失敗'), findsOneWidget);
    expect(find.text('建立旅程'), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, '照片失敗'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('複製單筆'));
    await tester.pumpAndSettle();
    expect(jsonDecode(clipboard!)['entries'], hasLength(1));
    expect(clipboard, isNot(contains('secret-token')));
    expect(clipboard, isNot(contains('private@example.com')));
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('所有結果'));
    await tester.tap(find.text('所有結果'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('失敗').last);
    await tester.pumpAndSettle();
    expect(find.text('照片失敗'), findsOneWidget);
    expect(find.text('建立旅程'), findsNothing);
    await tester.ensureVisible(find.text('所有類型'));
    await tester.tap(find.text('所有類型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('錯誤').last);
    await tester.pumpAndSettle();
    expect(find.text('照片失敗'), findsOneWidget);
    await tester.ensureVisible(find.text('複製全部 JSON'));
    await tester.tap(find.text('複製全部 JSON'));
    await tester.pumpAndSettle();
    expect(jsonDecode(clipboard!)['entries'], hasLength(2));
    await tester.ensureVisible(find.text('記錄操作'));
    await tester.tap(find.text('記錄操作'));
    await tester.pumpAndSettle();
    expect(log.enabled, isFalse);
    expect(log.entries, hasLength(2));
    await tester.ensureVisible(find.text('自動捲動至最新紀錄'));
    await tester.tap(find.text('自動捲動至最新紀錄'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('清除紀錄'));
    await tester.tap(find.text('清除紀錄'));
    await tester.pumpAndSettle();
    expect(log.entries, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    log.dispose();
  });
}
