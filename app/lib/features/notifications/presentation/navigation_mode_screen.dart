import 'package:flutter/material.dart';
import 'package:trip_planner_app/core/theme/app_theme.dart';
import 'package:trip_planner_app/features/trips/data/trip_store.dart';

class NavigationModeScreen extends StatefulWidget {
  const NavigationModeScreen({super.key, required this.tripId});

  final String tripId;

  @override
  State<NavigationModeScreen> createState() => _NavigationModeScreenState();
}

class _NavigationModeScreenState extends State<NavigationModeScreen> {
  final TripStore _tripStore = TripStore.instance;

  @override
  void initState() {
    super.initState();
    _tripStore.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final trip = _tripStore.findById(widget.tripId);
    if (_tripStore.isLoading && trip == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (trip == null || trip.days.isEmpty) {
      return const Scaffold(body: Center(child: Text('找不到可導航的旅程')));
    }

    final activeDay = trip.days.first;

    return Scaffold(
      appBar: AppBar(title: const Text('導航模式')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.accentStrong,
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '前景定位示意',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 10),
                Text(
                  '這一頁會是之後 geolocator + local notifications 的主要入口。當距離下一站 500m 內時，會發送到點提醒。',
                  style: TextStyle(color: Color(0xFFD9E9FA), height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final stop in activeDay.stops) ...[
            Card(
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                leading: CircleAvatar(
                  backgroundColor: AppColors.accent.withValues(alpha: 0.1),
                  child: const Icon(Icons.place_outlined,
                      color: AppColors.accentStrong),
                ),
                title: Text(stop.title),
                subtitle: Text('${stop.timeLabel ?? '未排定'} · 預設 500m 提醒'),
                trailing: const Icon(Icons.chevron_right_rounded),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
