import 'package:flutter/material.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_member.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';
import 'package:trip_planner_app/features/trips/data/trip_store.dart';

class MemberManagementScreen extends StatefulWidget {
  const MemberManagementScreen({super.key, required this.tripId});

  final String tripId;

  @override
  State<MemberManagementScreen> createState() => _MemberManagementScreenState();
}

class _MemberManagementScreenState extends State<MemberManagementScreen> {
  final TripStore _store = TripStore.instance;
  List<TripMember>? _members;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final members = await _store.fetchTripMembers(widget.tripId);
      if (mounted) {
        setState(() {
          _members = members;
          _isLoading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = '載入成員失敗，請稍後再試。';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _changePermission(TripMember member, TripPermission permission) async {
    try {
      await _store.updateMemberPermission(
        widget.tripId,
        member.userId,
        permission,
      );
      if (mounted) {
        setState(() {
          _members = _store.cachedMembers(widget.tripId);
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('變更權限失敗，請稍後再試。')),
        );
      }
    }
  }

  Future<void> _removeMember(TripMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除成員'),
        content: Text('確定要將「${member.displayName}」從行程中移除嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _store.removeMember(widget.tripId, member.userId);
      if (mounted) {
        setState(() {
          _members = _store.cachedMembers(widget.tripId);
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('移除成員失敗，請稍後再試。')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('成員管理'),
        actions: [
          IconButton(
            onPressed: _loadMembers,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '重新整理',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMessage!),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _loadMembers,
              child: const Text('重試'),
            ),
          ],
        ),
      );
    }

    final members = _members ?? const [];

    if (members.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.group_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text('尚無協作成員', style: TextStyle(color: Colors.grey)),
            SizedBox(height: 4),
            Text(
              '分享邀請碼後，加入的使用者會出現在此。',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: members.length,
      separatorBuilder: (_, __) => const Divider(indent: 72, endIndent: 16),
      itemBuilder: (context, index) {
        final member = members[index];
        return _MemberTile(
          member: member,
          onPermissionChanged: (permission) =>
              _changePermission(member, permission),
          onRemove: () => _removeMember(member),
        );
      },
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.onPermissionChanged,
    required this.onRemove,
  });

  final TripMember member;
  final ValueChanged<TripPermission> onPermissionChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = member.displayName.isNotEmpty
        ? member.displayName[0].toUpperCase()
        : '?';

    return ListTile(
      leading: CircleAvatar(
        backgroundImage: member.avatarUrl != null
            ? NetworkImage(member.avatarUrl!)
            : null,
        child: member.avatarUrl == null ? Text(initial) : null,
      ),
      title: Text(
        member.displayName,
        style: theme.textTheme.bodyLarge
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: member.email != null
          ? Text(
              member.email!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.grey),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<TripPermission>(
            segments: const [
              ButtonSegment(
                value: TripPermission.editor,
                label: Text('可編輯'),
              ),
              ButtonSegment(
                value: TripPermission.viewer,
                label: Text('唯讀'),
              ),
            ],
            selected: {member.permission},
            onSelectionChanged: (values) {
              if (values.isNotEmpty) {
                onPermissionChanged(values.first);
              }
            },
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.person_remove_outlined),
            tooltip: '移除成員',
            color: theme.colorScheme.error,
          ),
        ],
      ),
      isThreeLine: member.email != null,
    );
  }
}
