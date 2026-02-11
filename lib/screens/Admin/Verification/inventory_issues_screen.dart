import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ration_aid/models/procurement_model.dart';
import 'package:ration_aid/screens/Admin/widgets/admin_scaffold.dart';
import 'package:ration_aid/screens/Admin/widgets/frosted_panel.dart';
import 'package:ration_aid/services/audit_service.dart';

class InventoryIssuesScreen extends StatefulWidget {
  const InventoryIssuesScreen({super.key});

  @override
  State<InventoryIssuesScreen> createState() => _InventoryIssuesScreenState();
}

class _InventoryIssuesScreenState extends State<InventoryIssuesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> _resolveIssue(ProcurementRequest request, String action) async {
    // action: 'write_off' (accept loss) | 'ignore' (reject report)

    try {
      if (action == 'write_off') {
        // Mark as written off - stock is removed/reduced effectively
        await _firestore
            .collection('procurement_requests')
            .doc(request.id)
            .update({
              'status': 'written_off',
              'resolvedAt': FieldValue.serverTimestamp(),
              'resolutionAction': 'write_off',
            });
        await AuditService.logAction(
          action: 'inventory_write_off',
          entityType: 'procurement',
          entityId: request.id,
          details: 'Issue resolved: Stock written off.',
        );
      } else {
        // Revert to 'stocked' (available)
        await _firestore
            .collection('procurement_requests')
            .doc(request.id)
            .update({
              'status': 'verified', // Back to verified/stocked status
              'reviewStatus': 'issue_ignored',
              'resolvedAt': FieldValue.serverTimestamp(),
            });
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Issue resolved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Inventory Issues',
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('procurement_requests')
            .where('status', isEqualTo: 'issue_reported')
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
                    'No reported issues',
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
              final data = docs[index].data() as Map<String, dynamic>;
              final request = ProcurementRequest.fromFirestore(docs[index]);

              return FrostedPanel(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Issue: ${(data['issueType'] ?? 'Unknown').toString().toUpperCase()}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Pack: ${request.packName}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Reason: ${data['issueReason'] ?? "No reason provided"}',
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => _resolveIssue(request, 'ignore'),
                            child: const Text('Dismiss (Keep Stock)'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () =>
                                _resolveIssue(request, 'write_off'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Write Off'),
                          ),
                        ],
                      ),
                    ],
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
