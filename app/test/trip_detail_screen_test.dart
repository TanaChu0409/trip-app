import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner_app/features/trip_detail/presentation/trip_detail_screen.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';
import 'package:trip_planner_app/features/trips/data/trip_store.dart';

class FakeTripStore extends ChangeNotifier implements TripStore {
  TripSummary? trip;

  void update(TripSummary value) {
    trip = value;
    notifyListeners();
  }

  @override
  TripSummary? findById(String id) => trip?.id == id ? trip : null;
  @override
  bool get isLoading => false;
  @override
  bool get isLoadingArchived => false;
  @override
  Object? get loadError => null;
  @override
  Object? get archivedLoadError => null;
  @override
  Future<void> ensureLoaded({bool force = false}) async {}
  @override
  Future<void> ensureArchivedTripsLoaded({bool force = false}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TripSummary makeTrip(
    {String id = 'trip',
    int count = 3,
    bool archived = false,
    TripRole role = TripRole.guest}) {
  final now = DateTime.now();
  return TripSummary(
    id: id,
    title: 'Test trip',
    dateRange: 'Test dates',
    role: role,
    permission: TripPermission.viewer,
    isArchived: archived,
    days: List.generate(
        count,
        (index) => TripDay(
              id: '$id-$index',
              label: 'Day $index',
              dateLabel: 'Date $index',
              subtitle: '',
              stops: [],
              date: DateTime(now.year, now.month, now.day + index - 1),
            )),
  );
}

Widget screen(FakeTripStore store,
        {String id = 'trip', bool archived = false}) =>
    MaterialApp(
        home: TripDetailScreen(
            tripId: id, tripStore: store, loadArchivedTrip: archived));

int selectedIndex(WidgetTester tester) =>
    tester.widget<TabBar>(find.byType(TabBar)).controller!.index;

void main() {
  for (final role in TripRole.values) {
    testWidgets('loaded $role trip selects today', (tester) async {
      final store = FakeTripStore()..trip = makeTrip(role: role);
      await tester.pumpWidget(screen(store));
      await tester.pumpAndSettle();
      expect(selectedIndex(tester), 1);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  }

  testWidgets('archived trip selects today', (tester) async {
    final store = FakeTripStore()..trip = makeTrip(archived: true);
    await tester.pumpWidget(screen(store, archived: true));
    await tester.pumpAndSettle();
    expect(selectedIndex(tester), 1);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('delayed data selects today and preserves manual selection',
      (tester) async {
    final store = FakeTripStore();
    await tester.pumpWidget(screen(store));
    store.update(makeTrip());
    await tester.pumpAndSettle();
    expect(selectedIndex(tester), 1);
    await tester.tap(find.text('Day 2 · Date 2'));
    await tester.pumpAndSettle();
    expect(selectedIndex(tester), 2);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push<void>(MaterialPageRoute(
      builder: (_) => const Scaffold(body: Text('Editing')),
    ));
    await tester.pumpAndSettle();
    store.update(store.trip!.copyWith(title: 'Updated'));
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();
    expect(selectedIndex(tester), 2);
    store.update(store.trip!.copyWith(days: store.trip!.days.take(2).toList()));
    await tester.pumpAndSettle();
    expect(selectedIndex(tester), 1);
    await tester.tap(find.text('Day 0 · Date 0'));
    await tester.pumpAndSettle();
    expect(selectedIndex(tester), 0);
    await tester.pumpWidget(const SizedBox());
    store.update(makeTrip());
    await tester.pumpWidget(screen(store));
    await tester.pumpAndSettle();
    expect(selectedIndex(tester), 1);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('legacy dates select first and refresh preserves selection',
      (tester) async {
    final store = FakeTripStore();
    final trip = makeTrip();
    store.trip = trip.copyWith(days: [
      for (final day in trip.days)
        TripDay.fromCacheJson(day.toCacheJson()..remove('date')),
    ]);
    await tester.pumpWidget(screen(store));
    await tester.pumpAndSettle();
    expect(selectedIndex(tester), 0);
    store.update(trip);
    await tester.pumpAndSettle();
    expect(selectedIndex(tester), 0);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('empty days wait for data even when controller length stays one',
      (tester) async {
    final store = FakeTripStore()..trip = makeTrip(count: 0);
    await tester.pumpWidget(screen(store));
    expect(find.text('尚未建立行程日'), findsOneWidget);
    final today = makeTrip().days[1];
    store.update(store.trip!.copyWith(days: [today]));
    await tester.pumpAndSettle();
    expect(selectedIndex(tester), 0);
    // Initial selection was applied, so later expansion must keep index zero.
    store.update(makeTrip());
    await tester.pumpAndSettle();
    expect(selectedIndex(tester), 0);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('a different trip on the same state selects today again',
      (tester) async {
    final store = FakeTripStore()..trip = makeTrip();
    await tester.pumpWidget(screen(store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Day 2 · Date 2'));
    await tester.pumpAndSettle();
    store.trip = makeTrip(id: 'other');
    await tester.pumpWidget(screen(store, id: 'other'));
    await tester.pumpAndSettle();
    expect(selectedIndex(tester), 1);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
