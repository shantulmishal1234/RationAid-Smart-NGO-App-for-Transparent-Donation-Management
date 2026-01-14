import 'package:flutter/material.dart';
import 'package:ration_aid/screens/Admin/models/admin_enums.dart';

/// Filter widget for HRM role selection
class HrmRoleFilter extends StatelessWidget {
  final String selectedRole;
  final ValueChanged<String> onChanged;

  const HrmRoleFilter({
    super.key,
    required this.selectedRole,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const roles = {
      'all': 'All',
      'purchasers': 'Purchasers',
      'distributors': 'Distributors',
      'donors': 'Donors',
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: roles.entries.map((entry) {
          final isSelected = selectedRole == entry.key;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(entry.value),
              selected: isSelected,
              onSelected: (_) => onChanged(entry.key),
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
        }).toList(),
      ),
    );
  }
}
