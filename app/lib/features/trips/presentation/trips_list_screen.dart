import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:trip_planner_app/core/theme/app_theme.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';
import 'package:trip_planner_app/features/trips/data/trip_store.dart';
import 'package:trip_planner_app/features/trips/presentation/widgets/trip_card.dart';
import 'package:trip_planner_app/features/trips/presentation/widgets/trip_editor_sheet.dart';

class TripsListScreen extends StatefulWidget {
  const TripsListScreen({super.key});

  @override
  State<TripsListScreen> createState() => _TripsListScreenState();
}

class _TripsListScreenState extends State<TripsListScreen> {
  final TripStore _tripStore = TripStore.instance;

  @override
  void initState() {
    super.initState();
    _tripStore.addListener(_handleTripsChanged);
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
    final ownedTrips = trips.where((trip) => trip.role == TripRole.owner).toList();
    final sharedTrips = trips.where((trip) => trip.role == TripRole.guest).toList();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _tripStore.isLoading ? null : () => _showTripEditorSheet(context),
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
          child: _tripStore.isLoading && trips.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 96),
                  children: [
                    Text('桃園嘉義行動導覽', style: Theme.of(context).textTheme.headlineLarge),
                    const SizedBox(height: 12),
                    const Text('目前已接上 Supabase 旅程同步，owner 可直接建立、編輯、刪除旅程。'),
                    const SizedBox(height: 16),
                    _StatusBanner(
                      isRemoteActive: _tripStore.isRemoteActive,
                      isLoading: _tripStore.isLoading,
                      message: _tripStore.statusMessage,
                    ),
                    const SizedBox(height: 24),
                    _HeroPanel(
                      ownedTrips: ownedTrips,
                      isRemoteActive: _tripStore.isRemoteActive,
                    ),
                    const SizedBox(height: 24),
                    _SectionHeader(
                      title: '我的旅程',
                      actionLabel: '邀請碼加入',
                      onPressed: _tripStore.isLoading ? null : () => _showJoinTripSheet(context),
                    ),
                    const SizedBox(height: 12),
                    if (ownedTrips.isEmpty)
                      const _EmptySection(
                        title: '還沒有自己的旅程',
                        description: '按右下角的「新增旅程」後，會同步建立到 Supabase。',
                      )
                    else
                      for (final trip in ownedTrips) ...[
                        TripCard(
                          trip: trip,
                          onTap: () => context.go('/trips/${trip.id}'),
                          onActionSelected: (action) => _handleTripAction(context, trip, action),
                        ),
                        const SizedBox(height: 12),
                      ],
                    const SizedBox(height: 16),
                    const _SectionHeader(title: '分享給我的'),
                    const SizedBox(height: 12),
                    if (sharedTrips.isEmpty)
                      const _EmptySection(
                        title: '尚未加入任何共享旅程',
                        description: '輸入 6 碼邀請碼後，會把唯讀旅程加到這裡。',
                      )
                    else
                      for (final trip in sharedTrips) ...[
                        TripCard(
                          trip: trip,
                          onTap: () => context.go('/trips/${trip.id}'),
                          onActionSelected: (action) => _handleTripAction(context, trip, action),
                        ),
                        const SizedBox(height: 12),
                      ],
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _showTripEditorSheet(
    BuildContext context, {
    TripSummary? initialTrip,
  }) async {
    final trip = await showModalBottomSheet<TripSummary>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TripEditorSheet(initialTrip: initialTrip),
    );

    if (!context.mounted || trip == null) {
      return;
    }

    context.go('/trips/${trip.id}');
  }

  Future<void> _handleTripAction(
    BuildContext context,
    TripSummary trip,
    TripCardAction action,
  ) async {
    switch (action) {
      case TripCardAction.editTrip:
        return _showTripEditorSheet(context, initialTrip: trip);
      case TripCardAction.deleteTrip:
        return _confirmDeleteTrip(context, trip);
      case TripCardAction.leaveTrip:
        return _confirmLeaveTrip(context, trip);
    }
  }

  Future<void> _confirmDeleteTrip(BuildContext context, TripSummary trip) async {
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
                style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                child: const Text('確認刪除'),
              ),
            ],
          ),
        ) ??
        false;

    if (!context.mounted || !shouldDelete) {
      return;
    }

    try {
      final deleted = await _tripStore.deleteTrip(trip.id);
      if (!context.mounted) {
        return;
      }
      _showMessage(context, deleted ? '已刪除旅程：${trip.title}' : '刪除旅程失敗');
    } on TripStoreException catch (error) {
      if (context.mounted) {
        _showMessage(context, error.message);
      }
    }
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

    try {
      final left = await _tripStore.leaveSharedTrip(trip.id);
      if (!context.mounted) {
        return;
      }
      _showMessage(context, left ? '已退出旅程：${trip.title}' : '退出旅程失敗');
    } on TripStoreException catch (error) {
      if (context.mounted) {
        _showMessage(context, error.message);
      }
    }
  }

  void _showJoinTripSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _JoinTripSheet(),
    );
  }

  void _showMessage(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.isRemoteActive,
    required this.isLoading,
    required this.message,
  });

  final bool isRemoteActive;
  final bool isLoading;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isRemoteActive ? const Color(0xFFE8F7EE) : const Color(0xFFFFF3E2);
    final foregroundColor = isRemoteActive ? const Color(0xFF1E7A4E) : const Color(0xFF8A5A00);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(
            isRemoteActive ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
            color: foregroundColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message ?? (isRemoteActive ? 'Supabase 已連線。' : '目前使用示範資料。'),
              style: TextStyle(
                color: foregroundColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (isLoading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.ownedTrips,
    required this.isRemoteActive,
  });

  final List<TripSummary> ownedTrips;
  final bool isRemoteActive;

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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'Owner 可編輯 · Guest 唯讀',
              style: TextStyle(
                color: AppColors.accentStrong,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text('旅程總覽', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _SummaryCard(value: '${ownedTrips.length}', label: '我的旅程'),
              _SummaryCard(value: '$totalStops', label: '已整理停靠點'),
              _SummaryCard(value: isRemoteActive ? 'Supabase' : '示範資料', label: '同步平台'),
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
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        if (actionLabel != null && onPressed != null)
          TextButton(onPressed: onPressed, child: Text(actionLabel!)),
      ],
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(description),
        ],
      ),
    );
  }
}

class _JoinTripSheet extends StatefulWidget {
  const _JoinTripSheet();

  @override
  State<_JoinTripSheet> createState() => _JoinTripSheetState();
}

class _JoinTripSheetState extends State<_JoinTripSheet> {
  final _controller = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
            const Text('輸入 6 碼邀請碼後，App 會在 Supabase 建立唯讀 shared_access。'),
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              enabled: !_isSubmitting,
              maxLength: 6,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: '輸入 6 碼邀請碼',
                hintText: '例如 A1B2C3',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('加入唯讀旅程'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);

    try {
      final joined = await TripStore.instance.joinTrip(_controller.text);
      if (!mounted) {
        return;
      }

      if (joined) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已加入共享旅程。')));
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('請確認邀請碼是否正確，且目前已連上 Supabase。')),
        );
      }
    } on TripStoreException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}
