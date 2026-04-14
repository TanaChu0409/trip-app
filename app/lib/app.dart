import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trip_planner_app/core/router/app_router.dart';
import 'package:trip_planner_app/core/theme/app_theme.dart';

class TripPlannerApp extends ConsumerWidget {
  const TripPlannerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: '桃園嘉義行動導覽',
      theme: buildAppTheme(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
