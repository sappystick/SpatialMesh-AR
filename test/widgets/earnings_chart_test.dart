import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../lib/widgets/earnings_chart.dart';
import '../../lib/core/app_theme.dart';

void main() {
  group('EarningsChart Widget Tests', () {
    late List<Map<String, dynamic>> testData;
    late DateTime now;

    setUp(() {
      now = DateTime.now();
      // Generate test data for the past week
      testData = List.generate(7, (index) {
        return {
          'amount': 100.0 + (index * 25), // Increasing amounts
          'timestamp': now.subtract(Duration(days: 6 - index)),
        };
      });
    });

    testWidgets('renders chart with correct data points', (WidgetTester tester) async {
      // Build widget
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.blue,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: EarningsChart(
                data: testData,
                timeRange: 'week',
                onSelectDate: (_) {},
              ),
            ),
          ),
        ),
      );

      // Verify chart is rendered
      expect(find.byType(LineChart), findsOneWidget);
      expect(find.text('Earnings Trend'), findsOneWidget);

      // Find the LineChart widget and verify its data
      final LineChart chart = tester.widget(find.byType(LineChart));
      final lineChartData = chart.data;

      // Verify line bar data exists
      expect(lineChartData.lineBarsData.length, 1);
      expect(lineChartData.lineBarsData.first.spots.length, testData.length);

      // Verify spot values match test data
      for (var i = 0; i < testData.length; i++) {
        final spot = lineChartData.lineBarsData.first.spots[i];
        expect(spot.x, i.toDouble());
        expect(spot.y, testData[i]['amount']);
      }
    });

    testWidgets('handles touch interactions correctly', (WidgetTester tester) async {
      DateTime? selectedDate;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: EarningsChart(
                data: testData,
                timeRange: 'week',
                onSelectDate: (date) {
                  selectedDate = date;
                },
              ),
            ),
          ),
        ),
      );

      // Simulate tap on chart
      await tester.tap(find.byType(LineChart));
      await tester.pump();

      // Verify onSelectDate callback was called
      expect(selectedDate, isNotNull);
    });

    testWidgets('displays different time ranges correctly', (WidgetTester tester) async {
      final timeRanges = ['day', 'week', 'month', 'year'];

      for (final range in timeRanges) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 400,
                child: EarningsChart(
                  data: testData,
                  timeRange: range,
                  onSelectDate: (_) {},
                ),
              ),
            ),
          ),
        );

        // Verify chart adapts to time range
        final chart = tester.widget<LineChart>(find.byType(LineChart));
        expect(chart.data.lineBarsData.first.spots.length, testData.length);

        await tester.pump();
      }
    });

    testWidgets('handles empty data gracefully', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: EarningsChart(
                data: [],
                timeRange: 'week',
                onSelectDate: (_) {},
              ),
            ),
          ),
        ),
      );

      // Verify chart still renders without data
      expect(find.byType(LineChart), findsOneWidget);
      expect(find.text('Earnings Trend'), findsOneWidget);

      final chart = tester.widget<LineChart>(find.byType(LineChart));
      expect(chart.data.lineBarsData.first.spots.isEmpty, true);
    });

    testWidgets('theme changes are reflected correctly', (WidgetTester tester) async {
      // Test light theme
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: EarningsChart(
                data: testData,
                timeRange: 'week',
                onSelectDate: (_) {},
              ),
            ),
          ),
        ),
      );

      var chart = tester.widget<LineChart>(find.byType(LineChart));
      final lightThemeData = chart.data;

      // Test dark theme
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: EarningsChart(
                data: testData,
                timeRange: 'week',
                onSelectDate: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      chart = tester.widget<LineChart>(find.byType(LineChart));
      final darkThemeData = chart.data;

      // Verify theme differences
      expect(
        lightThemeData.lineBarsData.first.gradient,
        isNot(equals(darkThemeData.lineBarsData.first.gradient)),
      );
    });

    testWidgets('chart respects container constraints', (WidgetTester tester) async {
      const chartHeight = 300.0;
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: chartHeight,
              child: EarningsChart(
                data: testData,
                timeRange: 'week',
                onSelectDate: (_) {},
              ),
            ),
          ),
        ),
      );

      final chartBox = tester.element(find.byType(LineChart)).renderObject as RenderBox;
      expect(chartBox.size.height, chartHeight);
    });
  });
}