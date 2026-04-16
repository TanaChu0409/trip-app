import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:trip_planner_app/core/supabase/supabase_error_formatter.dart';
import 'package:trip_planner_app/core/theme/app_theme.dart';
import 'package:trip_planner_app/core/ui/app_scaffold_messenger.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';
import 'package:trip_planner_app/features/trips/data/trip_store.dart';
import 'package:trip_planner_app/features/trips/presentation/widgets/trip_color_picker.dart';

class StopFormScreen extends StatefulWidget {
  const StopFormScreen({
    super.key,
    required this.tripId,
    required this.dayId,
    this.stopId,
  });

  final String tripId;
  final String dayId;
  final String? stopId;

  @override
  State<StopFormScreen> createState() => _StopFormScreenState();
}

class _StopFormScreenState extends State<StopFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _timeController = TextEditingController();
  final _noteController = TextEditingController();
  final _badgeController = TextEditingController();
  final _mapUrlController = TextEditingController();
  final List<_ParkingSpotDraft> _parkingSpots = [];
  final TripStore _tripStore = TripStore.instance;

  String? _selectedColor;
  bool _isHighlight = false;
  bool _isSaving = false;
  bool _initialized = false;

  bool get _isEditMode => widget.stopId != null;

  @override
  void initState() {
    super.initState();
    _tripStore.ensureLoaded();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _timeController.dispose();
    _noteController.dispose();
    _badgeController.dispose();
    _mapUrlController.dispose();
    for (final parkingSpot in _parkingSpots) {
      parkingSpot.dispose();
    }
    super.dispose();
  }

  TripSummary? get _trip => _tripStore.findById(widget.tripId);

  TripDay? get _day => _tripStore.findDay(widget.tripId, widget.dayId);

  StopItem? get _currentStop {
    final stopId = widget.stopId;
    if (stopId == null) {
      return null;
    }

    return _tripStore.findStop(widget.tripId, widget.dayId, stopId);
  }

  @override
  Widget build(BuildContext context) {
    _initializeFormIfNeeded();
    final trip = _trip;
    final day = _day;
    if (_tripStore.isLoading && trip == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (trip == null || day == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('找不到行程')),
        body: const Center(child: Text('這個行程地點不存在或已被刪除。')),
      );
    }

    final isReadOnly = trip.role == TripRole.guest;
    if (isReadOnly) {
      return Scaffold(
        appBar: AppBar(title: const Text('唯讀旅程')),
        body: const Center(child: Text('受邀唯讀旅程無法編輯地點。')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? '編輯地點' : '新增地點'),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF5F9FE), Color(0xFFDDE8F3)],
          ),
        ),
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.84),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(day.label,
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text('${trip.title} · ${day.dateLabel}'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildSectionCard(
                  context,
                  title: '地點資訊',
                  children: [
                    TextFormField(
                      controller: _titleController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: '地點名稱'),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '請輸入地點名稱';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _timeController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: '抵達時間（選填）',
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_timeController.text.isNotEmpty)
                              IconButton(
                                tooltip: '清除時間',
                                onPressed: _isSaving
                                    ? null
                                    : () =>
                                        setState(() => _timeController.clear()),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            IconButton(
                              tooltip: '選擇時間',
                              onPressed: _isSaving ? null : _pickTime,
                              icon: const Icon(Icons.access_time_rounded),
                            ),
                          ],
                        ),
                      ),
                      onTap: _isSaving ? null : _pickTime,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _noteController,
                      minLines: 3,
                      maxLines: 5,
                      decoration: const InputDecoration(labelText: '備註（選填）'),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _badgeController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: '標籤（選填）'),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _mapUrlController,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(labelText: '地圖連結（選填）'),
                      validator: _validateOptionalUrl,
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile.adaptive(
                      value: _isHighlight,
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: AppColors.accentStrong,
                      activeTrackColor: AppColors.accentSoft,
                      title: const Text('標記為重點地點'),
                      subtitle: const Text('重點地點會使用較醒目的卡片底色。'),
                      onChanged: _isSaving
                          ? null
                          : (value) => setState(() => _isHighlight = value),
                    ),
                    const SizedBox(height: 14),
                    TripColorPicker(
                      label: '地點顏色',
                      description: '可為這個地點設定獨立顏色；未設定時沿用旅程顏色。',
                      selectedColor: _selectedColor,
                      showDefaultOption: true,
                      defaultLabel: '沿用旅程顏色',
                      onColorChanged: (value) =>
                          setState(() => _selectedColor = value),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSectionCard(
                  context,
                  title: '鄰近停車場',
                  action: OutlinedButton.icon(
                    onPressed: _isSaving ? null : _addParkingSpot,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('新增停車場'),
                  ),
                  children: [
                    if (_parkingSpots.isEmpty)
                      Text(
                        '尚未加入停車場資訊。',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.muted),
                      ),
                    for (var index = 0;
                        index < _parkingSpots.length;
                        index += 1) ...[
                      _ParkingSpotFields(
                        key: ValueKey(
                            _parkingSpots[index].id ?? 'parking-$index'),
                        draft: _parkingSpots[index],
                        index: index,
                        isSaving: _isSaving,
                        onRemove: () => _removeParkingSpot(index),
                      ),
                      if (index != _parkingSpots.length - 1)
                        const SizedBox(height: 12),
                    ],
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _isSaving ? null : _submit,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_isSaving ? '儲存中...' : '儲存地點'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _initializeFormIfNeeded() {
    if (_initialized) {
      return;
    }

    final stop = _currentStop;
    if (stop != null) {
      _titleController.text = stop.title;
      _timeController.text = stop.timeLabel ?? '';
      _noteController.text = stop.note ?? '';
      _badgeController.text = stop.badge ?? '';
      _mapUrlController.text = stop.mapUrl ?? '';
      _selectedColor = stop.color;
      _isHighlight = stop.isHighlight;
      for (final parkingSpot in stop.parkingSpots) {
        _parkingSpots.add(_ParkingSpotDraft.fromParkingSpot(parkingSpot));
      }
    }

    _initialized = true;
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required List<Widget> children,
    Widget? action,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child:
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
              ),
              if (action != null) action,
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Future<void> _pickTime() async {
    final initialTime = _parseTime(_timeController.text) ?? TimeOfDay.now();
    final selected = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (!mounted || selected == null) {
      return;
    }

    setState(() {
      _timeController.text = _formatTime(selected);
    });
  }

  void _addParkingSpot() {
    setState(() {
      _parkingSpots.add(_ParkingSpotDraft.empty());
    });
  }

  void _removeParkingSpot(int index) {
    setState(() {
      final removed = _parkingSpots.removeAt(index);
      removed.dispose();
    });
  }

  Future<void> _submit() async {
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final stop = StopItem(
        id: _currentStop?.id,
        title: _titleController.text.trim(),
        timeLabel: _cleanOptional(_timeController.text),
        note: _cleanOptional(_noteController.text),
        badge: _cleanOptional(_badgeController.text),
        mapUrl: _cleanOptional(_mapUrlController.text),
        color: _selectedColor,
        isHighlight: _isHighlight,
        parkingSpots: [
          for (var index = 0; index < _parkingSpots.length; index += 1)
            _parkingSpots[index].toParkingSpot(index),
        ],
        sortOrder: _currentStop?.sortOrder ?? 0,
      );

      if (_isEditMode) {
        await _tripStore.updateStop(
          tripId: widget.tripId,
          dayId: widget.dayId,
          stop: stop,
        );
      } else {
        await _tripStore.addStop(
          tripId: widget.tripId,
          dayId: widget.dayId,
          stop: stop,
        );
      }

      if (!mounted) {
        return;
      }

      showAppSnackBar(
        SnackBar(content: Text(_isEditMode ? '已更新地點' : '已新增地點')),
      );
      context.go('/trips/${widget.tripId}');
    } catch (error) {
      if (!mounted) {
        return;
      }

      showAppSnackBar(
        SnackBar(content: Text(SupabaseErrorFormatter.userMessage(error))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  String? _validateOptionalUrl(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return '請輸入有效的網址';
    }

    return null;
  }

  String? _cleanOptional(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  TimeOfDay? _parseTime(String raw) {
    if (raw.isEmpty) {
      return null;
    }

    final parts = raw.split(':');
    if (parts.length != 2) {
      return null;
    }

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return null;
    }

    return TimeOfDay(hour: hour, minute: minute);
  }

  String _formatTime(TimeOfDay value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _ParkingSpotFields extends StatelessWidget {
  const _ParkingSpotFields({
    super.key,
    required this.draft,
    required this.index,
    required this.isSaving,
    required this.onRemove,
  });

  final _ParkingSpotDraft draft;
  final int index;
  final bool isSaving;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFD),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.10)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '停車場 ${index + 1}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: '移除停車場',
                onPressed: isSaving ? null : onRemove,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: draft.nameController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: '停車場名稱'),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return '請輸入停車場名稱';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: draft.mapUrlController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: '停車場地圖連結'),
            validator: (value) {
              final trimmed = value?.trim();
              if (trimmed == null || trimmed.isEmpty) {
                return '請輸入停車場地圖連結';
              }

              final uri = Uri.tryParse(trimmed);
              if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
                return '請輸入有效的網址';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }
}

class _ParkingSpotDraft {
  _ParkingSpotDraft({
    required this.id,
    required this.nameController,
    required this.mapUrlController,
  });

  factory _ParkingSpotDraft.empty() {
    return _ParkingSpotDraft(
      id: null,
      nameController: TextEditingController(),
      mapUrlController: TextEditingController(),
    );
  }

  factory _ParkingSpotDraft.fromParkingSpot(ParkingSpot parkingSpot) {
    return _ParkingSpotDraft(
      id: parkingSpot.id,
      nameController: TextEditingController(text: parkingSpot.name),
      mapUrlController: TextEditingController(text: parkingSpot.mapUrl),
    );
  }

  final String? id;
  final TextEditingController nameController;
  final TextEditingController mapUrlController;

  ParkingSpot toParkingSpot(int index) {
    return ParkingSpot(
      id: id,
      name: nameController.text.trim(),
      mapUrl: mapUrlController.text.trim(),
      sortOrder: index,
    );
  }

  void dispose() {
    nameController.dispose();
    mapUrlController.dispose();
  }
}
