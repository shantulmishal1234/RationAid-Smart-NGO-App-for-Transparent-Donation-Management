import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ration_aid/models/procurement_model.dart';
import 'package:ration_aid/services/procurement_service.dart';
import 'package:ration_aid/screens/Admin/widgets/frosted_panel.dart';
import 'package:ration_aid/screens/Admin/widgets/admin_scaffold.dart';
import 'package:intl/intl.dart';

class PurchaseApprovalScreen extends StatefulWidget {
  const PurchaseApprovalScreen({super.key});

  @override
  State<PurchaseApprovalScreen> createState() => _PurchaseApprovalScreenState();
}

/// Formerly StockVerificationSection
/// Now verifies PENDING STOCK (Purchased but not yet in inventory)
class _PurchaseApprovalScreenState extends State<PurchaseApprovalScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  void _showVerificationDialog(ProcurementRequest request) {
    final currencyFormat = NumberFormat.currency(
      locale: 'en_PK',
      symbol: 'Rs. ',
      decimalDigits: 0,
    );
    final totalSpent = currencyFormat.format(request.totalSpent);
    final date = DateFormat.yMMMd().format(
      request.purchasedAt ?? DateTime.now(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verify Purchase & Stock In'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Pack: ${request.packName}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('Family Area: ${request.familyAddress}'),
                Text('Purchaser: ${request.purchaserName}'),
                Text('Date: $date'),
                const Divider(),
                Text(
                  'Total Spent: $totalSpent',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Receipt:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (request.receiptUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: GestureDetector(
                      onTap: () {
                        // View full image dialog could go here
                      },
                      child: Image.network(
                        request.receiptUrl!,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 100,
                          color: Colors.grey[200],
                          child: const Center(
                            child: Text('Failed to load receipt'),
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  const Text(
                    'No Receipt Uploaded',
                    style: TextStyle(color: Colors.red),
                  ),

                const SizedBox(height: 12),
                const Text(
                  'Items:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                ...request.items
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(item.name),
                            Text(currencyFormat.format(item.actualCost)),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              _showRejectDialog(request);
            },
            child: const Text('Reject', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await ProcurementService.adminVerifyPurchase(request.id);
                if (context.mounted) Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Stock Verified & Added to Inventory'),
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Approve & Stock In'),
          ),
        ],
      ),
    );
  }

  void _showRejectDialog(ProcurementRequest request) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Purchase'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
            labelText: 'Reason for Rejection',
            hintText: 'e.g., Receipt unclear, cost mismatch',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (reasonController.text.isEmpty) return;
              try {
                await ProcurementService.adminRejectPurchase(
                  request.id,
                  reasonController.text,
                );
                if (context.mounted) Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Purchase Rejected')),
                );
              } catch (e) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Stock Verification', // Updated title
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('procurement_requests')
            .where('status', isEqualTo: 'purchased')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No pending verifications',
                    style: TextStyle(color: Colors.grey[500], fontSize: 16),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final request = ProcurementRequest.fromFirestore(docs[index]);
              return FrostedPanel(
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.assignment_turned_in,
                      color: Colors.blue,
                    ),
                  ),
                  title: Text(
                    request.packName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Spent: Rs. ${request.totalSpent.toStringAsFixed(0)}',
                  ),
                  trailing: ElevatedButton(
                    onPressed: () => _showVerificationDialog(request),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: const Text('Verify'),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
