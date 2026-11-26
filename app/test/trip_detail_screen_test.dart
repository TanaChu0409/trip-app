import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner_app/features/trip_detail/presentation/trip_detail_screen.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';
import 'package:trip_planner_app/features/trips/data/trip_store.dart';

class FakeTripStore extends ChangeNotifier implements TripStore {
  TripSummary? trip;
  int colorSaves = 0;
  bool failColorSave = false;
  Map<String, String>? savedNames;
  String? savedTitle;
  @override
  Future<bool> updateTripDetails(String tripId,
      {required String title,
      required DateTime startDate,
      required DateTime endDate,
      required String? color,
      Map<String, String> colorNames = const {}}) async {
    colorSaves++;
    if (failColorSave) throw StateError('offline');
    savedNames = Map.of(colorNames);
    savedTitle = title;
    return true;
  }

  bool get isObserved => hasListeners;

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
  for (final permission in [TripPermission.editor, TripPermission.viewer]) {
    testWidgets('edit entry respects guest permission $permission',
        (tester) async {
      final store = FakeTripStore()
        ..trip = makeTrip().copyWith(permission: permission);
      await tester.pumpWidget(screen(store));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('旅程操作'));
      await tester.pumpAndSettle();
      expect(find.text('編輯旅程'),
          permission == TripPermission.editor ? findsOneWidget : findsNothing);
    });
  }
  testWidgets('archived owner cannot edit metadata', (tester) async {
    final store = FakeTripStore()
      ..trip = makeTrip(role: TripRole.owner, archived: true);
    await tester.pumpWidget(screen(store));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('旅程操作'));
    await tester.pumpAndSettle();
    expect(find.text('編輯旅程'), findsNothing);
  });
  testWidgets('edit validates title and submits trimmed name', (tester) async {
    final store = FakeTripStore()..trip = makeTrip(role: TripRole.owner);
    await tester.pumpWidget(screen(store));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('旅程操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('編輯旅程'));
    await tester.pumpAndSettle();
    expect(find.text('Test trip'), findsWidgets);
    await tester.enterText(find.byType(TextFormField), '  ');
    await tester.tap(find.widgetWithText(FilledButton, '儲存'));
    await tester.pumpAndSettle();
    expect(find.text('請輸入旅程名稱'), findsOneWidget);
    expect(store.colorSaves, 0);
    await tester.enterText(find.byType(TextFormField), '  新名稱  ');
    await tester.tap(find.widgetWithText(FilledButton, '儲存'));
    await tester.pumpAndSettle();
    expect(store.savedTitle, '新名稱');
    expect(store.colorSaves, 1);
  });
  test('trip date cache supports explicit and legacy dates', () {
    final trip = makeTrip().copyWith(
        startDate: DateTime(2026, 1, 1), endDate: DateTime(2026, 1, 3));
    final json = trip.toCacheJson();
    expect(TripSummary.fromCacheJson(json).resolvedStartDate,
        DateTime(2026, 1, 1));
    json.remove('start_date');
    json.remove('end_date');
    final legacy = TripSummary.fromCacheJson(json);
    expect(legacy.resolvedStartDate, trip.days.first.date);
    expect(legacy.resolvedEndDate, trip.days.last.date);
  });

  testWidgets('day tabs show weekdays and scroll on narrow screens',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = FakeTripStore()
      ..trip = makeTrip().copyWith(days: [
        for (var index = 0; index < 4; index++)
          TripDay(
            id: 'day-$index',
            label: ['第一天', '第二天', '第三天', '第四天'][index],
            dateLabel: '12/${12 + index}',
            date: index == 3 ? null : DateTime(2026, 12, 12 + index),
            subtitle: '',
            stops: [],
          ),
      ]);
    await tester.pumpWidget(screen(store));
    await tester.pumpAndSettle();

    expect(find.text('第一天 · 12/12 (六)'), findsOneWidget);
    expect(find.text('第二天 · 12/13 (日)'), findsOneWidget);
    expect(find.text('第三天 · 12/14 (一)'), findsOneWidget);
    expect(find.text('第四天 · 12/15'), findsOneWidget);
    expect(tester.widget<TabBar>(find.byType(TabBar)).isScrollable, isTrue);
    await tester.drag(find.byType(TabBar), const Offset(-600, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第四天 · 12/15'));
    await tester.pumpAndSettle();
    expect(selectedIndex(tester), 3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets(
      'trip colour cancel discards and failed save preserves name for retry',
      (tester) async {
    final store = FakeTripStore()
      ..trip = makeTrip(role: TripRole.owner)
          .copyWith(color: '#123456', customColorNames: {'#123456': '原名'});
    await tester.pumpWidget(screen(store));
    await tester.pumpAndSettle();
    Future<void> openColors() async {
      await tester.tap(find.byTooltip('旅程操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('編輯旅程'));
      await tester.pumpAndSettle();
    }

    Future<void> rename(String name) async {
      await tester.tap(find.text('修改名稱'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('custom-color-name')), name);
      await tester.tap(find.widgetWithText(FilledButton, '確認').last);
      await tester.pumpAndSettle();
    }

    await openColors();
    await rename('取消的名稱');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(store.colorSaves, 0);
    await openColors();
    expect(find.text('原名'), findsOneWidget);
    await rename('海洋藍');
    store.failColorSave = true;
    await tester.tap(find.widgetWithText(FilledButton, '儲存'));
    await tester.pumpAndSettle();
    expect(find.text('操作失敗，請稍後再試。'), findsOneWidget);
    expect(find.text('海洋藍'), findsOneWidget);
    store.failColorSave = false;
    await tester.tap(find.widgetWithText(FilledButton, '儲存'));
    await tester.pumpAndSettle();
    expect(store.savedNames, {'#123456': '海洋藍'});
    expect(store.colorSaves, 2);
    expect(find.text('編輯旅程'), findsNothing);
  });

  for (final initiallyLoaded in [true, false]) {
    testWidgets('rebinds replacement store (loaded: $initiallyLoaded)',
        (tester) async {
      final oldStore = FakeTripStore()..trip = makeTrip();
      final replacement = FakeTripStore();
      if (initiallyLoaded) {
        replacement.trip = makeTrip().copyWith(title: 'Replacement');
      }
      await tester.pumpWidget(screen(oldStore));
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(TripDetailScreen));
      expect(oldStore.isObserved, isTrue);

      await tester.pumpWidget(screen(replacement));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(TripDetailScreen)), same(state));
      expect(oldStore.isObserved, isFalse);
      expect(replacement.isObserved, isTrue);
      if (initiallyLoaded) {
        expect(find.text('Replacement'), findsOneWidget);
        expect(selectedIndex(tester), 1);
      } else {
        expect(find.text('找不到旅程'), findsOneWidget);
      }

      oldStore.update(makeTrip().copyWith(title: 'Obsolete'));
      replacement.update(makeTrip().copyWith(title: 'New update'));
      await tester.pumpAndSettle();
      expect(find.text('New update'), findsOneWidget);
      expect(find.text('Obsolete'), findsNothing);
      expect(selectedIndex(tester), 1);
      await tester.pumpWidget(const SizedBox());
      expect(replacement.isObserved, isFalse);
      oldStore.dispose();
      replacement.dispose();
    });
  }

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
    await tester.tap(find.textContaining('Day 2 · Date 2'));
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
    await tester.tap(find.textContaining('Day 0 · Date 0'));
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
    await tester.tap(find.textContaining('Day 2 · Date 2'));
    await tester.pumpAndSettle();
    store.trip = makeTrip(id: 'other');
    await tester.pumpWidget(screen(store, id: 'other'));
    await tester.pumpAndSettle();
    expect(selectedIndex(tester), 1);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
