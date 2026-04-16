import 'package:flutter/material.dart';
import 'package:trip_planner_app/core/theme/app_theme.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';

enum TripCardAction { deleteTrip, leaveTrip }

class TripCard extends StatelessWidget {
  const TripCard({
    super.key,
    required this.trip,
    required this.onTap,
    required this.onActionSelected,
  });

  final TripSummary trip;
  final VoidCallback onTap;
  final ValueChanged<TripCardAction> onActionSelected;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      trip.title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.text,
                          ),
                    ),
                  ),
                  if (trip.role == TripRole.guest)
                    const Chip(label: Text('唯讀'))
                  else
                    const Chip(label: Text('可編輯')),
                  PopupMenuButton<TripCardAction>(
                    tooltip: '旅程操作',
                    onSelected: onActionSelected,
                    itemBuilder: (context) => [
                      if (trip.role == TripRole.owner)
                        const PopupMenuItem(
                          value: TripCardAction.deleteTrip,
                          child: Text('刪除旅程'),
                        )
                      else
                        const PopupMenuItem(
                          value: TripCardAction.leaveTrip,
                          child: Text('退出旅程'),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(trip.dateRange),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MetaPill(label: '${trip.days.length} 天'),
                  _MetaPill(label: '${trip.stopCount} 個停靠點'),
                  _MetaPill(label: trip.role == TripRole.owner ? '我的旅程' : '分享給我的'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.accentStrong,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
