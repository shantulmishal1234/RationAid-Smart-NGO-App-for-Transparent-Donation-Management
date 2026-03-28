import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/services/funding_service.dart';
import 'package:ration_aid/screens/Admin/House Hold Section/admin_grf_audit_screen.dart';
import 'package:ration_aid/screens/Admin/House Hold Section/admin_inkind_pool_screen.dart';

class AdminGRFWalletCard extends StatefulWidget {
  final VoidCallback? onManage;
  final VoidCallback? onManageInKind;

  const AdminGRFWalletCard({super.key, this.onManage, this.onManageInKind});

  @override
  State<AdminGRFWalletCard> createState() => _AdminGRFWalletCardState();
}

class _AdminGRFWalletCardState extends State<AdminGRFWalletCard> {
  Future<void> _showSmartAllocationSheet(
    BuildContext context,
    double currentBalance,
  ) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) =>
          _AdminGRFAllocationSheet(currentBalance: currentBalance),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('families')
          .doc('general_relief_fund')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        final doc = snapshot.data;
        if (doc == null) return const SizedBox.shrink();

        final data = doc.data() as Map<String, dynamic>?;
        final balance = (data?['raisedAmount'] as num?)?.toDouble() ?? 0.0;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2C3E50), Color(0xFF3498DB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    // LEFT HALF: GRF Cash Wallet
                    Expanded(
                      child: InkWell(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          bottomLeft: Radius.circular(16),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  AdminGRFAuditScreen(currentBalance: balance),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.2,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Icon(
                                      Icons.account_balance_wallet,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'GRF Cash Wallet',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'PKR ${balance.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 32,
                                child: TextButton.icon(
                                  onPressed: () => _showSmartAllocationSheet(
                                    context,
                                    balance,
                                  ),
                                  icon: const Icon(Icons.send, size: 14),
                                  label: const Text(
                                    'Transfer',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    disabledForegroundColor: Colors.white54,
                                    backgroundColor: Colors.white.withValues(
                                      alpha: 0.1,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // DIVIDER
                    Container(
                      width: 1,
                      color: Colors.white.withValues(alpha: 0.2),
                      margin: const EdgeInsets.symmetric(vertical: 16),
                    ),

                    // RIGHT HALF: GRF In-Kind Pool
                    Expanded(
                      child: InkWell(
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(16),
                          bottomRight: Radius.circular(16),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AdminInKindPoolScreen(),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.2,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Icon(
                                      Icons.inventory_2,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'GRF In-Kind Pool',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Manage Pool',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The Smart Allocation Bottom Sheet
/// Automatically sorts families based on Emergency status and Completion %.
class _AdminGRFAllocationSheet extends StatefulWidget {
  final double currentBalance;

  const _AdminGRFAllocationSheet({required this.currentBalance});

  @override
  State<_AdminGRFAllocationSheet> createState() =>
      _AdminGRFAllocationSheetState();
}

class _AdminGRFAllocationSheetState extends State<_AdminGRFAllocationSheet> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController(
    text: 'Allocated from GRF to close funding gap',
  );

  String? _expandedFamilyId;
  bool _isProcessing = false;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// Calculates the intelligent priority score.
  /// Tier 1: Emergency = 1000
  /// Tier 2: Completion Percentage (0.0 to 100.0)
  /// Tier 3: Staleness (not explicitly modeled as double, sorting handles via updatedAt).
  double _calculatePriority(Map<String, dynamic> data) {
    if (data['isEmergency'] == true) return 1000.0;

    final target =
        ((data['assignedPackBudget'] ?? data['targetAmount'] ?? 0) as num)
            .toDouble();
    if (target <= 0) return 0.0;

    final raised = (data['raisedAmount'] as num? ?? 0).toDouble();
    return (raised / target) *
        100.0; // Higher completion % = higher priority to quick-close
  }

  /// Submits the allocation transaction
  Future<void> _submitAllocation(
    String familyId,
    String familyName,
    double gap,
  ) async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    if (amount > widget.currentBalance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exceeds available GRF Balance')),
      );
      return;
    }

    if (amount > gap) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot over-allocate beyond family target'),
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      await FundingService.allocateFromGRF(
        targetFamilyId: familyId,
        amount: amount,
        adminNote: _noteController.text.trim(),
        adminUid: FirebaseAuth.instance.currentUser?.uid,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Successfully allocated PKR ${amount.toStringAsFixed(0)} to $familyName',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.blue.shade50.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border(
                bottom: BorderSide(color: Colors.blue.shade100, width: 1),
              ),
            ),
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade200,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Smart GRF Allocation',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'PKR ${widget.currentBalance.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Family List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('families')
                  .where('status', isEqualTo: 'accepted')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData) return const SizedBox.shrink();

                // Advanced Filtering and Sorting Algorithm
                var docs = snapshot.data!.docs.where((doc) {
                  if (doc.id == 'general_relief_fund') return false;

                  final data = doc.data() as Map<String, dynamic>;
                  final target =
                      ((data['assignedPackBudget'] ?? data['targetAmount'] ?? 0)
                              as num)
                          .toDouble();
                  final raised = (data['raisedAmount'] as num? ?? 0).toDouble();

                  // Filter out fully funded families to save time
                  if (target <= 0 || raised >= target) return false;

                  return true;
                }).toList();

                docs.sort((a, b) {
                  final dataA = a.data() as Map<String, dynamic>;
                  final dataB = b.data() as Map<String, dynamic>;

                  final scoreA = _calculatePriority(dataA);
                  final scoreB = _calculatePriority(dataB);

                  // Sort descending by score
                  final scoreComparison = scoreB.compareTo(scoreA);
                  if (scoreComparison != 0) return scoreComparison;

                  // Tie-breaker: oldest updated first (staleness)
                  final updatedA =
                      (dataA['updatedAt'] as Timestamp?)?.toDate() ??
                      DateTime.now();
                  final updatedB =
                      (dataB['updatedAt'] as Timestamp?)?.toDate() ??
                      DateTime.now();
                  return updatedA.compareTo(updatedB);
                });

                if (docs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'All families are fully funded! No active gaps to fill.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;

                    final target =
                        ((data['assignedPackBudget'] ??
                                    data['targetAmount'] ??
                                    0)
                                as num)
                            .toDouble();
                    final raised = (data['raisedAmount'] as num? ?? 0)
                        .toDouble();
                    final gap = target - raised;
                    final progress = (raised / target).clamp(0.0, 1.0);

                    final name =
                        data['registeredName'] ??
                        data['area'] ??
                        'Family ${doc.id.substring(0, 6)}';
                    final isEmergency = data['isEmergency'] == true;

                    final isExpanded = _expandedFamilyId == doc.id;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: isExpanded
                              ? Colors.blue.shade200
                              : Colors.grey.shade200,
                          width: isExpanded ? 2 : 1,
                        ),
                      ),
                      elevation: isExpanded ? 4 : 0,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          // Auto-fill the amount when expanded
                          if (_expandedFamilyId != doc.id) {
                            _amountController.text = gap.toStringAsFixed(0);
                          }
                          setState(() {
                            _expandedFamilyId = isExpanded ? null : doc.id;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              name,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            if (isEmergency) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.red.shade100,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  'URGENT',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.red.shade800,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        // Progress Bar
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          child: LinearProgressIndicator(
                                            value: progress,
                                            backgroundColor:
                                                Colors.grey.shade200,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  isEmergency
                                                      ? Colors.red
                                                      : Colors.blue,
                                                ),
                                            minHeight: 8,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'Gap: PKR ${gap.toStringAsFixed(0)}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                color: Colors.orange.shade700,
                                              ),
                                            ),
                                            Text(
                                              '${(progress * 100).toStringAsFixed(0)}% Funded',
                                              style: const TextStyle(
                                                color: Colors.grey,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  // Fund Button toggle
                                  Icon(
                                    isExpanded
                                        ? Icons.keyboard_arrow_up
                                        : Icons.add_circle,
                                    color: isExpanded
                                        ? Colors.blue
                                        : Colors.green,
                                    size: 32,
                                  ),
                                ],
                              ),

                              // Expanded Allocation Form
                              if (isExpanded) ...[
                                const SizedBox(height: 16),
                                const Divider(),
                                const SizedBox(height: 16),
                                TextField(
                                  controller: _amountController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: InputDecoration(
                                    labelText: 'Allocation Amount',
                                    prefixText: 'PKR ',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _noteController,
                                  decoration: InputDecoration(
                                    labelText: 'Allocation Note',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: ElevatedButton(
                                    onPressed: _isProcessing
                                        ? null
                                        : () => _submitAllocation(
                                            doc.id,
                                            name,
                                            gap,
                                          ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue.shade700,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: _isProcessing
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Text(
                                            'Confirm Allocation',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
