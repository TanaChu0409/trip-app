import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:trip_planner_app/core/supabase/supabase_error_formatter.dart';
import 'package:trip_planner_app/core/theme/app_theme.dart';
import 'package:trip_planner_app/features/auth/data/auth_service.dart';
import 'package:trip_planner_app/features/trips/data/join_trip_result.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';
import 'package:trip_planner_app/features/trips/data/trip_store.dart';
import 'package:trip_planner_app/features/trips/presentation/widgets/trip_color_picker.dart';
import 'package:trip_planner_app/features/trips/presentation/widgets/trip_card.dart';

class TripsListScreen extends ConsumerStatefulWidget {
  const TripsListScreen({super.key});

  @override
  ConsumerState<TripsListScreen> createState() => _TripsListScreenState();
}

class _TripsListScreenState extends ConsumerState<TripsListScreen> {
  final TripStore _tripStore = TripStore.instance;

  @override
  void initState() {
    super.initState();
    _tripStore.addListener(_handleTripsChanged);
    _tripStore.ensureLoaded();
  }

  @override
  void dispose() {
    _tripStore.removeListener(_handleTripsChanged);
    super.dispose();
  }

  void _handleTripsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final trips = _tripStore.trips;
    final ownedTrips =
        trips.where((trip) => trip.role == TripRole.owner).toList();
    final sharedTrips =
        trips.where((trip) => trip.role == TripRole.guest).toList();
    final isLoading = _tripStore.isLoading && trips.isEmpty;
    final hasLoadError = _tripStore.loadError != null && trips.isEmpty;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateTripSheet(context),
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('新增旅程'),
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
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 96),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '旅遊規劃APP',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                  ),
                  IconButton.outlined(
                    tooltip: '登出',
                    onPressed: () => _signOut(context),
                    icon: const Icon(Icons.logout_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _HeroPanel(ownedTrips: ownedTrips),
              const SizedBox(height: 24),
              if (isLoading) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 24),
              ] else if (hasLoadError) ...[
                _LoadErrorCard(
                  onRetry: () => _tripStore.reloadTrips(),
                  errorMessage:
                      SupabaseErrorFormatter.userMessage(_tripStore.loadError!),
                ),
                const SizedBox(height: 24),
              ],
              _SectionHeader(
                title: '我的旅程',
                actionLabel: '邀請碼加入',
                onPressed: () => _showJoinTripSheet(context),
              ),
              const SizedBox(height: 12),
              if (!isLoading && ownedTrips.isEmpty)
                const _EmptyTripsCard(message: '目前沒有任何旅程，請先建立一個新的旅程。'),
              for (final trip in ownedTrips) ...[
                TripCard(
                  trip: trip,
                  onTap: () => context.go('/trips/${trip.id}'),
                  onActionSelected: (action) =>
                      _handleTripAction(context, trip, action),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 16),
              const _SectionHeader(title: '分享給我的'),
              const SizedBox(height: 12),
              if (!isLoading && sharedTrips.isEmpty)
                const _EmptyTripsCard(message: '目前沒有加入任何分享旅程。'),
              for (final trip in sharedTrips) ...[
                TripCard(
                  trip: trip,
                  onTap: () => context.go('/trips/${trip.id}'),
                  onActionSelected: (action) =>
                      _handleTripAction(context, trip, action),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCreateTripSheet(BuildContext context) async {
    final createdTrip = await showModalBottomSheet<TripSummary>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _CreateTripSheet(),
    );

    if (!context.mounted || createdTrip == null) {
      return;
    }

    context.go('/trips/${createdTrip.id}');
  }

  Future<void> _handleTripAction(
    BuildContext context,
    TripSummary trip,
    TripCardAction action,
  ) async {
    switch (action) {
      case TripCardAction.deleteTrip:
        await _confirmDeleteTrip(context, trip);
      case TripCardAction.leaveTrip:
        await _confirmLeaveTrip(context, trip);
    }
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await ref.read(authServiceProvider).signOut();
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已登出')));
    } catch (_) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登出失敗，請稍後再試')),
      );
    }
  }

  Future<void> _confirmDeleteTrip(
      BuildContext context, TripSummary trip) async {
    final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('刪除旅程？'),
            content: Text('此動作無法復原，${trip.title} 的天數、停靠點、停車資訊與提醒都會一併刪除。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700),
                child: const Text('確認刪除'),
              ),
            ],
          ),
        ) ??
        false;

    if (!context.mounted || !shouldDelete) {
      return;
    }

    final deleted = await _tripStore.deleteTrip(trip.id);
    if (!context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(deleted ? '已刪除旅程：${trip.title}' : '刪除旅程失敗')),
    );
  }

  Future<void> _confirmLeaveTrip(BuildContext context, TripSummary trip) async {
    final shouldLeave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('退出分享旅程？'),
            content: Text('退出後，${trip.title} 會從「分享給我的」列表移除，相關提醒也會一起清除。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('確認退出'),
              ),
            ],
          ),
        ) ??
        false;

    if (!context.mounted || !shouldLeave) {
      return;
    }

    final left = await _tripStore.leaveSharedTrip(trip.id);
    if (!context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(left ? '已退出旅程：${trip.title}' : '退出旅程失敗')),
    );
  }

  Future<void> _showJoinTripSheet(BuildContext context) async {
    final joinedTrip = await showModalBottomSheet<TripSummary>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _JoinTripSheet(),
    );

    if (!context.mounted || joinedTrip == null) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text('已透過分享碼加入：${joinedTrip.title}')),
    );
    context.go('/trips/${joinedTrip.id}');
  }
}

