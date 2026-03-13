import 'package:flutter/material.dart';
import '../../../theme/app_colors.dart'; // Relative import to avoid package resolution issues
import '../../../models/family_model.dart';

/// Family card widget for displaying family information
class FamilyCard extends StatelessWidget {
  final Family family;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final int? serialNumber;

  const FamilyCard({
    super.key,
    required this.family,
    required this.onTap,
    this.onEdit,
    this.serialNumber,
  });

  Color _statusColor() {
    switch (family.status) {
      case 'accepted':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'discarded':
        return Colors.grey;
      case 'pending_review':
        return Colors.deepPurple[300]!;
      default:
        return Colors.orange;
    }
  }

  String _statusLabel() {
    switch (family.status) {
      case 'accepted':
        return 'Accepted';
      case 'rejected':
        return 'Rejected';
      case 'discarded':
        return 'Discarded';
      case 'pending_review':
        return 'Under Review';
      default:
        return 'Pending';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Calculate progress with surplus
    final raised = family.raisedAmount;
    final target = family.targetAmount > 0
        ? family.targetAmount
        : 1; // Avoid div by zero
    final surplus = family.surplusAmount;
    final totalAvailable = raised + surplus;

    // If overfunded, we clamp progress at 1.0 but change color
    final progress = (totalAvailable / target).clamp(0.0, 1.0);
    final isOverFunded = surplus > 0;

    return RepaintBoundary(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isOverFunded
                  ? Colors.deepOrange.withValues(alpha: 0.5)
                  : theme.dividerColor.withValues(alpha: 0.6),
              width: isOverFunded ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: isDark
                    ? Colors.blueGrey[800]
                    : Colors.blueGrey[50],
                child: Text(
                  serialNumber != null
                      ? serialNumber.toString()
                      : family.familySize.toString(),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      family.name ?? 'Unnamed Family',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      family.area,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      family.address ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                        fontSize: 10,
                      ),
                    ),
                    // Removed volunteer assigned name UI
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor().withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _statusColor().withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      _statusLabel(),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: _statusColor(),
                      ),
                    ),
                  ),
                  if (family.status == 'accepted' &&
                      family.targetAmount > 0) ...[
                    const SizedBox(height: 6),
                    SizedBox(
                      width: 80, // Slightly wider for surplus text
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor:
                                  theme.brightness == Brightness.dark
                                  ? Colors.grey[800]
                                  : Colors.grey[200],
                              color: isOverFunded
                                  ? Colors.deepOrange
                                  : (progress >= 1.0
                                        ? Colors.green
                                        : AppColors.donorGreen),
                              minHeight: 4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (isOverFunded)
                                Text(
                                  '+${surplus.toInt()} ',
                                  style: const TextStyle(
                                    fontSize: 8,
                                    color: Colors.deepOrange,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              Text(
                                '${(progress * 100).toInt()}%',
                                style: TextStyle(
                                  fontSize: 8,
                                  color: isOverFunded
                                      ? Colors.deepOrange
                                      : (progress >= 1.0
                                            ? Colors.green
                                            : AppColors.donorGreen),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (onEdit != null) ...[
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: onEdit,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.edit_outlined,
                          size: 14,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
