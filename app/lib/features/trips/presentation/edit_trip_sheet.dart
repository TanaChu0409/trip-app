import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trip_planner_app/core/supabase/supabase_error_formatter.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';
import 'package:trip_planner_app/features/trips/data/trip_store.dart';
import 'package:trip_planner_app/features/trips/presentation/widgets/trip_color_picker.dart';

class EditTripSheet extends StatefulWidget {
  const EditTripSheet({super.key, required this.trip, required this.store});
  final TripSummary trip;
  final TripStore store;
  @override
  State<EditTripSheet> createState() => _EditTripSheetState();
}

class _EditTripSheetState extends State<EditTripSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late DateTime _start;
  late DateTime _end;
  String? _color;
  final _names = <String, String>{};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.trip.title);
    _start = widget.trip.resolvedStartDate!;
    _end = widget.trip.resolvedEndDate!;
    _color = widget.trip.color;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  String _date(DateTime d) => '${d.year}/${d.month}/${d.day}';

  Future<void> _pick(bool start) async {
    final value = start ? _start : _end;
    final picked = await showDatePicker(
        context: context,
        initialDate: value,
        firstDate: DateTime(value.year < 2025 ? value.year : 2025),
        lastDate: DateTime(value.year + 100, 12, 31));
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        final duration = DateTime.utc(_end.year, _end.month, _end.day)
            .difference(DateTime.utc(_start.year, _start.month, _start.day))
            .inDays;
        _start = picked;
        _end = DateTime(picked.year, picked.month, picked.day + duration);
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    if (_end.isBefore(_start)) {
      setState(() => _error = '結束日期不可早於開始日期');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final refreshed = await widget.store.updateTripDetails(widget.trip.id,
          title: _title.text.trim(),
          startDate: _start,
          endDate: _end,
          color: _color,
          colorNames: _names);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(refreshed ? '旅程已更新' : '已儲存，請重新整理')));
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is PostgrestException &&
                error.message == 'trip_days_have_stops'
            ? '第 ${error.details} 天仍有地點，請先移動或移除後再縮短旅程。'
            : error is StateError && error.message.toString().contains('權限')
                ? error.message.toString()
                : SupabaseErrorFormatter.userMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
          child: Form(
              key: _form,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('編輯旅程', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    AbsorbPointer(
                        absorbing: _saving,
                        child: Column(children: [
                          TextFormField(
                              controller: _title,
                              decoration:
                                  const InputDecoration(labelText: '旅程名稱'),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? '請輸入旅程名稱'
                                  : null),
                          ListTile(
                              title: const Text('開始日期'),
                              subtitle: Text(_date(_start)),
                              onTap: () => _pick(true)),
                          ListTile(
                              title: const Text('結束日期'),
                              subtitle: Text(_date(_end)),
                              onTap: () => _pick(false)),
                          const Text('修改開始日期會依第幾天平移既有行程；縮短旅程前，請先移動或移除尾端日期的地點。'),
                          const SizedBox(height: 16),
                          TripColorPicker(
                              selectedColor: _color,
                              savedCustomColors: widget.trip.customStopColors,
                              customColorNames: {
                                ...widget.trip.customColorNames,
                                ..._names
                              },
                              onColorChanged: (v) => setState(() => _color = v),
                              onColorNamed: (hex, name) => setState(() {
                                    if (widget.trip.customColorNames[hex] ==
                                        name) {
                                      _names.remove(hex);
                                    } else {
                                      _names[hex] = name;
                                    }
                                  })),
                        ])),
                    if (_error != null)
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    const SizedBox(height: 16),
                    FilledButton(
                        onPressed: _saving ? null : _save,
                        child: Text(_saving ? '儲存中…' : '儲存')),
                    TextButton(
                        onPressed:
                            _saving ? null : () => Navigator.of(context).pop(),
                        child: const Text('取消')),
                  ])),
        ),
      );
}
