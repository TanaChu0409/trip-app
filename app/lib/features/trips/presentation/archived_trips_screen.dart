import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:trip_planner_app/core/supabase/supabase_error_formatter.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';
import 'package:trip_planner_app/features/trips/data/trip_store.dart';
import 'package:trip_planner_app/features/trips/presentation/widgets/trip_card.dart';

class ArchivedTripsScreen extends StatefulWidget {
  const ArchivedTripsScreen({super.key});

  @override
  State<ArchivedTripsScreen> createState() => _ArchivedTripsScreenState();
}

class _ArchivedTripsScreenState extends State<ArchivedTripsScreen> {
  final TripStore _tripStore = TripStore.instance;

  @override
  void initState() {
    super.initState();
    _tripStore.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _tripStore,
      builder: (context, _) {
        final trips = _tripStore.archivedTrips;
        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF5F9FE), Color(0xFFDDE8F3)],
              ),
            ),
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  Row(children: [
                    IconButton(
                      tooltip: '返回旅程列表',
                      onPressed: () => context.go('/trips'),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text('封存旅程',
                            style: Theme.of(context).textTheme.headlineMedium)),
                  ]),
                  const SizedBox(height: 8),
                  const Text('封存旅程可完整瀏覽，但不能編輯、邀請成員或使用導航。'),
                  const SizedBox(height: 24),
                  if (_tripStore.isLoading && trips.isEmpty)
                    const Center(child: CircularProgressIndicator())
                  else if (_tripStore.loadError != null && trips.isEmpty)
                    _ArchivedLoadErrorCard(
                      message: SupabaseErrorFormatter.userMessage(
                          _tripStore.loadError!),
                      onRetry: _tripStore.reloadTrips,
                    )
                  else if (trips.isEmpty)
                    const _ArchivedEmptyCard()
                  else
                    for (final trip in trips) ...[
                      TripCard(
                        trip: trip,
                        onTap: () => context.go('/trips/archived/${trip.id}'),
                        onActionSelected: (action) =>
                            _handleAction(trip, action),
                        showActions: trip.role == TripRole.guest,
                      ),
                      const SizedBox(height: 12),
                    ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleAction(TripSummary trip, TripCardAction action) async {
    if (action != TripCardAction.leaveTrip) return;
    final restored = await _tripStore.leaveSharedTrip(trip.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(restored ? '已退出旅程：${trip.title}' : '退出旅程失敗')),
    );
  }
}

class _ArchivedEmptyCard extends StatelessWidget {
  const _ArchivedEmptyCard();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Text('目前沒有封存的旅程。'),
      );
}

class _ArchivedLoadErrorCard extends StatelessWidget {
  const _ArchivedLoadErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('封存旅程載入失敗'),
            const SizedBox(height: 8),
            Text(message),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('重新載入')),
          ],
        ),
      );
}
