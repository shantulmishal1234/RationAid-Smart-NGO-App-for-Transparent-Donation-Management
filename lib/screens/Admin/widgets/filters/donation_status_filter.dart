import 'package:flutter/material.dart';
import 'package:ration_aid/screens/Admin/models/admin_enums.dart';

/// Filter chips widget for donation status selection
class DonationStatusFilterChips extends StatelessWidget {
  final DonationStatusFilter selected;
  final ValueChanged<DonationStatusFilter> onChanged;

  const DonationStatusFilterChips({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip(context, DonationStatusFilter.all, 'All'),
          _chip(context, DonationStatusFilter.pending, 'Pending'),
          _chip(context, DonationStatusFilter.underReview, 'Under review'),
          _chip(context, DonationStatusFilter.verified, 'Verified'),
          _chip(context, DonationStatusFilter.rejected, 'Rejected'),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, DonationStatusFilter value, String label) {
    final isSelected = selected == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => onChanged(value),
        selectedColor: AdminColors.primaryBlue.withValues(alpha: 0.2),
        labelStyle: TextStyle(
          color: isSelected ? AdminColors.primaryBlue : Colors.grey[700],
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
        ),
        side: BorderSide(
          color: isSelected ? AdminColors.primaryBlue : Colors.grey[300]!,
        ),
      ),
    );
  }
}
