import 'package:flutter/material.dart';
import 'package:trip_planner_app/core/theme/app_theme.dart';

class TripColorPicker extends StatelessWidget {
  const TripColorPicker({
    super.key,
    required this.selectedColor,
    required this.onColorChanged,
    this.label = '旅程顏色',
    this.description = '可隨時在旅程內更改顏色。',
    this.showDefaultOption = false,
    this.defaultLabel = '使用旅程顏色',
  });

  final String? selectedColor;
  final ValueChanged<String?> onColorChanged;
  final String label;
  final String description;
  final bool showDefaultOption;
  final String defaultLabel;

  @override
  Widget build(BuildContext context) {
    final selectedHex = selectedColor ?? TripColors.defaultHex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(description),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (showDefaultOption)
              _DefaultColorOption(
                label: defaultLabel,
                isSelected: selectedColor == null,
                onTap: () => onColorChanged(null),
              ),
            for (final option in TripColors.presets)
              _TripColorOption(
                option: option,
                isSelected: option.hex == selectedHex,
                onTap: () => onColorChanged(option.hex),
              ),
          ],
        ),
      ],
    );
  }
}

class _DefaultColorOption extends StatelessWidget {
  const _DefaultColorOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? AppColors.text : AppColors.accentSoft,
                width: isSelected ? 3 : 1.5,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A00264D),
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              Icons.format_paint_outlined,
              color: isSelected ? AppColors.text : AppColors.muted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.text,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}

class _TripColorOption extends StatelessWidget {
  const _TripColorOption({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  final TripPaletteColor option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: option.color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? AppColors.text : Colors.white,
                width: isSelected ? 3 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: option.color.withValues(alpha: 0.28),
                  blurRadius: isSelected ? 14 : 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: isSelected
                ? Icon(
                    Icons.check_rounded,
                    color: onAccentColor(option.color),
                  )
                : null,
          ),
          const SizedBox(height: 6),
          Text(
            option.label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.text,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}
