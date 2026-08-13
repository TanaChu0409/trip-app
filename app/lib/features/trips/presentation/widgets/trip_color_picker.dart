import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart' as fcp;
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
    this.savedCustomColors = const [],
    this.onRemoveSavedCustomColor,
  });

  final String? selectedColor;
  final ValueChanged<String?> onColorChanged;
  final String label;
  final String description;
  final bool showDefaultOption;
  final String defaultLabel;
  final List<String> savedCustomColors;
  final Future<void> Function(String color)? onRemoveSavedCustomColor;

  @override
  Widget build(BuildContext context) {
    final selectedHex = selectedColor ?? TripColors.defaultHex;
    final isCustom = selectedColor != null &&
        !TripColors.presets.any((p) => p.hex == selectedColor) &&
        !savedCustomColors.contains(selectedColor);

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
            for (final color in savedCustomColors)
              _SavedCustomColorOption(
                color: color,
                isSelected: color == selectedColor,
                onTap: () => onColorChanged(color),
                onRemove: onRemoveSavedCustomColor == null
                    ? null
                    : () => _confirmRemoveSavedColor(context, color),
              ),
            _CustomColorOption(
              isSelected: isCustom,
              customColor: isCustom ? colorFromHex(selectedColor) : null,
              onTap: () => _showColorPickerDialog(context),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmRemoveSavedColor(BuildContext context, String color) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('移除旅行色票？'),
        content: Text('$color 將不再供這趟旅行的新地點選用；已使用此顏色的地點不會改變。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('移除')),
        ],
      ),
    );
    if (confirmed == true) await onRemoveSavedCustomColor?.call(color);
  }

  Future<void> _showColorPickerDialog(BuildContext context) async {
    final initialColor =
        colorFromHex(selectedColor, fallback: TripColors.presets.first.color);
    final hexController = TextEditingController(
      text: hexFromColor(initialColor).replaceFirst('#', ''),
    );
    Color pickedColor = initialColor;
    String? hexError;
    bool isUpdatingHexFromPicker = false;

    void syncHexController(Color color) {
      final nextHex = hexFromColor(color).replaceFirst('#', '');
      final currentValue = hexController.value;
      final selection = currentValue.selection;
      final nextLength = nextHex.length;

      int clampSelectionOffset(int offset) =>
          selection.isValid ? offset.clamp(0, nextLength) : nextLength;

      isUpdatingHexFromPicker = true;
      hexController.value = TextEditingValue(
        text: nextHex,
        selection: TextSelection(
          baseOffset: clampSelectionOffset(selection.baseOffset),
          extentOffset: clampSelectionOffset(selection.extentOffset),
        ),
        composing: currentValue.composing.isValid &&
                currentValue.composing.start <= nextLength &&
                currentValue.composing.end <= nextLength
            ? currentValue.composing
            : TextRange.empty,
      );
      isUpdatingHexFromPicker = false;
    }

    try {
      final dialogResult = await showDialog<_ColorPickerResult>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('選擇自訂顏色'),
                contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      fcp.ColorPicker(
                        pickerColor: pickedColor,
                        onColorChanged: (color) {
                          syncHexController(color);
                          setDialogState(() {
                            pickedColor = color;
                            hexError = null;
                          });
                        },
                        colorPickerWidth: 280,
                        pickerAreaHeightPercent: 0.7,
                        enableAlpha: false,
                        labelTypes: const [],
                        displayThumbColor: true,
                        paletteType: fcp.PaletteType.hsvWithHue,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: hexController,
                        decoration: InputDecoration(
                          prefixText: '#',
                          labelText: '輸入色碼',
                          hintText: 'RRGGBB',
                          errorText: hexError,
                          counterText: '',
                        ),
                        maxLength: 6,
                        maxLengthEnforcement: MaxLengthEnforcement.enforced,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9A-Fa-f]'),
                          ),
                        ],
                        onChanged: (value) {
                          if (isUpdatingHexFromPicker) {
                            return;
                          }

                          setDialogState(() {
                            if (value.length == 6) {
                              pickedColor = colorFromHex('#$value');
                            }
                            hexError = null;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(null),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () {
                      final hexText = hexController.text;
                      if (hexText.length != 6) {
                        setDialogState(
                          () => hexError = '請輸入完整的 6 位色碼',
                        );
                        return;
                      }
                      Navigator.of(dialogContext).pop(
                        _ColorPickerResult(color: pickedColor),
                      );
                    },
                    child: const Text('確認'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (dialogResult != null) {
        onColorChanged(hexFromColor(dialogResult.color));
      }
    } finally {
      hexController.dispose();
    }
  }
}

class _SavedCustomColorOption extends StatelessWidget {
  const _SavedCustomColorOption({
    required this.color,
    required this.isSelected,
    required this.onTap,
    this.onRemove,
  });

  final String color;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final displayColor = colorFromHex(color);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              _ColorCircle(color: displayColor, isSelected: isSelected),
              if (onRemove != null)
                Positioned(
                  right: -7,
                  top: -7,
                  child: InkWell(
                    onTap: onRemove,
                    customBorder: const CircleBorder(),
                    child: const CircleAvatar(
                      radius: 10,
                      backgroundColor: AppColors.text,
                      child: Icon(Icons.close_rounded, size: 13, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(color, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500)),
        ],
      ),
    );
  }
}

class _ColorCircle extends StatelessWidget {
  const _ColorCircle({required this.color, required this.isSelected});
  final Color color;
  final bool isSelected;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: isSelected ? AppColors.text : Colors.white, width: isSelected ? 3 : 1),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.28), blurRadius: isSelected ? 14 : 8, offset: const Offset(0, 4))],
        ),
        child: isSelected ? Icon(Icons.check_rounded, color: onAccentColor(color)) : null,
      );
}

class _ColorPickerResult {
  const _ColorPickerResult({required this.color});
  final Color color;
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

class _CustomColorOption extends StatelessWidget {
  const _CustomColorOption({
    required this.isSelected,
    required this.onTap,
    this.customColor,
  });

  final bool isSelected;
  final VoidCallback onTap;
  final Color? customColor;

  @override
  Widget build(BuildContext context) {
    final displayColor = customColor ?? Colors.white;
    final hasCustom = customColor != null;

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
              color: displayColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? AppColors.text : AppColors.accentSoft,
                width: isSelected ? 3 : 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: hasCustom
                      ? displayColor.withValues(alpha: 0.28)
                      : const Color(0x1A00264D),
                  blurRadius: isSelected ? 14 : 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: isSelected && hasCustom
                ? Icon(
                    Icons.check_rounded,
                    color: onAccentColor(displayColor),
                  )
                : Icon(
                    Icons.palette_outlined,
                    color: hasCustom
                        ? onAccentColor(displayColor)
                        : AppColors.muted,
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            '自訂顏色',
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
