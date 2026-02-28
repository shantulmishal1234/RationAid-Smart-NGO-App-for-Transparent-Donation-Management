import 'package:flutter/material.dart';
import 'package:ration_aid/models/donation_model.dart';

/// Donation card widget for displaying donation information
class DonationCard extends StatelessWidget {
  final String id;
  final String donorName;
  final String donorEmail;
  final double amount;
  final String currency;
  final String method;
  final DonationStatus status;
  final VoidCallback onTap;
  final int? serialNumber;

  const DonationCard({
    super.key,
    required this.id,
    required this.donorName,
    required this.donorEmail,
    required this.amount,
    required this.currency,
    required this.method,
    required this.status,
    required this.onTap,
    this.serialNumber,
  });

  Color _statusColor() {
    switch (status) {
      case DonationStatus.verified:
        return Colors.green;
      case DonationStatus.underVerification:
        return Colors.orange;
      case DonationStatus.rejected:
        return Colors.red;
      case DonationStatus.pending:
        return Colors.grey;
      case DonationStatus.inProcess:
        return Colors.blue;
      case DonationStatus.outForDelivery:
      case DonationStatus.delivered:
        return Colors.purple;
      case DonationStatus.closed:
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel() {
    return status.displayName;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return RepaintBoundary(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.dividerColor.withValues(alpha: 0.6)),
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
                      : amount.toInt().toString(),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      donorName,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      donorEmail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '$amount $currency • $method',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _statusColor().withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _statusColor().withValues(alpha: 0.2)),
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
            ],
          ),
        ),
      ),
    );
  }
}
