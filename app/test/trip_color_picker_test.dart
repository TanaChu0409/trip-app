import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner_app/features/trips/presentation/widgets/trip_color_picker.dart';

void main() {
  Widget buildPicker({
    String? selectedColor,
    List<String> savedColors = const [],
  }) {
    return MaterialApp(
      home: Scaffold(
        body: TripColorPicker(
          selectedColor: selectedColor,
          savedCustomColors: savedColors,
          onColorChanged: (_) {},
        ),
      ),
    );
  }

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
