import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';
import 'package:trip_planner_app/core/router/invite_link_controller.dart';
import 'package:trip_planner_app/features/trips/presentation/invite_accept_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trip_planner_app/features/auth/presentation/auth_screen.dart';
import 'package:trip_planner_app/features/auth/data/auth_provider.dart';
import 'package:trip_planner_app/features/trip_detail/presentation/member_management_screen.dart';
import 'package:trip_planner_app/features/trip_detail/presentation/stop_form_screen.dart';
import 'package:trip_planner_app/features/trip_detail/presentation/trip_detail_screen.dart';
import 'package:trip_planner_app/features/trips/presentation/trips_list_screen.dart';
import 'package:trip_planner_app/features/trips/presentation/archived_trips_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authStateListenable = ref.watch(authStateListenableProvider);
  final invites = ref.watch(inviteLinkControllerProvider);

  final router = GoRouter(
    initialLocation: '/trips',
    refreshListenable: Listenable.merge([authStateListenable, invites]),
    redirect: (context, state) {
      return invites.redirect(state.matchedLocation,
          authenticated: authStateListenable.isAuthenticated);
    },
    routes: [
      GoRoute(
          path: '/invite/:token',
          builder: (context, state) =>
              InviteAcceptScreen(token: state.pathParameters['token']!)),
      GoRoute(
        path: '/auth',
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: '/trips',
        builder: (context, state) => const TripsListScreen(),
        routes: [
          GoRoute(
            path: 'archived',
            builder: (context, state) => const ArchivedTripsScreen(),
            routes: [
              GoRoute(
                path: ':tripId',
                builder: (context, state) => TripDetailScreen(
                  tripId: state.pathParameters['tripId']!,
                  loadArchivedTrip: true,
                ),
              ),
            ],
          ),
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
                path: 'members',
                builder: (context, state) {
                  final tripId = state.pathParameters['tripId']!;
                  return MemberManagementScreen(tripId: tripId);
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
