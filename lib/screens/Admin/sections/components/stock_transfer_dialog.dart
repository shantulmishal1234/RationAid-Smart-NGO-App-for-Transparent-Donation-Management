import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/services/inventory_service.dart';
import 'package:ration_aid/theme/app_colors.dart';

class StockTransferDialog extends StatefulWidget {
  final String stockId;
  final String currentFamilyId;
  final Map<String, num> items;
  final String adminUid;
  final Map<String, dynamic> itemValueSnapshot;

  const StockTransferDialog({
    super.key,
    required this.stockId,
    required this.currentFamilyId,
    required this.items,
    required this.adminUid,
    required this.itemValueSnapshot,
  });

  @override
  State<StockTransferDialog> createState() => _StockTransferDialogState();
}

class _StockTransferDialogState extends State<StockTransferDialog> {
  String? _selectedFamilyId;
  String? _selectedFamilyName;
  List<Map<String, String>> _familyOptions = [];
  bool _loadingFamilies = true;
  bool _isTransferring = false;

  @override
  void initState() {
    super.initState();
    _loadFamilies();
  }

  Future<void> _loadFamilies() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('families')
          .where('status', isEqualTo: 'accepted')
          .where('isArchived', isEqualTo: false)
          .limit(100)
          .get();

      final list = snap.docs
          .where((doc) => doc.id != widget.currentFamilyId) // Exclude current
          .map((d) {
            final data = d.data();
            final needs = data['needs'] as Map? ?? {};
            final hasNeed = widget.items.keys.any((k) => (needs[k] ?? 0) > 0);

            return {
              'id': d.id,
              'name': (data['area'] ?? 'Unknown Area') as String,
              'city': (data['city'] ?? '') as String,
              'hasNeed': hasNeed ? 'yes' : 'no',
            };
          })
          .toList();

      if (mounted) {
        setState(() {
          _familyOptions = list;
          _loadingFamilies = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingFamilies = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('🔄 Transfer Stock'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Move these items to a different family:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              children: widget.items.entries.map((e) {
                return Chip(
                  label: Text(
                    '${e.key} ×${e.value}',
                    style: const TextStyle(fontSize: 10),
                  ),
                  backgroundColor: AppColors.primaryBlue.withOpacity(0.1),
                  padding: EdgeInsets.zero,
                );
              }).toList(),
            ),
            const Divider(height: 24),
            const Text(
              'Select Target Family',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            if (_loadingFamilies)
              const Center(child: CircularProgressIndicator())
            else if (_familyOptions.isEmpty)
              const Text('No eligible families found.')
            else
              DropdownButtonFormField<String>(
                isExpanded: true,
                hint: const Text('Search for a family...'),
                initialValue: _selectedFamilyId,
                items: _familyOptions.map((f) {
                  final isNeeded = f['hasNeed'] == 'yes';
                  return DropdownMenuItem<String>(
                    value: f['id'],
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${f['name']}, ${f['city']}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: isNeeded ? null : Colors.grey,
                            ),
                          ),
                        ),
                        if (isNeeded)
                          const Icon(
                            Icons.star,
                            size: 12,
                            color: Colors.orange,
                          ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedFamilyId = val;
                    _selectedFamilyName = _familyOptions.firstWhere(
                      (f) => f['id'] == val,
                    )['name'];
                  });
                },
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            const Text(
              '⚠️ This will restore needs for the original family and satisfy needs for the new family.',
              style: TextStyle(
                fontSize: 10,
                color: Colors.orange,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isTransferring ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _selectedFamilyId == null || _isTransferring
              ? null
              : _handleTransfer,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryBlue,
            foregroundColor: Colors.white,
          ),
          child: _isTransferring
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Transfer Now'),
        ),
      ],
    );
  }

  Future<void> _handleTransfer() async {
    setState(() => _isTransferring = true);
    try {
      await InventoryService.transferStock(
        stockId: widget.stockId,
        fromFamilyId: widget.currentFamilyId,
        toFamilyId: _selectedFamilyId!,
        adminUid: widget.adminUid,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text('✅ Successfully transferred to $_selectedFamilyName'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isTransferring = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Transfer failed: $e'),
          ),
        );
      }
    }
  }
}
