import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'diagnostic_log.dart';

class DiagnosticButton extends StatelessWidget {
  const DiagnosticButton({super.key});
  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/diagnostics'),
          builder: (_) => const DiagnosticScreen(),
        )),
        icon: const Icon(Icons.receipt_long_outlined),
        label: const Text('操作紀錄'),
      );
}

class DiagnosticScreen extends StatefulWidget {
  const DiagnosticScreen({super.key, this.log});
  final DiagnosticLog? log;
  @override
  State<DiagnosticScreen> createState() => _DiagnosticScreenState();
}

class _DiagnosticScreenState extends State<DiagnosticScreen> {
  late final DiagnosticLog _log = widget.log ?? DiagnosticLog.instance;
  final _scroll = ScrollController();
  String _search = '';
  String? _kind;
  String? _outcome;
  bool _autoScroll = true;
  bool _scrollScheduled = false;

  @override
  void initState() {
    super.initState();
    _log.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (!_autoScroll || _scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (mounted && _autoScroll && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _log.removeListener(_changed);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已複製操作紀錄')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('無法複製，請選取詳情文字後手動複製。')),
        );
      }
    }
  }

  void _details(DiagnosticEntry entry) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/diagnostics/detail'),
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('紀錄詳情')),
        body: AnimatedBuilder(
            animation: _log,
            builder: (context, _) {
              if (!_log.entries.contains(entry)) {
                return const Center(child: Text('此紀錄已清除或淘汰'));
              }
              final text =
                  const JsonEncoder.withIndent('  ').convert(entry.toJson());
              return SafeArea(
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                Text(entry.label,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                    onPressed: () => _copy(_log.export(entry)),
                    icon: const Icon(Icons.copy),
                    label: const Text('複製單筆')),
                const SizedBox(height: 12),
                SelectableText(text,
                    style: const TextStyle(fontFamily: 'monospace')),
              ]));
            }),
      ),
    ));
  }

  static const kinds = {
    'operation': '操作',
    'request': 'Request',
    'response': 'Response',
    'error': '錯誤',
    'route': '頁面',
    'realtime': '即時同步',
  };
  static const outcomes = {
    'pending': '進行中',
    'success': '成功',
    'failure': '失敗',
    'cancelled': '已取消',
  };

  @override
  Widget build(BuildContext context) {
    final entries = _log.entries
        .where((e) =>
            (_kind == null || e.kind == _kind) &&
            (_outcome == null || e.outcome == _outcome) &&
            e.json.toLowerCase().contains(_search.toLowerCase()))
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    return Scaffold(
      appBar: AppBar(title: const Text('操作紀錄')),
      body: SafeArea(
          child: Column(children: [
        Expanded(
            flex: 0,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.5),
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    const Text('僅保留本次執行的紀錄，重新啟動或重新整理後清除。內容已遮蔽；'
                        '外部登入頁、地圖 App、圖片下載與底層即時連線封包不在 HTTP 紀錄範圍內。'),
                    SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('記錄操作'),
                        value: _log.enabled,
                        onChanged: (value) => _log.enabled = value),
                    SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('自動捲動至最新紀錄'),
                        value: _autoScroll,
                        onChanged: (value) =>
                            setState(() => _autoScroll = value)),
                    TextField(
                        decoration: const InputDecoration(
                            labelText: '搜尋紀錄', prefixIcon: Icon(Icons.search)),
                        onChanged: (value) => setState(() => _search = value)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 12, runSpacing: 8, children: [
                      DropdownButton<String>(
                          value: _kind ?? '',
                          items: [
                            const DropdownMenuItem(
                                value: '', child: Text('所有類型')),
                            ...kinds.entries.map((e) => DropdownMenuItem(
                                value: e.key, child: Text(e.value)))
                          ],
                          onChanged: (v) =>
                              setState(() => _kind = v == '' ? null : v)),
                      DropdownButton<String>(
                          value: _outcome ?? '',
                          items: [
                            const DropdownMenuItem(
                                value: '', child: Text('所有結果')),
                            ...outcomes.entries.map((e) => DropdownMenuItem(
                                value: e.key, child: Text(e.value)))
                          ],
                          onChanged: (v) =>
                              setState(() => _outcome = v == '' ? null : v)),
                      OutlinedButton.icon(
                          onPressed: () => _copy(_log.export()),
                          icon: const Icon(Icons.copy),
                          label: const Text('複製全部 JSON')),
                      TextButton(
                          onPressed: _log.clear, child: const Text('清除紀錄')),
                    ]),
                    Text('${entries.length} 筆 · 已淘汰 ${_log.droppedEntries} 筆 · '
                        '${(_log.retainedBytes / 1024).toStringAsFixed(1)} KiB'),
                  ])),
            )),
        const Divider(height: 1),
        Expanded(
            child: entries.isEmpty
                ? const Center(child: Text('沒有符合條件的紀錄'))
                : ListView.builder(
                    controller: _scroll,
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final e = entries[index];
                      final value = e.toJson();
                      final details = value['details'] as Map<String, dynamic>;
                      final time =
                          DateTime.parse(e.time).toLocal().toIso8601String();
                      return ListTile(
                          isThreeLine: true,
                          leading: Icon(e.outcome == 'failure'
                              ? Icons.error_outline
                              : Icons.receipt_outlined),
                          title: Text(e.label),
                          subtitle: Text(
                              '$time · ${kinds[e.kind]} · ${outcomes[e.outcome]}\n'
                              '${value['operationId'] ?? ''} ${details['requestId'] ?? ''} '
                              '${details['method'] ?? ''} ${details['path'] ?? ''}',
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis),
                          onTap: () => _details(e));
                    })),
      ])),
    );
  }
}
