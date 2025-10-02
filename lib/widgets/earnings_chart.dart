import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../core/app_theme.dart';

class EarningsChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final String timeRange;
  final Function(DateTime) onSelectDate;

  const EarningsChart({
    Key? key,
    required this.data,
    required this.timeRange,
    required this.onSelectDate,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Card(
      elevation: AppTheme.elevationLow,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Earnings Trend',
              style: theme.textTheme.titleMedium,
            ),
            SizedBox(height: 16),
            Expanded(
              child: LineChart(
                LineChartData(
                  gridData: _buildGridData(theme),
                  titlesData: _buildTitlesData(theme),
                  borderData: _buildBorderData(),
                  lineBarsData: [_buildLineData(theme)],
                  lineTouchData: _buildTouchData(theme),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  FlGridData _buildGridData(ThemeData theme) {
    return FlGridData(
      show: true,
      drawVerticalLine: true,
      horizontalInterval: _getInterval(),
      verticalInterval: 1,
      getDrawingHorizontalLine: (value) {
        return FlLine(
          color: theme.colorScheme.outline.withOpacity(0.2),
          strokeWidth: 1,
        );
      },
      getDrawingVerticalLine: (value) {
        return FlLine(
          color: theme.colorScheme.outline.withOpacity(0.2),
          strokeWidth: 1,
        );
      },
    );
  }

  FlTitlesData _buildTitlesData(ThemeData theme) {
    return FlTitlesData(
      show: true,
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 30,
          interval: 1,
          getTitlesWidget: (value, meta) {
            return SideTitleWidget(
              axisSide: meta.axisSide,
              child: Text(
                _getBottomTitle(value.toInt()),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 45,
          interval: _getInterval(),
          getTitlesWidget: (value, meta) {
            return SideTitleWidget(
              axisSide: meta.axisSide,
              child: Text(
                '\$${value.toStringAsFixed(0)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            );
          },
        ),
      ),
      rightTitles: AxisTitles(
        sideTitles: SideTitles(showTitles: false),
      ),
      topTitles: AxisTitles(
        sideTitles: SideTitles(showTitles: false),
      ),
    );
  }

  FlBorderData _buildBorderData() {
    return FlBorderData(
      show: true,
      border: Border.all(
        color: Colors.transparent,
      ),
    );
  }

  LineChartBarData _buildLineData(ThemeData theme) {
    return LineChartBarData(
      spots: _getSpots(),
      isCurved: true,
      gradient: LinearGradient(
        colors: [
          theme.colorScheme.primary,
          theme.colorScheme.primary.withOpacity(0.5),
        ],
      ),
      barWidth: 3,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, bar, index) {
          return FlDotCirclePainter(
            radius: 4,
            color: theme.colorScheme.primary,
            strokeWidth: 2,
            strokeColor: theme.colorScheme.surface,
          );
        },
      ),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.colorScheme.primary.withOpacity(0.2),
            theme.colorScheme.primary.withOpacity(0.0),
          ],
        ),
      ),
    );
  }

  LineTouchData _buildTouchData(ThemeData theme) {
    final dateFormat = _getDateFormat();
    
    return LineTouchData(
      touchTooltipData: LineTouchTooltipData(
        tooltipBgColor: theme.colorScheme.surface,
        tooltipRoundedRadius: 8,
        getTooltipItems: (spots) {
          return spots.map((spot) {
            final date = _getDateFromIndex(spot.x.toInt());
            return LineTooltipItem(
              '${dateFormat.format(date)}\n\$${spot.y.toStringAsFixed(2)}',
              theme.textTheme.bodySmall!.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            );
          }).toList();
        },
      ),
      touchCallback: (event, response) {
        if (event is FlTapUpEvent && response?.lineBarSpots != null) {
          final spot = response!.lineBarSpots!.first;
          final date = _getDateFromIndex(spot.x.toInt());
          onSelectDate(date);
        }
      },
      handleBuiltInTouches: true,
    );
  }

  List<FlSpot> _getSpots() {
    final spots = <FlSpot>[];
    for (var i = 0; i < data.length; i++) {
      spots.add(FlSpot(
        i.toDouble(),
        data[i]['amount'] as double,
      ));
    }
    return spots;
  }

  String _getBottomTitle(int value) {
    final date = _getDateFromIndex(value);
    switch (timeRange) {
      case 'day':
        return DateFormat('HH:mm').format(date);
      case 'week':
        return DateFormat('E').format(date);
      case 'month':
        return DateFormat('d').format(date);
      case 'year':
        return DateFormat('MMM').format(date);
      default:
        return '';
    }
  }

  DateTime _getDateFromIndex(int index) {
    final now = DateTime.now();
    switch (timeRange) {
      case 'day':
        return now.subtract(Duration(hours: 23 - index));
      case 'week':
        return now.subtract(Duration(days: 6 - index));
      case 'month':
        return now.subtract(Duration(days: 29 - index));
      case 'year':
        return DateTime(now.year, now.month - 11 + index);
      default:
        return now;
    }
  }

  DateFormat _getDateFormat() {
    switch (timeRange) {
      case 'day':
        return DateFormat('HH:mm');
      case 'week':
        return DateFormat('EEE, MMM d');
      case 'month':
        return DateFormat('MMM d');
      case 'year':
        return DateFormat('MMM yyyy');
      default:
        return DateFormat();
    }
  }

  double _getInterval() {
    final values = data.map((e) => e['amount'] as double).toList();
    if (values.isEmpty) return 10;
    
    final max = values.reduce((curr, next) => curr > next ? curr : next);
    final interval = max / 5;
    
    // Round to nearest nice number
    final magnitude = interval.floor().toString().length - 1;
    final base = pow(10, magnitude).toDouble();
    return (interval / base).ceil() * base;
  }
}