class _CreateTripSheet extends StatefulWidget {
  const _CreateTripSheet();

  @override
  State<_CreateTripSheet> createState() => _CreateTripSheetState();
}

class _CreateTripSheetState extends State<_CreateTripSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  DateTime _startDate = DateTime(2026, 5, 1);
  DateTime _endDate = DateTime(2026, 5, 3);
  String? _selectedColor = TripColors.defaultHex;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        decoration: const BoxDecoration(
          color: Color(0xFFF6FAFF),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('新增旅程', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text('建立後會直接寫入 Supabase，並同步建立對應天數。'),
              const SizedBox(height: 18),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: '旅程名稱',
                  hintText: '例如 台南兩天一夜',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '請輸入旅程名稱';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              _DateField(
                label: '開始日期',
                value: _formatDate(_startDate),
                onTap: () => _pickDate(isStartDate: true),
              ),
              const SizedBox(height: 12),
              _DateField(
                label: '結束日期',
                value: _formatDate(_endDate),
                onTap: () => _pickDate(isStartDate: false),
              ),
              const SizedBox(height: 18),
              TripColorPicker(
                selectedColor: _selectedColor,
                onColorChanged: (value) =>
                    setState(() => _selectedColor = value),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50)),
                child: Text(_isSubmitting ? '建立中...' : '建立旅程'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate({required bool isStartDate}) async {
    final initialDate = isStartDate ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2025, 1, 1),
      lastDate: DateTime(2030, 12, 31),
    );

    if (picked == null) {
      return;
    }

    setState(() {
      if (isStartDate) {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate;
        }
      } else {
        _endDate = picked.isBefore(_startDate) ? _startDate : picked;
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final trip = await TripStore.instance.createTrip(
        title: _titleController.text.trim(),
        startDate: _startDate,
        endDate: _endDate,
        color: _selectedColor,
      );

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(trip);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SupabaseErrorFormatter.userMessage(error))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}/$month/$day';
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.calendar_today_outlined, size: 18),
          ],
        ),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.ownedTrips});

  final List<TripSummary> ownedTrips;

  @override
  Widget build(BuildContext context) {
    final totalStops = ownedTrips.fold(0, (sum, trip) => sum + trip.stopCount);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFAFDFF), Color(0xFFE2EDF8)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2400264D),
            blurRadius: 32,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('旅程總覽', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _SummaryCard(value: '${ownedTrips.length}', label: '我的旅程'),
              _SummaryCard(value: '$totalStops', label: '已整理停靠點'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(label),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.actionLabel, this.onPressed});

  final String title;
  final String? actionLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        if (actionLabel != null && onPressed != null)
          TextButton(onPressed: onPressed, child: Text(actionLabel!)),
      ],
    );
  }
}

class _JoinTripSheet extends StatefulWidget {
  const _JoinTripSheet();

  @override
  State<_JoinTripSheet> createState() => _JoinTripSheetState();
}

class _JoinTripSheetState extends State<_JoinTripSheet> {
  final TextEditingController _codeController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        decoration: const BoxDecoration(
          color: Color(0xFFF6FAFF),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('邀請碼加入', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('輸入 6 碼分享碼後，加入旅程並開始協作（可編輯）。'),
            const SizedBox(height: 18),
            TextField(
              controller: _codeController,
              maxLength: 6,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]'))
              ],
              decoration: const InputDecoration(
                labelText: '輸入 6 碼分享碼',
                hintText: '例如 A1B2C3',
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50)),
              child: Text(_isSubmitting ? '加入中...' : '加入旅程'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    if (code.isEmpty) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('請先輸入分享碼')));
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final result = await TripStore.instance.joinTripByCode(code);
      if (!mounted) {
        return;
      }

      switch (result.status) {
        case JoinTripByCodeStatus.success:
          Navigator.of(context).pop(result.trip);
        case JoinTripByCodeStatus.tripNotFound:
          messenger.hideCurrentSnackBar();
          messenger
              .showSnackBar(const SnackBar(content: Text('查無對應旅程，請確認分享碼')));
        case JoinTripByCodeStatus.alreadyJoined:
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(const SnackBar(content: Text('這個分享碼已經加入過了')));
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(SupabaseErrorFormatter.userMessage(error))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }
}

class _EmptyTripsCard extends StatelessWidget {
  const _EmptyTripsCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(message),
    );
  }
}

class _LoadErrorCard extends StatelessWidget {
  const _LoadErrorCard({required this.onRetry, required this.errorMessage});

  final VoidCallback onRetry;
  final String errorMessage;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '旅程資料載入失敗',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(errorMessage),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('重新載入')),
        ],
      ),
    );
  }
}
