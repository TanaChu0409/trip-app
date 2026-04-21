import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:trip_planner_app/core/supabase/supabase_error_formatter.dart';
import 'package:trip_planner_app/core/theme/app_theme.dart';
import 'package:trip_planner_app/features/trip_detail/presentation/widgets/day_tab.dart';
import 'package:trip_planner_app/features/trips/data/invite_member_result.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';
import 'package:trip_planner_app/features/trips/data/trip_store.dart';
import 'package:trip_planner_app/features/trips/presentation/widgets/trip_color_picker.dart';

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

  // Cached trip reference – rebuilt only when this specific trip changes.
  TripSummary? _currentTrip;
  bool _isStoreLoading = false;

  @override
  void initState() {
    super.initState();
    _currentTrip = _tripStore.findById(widget.tripId);
    _isStoreLoading = _tripStore.isLoading;
    final initialDayCount =
        _currentTrip == null || _currentTrip!.days.isEmpty
            ? 1
            : _currentTrip!.days.length;
    _tabController = TabController(length: initialDayCount, vsync: this);
    _tabController.addListener(_handleTabChanged);
    _tripStore.addListener(_handleStoreChanged);
    _tripStore.ensureLoaded();
  }

  @override
  void dispose() {
    _tripStore.removeListener(_handleStoreChanged);
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  /// Called on every TripStore notification.  Rebuilds only when the trip
  /// that belongs to this screen changes, avoiding unnecessary redraws caused
  /// by mutations to other trips in the store.
  void _handleStoreChanged() {
    if (!mounted) return;
    final newTrip = _tripStore.findById(widget.tripId);
    final newLoading = _tripStore.isLoading;
    if (identical(_currentTrip, newTrip) && _isStoreLoading == newLoading) {
      return;
    }
    setState(() {
      _currentTrip = newTrip;
      _isStoreLoading = newLoading;
      if (newTrip != null) {
        _syncTabController(newTrip.days.isEmpty ? 1 : newTrip.days.length);
      }
    });
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
    final trip = _currentTrip;
    if (_isStoreLoading && trip == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (trip == null) {
      return const Scaffold(body: Center(child: Text('找不到旅程')));
    }

    final isReadOnly = !trip.canEdit;
    final tripColor = colorFromHex(trip.color);
    final tripColorSoft = tintColor(tripColor, amount: 0.84);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      floatingActionButton: isReadOnly ||
              trip.days.isEmpty ||
              _hideFloatingActionButton
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                final currentDay = trip.days[
                    _tabController.index.clamp(0, trip.days.length - 1)];
                context.push(
                  '/trips/${trip.id}/days/${currentDay.id}/stops/new',
                );
              },
              backgroundColor: tripColor,
              foregroundColor: onAccentColor(tripColor),
              icon: const Icon(Icons.add_rounded),
              label: const Text('新增地點'),
            ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [tintColor(tripColor, amount: 0.94), tripColorSoft],
          ),
        ),
        child: SafeArea(
          child: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    _TripHeader(
                      trip: trip,
                      tripColor: tripColor,
                      onBackPressed: () => context.go('/trips'),
                      onActionSelected: (action) =>
                          _handleAction(context, trip, action),
                    ),
                    _TripSummaryCard(
                      trip: trip,
                      tripColor: tripColor,
                      onInviteMember: () => _showInviteMemberSheet(context, trip),
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
                      color: tintColor(tripColor, amount: 0.9),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.centerLeft,
                      child: TabBar(
                        controller: _tabController,
                        labelColor: shadeColor(tripColor, amount: 0.16),
                        unselectedLabelColor: AppColors.muted,
                        indicatorColor: tripColor,
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
                          tripColor: trip.color,
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
      case _TripDetailAction.changeColor:
        await _changeTripColor(context, trip);
        return;
      case _TripDetailAction.manageMembers:
        if (context.mounted) {
          context.push('/trips/${trip.id}/members');
        }
        return;
    }
  }

  Future<void> _changeTripColor(BuildContext context, TripSummary trip) async {
    String? selectedColor = trip.color;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '更改旅程顏色',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 20),
                  TripColorPicker(
                    selectedColor: selectedColor,
                    onColorChanged: (value) =>
                        setSheetState(() => selectedColor = value),
                    description: '選擇後立即套用至整個旅程。',
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('確認'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (!context.mounted) {
      return;
    }

    if (selectedColor == trip.color) {
      return;
    }

    final updated = await _tripStore.updateTripColor(trip.id, selectedColor);
    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(updated ? '已更新旅程顏色' : '更新顏色失敗'),
      ),
    );
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

  Future<void> _showInviteMemberSheet(
      BuildContext context, TripSummary trip) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _InviteMemberSheet(tripId: trip.id),
    );
  }
}

enum _TripDetailAction { deleteTrip, leaveTrip, changeColor, manageMembers }

class _TripHeader extends StatelessWidget {
  const _TripHeader({
    required this.trip,
    required this.tripColor,
    required this.onBackPressed,
    required this.onActionSelected,
  });

