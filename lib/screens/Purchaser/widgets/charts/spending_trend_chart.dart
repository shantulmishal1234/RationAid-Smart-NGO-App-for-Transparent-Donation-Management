import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:intl/intl.dart';

class SpendingTrendChart extends StatefulWidget {
  final Map<DateTime, double> dailyData;

  const SpendingTrendChart({super.key, required this.dailyData});

  @override
  State<SpendingTrendChart> createState() => _SpendingTrendChartState();
}

class _SpendingTrendChartState extends State<SpendingTrendChart> {
  int? touchedIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.dailyData.isEmpty) {
      return const Center(child: Text("No data available"));
    }

    // Convert map to sorted list
    final sortedEntries = widget.dailyData.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final maxVal = sortedEntries.fold<double>(
      0,
      (prev, e) => e.value > prev ? e.value : prev,
    );
    // Add 20% buffer to Y-axis
    final uploadLimit = (maxVal * 1.2).ceilToDouble();

    return AspectRatio(
      aspectRatio: 1.5,
      child: BarChart(
        BarChartData(
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => Colors.blueGrey,
              tooltipHorizontalAlignment: FLHorizontalAlignment.center,
              tooltipMargin: -10,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final date = sortedEntries[group.x.toInt()].key;
                final dateStr = DateFormat('MMM dd').format(date);
                return BarTooltipItem(
                  '$dateStr\n',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  children: <TextSpan>[
                    TextSpan(
                      text: 'Rs ${(rod.toY).toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Colors.yellow, // Highlight amount
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                );
              },
            ),
            touchCallback: (FlTouchEvent event, barTouchResponse) {
              setState(() {
                if (!event.isInterestedForInteractions ||
                    barTouchResponse == null ||
                    barTouchResponse.spot == null) {
                  touchedIndex = -1;
                  return;
                }
                touchedIndex = barTouchResponse.spot!.touchedBarGroupIndex;
              });
            },
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (double value, TitleMeta meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= sortedEntries.length) {
                    return const SizedBox.shrink();
                  }

                  final date = sortedEntries[index].key;
                  // Show Day Name (Mon, Tue)
                  return SideTitleWidget(
                    meta: meta,
                    space: 4,
                    child: Text(
                      DateFormat('E').format(date).substring(0, 1),
                      style: TextStyle(
                        color: touchedIndex == index
                            ? AppColors.purchaserOrange
                            : Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  );
                },
                reservedSize: 30,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: false, // Cleaner look without Y-axis numbers
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: sortedEntries.asMap().entries.map((e) {
            final index = e.key;
            final data = e.value;
            final isTouched = index == touchedIndex;
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: data.value,
                  color: isTouched
                      ? AppColors.purchaserOrange
                      : AppColors.purchaserOrange.withValues(alpha: 0.7),
                  width: 16,
                  borderRadius: BorderRadius.circular(4),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: uploadLimit, // Full height background
                    color: Colors.grey.withValues(alpha: 0.1),
                  ),
                ),
              ],
            );
          }).toList(),
          gridData: const FlGridData(show: false),
        ),
      ),
    );
  }
}
