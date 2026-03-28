import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:ration_aid/screens/Admin/widgets/frosted_panel.dart';
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text(
          'GRF Financial Audit',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: AppColors.primaryBlue,
              ),
              labelColor: Colors.white,
              unselectedLabelColor: isDark ? Colors.white60 : Colors.black54,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(
                  child: Text(
                    'Incoming',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
                Tab(
                  child: Text(
                    'Outgoing',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _buildPremiumHeader(),
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

  Widget _buildPremiumHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      child: FrostedPanel(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AVAILABLE BALANCE',
                      style: TextStyle(
                        color: AppColors.primaryBlue.withValues(alpha: 0.8),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'PKR ${widget.currentBalance.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: AppColors.primaryBlue,
                    size: 30,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                _buildMiniStat(
                  'Donations',
                  Icons.arrow_downward_rounded,
                  AppColors.donorGreen,
                  'Total In',
                ),
                const SizedBox(width: 12),
                _buildMiniStat(
                  'Allocations',
                  Icons.arrow_upward_rounded,
                  Colors.orange,
                  'Total Out',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, IconData icon, Color color, String sub) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.1), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              sub,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncomingLedger() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('donations')
          .where('familyId', isEqualTo: 'general_relief_fund')
          .where('status', isEqualTo: 'verified')
          .orderBy('updatedAt', descending: true)
          .limit(100)
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

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          itemCount: displayDocs.length,
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
      stream: FirebaseFirestore.instance
          .collection('donations')
          .where('isGrfAllocation', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(100)
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

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          itemCount: displayDocs.length,
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
          Icon(icon, size: 64, color: Colors.grey.withValues(alpha: 0.2)),
          const SizedBox(height: 24),
          Text(
            message,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.grey,
              fontWeight: FontWeight.w600,
            ),
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

    final color = widget.isIncoming ? AppColors.donorGreen : Colors.redAccent;
    final icon = widget.isIncoming
        ? Icons.add_circle_outline_rounded
        : Icons.remove_circle_outline_rounded;
    final prefix = widget.isIncoming ? '+' : '-';

    return FrostedPanel(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(icon, color: color, size: 22),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              letterSpacing: -0.3,
                              color: theme.colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.date,
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$prefix PKR ${widget.amount.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: color,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Icon(
                          _isExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: Colors.grey.withValues(alpha: 0.5),
                        ),
                      ],
                    ),
                  ],
                ),
                if (_isExpanded) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.03)
                          : Colors.black.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: widget.details
                          .map(
                            (detail) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 90,
                                    child: Text(
                                      detail.label,
                                      style: TextStyle(
                                        color: Colors.grey.shade500,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      detail.value,
                                      style: TextStyle(
                                        color: theme.colorScheme.onSurface,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
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
