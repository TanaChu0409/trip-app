import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:trip_planner_app/core/theme/app_theme.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';

class StopCard extends StatelessWidget {
  const StopCard({
    super.key,
    required this.stop,
    required this.isReadOnly,
    this.onTap,
    this.trailing,
  });

  final StopItem stop;
  final bool isReadOnly;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 68,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              stop.timeLabel ?? '未排定',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.accentStrong,
              ),
            ),
          ),
        ),
        Expanded(
          child: Card(
            color: stop.isHighlight
                ? const Color(0xFFE8F2FB)
                : AppColors.surface.withValues(alpha: 0.92),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            stop.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (stop.badge != null) ...[
                          const SizedBox(width: 8),
                          Chip(label: Text(stop.badge!)),
                        ],
                        if (trailing != null) ...[
                          const SizedBox(width: 8),
                          trailing!,
                        ],
                      ],
                    ),
                    if (stop.note != null) ...[
                      const SizedBox(height: 8),
                      Text(stop.note!),
                    ],
                    if (stop.mapUrl != null) ...[
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: () => _openMap(stop.mapUrl!),
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('開啟地圖'),
                      ),
                    ],
                    if (stop.parkingSpots.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const Text(
                        '附近停車場',
                        style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.text),
                      ),
                      const SizedBox(height: 8),
                      for (final parking in stop.parkingSpots) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.accent.withValues(alpha: 0.08)),
                          ),
                          child: Row(
                            children: [
                              Expanded(child: Text(parking.name, style: const TextStyle(color: AppColors.text))),
                              TextButton(
                                onPressed: () => _openMap(parking.mapUrl),
                                child: const Text('導航'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 8),
                    Text(
                      isReadOnly ? '唯讀模式仍可接收通知與使用導航模式。' : '點擊可編輯，長按拖曳可調整順序。',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openMap(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }
}
