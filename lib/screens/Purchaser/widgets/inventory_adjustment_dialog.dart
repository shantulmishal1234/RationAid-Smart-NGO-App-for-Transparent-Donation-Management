import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ration_aid/models/procurement_model.dart';
import 'package:ration_aid/services/audit_service.dart';

class InventoryAdjustmentDialog extends StatefulWidget {
  final ProcurementRequest request;

  const InventoryAdjustmentDialog({super.key, required this.request});

  @override
  State<InventoryAdjustmentDialog> createState() =>
      _InventoryAdjustmentDialogState();
}

class _InventoryAdjustmentDialogState extends State<InventoryAdjustmentDialog> {
  final _reasonController = TextEditingController();

  String _type = 'damage'; // damage, loss, other

  Future<void> _submitAdjustment() async {
    if (_reasonController.text.isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      final user = FirebaseAuth.instance.currentUser;

      // Create an adjustment request or log it directly depending on strictness.
      // Requirement: "Manual adjustment -> admin approval"
      // So we will flag the procurement request as 'issue_reported' and add details.

      await FirebaseFirestore.instance
          .collection('procurement_requests')
          .doc(widget.request.id)
          .update({
            'status': 'issue_reported',
            'issueType': _type,
            'issueReason': _reasonController.text,
            'issueReportedBy': user?.uid,
            'issueReportedAt': FieldValue.serverTimestamp(),
          });

      await AuditService.logAction(
        action: 'report_inventory_issue',
        entityType: 'procurement',
        entityId: widget.request.id,
        details: 'Type: $_type, Reason: ${_reasonController.text}',
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Issue reported to Admin')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Report Inventory Issue'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            value: _type,
            items: const [
              DropdownMenuItem(value: 'damage', child: Text('Damage')),
              DropdownMenuItem(value: 'loss', child: Text('Loss / Theft')),
              DropdownMenuItem(value: 'expiry', child: Text('Expiry')),
              DropdownMenuItem(value: 'other', child: Text('Other')),
            ],
            onChanged: (val) => setState(() => _type = val!),
            decoration: const InputDecoration(labelText: 'Issue Type'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reasonController,
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'Explain the situation...',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isProcessing ? null : _submitAdjustment,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
          child: const Text('Report'),
        ),
      ],
    );
  }
}
