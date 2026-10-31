import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:trip_planner_app/core/router/app_router.dart';
import 'package:trip_planner_app/features/auth/data/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trip_planner_app/core/router/invite_link_controller.dart';

void main() {
  test('trip navigation path is not registered', () async {
    SharedPreferences.setMockInitialValues({});
    final invites = InviteLinkController(await SharedPreferences.getInstance());
    addTearDown(invites.dispose);
    final container = ProviderContainer(
      overrides: [
        inviteLinkControllerProvider.overrideWithValue(invites),
        authStateListenableProvider.overrideWith(
          (ref) => AuthStateListenable(const Stream<bool>.empty(), true),
        ),
      ],
    );
    addTearDown(container.dispose);

    final routes = container.read(appRouterProvider).configuration.routes;
    final paths = _allRoutePaths(routes);

    expect(paths, isNot(contains('navigation')));
  });
}

List<String> _allRoutePaths(List<RouteBase> routes) => [
      for (final route in routes)
        if (route is GoRoute) ...[
          route.path,
          ..._allRoutePaths(route.routes),
        ],
    ];
