import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trip_planner_app/features/auth/data/auth_service.dart';
import 'package:trip_planner_app/features/trips/data/trip_store.dart';

final authStateChangesProvider = StreamProvider<bool>((ref) {
  final authService = ref.watch(authServiceProvider);
  final controller = StreamController<bool>();

  controller.add(authService.currentSession != null);
  final subscription = authService.authStateChanges.listen((authState) {
    controller.add(authState.session != null);
  });

  ref.onDispose(() async {
    await subscription.cancel();
    await controller.close();
  });

  return controller.stream;
});

final authStateListenableProvider = Provider<AuthStateListenable>((ref) {
  final authService = ref.watch(authServiceProvider);
  final stream = authService.authStateChanges.map((authState) => authState.session != null);
  final listenable = AuthStateListenable(stream, authService.currentSession != null);

  ref.onDispose(listenable.dispose);
  return listenable;
});

class AuthStateListenable extends ChangeNotifier {
  AuthStateListenable(Stream<bool> authStateStream, bool initialValue)
    : _isAuthenticated = initialValue {
    _subscription = authStateStream.listen((isAuthenticated) {
      if (_isAuthenticated == isAuthenticated) {
        return;
      }

      final wasAuthenticated = _isAuthenticated;
      _isAuthenticated = isAuthenticated;

      // When the user signs out (or their session expires), clear all cached
      // trip data and cancel the Realtime subscription so the next user starts
      // with a clean slate.
      if (wasAuthenticated && !isAuthenticated) {
        TripStore.instance.clearForSignOut();
      }

      notifyListeners();
    });
  }

  late final StreamSubscription<bool> _subscription;
  bool _isAuthenticated;

  bool get isAuthenticated => _isAuthenticated;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}