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
    final tripColor = colorFromHex(trip.color);
    final tripColorSoft = tintColor(tripColor, amount: 0.9);
    final tripColorStrong = shadeColor(tripColor, amount: 0.18);

    return Card(
      color: tintColor(tripColor, amount: 0.95),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      color: tripColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: tripColor.withValues(alpha: 0.28),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      trip.title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: tripColorStrong,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
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
              Text(
                trip.dateRange,
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MetaPill(
                    label: '${trip.days.length} 天',
                    backgroundColor: tripColorSoft,
                    textColor: tripColorStrong,
                  ),
                  _MetaPill(
                    label: '${trip.stopCount} 個停靠點',
                    backgroundColor: tripColorSoft,
                    textColor: tripColorStrong,
                  ),
                  _MetaPill(
                    label: trip.role == TripRole.owner ? '我的旅程' : '分享給我的',
                    backgroundColor: tripColorSoft,
                    textColor: tripColorStrong,
                  ),
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
  const _MetaPill({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });

  final String label;
  final Color backgroundColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