  final TripSummary trip;
  final Color tripColor;
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
              trip.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: shadeColor(tripColor, amount: 0.2),
                  ),
            ),
          ),
          _buildMenu(context),
        ],
      ),
    );
  }

  Widget _buildMenu(BuildContext context) {
    // Owner: can manage members, change color, delete trip
    if (trip.role == TripRole.owner) {
      return PopupMenuButton<_TripDetailAction>(
        tooltip: '旅程操作',
        onSelected: onActionSelected,
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: _TripDetailAction.manageMembers,
            child: Text('成員管理'),
          ),
          PopupMenuItem(
            value: _TripDetailAction.changeColor,
            child: Text('更改顏色'),
          ),
          PopupMenuItem(
            value: _TripDetailAction.deleteTrip,
            child: Text('刪除旅程'),
          ),
        ],
        icon: const Icon(Icons.more_vert_rounded),
      );
    }

    // Editor guest: can change color and leave
    if (trip.permission == TripPermission.editor) {
      return PopupMenuButton<_TripDetailAction>(
        tooltip: '旅程操作',
        onSelected: onActionSelected,
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: _TripDetailAction.changeColor,
            child: Text('更改顏色'),
          ),
          PopupMenuItem(
            value: _TripDetailAction.leaveTrip,
            child: Text('退出旅程'),
          ),
        ],
        icon: const Icon(Icons.more_vert_rounded),
      );
    }

    // Viewer guest: can only leave
    return PopupMenuButton<_TripDetailAction>(
      tooltip: '旅程操作',
      onSelected: onActionSelected,
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _TripDetailAction.leaveTrip,
          child: Text('退出旅程'),
        ),
      ],
      child: const Chip(label: Text('唯讀')),
    );
  }
}

class _TripSummaryCard extends StatelessWidget {
  const _TripSummaryCard({
    required this.trip,
    required this.tripColor,
    required this.onInviteMember,
    required this.onOpenNavigation,
  });

  final TripSummary trip;
  final Color tripColor;
  final VoidCallback onInviteMember;
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
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              tintColor(tripColor, amount: 0.97),
              tintColor(tripColor, amount: 0.84),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: tintColor(tripColor, amount: 0.9),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                trip.dateRange,
                style: TextStyle(
                  color: shadeColor(tripColor, amount: 0.2),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('旅程摘要', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(
              switch (trip.role) {
                TripRole.owner =>
                  'Owner 模式，可直接新增、編輯、刪除與排序行程地點。',
                TripRole.guest =>
                  trip.permission == TripPermission.editor
                      ? '協作模式，可新增、編輯、刪除行程地點與更改顏色。'
                      : '受邀唯讀模式，可接收時程提醒與地點提醒。',
              },
            ),
            if (trip.role == TripRole.owner) ...[  
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onInviteMember,
                icon: const Icon(Icons.person_add_rounded),
                label: const Text('邀請成員'),
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

class _InviteMemberSheet extends StatefulWidget {
  const _InviteMemberSheet({required this.tripId});

  final String tripId;

  @override
  State<_InviteMemberSheet> createState() => _InviteMemberSheetState();
}

class _InviteMemberSheetState extends State<_InviteMemberSheet> {
  final TextEditingController _emailController = TextEditingController();
  TripPermission _selectedPermission = TripPermission.editor;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
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
            Text('邀請成員', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('輸入對方的 Email 地址邀請加入行程。'),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 16, color: Colors.orange.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '提醒：對方須先登入本應用程式以建立帳號',
                    style: TextStyle(
                        fontSize: 13, color: Colors.orange.shade800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: '對方的 Email',
                hintText: '例如 someone@example.com',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            Text('權限', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<TripPermission>(
              segments: const [
                ButtonSegment(
                  value: TripPermission.editor,
                  label: Text('可編輯'),
                  icon: Icon(Icons.edit_outlined),
                ),
                ButtonSegment(
                  value: TripPermission.viewer,
                  label: Text('僅限查看'),
                  icon: Icon(Icons.visibility_outlined),
                ),
              ],
              selected: {_selectedPermission},
              onSelectionChanged: (selection) {
                setState(() => _selectedPermission = selection.first);
              },
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              style:
                  FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              child: Text(_isSubmitting ? '邀請中...' : '傳送邀請'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final messenger = ScaffoldMessenger.of(context);

    if (email.isEmpty) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('請輸入對方的 Email')));
      return;
    }
    if (!email.contains('@')) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('請輸入有效的 Email 格式')));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final result = await TripStore.instance
          .inviteMemberByEmail(widget.tripId, email, _selectedPermission);
      if (!mounted) return;

      switch (result.status) {
        case InviteMemberStatus.success:
          Navigator.of(context).pop();
          messenger.hideCurrentSnackBar();
          messenger
              .showSnackBar(SnackBar(content: Text('已成功邀請 $email 加入行程')));
          return;
        case InviteMemberStatus.userNotFound:
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(const SnackBar(
            content: Text('找不到此帳號，請確認對方已登入過本應用程式'),
          ));
          return;
        case InviteMemberStatus.alreadyMember:
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
              const SnackBar(content: Text('這位成員已在行程中')));
          return;
        case InviteMemberStatus.cannotInviteSelf:
          messenger.hideCurrentSnackBar();
          messenger
              .showSnackBar(const SnackBar(content: Text('無法邀請自己')));
          return;
        case InviteMemberStatus.notOwner:
        case InviteMemberStatus.invalidPermission:
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
              const SnackBar(content: Text('邀請失敗，請稍後再試')));
          return;
      }
    } catch (error) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(SupabaseErrorFormatter.userMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
