import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trip_planner_app/core/router/invite_link_controller.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';
import 'package:trip_planner_app/features/trips/data/trip_invite_link.dart';
import 'package:trip_planner_app/features/trips/presentation/invite_accept_screen.dart';

void main() {
  final token = 'b' * 64;
  const preview = TripInviteLinkResult(
      status: TripInviteStatus.success,
      title: '朋友的旅程',
      tripId: 'trip1',
      permission: TripPermission.viewer);

  testWidgets('acceptance is explicit and clears invitation before navigation',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller =
        InviteLinkController(await SharedPreferences.getInstance());
    await controller.remember(token);
    var accepts = 0;
    final router = GoRouter(initialLocation: '/invite/$token', routes: [
      GoRoute(
          path: '/invite/:token',
          builder: (_, state) =>
              InviteAcceptScreen(token: state.pathParameters['token']!)),
      GoRoute(
          path: '/trips/:tripId',
          builder: (_, __) => const Scaffold(body: Text('已加入旅程'))),
      GoRoute(
          path: '/trips', builder: (_, __) => const Scaffold(body: Text('列表'))),
    ]);
    await tester.pumpWidget(ProviderScope(overrides: [
      inviteLinkControllerProvider.overrideWithValue(controller),
      previewTripInviteProvider.overrideWithValue((_) async => preview),
      acceptTripInviteProvider.overrideWithValue((_) async {
        accepts++;
        return preview;
      }),
    ], child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    expect(find.text('朋友的旅程'), findsOneWidget);
    expect(find.text('加入權限：唯讀'), findsOneWidget);
    expect(accepts, 0);
    await tester.tap(find.text('確認加入'));
    await tester.pumpAndSettle();
    expect(accepts, 1);
    expect(controller.pendingRoute, isNull);
    expect(find.text('已加入旅程'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
    controller.dispose();
  });

  testWidgets('revoked link cannot be accepted', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller =
        InviteLinkController(await SharedPreferences.getInstance());
    await tester.pumpWidget(ProviderScope(overrides: [
      inviteLinkControllerProvider.overrideWithValue(controller),
      previewTripInviteProvider.overrideWithValue((_) async =>
          const TripInviteLinkResult(status: TripInviteStatus.invalidLink)),
    ], child: MaterialApp(home: InviteAcceptScreen(token: token))));
    await tester.pumpAndSettle();
    expect(find.text('邀請連結已失效或已撤銷'), findsOneWidget);
    expect(find.text('確認加入'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
