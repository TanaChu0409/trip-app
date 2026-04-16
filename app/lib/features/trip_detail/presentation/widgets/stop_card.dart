import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:trip_planner_app/core/theme/app_theme.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';

class StopCard extends StatelessWidget {
  const StopCard({
    super.key,
    required this.stop,
    required this.tripColor,
    required this.isReadOnly,
    this.onTap,
    this.trailing,
  });

  final StopItem stop;
  final String? tripColor;
  final bool isReadOnly;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final accentColor = colorFromHex(stop.color ?? tripColor);
    final accentSoft = tintColor(
      accentColor,
      amount: stop.color == null ? 0.94 : 0.9,
    );
    final accentStrong = shadeColor(accentColor, amount: 0.18);
    final cardColor =
        stop.isHighlight ? tintColor(accentColor, amount: 0.82) : accentSoft;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 68,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              stop.timeLabel ?? '未排定',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: accentStrong,
              ),
            ),
          ),
        ),
        Expanded(
          child: Card(
            color: cardColor,
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
                        Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(top: 6),
                          decoration: BoxDecoration(
                            color: accentColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: accentColor.withValues(alpha: 0.24),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            stop.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: accentStrong),
                          ),
                        ),
                        if (stop.badge != null) ...[
                          const SizedBox(width: 8),
                          Chip(
                            backgroundColor:
                                tintColor(accentColor, amount: 0.86),
                            labelStyle: TextStyle(
                              color: accentStrong,
                              fontWeight: FontWeight.w700,
                            ),
                            label: Text(stop.badge!),
                          ),
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
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final parking in stop.parkingSpots) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: accentColor.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  parking.name,
                                  style: const TextStyle(
                                    color: AppColors.text,
                                  ),
                                ),
                              ),
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
                      isReadOnly
                          ? '唯讀模式仍可接收通知與使用導航模式。'
                          : '點擊可編輯，長按拖曳可調整順序。',
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
