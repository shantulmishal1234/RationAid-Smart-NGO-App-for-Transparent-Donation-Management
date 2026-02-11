import 'package:flutter/material.dart';
import 'package:ration_aid/models/procurement_model.dart';

import 'package:intl/intl.dart';
import 'package:ration_aid/theme/app_colors.dart';

class ProcurementCard extends StatelessWidget {
  final ProcurementRequest request;
  final VoidCallback onTap;
  final String actionLabel;

  const ProcurementCard({
    super.key,
    required this.request,
    required this.onTap,
    this.actionLabel = 'Process',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currencyFormat = NumberFormat.currency(
      locale: 'en_PK',
      symbol: 'Rs. ',
      decimalDigits: 0,
    );

    final isOverdue = DateTime.now().difference(request.createdAt).inDays > 7;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.3)
                : Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: theme.dividerColor.withOpacity(isDark ? 0.1 : 0.05),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: request.status == ProcurementStatus.rejected
                            ? Colors.red.withOpacity(0.1)
                            : AppColors.purchaserOrange.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        request.status == ProcurementStatus.rejected
                            ? Icons.report_problem_outlined
                            : Icons.shopping_cart_outlined,
                        color: request.status == ProcurementStatus.rejected
                            ? Colors.red
                            : AppColors.purchaserOrange,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            request.packName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 14,
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.6,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  request.familyAddress,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.6),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _buildStatusChip(theme),
                  ],
                ),

                if (isOverdue && request.status == ProcurementStatus.pending)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withOpacity(0.2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.access_time,
                            size: 14,
                            color: Colors.red,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Action Required: Overdue',
                            style: TextStyle(
                              color: Colors.red[700],
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                if (request.status == ProcurementStatus.rejected &&
                    request.adminRemarks != null)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.withOpacity(0.2)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            request.adminRemarks!,
                            style: TextStyle(
                              color: Colors.red[800],
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Estimated Cost',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                        Text(
                          currencyFormat.format(request.budgetLimit),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: onTap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            request.status == ProcurementStatus.rejected
                            ? Colors.red
                            : AppColors.purchaserOrange,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 0,
                        ), // Compact button
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        actionLabel,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(ThemeData theme) {
    Color color;
    String label;

    switch (request.status) {
      case ProcurementStatus.purchased:
        color = Colors.blue;
        label = 'Review';
        break;
      case ProcurementStatus.rejected:
        color = Colors.red;
        label = 'Rejected';
        break;
      case ProcurementStatus.verified:
        color = Colors.green;
        label = 'Verified';
        break;
      default:
        color = Colors.orange;
        label = 'Pending';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
