import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:trip_planner_app/core/theme/app_theme.dart';
import 'package:trip_planner_app/features/trip_detail/presentation/widgets/day_tab.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';
import 'package:trip_planner_app/features/trips/data/trip_store.dart';

class TripDetailScreen extends StatefulWidget {
  const TripDetailScreen({super.key, required this.tripId});

  final String tripId;

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen>
  with TickerProviderStateMixin {
  static const double _tabBarHeaderHeight = 56;

  late TabController _tabController;
  final TripStore _tripStore = TripStore.instance;
  bool _hideFloatingActionButton = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    _tabController.addListener(_handleTabChanged);
    _tripStore.ensureLoaded();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _syncTabController(int nextLength) {
    if (_tabController.length == nextLength) {
      return;
    }

    final previousController = _tabController;
    final nextIndex = previousController.index.clamp(0, nextLength - 1);
    previousController.removeListener(_handleTabChanged);
    _tabController = TabController(
      length: nextLength,
      vsync: this,
      initialIndex: nextIndex,
    );
    _tabController.addListener(_handleTabChanged);
    previousController.dispose();
    _hideFloatingActionButton = false;
  }

  void _handleTabChanged() {
    if (!mounted || _tabController.indexIsChanging) {
      return;
    }

    setState(() {
      _hideFloatingActionButton = false;
    });
  }

  void _handleBottomAddButtonVisibilityChanged(bool isVisible) {
    if (_hideFloatingActionButton == isVisible || !mounted) {
      return;
    }

    setState(() {
      _hideFloatingActionButton = isVisible;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _tripStore,
      builder: (context, _) {
        final trip = _tripStore.findById(widget.tripId);
        if (_tripStore.isLoading && trip == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (trip == null) {
          return const Scaffold(body: Center(child: Text('找不到旅程')));
        }

        _syncTabController(trip.days.isEmpty ? 1 : trip.days.length);

        final isReadOnly = trip.role == TripRole.guest;

        return Scaffold(
          resizeToAvoidBottomInset: false,
          floatingActionButton: isReadOnly ||
                  trip.days.isEmpty ||
                  _hideFloatingActionButton
              ? null
              : FloatingActionButton.extended(
                  onPressed: () {
                    final currentDay = trip.days[
                      _tabController.index.clamp(0, trip.days.length - 1)
                    ];
                    context.push(
                      '/trips/${trip.id}/days/${currentDay.id}/stops/new',
                    );
                  },
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('新增地點'),
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
              child: NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) => [
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        _TripHeader(
                          title: trip.title,
                          isReadOnly: isReadOnly,
                          onBackPressed: () => context.go('/trips'),
                          onActionSelected: (action) =>
                              _handleAction(context, trip, action),
                        ),
                        _TripSummaryCard(
                          trip: trip,
                          isReadOnly: isReadOnly,
                          onCopyShareCode: () => _copyShareCode(context, trip),
                          onOpenNavigation: () =>
                              context.go('/trips/${trip.id}/navigation'),
                        ),
                      ],
                    ),
                  ),
                  if (trip.days.isNotEmpty)
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _TripDayTabBarHeaderDelegate(
                        height: _tabBarHeaderHeight,
                        child: Container(
                          color: const Color(0xFFEAF2F9),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          alignment: Alignment.centerLeft,
                          child: TabBar(
                            controller: _tabController,
                            isScrollable: true,
                            tabs: [
                              for (final day in trip.days)
                                Tab(text: '${day.label} · ${day.dateLabel}'),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
                body: trip.days.isEmpty
                    ? const Center(child: Text('尚未建立行程日'))
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          for (var index = 0;
                              index < trip.days.length;
                              index += 1)
                            DayTab(
                              tripId: trip.id,
                              day: trip.days[index],
                              isReadOnly: isReadOnly,
                              isActive: index == _tabController.index,
                              onAddButtonVisibilityChanged:
                                  _handleBottomAddButtonVisibilityChanged,
                            ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    TripSummary trip,
    _TripDetailAction action,
  ) async {
    switch (action) {
      case _TripDetailAction.deleteTrip:
        await _deleteTrip(context, trip);
        return;
      case _TripDetailAction.leaveTrip:
        await _leaveTrip(context, trip);
        return;
    }
  }

  Future<void> _deleteTrip(BuildContext context, TripSummary trip) async {
    final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('刪除旅程？'),
            content: Text('此動作無法復原，${trip.title} 的所有行程與提醒都會刪除。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                ),
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

    if (deleted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已刪除旅程：${trip.title}')));
      context.go('/trips');
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('刪除旅程失敗')));
  }

  Future<void> _leaveTrip(BuildContext context, TripSummary trip) async {
    final shouldLeave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('退出分享旅程？'),
            content: Text('退出後，${trip.title} 將從分享列表移除，相關提醒也會清掉。'),
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

    if (left) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已退出旅程：${trip.title}')));
      context.go('/trips');
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('退出旅程失敗')));
  }

  Future<void> _copyShareCode(BuildContext context, TripSummary trip) async {
    final shareCode = trip.shareCode;
    if (shareCode == null) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: shareCode));
    if (!context.mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text('已複製 ${trip.title} 的分享碼：$shareCode')),
    );
  }
}

enum _TripDetailAction { deleteTrip, leaveTrip }

class _TripHeader extends StatelessWidget {
  const _TripHeader({
    required this.title,
    required this.isReadOnly,
    required this.onBackPressed,
    required this.onActionSelected,
  });

  final String title;
  final bool isReadOnly;
  final VoidCallback onBackPressed;
  final ValueChanged<_TripDetailAction> onActionSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onBackPressed,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          if (isReadOnly)
            PopupMenuButton<_TripDetailAction>(
              tooltip: '旅程操作',
              onSelected: onActionSelected,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _TripDetailAction.leaveTrip,
                  child: Text('退出旅程'),
                ),
              ],
              child: const Chip(label: Text('唯讀')),
            )
          else
            PopupMenuButton<_TripDetailAction>(
              tooltip: '旅程操作',
              onSelected: onActionSelected,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _TripDetailAction.deleteTrip,
                  child: Text('刪除旅程'),
                ),
              ],
              icon: const Icon(Icons.more_vert_rounded),
            ),
        ],
      ),
    );
  }
}

