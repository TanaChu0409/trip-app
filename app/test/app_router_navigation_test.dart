import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:trip_planner_app/core/router/app_router.dart';
import 'package:trip_planner_app/features/auth/data/auth_provider.dart';

void main() {
  test('trip navigation path is not registered', () {
    final container = ProviderContainer(
      overrides: [
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
