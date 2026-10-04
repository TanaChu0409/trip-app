import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trip_planner_app/core/router/invite_link_controller.dart';
import 'package:trip_planner_app/features/trips/data/trip_invite_link.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';

void main() {
  final token = 'a' * 64;
  const base = 'https://tanachu0409.github.io/trip-app/';
  test(
      'login restores pending route; warm links replace it; exit stays cleared',
      () async {
    SharedPreferences.setMockInitialValues({});
    final controller =
        InviteLinkController(await SharedPreferences.getInstance());
    expect(
        controller.redirect('/invite/$token', authenticated: false), '/auth');
    expect(controller.redirect('/auth', authenticated: false), isNull);
    expect(controller.redirect('/auth', authenticated: true), '/invite/$token');
    expect(controller.redirect('/invite/$token', authenticated: true), isNull);
    final second = 'c' * 64;
    await controller.remember(second);
    expect(controller.redirect('/invite/$token', authenticated: true),
        '/invite/$second');
    expect(controller.redirect('/invite/$second', authenticated: true), isNull);
    await controller.clear();
    expect(controller.redirect('/invite/$second', authenticated: true), isNull);
    expect(controller.redirect('/trips', authenticated: true), isNull);
    expect(controller.pendingRoute, isNull);
    controller.dispose();
  });
  test('share URL retains Pages subpath and does not use a path route', () {
    expect(InviteLinkController.buildUrl(token, base: base),
        '$base?invite=$token');
    expect(
        InviteLinkController.tokenFromUri(Uri.parse('$base?invite=$token'),
            base: base),
        token);
  });
  test('rejects foreign hosts, paths, duplicate and malformed tokens', () {
    for (final url in [
      'https://evil.test/trip-app/?invite=$token',
      'https://tanachu0409.github.io/other/?invite=$token',
      '$base?invite=$token&invite=$token',
      '$base?invite=bad'
    ]) {
      expect(InviteLinkController.tokenFromUri(Uri.parse(url), base: base),
          isNull);
    }
    for (final url in [
      '',
      'http://example.com/',
      'https://user@example.com/',
      'https://example.com/?x=y',
      'https://example.com/#/trips'
    ]) {
      expect(
          () => InviteLinkController.parseBaseUrl(url), throwsFormatException);
    }
    expect(
        InviteLinkController.parseBaseUrl('http://localhost:3000').path, '/');
  });
  test('pending invitation survives OAuth reload and is cleared on exit',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final first = InviteLinkController(prefs);
    await first.remember(token);
    expect(first.pendingRoute, '/invite/$token');
    await first.remember('https://evil.test');
    expect(first.pendingRoute, '/invite/$token');
    expect(prefs.getString('pending_trip_invite'), token);
    await first.clear();
    expect(first.pendingRoute, isNull);
    expect(prefs.containsKey('pending_trip_invite'), isFalse);
    first.dispose();
  });
  test('RPC statuses are explicit and existing member permission is preserved',
      () {
    for (final entry in {
      'success': TripInviteStatus.success,
      'already_member': TripInviteStatus.alreadyMember,
      'owner': TripInviteStatus.owner,
      'invalid_link': TripInviteStatus.invalidLink,
      'trip_archived': TripInviteStatus.tripArchived,
      'not_owner': TripInviteStatus.notOwner,
      'invalid_permission': TripInviteStatus.invalidPermission
    }.entries) {
      expect(TripInviteLinkResult.fromJson({'status': entry.key}).status,
          entry.value);
    }
    expect(
        TripInviteLinkResult.fromJson(
            {'status': 'already_member', 'permission': 'viewer'}).permission,
        TripPermission.viewer);
    expect(() => TripInviteLinkResult.fromJson({'status': 'unknown'}),
        throwsFormatException);
    expect(
        () => TripInviteLinkResult.fromJson(
            {'status': 'success', 'permission': 'admin'}),
        throwsFormatException);
  });
}