class _TripSummaryCard extends StatelessWidget {
  const _TripSummaryCard({
    required this.trip,
    required this.isReadOnly,
    required this.onCopyShareCode,
    required this.onOpenNavigation,
  });

  final TripSummary trip;
  final bool isReadOnly;
  final VoidCallback onCopyShareCode;
  final VoidCallback onOpenNavigation;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFAFDFF), Color(0xFFE2EDF8)],
          ),
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
              child: Text(
                trip.dateRange,
                style: const TextStyle(
                  color: AppColors.accentStrong,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('旅程摘要', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(
              isReadOnly
                  ? '受邀唯讀模式，可接收時程提醒與地點提醒。'
                  : 'Owner 模式，可直接新增、編輯、刪除與排序行程地點。',
            ),
            if (!isReadOnly && trip.shareCode != null) ...[
              const SizedBox(height: 16),
              _ShareCodePanel(
                shareCode: trip.shareCode!,
                onCopy: onCopyShareCode,
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MiniStat(value: '${trip.days.length}', label: '天數'),
                _MiniStat(value: '${trip.stopCount}', label: '停靠點'),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onOpenNavigation,
              icon: const Icon(Icons.navigation_outlined),
              label: const Text('開啟導航模式'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripDayTabBarHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _TripDayTabBarHeaderDelegate({
    required this.height,
    required this.child,
  });

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _TripDayTabBarHeaderDelegate oldDelegate) {
    return oldDelegate.height != height || oldDelegate.child != child;
  }
}

class _ShareCodePanel extends StatelessWidget {
  const _ShareCodePanel({required this.shareCode, required this.onCopy});

  final String shareCode;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(22),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackVertically = constraints.maxWidth < 520;

          if (stackVertically) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ShareCodeContent(shareCode: shareCode),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('複製'),
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: _ShareCodeContent(shareCode: shareCode)),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded),
                label: const Text('複製'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ShareCodeContent extends StatelessWidget {
  const _ShareCodeContent({required this.shareCode});

  final String shareCode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '分享碼',
          style: TextStyle(
            color: AppColors.accentStrong,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          shareCode,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
            color: AppColors.text,
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.76),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(label),
          ],
        ),
      ),
    );
  }
}
