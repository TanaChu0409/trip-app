import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trip_planner_app/features/auth/presentation/auth_screen.dart';
import 'package:trip_planner_app/features/auth/data/auth_provider.dart';
import 'package:trip_planner_app/features/notifications/presentation/navigation_mode_screen.dart';
import 'package:trip_planner_app/features/trip_detail/presentation/stop_form_screen.dart';
import 'package:trip_planner_app/features/trip_detail/presentation/trip_detail_screen.dart';
import 'package:trip_planner_app/features/trips/presentation/trips_list_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authStateListenable = ref.watch(authStateListenableProvider);

  return GoRouter(
    initialLocation: '/trips',
    refreshListenable: authStateListenable,
    redirect: (context, state) {
      final isAuthenticated = authStateListenable.isAuthenticated;
      final isAuthRoute = state.matchedLocation == '/auth';

      if (!isAuthenticated && !isAuthRoute) {
        return '/auth';
      }

      if (isAuthenticated && isAuthRoute) {
        return '/trips';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/auth',
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: '/trips',
        builder: (context, state) => const TripsListScreen(),
        routes: [
          GoRoute(
            path: ':tripId',
            builder: (context, state) {
              final tripId = state.pathParameters['tripId']!;
              return TripDetailScreen(tripId: tripId);
            },
            routes: [
              GoRoute(
                path: 'days/:dayId/stops/new',
                builder: (context, state) {
                  final tripId = state.pathParameters['tripId']!;
                  final dayId = state.pathParameters['dayId']!;
                  return StopFormScreen(
                    tripId: tripId,
                    dayId: dayId,
                  );
                },
              ),
              GoRoute(
                path: 'days/:dayId/stops/:stopId/edit',
                builder: (context, state) {
                  final tripId = state.pathParameters['tripId']!;
                  final dayId = state.pathParameters['dayId']!;
                  final stopId = state.pathParameters['stopId']!;
                  return StopFormScreen(
                    tripId: tripId,
                    dayId: dayId,
                    stopId: stopId,
                  );
                },
              ),
              GoRoute(
                path: 'navigation',
                builder: (context, state) {
                  final tripId = state.pathParameters['tripId']!;
                  return NavigationModeScreen(tripId: tripId);
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
