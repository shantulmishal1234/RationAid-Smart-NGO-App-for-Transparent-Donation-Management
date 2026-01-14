import 'package:flutter/material.dart';

/// Donation card widget for displaying donation information
class DonationCard extends StatelessWidget {
  final String id;
  final String donorName;
  final String donorEmail;
  final double amount;
  final String currency;
  final String method;
  final String status;
  final VoidCallback onTap;

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
  });

  Color _statusColor() {
    switch (status) {
      case 'verified':
        return Colors.green;
      case 'under_review':
        return Colors.orange;
      case 'rejected':
        return Colors.red;
      case 'pending':
      default:
        return Colors.blueGrey;
    }
  }

  String _statusLabel() {
    switch (status) {
      case 'verified':
        return 'Verified';
      case 'under_review':
        return 'Under review';
      case 'rejected':
        return 'Rejected';
      case 'pending':
      default:
        return 'Pending';
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.blueGrey[50],
              child: Text(
                amount.toInt().toString(),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    donorName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    donorEmail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$amount $currency • $method',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _statusColor().withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _statusLabel(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _statusColor(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
