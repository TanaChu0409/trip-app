import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner_app/features/trips/presentation/widgets/trip_color_picker.dart';

void main() {
  Widget buildPicker({
    String? selectedColor,
    List<String> savedColors = const [],
    Map<String, String> names = const {},
    void Function(String, String)? onNamed,
    ValueChanged<String?>? onChanged,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: TripColorPicker(
          selectedColor: selectedColor,
          savedCustomColors: savedColors,
          customColorNames: names,
          onColorNamed: onNamed,
          onColorChanged: onChanged ?? (_) {},
        ),
      ),
    );
  }

  final nameField = find.byKey(const ValueKey('custom-color-name'));

  testWidgets('custom name is required, trimmed and returned with the colour',
      (tester) async {
    String? hex;
    String? name;
    await tester.pumpWidget(buildPicker(
      selectedColor: '#123456',
      onNamed: (color, label) {
        hex = color;
        name = label;
      },
    ));
    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();
    await tester.enterText(nameField, '   ');
    await tester.tap(find.text('確認'));
    await tester.pumpAndSettle();
    expect(find.text('請輸入顏色名稱'), findsOneWidget);
    expect(name, isNull);
    await tester.enterText(nameField, '  海洋藍  ');
    await tester.tap(find.text('確認'));
    await tester.pumpAndSettle();
    expect(hex, '#123456');
    expect(name, '海洋藍');
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel discards edits and names are limited to 20 characters',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(buildPicker(
      selectedColor: '#123456',
      onNamed: (_, __) => calls++,
    ));
    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pumpAndSettle();
    await tester.enterText(nameField, '一' * 21);
    expect(tester.widget<TextField>(nameField).controller!.text, '一' * 20);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rename preloads the name without selecting another colour',
      (tester) async {
    String? renamed;
    var selections = 0;
    await tester.pumpWidget(buildPicker(
      selectedColor: '#ABCDEF',
      savedColors: ['#123456'],
      names: {'#123456': '海洋藍'},
      onNamed: (_, name) => renamed = name,
      onChanged: (_) => selections++,
    ));
    await tester.tap(find.byTooltip('修改名稱'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(nameField).controller!.text, '海洋藍');
    await tester.enterText(nameField, '深海藍');
    await tester.tap(find.text('確認'));
    await tester.pumpAndSettle();
    expect(renamed, '深海藍');
    expect(selections, 0);
  });

  testWidgets('entering an existing hex preloads its shared name',
      (tester) async {
    await tester.pumpWidget(buildPicker(names: {'#123456': '海洋藍'}));
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '123456');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(nameField).controller!.text, '海洋藍');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'long labels fit narrow layouts and expose their hex in a tooltip',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final name = '海' * 20;
    await tester.pumpWidget(
        buildPicker(savedColors: ['#123456'], names: {'#123456': name}));
    expect(find.text(name), findsOneWidget);
    expect(find.byTooltip('$name（#123456）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirming an existing name does not submit a rename',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(buildPicker(
      selectedColor: '#123456',
      names: {'#123456': '海洋藍'},
      onNamed: (_, __) => calls++,
    ));
    await tester.tap(find.text('修改名稱'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確認'));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets('selecting a saved colour shows one selected swatch',
      (tester) async {
    await tester.pumpWidget(
      buildPicker(selectedColor: '#123456', savedColors: const ['#123456']),
    );

    expect(find.text('#123456'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.palette_outlined), findsOneWidget);
  });

  testWidgets('an unsaved custom colour is selected in the custom control',
      (tester) async {
    await tester.pumpWidget(buildPicker(selectedColor: '#123456'));

    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.palette_outlined), findsNothing);
  });

  testWidgets('a preset colour does not select the custom control',
      (tester) async {
    await tester.pumpWidget(buildPicker(selectedColor: '#F97316'));

    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.palette_outlined), findsOneWidget);
  });

  testWidgets('the inherited trip colour option remains selectable',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TripColorPicker(
            selectedColor: null,
            showDefaultOption: true,
            onColorChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('使用旅程顏色'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    expect(find.byIcon(Icons.palette_outlined), findsOneWidget);
  });
}
