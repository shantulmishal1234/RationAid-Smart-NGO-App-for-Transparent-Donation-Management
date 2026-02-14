import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/theme/app_colors.dart';

class CategoryPieChart extends StatefulWidget {
  final Map<String, double> categoryData;

  const CategoryPieChart({super.key, required this.categoryData});

  @override
  State<CategoryPieChart> createState() => _CategoryPieChartState();
}

class _CategoryPieChartState extends State<CategoryPieChart> {
  int touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    if (widget.categoryData.isEmpty) {
      return const SizedBox.shrink();
    }

    final entries = widget.categoryData.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Take top 5, group others
    final topEntries = entries.take(5).toList();
    // Calculate total for percentage
    final total = entries.fold<double>(0, (sum, e) => sum + e.value);

    // Color Palette
    final colors = [
      AppColors.purchaserOrange,
      Colors.blue,
      Colors.green,
      Colors.amber,
      Colors.purple,
      Colors.grey,
    ];

    return Row(
      children: [
        // Pie Chart
        Expanded(
          flex: 3,
          child: AspectRatio(
            aspectRatio: 1,
            child: PieChart(
              PieChartData(
                pieTouchData: PieTouchData(
                  touchCallback: (FlTouchEvent event, pieTouchResponse) {
                    setState(() {
                      if (!event.isInterestedForInteractions ||
                          pieTouchResponse == null ||
                          pieTouchResponse.touchedSection == null) {
                        touchedIndex = -1;
                        return;
                      }
                      touchedIndex =
                          pieTouchResponse.touchedSection!.touchedSectionIndex;
                    });
                  },
                ),
                borderData: FlBorderData(show: false),
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: List.generate(topEntries.length, (i) {
                  final isTouched = i == touchedIndex;
                  final fontSize = isTouched ? 20.0 : 14.0;
                  final radius = isTouched ? 60.0 : 50.0;
                  final entry = topEntries[i];
                  final percent = (entry.value / total * 100);

                  return PieChartSectionData(
                    color: colors[i % colors.length],
                    value: entry.value,
                    title: '${percent.toStringAsFixed(0)}%',
                    radius: radius,
                    titleStyle: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [Shadow(color: Colors.black26, blurRadius: 2)],
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Legend
        Expanded(
          flex: 2,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(topEntries.length, (i) {
              final entry = topEntries[i];
              final isTouched = i == touchedIndex;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors[i % colors.length],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        entry.key,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isTouched
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: isTouched
                              ? Theme.of(context).colorScheme.onSurface
                              : Theme.of(context).hintColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}
