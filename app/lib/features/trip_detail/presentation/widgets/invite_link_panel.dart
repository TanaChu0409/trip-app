import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trip_planner_app/core/router/invite_link_controller.dart';
import 'package:trip_planner_app/core/supabase/supabase_error_formatter.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';
import 'package:trip_planner_app/features/trips/data/trip_invite_link.dart';
import 'package:trip_planner_app/features/trips/data/trip_store.dart';

final inviteBaseUrlProvider =
    Provider<String>((ref) => InviteLinkController.baseUrl);
final getTripInviteLinkProvider =
    Provider<Future<TripInviteLinkResult> Function(String)>(
        (ref) => TripStore.instance.getInviteLink);
final createTripInviteLinkProvider =
    Provider<Future<TripInviteLinkResult> Function(String, TripPermission)>(
        (ref) => TripStore.instance.createInviteLink);
final revokeTripInviteLinkProvider =
    Provider<Future<TripInviteLinkResult> Function(String)>(
        (ref) => TripStore.instance.revokeInviteLink);

class InviteLinkPanel extends ConsumerStatefulWidget {
  const InviteLinkPanel({super.key, required this.tripId});
  final String tripId;
  @override
  ConsumerState<InviteLinkPanel> createState() => _InviteLinkPanelState();
}

class _InviteLinkPanelState extends ConsumerState<InviteLinkPanel> {
  bool _busy = true;
  bool _active = false;
  bool _uncertain = false;
  String? _url;
  String? _error;
  bool _loaded = false;
  TripPermission _permission = TripPermission.viewer;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _check(TripInviteLinkResult result) {
    if (result.status != TripInviteStatus.success) {
      throw StateError(result.status == TripInviteStatus.tripArchived
          ? '封存旅程無法產生邀請連結'
          : '只有旅程擁有者可以管理邀請連結');
    }
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      InviteLinkController.parseBaseUrl(ref.read(inviteBaseUrlProvider));
      final result = await ref.read(getTripInviteLinkProvider)(widget.tripId);
      _check(result);
      if (mounted) {
        setState(() {
          _active = result.active;
          _uncertain = false;
          _permission = result.permission ?? TripPermission.viewer;
          _loaded = true;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = SupabaseErrorFormatter.userMessage(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _change({bool revoke = false}) async {
    if (_active) {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: Text(revoke ? '撤銷邀請連結？' : '重設邀請連結？'),
                  content: const Text('舊連結將立即失效，已加入的成員不受影響。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('確認'))
                  ]));
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
      // A failed response does not imply that the server rolled back.
      _url = null;
    });
    try {
      final result = revoke
          ? await ref.read(revokeTripInviteLinkProvider)(widget.tripId)
          : await ref.read(createTripInviteLinkProvider)(
              widget.tripId, _permission);
      _check(result);
      final url = revoke
          ? null
          : InviteLinkController.buildUrl(result.token!,
              base: ref.read(inviteBaseUrlProvider));
      if (mounted) {
        setState(() {
          _url = url;
          _active = !revoke;
          _uncertain = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = SupabaseErrorFormatter.userMessage(error);
          _uncertain = true;
          _active = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 16),
        const Text('持有連結的人可登入並確認加入。請只分享給信任的人。'),
        const SizedBox(height: 12),
        if (_busy) const LinearProgressIndicator(),
        if (_loaded) ...[
          Text(_uncertain
              ? '無法確認連結狀態，請重設取得新連結或重新撤銷。'
              : _active
                  ? '目前有有效的邀請連結'
                  : '尚無有效邀請連結'),
          const SizedBox(height: 12),
          SegmentedButton<TripPermission>(
              segments: const [
                ButtonSegment(value: TripPermission.editor, label: Text('可編輯')),
                ButtonSegment(value: TripPermission.viewer, label: Text('唯讀'))
              ],
              selected: {
                _permission
              },
              onSelectionChanged: _busy
                  ? null
                  : (values) => setState(() => _permission = values.first)),
          const SizedBox(height: 12),
          if (_url != null) ...[
            SelectableText(_url!),
            TextButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await Clipboard.setData(ClipboardData(text: _url!));
                          if (mounted) {
                            messenger.showSnackBar(
                                const SnackBar(content: Text('已複製邀請連結')));
                          }
                        } catch (_) {
                          if (mounted) {
                            messenger.showSnackBar(const SnackBar(
                                content: Text('無法複製，請長按連結手動複製')));
                          }
                        }
                      },
                icon: const Icon(Icons.copy),
                label: const Text('複製連結')),
          ],
          const Text('完整連結只會在產生當下顯示；關閉後需重設才能再次取得。'),
          const SizedBox(height: 12),
          Wrap(spacing: 12, children: [
            FilledButton(
                onPressed: _busy ? null : () => _change(),
                child: Text(_active ? '重設連結並套用權限' : '產生邀請連結')),
            if (_active)
              TextButton(
                  onPressed: _busy ? null : () => _change(revoke: true),
                  child: const Text('撤銷連結')),
          ]),
        ],
        if (_error != null) ...[
          Text(_error!),
          if (!_loaded)
            TextButton(onPressed: _busy ? null : _load, child: const Text('重試'))
        ],
      ]);
}
