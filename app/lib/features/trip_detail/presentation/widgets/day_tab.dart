import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';
import 'package:trip_planner_app/features/trips/data/trip_store.dart';
import 'package:trip_planner_app/features/trip_detail/presentation/widgets/stop_card.dart';

class DayTab extends StatefulWidget {
  const DayTab({
    super.key,
    required this.tripId,
    required this.day,
    required this.tripColor,
    required this.isReadOnly,
    required this.isActive,
    required this.onAddButtonVisibilityChanged,
  });

  final String tripId;
  final TripDay day;
  final String? tripColor;
  final bool isReadOnly;
  final bool isActive;
  final ValueChanged<bool> onAddButtonVisibilityChanged;

  @override
  State<DayTab> createState() => _DayTabState();
}

class _DayTabState extends State<DayTab> {
  final GlobalKey _addButtonKey = GlobalKey();
  bool _hasQueuedVisibilityCheck = false;
  bool _lastReportedVisibility = false;
  Size _viewportSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _scheduleVisibilityCheck();
  }

  @override
  void didUpdateWidget(covariant DayTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive ||
        oldWidget.isReadOnly != widget.isReadOnly ||
        oldWidget.day.stops.length != widget.day.stops.length) {
      _scheduleVisibilityCheck();
    }
  }

  void _scheduleVisibilityCheck() {
    if (_hasQueuedVisibilityCheck) {
      return;
    }

    _hasQueuedVisibilityCheck = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hasQueuedVisibilityCheck = false;
      if (!mounted) {
        return;
      }

      _reportAddButtonVisibility();
    });
  }

  void _reportAddButtonVisibility() {
    final isVisible = widget.isActive &&
        !widget.isReadOnly &&
        _isWidgetVisible(_addButtonKey, _viewportSize);
    if (_lastReportedVisibility == isVisible) {
      return;
    }

    _lastReportedVisibility = isVisible;
    widget.onAddButtonVisibilityChanged(isVisible);
  }

  bool _isWidgetVisible(GlobalKey key, Size viewportSize) {
    final targetContext = key.currentContext;
    if (targetContext == null || viewportSize == Size.zero) {
      return false;
    }

    final renderObject = targetContext.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return false;
    }

    final topLeft = renderObject.localToGlobal(Offset.zero);
    final rect = topLeft & renderObject.size;

    return rect.bottom > 0 &&
        rect.right > 0 &&
        rect.top < viewportSize.height &&
        rect.left < viewportSize.width;
  }

  @override
  Widget build(BuildContext context) {
    _viewportSize = MediaQuery.sizeOf(context);
    _scheduleVisibilityCheck();

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        _scheduleVisibilityCheck();
        return false;
      },
      child: ReorderableListView(
        padding: EdgeInsets.fromLTRB(8, 16, 8, widget.isReadOnly ? 24 : 40),
        buildDefaultDragHandles: false,
        onReorder: widget.isReadOnly
            ? (_, __) {}
            : (oldIndex, newIndex) async {
                await TripStore.instance.reorderStops(
                  tripId: widget.tripId,
                  dayId: widget.day.id,
                  oldIndex: oldIndex,
                  newIndex: newIndex,
                );
                _scheduleVisibilityCheck();
              },
        footer: widget.isReadOnly
            ? null
            : Padding(
                key: ValueKey('add-stop-${widget.day.id}'),
                padding: const EdgeInsets.only(top: 4, bottom: 80),
                child: OutlinedButton.icon(
                  key: _addButtonKey,
                  onPressed: () => context.push(
                      '/trips/${widget.tripId}/days/${widget.day.id}/stops/new'),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('新增地點'),
                ),
              ),
        children: [
          for (var index = 0; index < widget.day.stops.length; index += 1)
            Padding(
              key: ValueKey(widget.day.stops[index].id ?? 'stop-$index'),
              padding: EdgeInsets.only(
                  bottom:
                      index == widget.day.stops.length - 1 && widget.isReadOnly
                          ? 0
                          : 14),
              child: _buildStopItem(context, widget.day.stops[index], index),
            ),
        ],
      ),
    );
  }

  Widget _buildStopItem(BuildContext context, StopItem stop, int index) {
    final card = StopCard(
      stop: stop,
      tripColor: widget.tripColor,
      isReadOnly: widget.isReadOnly,
      onTap: widget.isReadOnly || stop.id == null
          ? null
          : () => context.push(
              '/trips/${widget.tripId}/days/${widget.day.id}/stops/${stop.id}/edit'),
      trailing: widget.isReadOnly
          ? null
          : ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.drag_handle_rounded),
              ),
            ),
    );

    if (widget.isReadOnly || stop.id == null) {
      return card;
    }

    return Dismissible(
      key: ValueKey('dismiss-${stop.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _handleDelete(context, stop),
      background: Container(
        decoration: BoxDecoration(
          color: Colors.red.shade700,
          borderRadius: BorderRadius.circular(24),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      child: card,
    );
  }

  Future<bool> _handleDelete(BuildContext context, StopItem stop) async {
    final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('刪除地點？'),
            content: Text('確定刪除 ${stop.title}？此動作無法復原。'),
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

    if (!shouldDelete) {
      return false;
    }

    final deleted = await TripStore.instance.deleteStop(
      tripId: widget.tripId,
      dayId: widget.day.id,
      stopId: stop.id!,
    );
    if (!context.mounted) {
      return deleted;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(deleted ? '已刪除地點：${stop.title}' : '刪除地點失敗')),
    );
    return deleted;
  }
}
