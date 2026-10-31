import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner_app/features/trip_detail/presentation/widgets/invite_link_panel.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';
import 'package:trip_planner_app/features/trips/data/trip_invite_link.dart';

void main() {
  for (final revoke in [false, true]) {
    testWidgets('uncertain ${revoke ? 'revoke' : 'reset'} discards old URL',
        (tester) async {
      final mutation = Completer<TripInviteLinkResult>();
      var creates = 0;
      await tester.pumpWidget(ProviderScope(
          overrides: [
            inviteBaseUrlProvider.overrideWithValue('https://example.com/'),
            getTripInviteLinkProvider.overrideWithValue((_) async =>
                const TripInviteLinkResult(status: TripInviteStatus.success)),
            createTripInviteLinkProvider.overrideWithValue((_, permission) {
              if (++creates == 1) {
                return Future.value(TripInviteLinkResult(
                    status: TripInviteStatus.success, token: 'a' * 64));
              }
              return mutation.future;
            }),
            revokeTripInviteLinkProvider
                .overrideWithValue((_) => mutation.future),
          ],
          child: const MaterialApp(
              home: Scaffold(
                  body: SingleChildScrollView(
                      child: InviteLinkPanel(tripId: 'trip1'))))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('產生邀請連結'));
      await tester.pumpAndSettle();
      expect(find.text('複製連結'), findsOneWidget);
      await tester.tap(find.text(revoke ? '撤銷連結' : '重設連結並套用權限'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('確認'));
      await tester.pump();
      expect(find.text('複製連結'), findsNothing);
      mutation.completeError(StateError('response lost after commit'));
      await tester.pumpAndSettle();
      expect(find.text('複製連結'), findsNothing);
      expect(find.text('目前有有效的邀請連結'), findsNothing);
      expect(find.text('無法確認連結狀態，請重設取得新連結或重新撤銷。'), findsOneWidget);
      expect(find.text('重設連結並套用權限'), findsOneWidget);
    });
  }

  testWidgets('hidden mounted panel retains a pending generated token',
      (tester) async {
    final mutation = Completer<TripInviteLinkResult>();
    var visible = true;
    late StateSetter changeVisibility;
    await tester.pumpWidget(ProviderScope(
        overrides: [
          inviteBaseUrlProvider.overrideWithValue('https://example.com/'),
          getTripInviteLinkProvider.overrideWithValue((_) async =>
              const TripInviteLinkResult(status: TripInviteStatus.success)),
          createTripInviteLinkProvider
              .overrideWithValue((_, __) => mutation.future),
        ],
        child: MaterialApp(
            home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
          changeVisibility = setState;
          return SingleChildScrollView(
              child: Visibility(
                  visible: visible,
                  maintainState: true,
                  child: const InviteLinkPanel(tripId: 'trip1')));
        })))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('產生邀請連結'));
    await tester.pump();
    changeVisibility(() => visible = false);
    await tester.pump();
    mutation.complete(TripInviteLinkResult(
        status: TripInviteStatus.success, token: 'b' * 64));
    await tester.pumpAndSettle();
    changeVisibility(() => visible = true);
    await tester.pumpAndSettle();
    expect(
        find.text('https://example.com/?invite=${'b' * 64}'), findsOneWidget);
    expect(find.text('複製連結'), findsOneWidget);
  });

  testWidgets('generate with chosen permission, copy, cancel reset, revoke',
      (tester) async {
    final token = 'd' * 64;
    var creates = 0;
    var revokes = 0;
    TripPermission? selected;
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    await tester.pumpWidget(ProviderScope(
        overrides: [
          inviteBaseUrlProvider
              .overrideWithValue('https://example.com/trip-app/'),
          getTripInviteLinkProvider.overrideWithValue((_) async =>
              const TripInviteLinkResult(status: TripInviteStatus.success)),
          createTripInviteLinkProvider
              .overrideWithValue((id, permission) async {
            creates++;
            selected = permission;
            return TripInviteLinkResult(
                status: TripInviteStatus.success,
                token: token,
                active: true,
                permission: permission);
          }),
          revokeTripInviteLinkProvider.overrideWithValue((_) async {
            revokes++;
            return const TripInviteLinkResult(status: TripInviteStatus.success);
          }),
        ],
        child: const MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: InviteLinkPanel(tripId: 'trip1'))))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('可編輯'));
    await tester.tap(find.text('產生邀請連結'));
    await tester.pumpAndSettle();
    expect(selected, TripPermission.editor);
    expect(creates, 1);
    await tester.tap(find.text('複製連結'));
    await tester.pumpAndSettle();
    expect(copied, 'https://example.com/trip-app/?invite=$token');
    await tester.tap(find.text('重設連結並套用權限'));
    await tester.pumpAndSettle();
    expect(find.text('舊連結將立即失效，已加入的成員不受影響。'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(creates, 1);
    await tester.tap(find.text('撤銷連結'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確認'));
    await tester.pumpAndSettle();
    expect(revokes, 1);
    expect(find.text('複製連結'), findsNothing);
    expect(find.text('尚無有效邀請連結'), findsOneWidget);
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
}
