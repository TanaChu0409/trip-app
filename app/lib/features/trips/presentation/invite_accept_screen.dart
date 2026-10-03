import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:trip_planner_app/core/router/invite_link_controller.dart';
import 'package:trip_planner_app/core/supabase/supabase_error_formatter.dart';
import 'package:trip_planner_app/features/trips/data/trip_invite_link.dart';
import 'package:trip_planner_app/features/trips/data/trip_store.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';

final previewTripInviteProvider =
    Provider<Future<TripInviteLinkResult> Function(String)>(
        (ref) => TripStore.instance.previewInviteLink);
final acceptTripInviteProvider =
    Provider<Future<TripInviteLinkResult> Function(String)>(
        (ref) => TripStore.instance.acceptInviteLink);

class InviteAcceptScreen extends ConsumerStatefulWidget {
  const InviteAcceptScreen({super.key, required this.token});
  final String token;
  @override
  ConsumerState<InviteAcceptScreen> createState() => _InviteAcceptScreenState();
}

class _InviteAcceptScreenState extends ConsumerState<InviteAcceptScreen> {
  TripInviteLinkResult? _preview;
  String? _error;
  bool _busy = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant InviteAcceptScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.token != widget.token) _load();
  }

  Future<void> _load() async {
    final token = widget.token;
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
    });
    try {
      final result = await ref.read(previewTripInviteProvider)(token);
      if (mounted && widget.token == token) setState(() => _preview = result);
    } catch (error) {
      if (mounted && widget.token == token) {
        setState(() => _error = SupabaseErrorFormatter.userMessage(error));
      }
    } finally {
      if (mounted && widget.token == token) setState(() => _busy = false);
    }
  }

  Future<void> _exit([String? tripId]) async {
    await ref.read(inviteLinkControllerProvider).clear();
    if (mounted) context.go(tripId == null ? '/trips' : '/trips/$tripId');
  }

  Future<void> _accept() async {
    final token = widget.token;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(acceptTripInviteProvider)(token);
      if (!mounted || widget.token != token) return;
      if (result.status == TripInviteStatus.success ||
          result.status == TripInviteStatus.alreadyMember ||
          result.status == TripInviteStatus.owner) {
        if (result.tripId == null) {
          throw const FormatException('Missing trip id');
        }
        await _exit(result.tripId);
      } else {
        setState(() => _preview = result);
      }
    } catch (error) {
      if (mounted && widget.token == token) {
        setState(() => _error = SupabaseErrorFormatter.userMessage(error));
      }
    } finally {
      if (mounted && widget.token == token) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final usable = preview != null &&
        (preview.status == TripInviteStatus.success ||
            preview.status == TripInviteStatus.alreadyMember ||
            preview.status == TripInviteStatus.owner);
    return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && !_busy) _exit();
        },
        child: Scaffold(
            appBar: AppBar(
                title: const Text('行程邀請'),
                leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _busy ? null : () => _exit())),
            body: Center(
                child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (_busy) const CircularProgressIndicator(),
                      if (usable) ...[
                        Text(preview.title ?? '行程邀請',
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 12),
                        Text(preview.permission == TripPermission.editor
                            ? '加入權限：可編輯'
                            : '加入權限：唯讀'),
                        if (preview.status == TripInviteStatus.alreadyMember)
                          const Text('你已經是此行程的成員'),
                        if (preview.status == TripInviteStatus.owner)
                          const Text('你是此行程的擁有者'),
                        const SizedBox(height: 20),
                        FilledButton(
                            onPressed: _busy ? null : _accept,
                            child: Text(
                                preview.status == TripInviteStatus.success
                                    ? '確認加入'
                                    : '開啟行程')),
                      ] else if (preview != null)
                        Text(preview.status == TripInviteStatus.tripArchived
                            ? '此行程已封存，無法加入'
                            : '邀請連結已失效或已撤銷'),
                      if (_error != null) ...[
                        Text(_error!),
                        TextButton(
                            onPressed: _busy ? null : _load,
                            child: const Text('重試'))
                      ],
                      TextButton(
                          onPressed: _busy ? null : () => _exit(),
                          child: const Text('返回行程列表')),
                    ])))));
  }
}
