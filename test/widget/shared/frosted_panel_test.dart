import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ration_aid/widgets/frosted_panel.dart';

void main() {
  group('FrostedPanel Widget', () {
    Widget buildTestWidget({
      required Widget child,
      EdgeInsetsGeometry? padding,
      EdgeInsetsGeometry? margin,
      Brightness brightness = Brightness.light,
    }) {
      return MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
          body: FrostedPanel(
            padding: padding,
            margin: margin,
            child: child,
          ),
        ),
      );
    }

    testWidgets('renders its child widget correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestWidget(child: const Text('Hello Frosted')),
      );

      expect(find.text('Hello Frosted'), findsOneWidget);
    });

    testWidgets('renders a Container at the root', (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestWidget(child: const SizedBox()),
      );

      expect(find.byType(Container), findsAtLeastNWidgets(1));
    });

    testWidgets('renders with default padding when none provided', (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestWidget(child: const Text('Default Padding')),
      );

      final paddingWidget = tester.widgetList<Padding>(find.byType(Padding)).last;
      expect(paddingWidget.padding, const EdgeInsets.all(14));
    });

    testWidgets('renders with custom padding when provided', (WidgetTester tester) async {
      const customPadding = EdgeInsets.symmetric(horizontal: 24, vertical: 12);

      await tester.pumpWidget(
        buildTestWidget(
          child: const Text('Custom Padding'),
          padding: customPadding,
        ),
      );

      final paddingWidget = tester.widgetList<Padding>(find.byType(Padding)).last;
      expect(paddingWidget.padding, customPadding);
    });

    testWidgets('renders child widget inside a Padding', (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestWidget(child: const Icon(Icons.star)),
      );

      expect(find.byType(Padding), findsAtLeastNWidgets(1));
      expect(find.byType(Icon), findsOneWidget);
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('renders correctly in dark mode without errors', (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          child: const Text('Dark Mode'),
          brightness: Brightness.dark,
        ),
      );

      expect(find.text('Dark Mode'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders correctly in light mode without errors', (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          child: const Text('Light Mode'),
          brightness: Brightness.light,
        ),
      );

      expect(find.text('Light Mode'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('can render complex child widgets', (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          child: Column(
            children: const [
              Text('Line 1'),
              Text('Line 2'),
              Icon(Icons.check),
            ],
          ),
        ),
      );

      expect(find.text('Line 1'), findsOneWidget);
      expect(find.text('Line 2'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('is a StatelessWidget', (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestWidget(child: const SizedBox()),
      );

      final frostedPanels = tester.widgetList<FrostedPanel>(find.byType(FrostedPanel));
      expect(frostedPanels.first, isA<StatelessWidget>());
    });
  });
}
