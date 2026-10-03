import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner_app/features/trip_detail/presentation/widgets/invite_link_panel.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';
import 'package:trip_planner_app/features/trips/data/trip_invite_link.dart';

void main() {
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
