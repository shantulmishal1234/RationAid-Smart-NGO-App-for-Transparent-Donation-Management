import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:ration_aid/screens/Admin/widgets/frosted_panel.dart';

class AdminDemographicsChart extends StatefulWidget {
  final int accepted;
  final int pending;
  final int rejected;
  final int discarded;

  const AdminDemographicsChart({
    super.key,
    required this.accepted,
    required this.pending,
    required this.rejected,
    required this.discarded,
  });

  @override
  State<AdminDemographicsChart> createState() => _AdminDemographicsChartState();
}

class _AdminDemographicsChartState extends State<AdminDemographicsChart> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final hasData =
        widget.accepted + widget.pending + widget.rejected + widget.discarded >
        0;

    return FrostedPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Family Application Status',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 24),
          if (!hasData)
            const SizedBox(
              height: 200,
              child: Center(child: Text('No data available')),
            )
          else
            SizedBox(
              height: 200,
              child: Stack(
                children: [
                  PieChart(
                    PieChartData(
                      pieTouchData: PieTouchData(
                        touchCallback: (FlTouchEvent event, pieTouchResponse) {
                          setState(() {
                            if (!event.isInterestedForInteractions ||
                                pieTouchResponse == null ||
                                pieTouchResponse.touchedSection == null) {
                              _touchedIndex = -1;
                              return;
                            }
                            _touchedIndex = pieTouchResponse
                                .touchedSection!
                                .touchedSectionIndex;
                          });
                        },
                      ),
                      borderData: FlBorderData(show: false),
                      sectionsSpace: 2,
                      centerSpaceRadius: 60,
                      sections: _showingSections(),
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Total',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                        Text(
                          '${widget.accepted + widget.pending + widget.rejected + widget.discarded}',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          _buildLegendRow(),
        ],
      ),
    );
  }

  List<PieChartSectionData> _showingSections() {
    return [
      _buildSection(
        index: 0,
        value: widget.accepted.toDouble(),
        color: AppColors.primaryBlue,
        title: '${widget.accepted}',
      ),
      _buildSection(
        index: 1,
        value: widget.pending.toDouble(),
        color: const Color(0xFFFFA726), // Amber
        title: '${widget.pending}',
      ),
      _buildSection(
        index: 2,
        value: widget.rejected.toDouble(),
        color: const Color(0xFFEF5350), // Red
        title: '${widget.rejected}',
      ),
      _buildSection(
        index: 3,
        value: widget.discarded.toDouble(),
        color: Colors.grey,
        title: '${widget.discarded}',
      ),
    ];
  }

  PieChartSectionData _buildSection({
    required int index,
    required double value,
    required Color color,
    required String title,
  }) {
    final isTouched = index == _touchedIndex;
    final fontSize = isTouched ? 18.0 : 12.0;
    final radius = isTouched ? 40.0 : 30.0;

    return PieChartSectionData(
      color: color,
      value: value,
      title: value > 0 ? title : '',
      radius: radius,
      titleStyle: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
      showTitle: value > 0,
    );
  }

  Widget _buildLegendRow() {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        _Indicator(color: AppColors.primaryBlue, text: 'Accepted'),
        _Indicator(color: const Color(0xFFFFA726), text: 'Pending'),
        _Indicator(color: const Color(0xFFEF5350), text: 'Rejected'),
        _Indicator(color: Colors.grey, text: 'Discarded'),
      ],
    );
  }
}

class _Indicator extends StatelessWidget {
  final Color color;
  final String text;

  const _Indicator({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}
