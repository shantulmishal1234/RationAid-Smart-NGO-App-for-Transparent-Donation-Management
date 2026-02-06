import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/models/family_model.dart';
import 'package:ration_aid/services/audit_service.dart';
import 'package:ration_aid/screens/Admin/widgets/admin_scaffold.dart';
import 'package:ration_aid/services/notification_service.dart';

class PurchaseApprovalScreen extends StatefulWidget {
  const PurchaseApprovalScreen({super.key});

  @override
  State<PurchaseApprovalScreen> createState() => _PurchaseApprovalScreenState();
}

class _PurchaseApprovalScreenState extends State<PurchaseApprovalScreen> {
  bool _isProcessing = false;

  /// Approve purchase for a family
  Future<void> _approvePurchase(Family family) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve Purchase?'),
        content: Text(
          'Confirm that you are authorizing the purchase of '
          '${family.assignedPackName ?? "Assigned Pack"} '
          'for ${family.numberOfAdults + family.numberOfChildren} members '
          'at a cost of PKR ${family.targetAmount.toStringAsFixed(0)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);
    try {
      final user = FirebaseAuth.instance.currentUser;

      await FirebaseFirestore.instance
          .collection('families')
          .doc(family.id)
          .update({
            'fulfillmentStatus': 'purchase_approved',
            'purchaseApprovedBy': user?.uid,
            'purchaseApprovedByName':
                user?.displayName ?? user?.email ?? 'Admin',
            'purchaseApprovedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

      await AuditService.logFamilyAction(
        action: 'Purchase Approved',
        familyId: family.id,
        familyName:
            'Family of ${family.familySize}', // Using size as proxy for name if needed
        details: 'Amount: ${family.targetAmount}',
      );

      // Notify Admins about pending delivery
      await NotificationService.sendAdminNotification(
        title: 'Purchase Approved',
        message: 'Purchase for a family has been approved. Pending delivery.',
        type: 'delivery_pending',
        relatedId: family.id,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Purchase approved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Purchase Approval',
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('families')
            .where('status', isEqualTo: 'accepted')
            .where('fundingStatus', isEqualTo: 'fully_funded')
            .where('fulfillmentStatus', isEqualTo: 'ready_for_purchase')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No pending purchases',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final family = Family.fromFirestore(doc);

              return _buildPurchaseCard(family);
            },
          );
        },
      ),
    );
  }

  Widget _buildPurchaseCard(Family family) {
    return Card(
      // Using standard card or FrostedPanel
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Pack ID: ${family.assignedPackId ?? "N/A"}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Review',
                    style: TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _row('Assigned Pack', family.assignedPackName ?? 'Standard Pack'),
            _row('Cost', 'PKR ${family.targetAmount.toStringAsFixed(0)}'),
            _row('Family Size', '${family.familySize} Members'),
            _row('Area', '${family.area}, ${family.city}'),

            const Divider(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isProcessing
                    ? null
                    : () => _approvePurchase(family),
                icon: const Icon(Icons.check, size: 18),
                label: Text(
                  _isProcessing ? 'Processing...' : 'Approve Purchase',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
