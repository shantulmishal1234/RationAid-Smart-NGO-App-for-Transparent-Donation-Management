import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ration_aid/utils/file_download_helper.dart';

class AdminGRFAuditScreen extends StatefulWidget {
  final double currentBalance;

  const AdminGRFAuditScreen({super.key, required this.currentBalance});

  @override
  State<AdminGRFAuditScreen> createState() => _AdminGRFAuditScreenState();
}

class _AdminGRFAuditScreenState extends State<AdminGRFAuditScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime dt) {
    return DateFormat('MMM d, y • h:mm a').format(dt);
  }

  Future<void> _exportToCSV() async {
    setState(() => _isExporting = true);
    try {
      final csvContent = StringBuffer();
      csvContent.writeln('Ration Aid - General Relief Fund Ledger');
      csvContent.writeln('Generated on: ${DateTime.now()}');
      csvContent.writeln(
        'Available Balance: PKR ${widget.currentBalance.toStringAsFixed(0)}',
      );
      csvContent.writeln('');

      // Fetch all incoming
      final incomingSnap = await FirebaseFirestore.instance
          .collection('donations')
          .where('familyId', isEqualTo: 'general_relief_fund')
          .where('status', isEqualTo: 'verified')
          .orderBy('updatedAt', descending: true)
          .get();

      // Fetch all outgoing
      final outgoingSnap = await FirebaseFirestore.instance
          .collection('donations')
          .where('isGrfAllocation', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .get();

      csvContent.writeln('INCOMING CONTRIBUTIONS (DONORS)');
      csvContent.writeln('Date,Donor Name,Donor Email,Amount (PKR)');
      for (var doc in incomingSnap.docs) {
        final data = doc.data();
        final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
        final name =
            (data['donorName'] as String?)?.replaceAll(',', ' ') ?? 'Anonymous';
        final email =
            (data['donorEmail'] as String?)?.replaceAll(',', ' ') ?? 'N/A';
        final date =
            (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now();
        csvContent.writeln(
          '${DateFormat('yyyy-MM-dd HH:mm:ss').format(date)},$name,$email,$amount',
        );
      }
      csvContent.writeln('');

      csvContent.writeln('OUTGOING ALLOCATIONS (ADMINS)');
      csvContent.writeln('Date,Admin UID,Target Family,Amount (PKR),Note');
      for (var doc in outgoingSnap.docs) {
        final data = doc.data();
        final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
        final family =
            (data['familyId'] as String?)?.replaceAll(',', ' ') ?? 'Unknown';
        final adminUid =
            (data['allocatedByUid'] as String?)?.replaceAll(',', ' ') ??
            'System';
        final note =
            (data['donationNote'] as String?)?.replaceAll(',', ' ') ?? '';
        final date =
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
        csvContent.writeln(
          '${DateFormat('yyyy-MM-dd HH:mm:ss').format(date)},$adminUid,$family,$amount,$note',
        );
      }

      final filePath = await FileDownloadHelper.downloadCsvFile(
        filename:
            'GRF_Ledger_Export_${DateTime.now().millisecondsSinceEpoch}.csv',
        csvContent: csvContent.toString(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ledger exported to $filePath'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GRF Financial Audit'),
        actions: [
          _isExporting
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.download_rounded),
                  tooltip: 'Export Ledger to CSV',
                  onPressed: _exportToCSV,
                ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.blue.shade700,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.blue.shade700,
          tabs: const [
            Tab(text: 'Incoming (Donors)'),
            Tab(text: 'Outgoing (Admins)'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Top Dashboard Stats
          _buildTopStatsBoard(),
          // Interactive Ledger Tabs
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildIncomingLedger(), _buildOutgoingLedger()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopStatsBoard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColorDark.withValues(alpha: 0.02),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.account_balance,
              color: Colors.blue.shade700,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Available GRF Balance',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'PKR ${widget.currentBalance.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIncomingLedger() {
    return StreamBuilder<QuerySnapshot>(
      // Querying verified donations destined for the general relief pool
      // IMPORTANT: This requires a composite index in Firebase Console.
      stream: FirebaseFirestore.instance
          .collection('donations')
          .where('familyId', isEqualTo: 'general_relief_fund')
          .where('status', isEqualTo: 'verified')
          .orderBy('updatedAt', descending: true)
          .limit(100) // Performance: Limit to 100 on initial load
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          if (snapshot.error.toString().contains('failed-precondition')) {
            return _buildIndexErrorState(context);
          }
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final displayDocs = snapshot.data?.docs ?? [];

        if (displayDocs.isEmpty) {
          return _buildEmptyState(
            'No incoming contributions yet',
            Icons.volunteer_activism,
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: displayDocs.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final data = displayDocs[index].data() as Map<String, dynamic>;
            final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
            final donorName = data['donorName'] as String? ?? 'Anonymous';
            final donorEmail = data['donorEmail'] as String? ?? 'N/A';
            final timestamp =
                (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now();
            final transactionId = displayDocs[index].id;

            return _ExpandableTransactionCard(
              isIncoming: true,
              amount: amount,
              title: donorName,
              date: _formatDate(timestamp),
              details: [
                _DetailRow('Donor Email', donorEmail),
                _DetailRow('Transaction ID', transactionId),
                _DetailRow('Time', DateFormat('HH:mm:ss a').format(timestamp)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildOutgoingLedger() {
    return StreamBuilder<QuerySnapshot>(
      // Querying explicit admin pseudo-donations mapping to out-bound GRF allocations
      // IMPORTANT: This requires a composite index in Firebase Console.
      stream: FirebaseFirestore.instance
          .collection('donations')
          .where('isGrfAllocation', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(100) // Performance: Limit to 100 on initial load
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          if (snapshot.error.toString().contains('failed-precondition')) {
            return _buildIndexErrorState(context);
          }
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final displayDocs = snapshot.data?.docs ?? [];

        if (displayDocs.isEmpty) {
          return _buildEmptyState(
            'No outgoing allocations yet',
            Icons.send_time_extension,
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: displayDocs.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final data = displayDocs[index].data() as Map<String, dynamic>;
            final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
            final targetFamily =
                data['familyId'] as String? ?? 'Unknown Family';
            final note = data['donationNote'] as String? ?? 'No note';
            final adminUid = data['allocatedByUid'] as String? ?? 'System';
            final timestamp =
                (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
            final idempotencyKey = data['idempotencyKey'] as String? ?? 'N/A';

            return _ExpandableTransactionCard(
              isIncoming: false,
              amount: amount,
              title: targetFamily,
              date: _formatDate(timestamp),
              details: [
                _DetailRow('Admin ID', adminUid),
                _DetailRow('Note', note),
                _DetailRow('Receipt Key', idempotencyKey),
                _DetailRow('Time', DateFormat('HH:mm:ss a').format(timestamp)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: Colors.grey.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildIndexErrorState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 64,
            color: Colors.orange,
          ),
          const SizedBox(height: 16),
          const Text(
            'Firebase Index Required',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Wait 2 minutes for the Firebase Index to build! See Debug Console for details.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

// ── CUSTOM COMPONENTS ────────────────────────────────────────────────────────

class _DetailRow {
  final String label;
  final String value;
  _DetailRow(this.label, this.value);
}

class _ExpandableTransactionCard extends StatefulWidget {
  final bool isIncoming;
  final double amount;
  final String title;
  final String date;
  final List<_DetailRow> details;

  const _ExpandableTransactionCard({
    required this.isIncoming,
    required this.amount,
    required this.title,
    required this.date,
    required this.details,
  });

  @override
  State<_ExpandableTransactionCard> createState() =>
      _ExpandableTransactionCardState();
}

class _ExpandableTransactionCardState
    extends State<_ExpandableTransactionCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final color = widget.isIncoming ? Colors.green : Colors.red;
    final icon = widget.isIncoming
        ? Icons.south_west_rounded
        : Icons.north_east_rounded;
    final prefix = widget.isIncoming ? '+' : '-';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isExpanded
              ? color.withValues(alpha: 0.5)
              : theme.dividerColor.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Area
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.date,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '$prefix PKR ${widget.amount.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                // Expandable Detail Area
                if (_isExpanded) ...[
                  const SizedBox(height: 16),
                  Divider(
                    color: theme.dividerColor.withValues(alpha: 0.1),
                    height: 1,
                  ),
                  const SizedBox(height: 12),
                  ...widget.details.map(
                    (detail) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 100,
                            child: Text(
                              detail.label,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              detail.value,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
