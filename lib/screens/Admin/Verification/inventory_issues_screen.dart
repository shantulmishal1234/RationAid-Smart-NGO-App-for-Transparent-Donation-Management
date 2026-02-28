import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ration_aid/models/procurement_model.dart';
import 'package:ration_aid/screens/Admin/widgets/frosted_panel.dart';
// Removed AdminScaffold import
import 'package:ration_aid/services/audit_service.dart';
import 'package:intl/intl.dart';

class InventoryIssuesScreen extends StatefulWidget {
  const InventoryIssuesScreen({super.key});

  @override
  State<InventoryIssuesScreen> createState() => _InventoryIssuesScreenState();
}

class _InventoryIssuesScreenState extends State<InventoryIssuesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Text(
              'Inventory Issues',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),

        Expanded(
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                // Summary Dashboard (Sticky)
                _buildSummaryDashboard(theme),

                // Tabs
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.dividerColor.withValues(alpha: 0.1),
                    ),
                  ),
                  child: TabBar(
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      color: theme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.primaryColor.withValues(alpha: 0.2),
                      ),
                    ),
                    labelColor: theme.primaryColor,
                    unselectedLabelColor: theme.hintColor,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    tabs: const [
                      Tab(text: 'Pending Actions'),
                      Tab(text: 'Resolution History'),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Tab Views
                Expanded(
                  child: FrostedPanel(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    padding: EdgeInsets.zero,
                    child: TabBarView(
                      children: [
                        _buildPendingList(theme),
                        _buildHistoryList(theme),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryDashboard(ThemeData theme) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('procurement_requests')
          .where('status', isEqualTo: 'issue_reported')
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        double totalRiskValue = 0;
        for (var doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          totalRiskValue += (data['totalSpent'] ?? 0).toDouble();
        }

        return FrostedPanel(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pending Issues',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${docs.length}',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 40, color: theme.dividerColor),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Value at Risk',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Rs ${totalRiskValue.toStringAsFixed(0)}',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPendingList(ThemeData theme) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('procurement_requests')
          .where('status', isEqualTo: 'issue_reported')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return _buildEmptyState(theme, 'No pending issues');

        // Client-side sorting to handle documents without 'issueReportedAt'
        final requests = docs
            .map((doc) => ProcurementRequest.fromFirestore(doc))
            .toList();
        requests.sort((a, b) {
          final aTime = a.issueReportedAt ?? DateTime(0);
          final bTime = b.issueReportedAt ?? DateTime(0);
          return bTime.compareTo(aTime); // Descending
        });

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: requests.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final request = requests[index];
            return _buildIssueCard(theme, request, isHistory: false);
          },
        );
      },
    );
  }

  Widget _buildHistoryList(ThemeData theme) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('procurement_requests')
          .where('status', whereIn: ['written_off', 'verified'])
          .limit(100)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return _buildEmptyState(theme, 'No history found');

        // Client-side sorting for history
        final requests = docs
            .map((doc) => ProcurementRequest.fromFirestore(doc))
            .where(
              (request) =>
                  request.resolutionAction != null ||
                  request.reviewStatus == 'issue_ignored',
            )
            .toList();

        requests.sort((a, b) {
          final aTime = a.resolvedAt ?? DateTime(0);
          final bTime = b.resolvedAt ?? DateTime(0);
          return bTime.compareTo(aTime); // Descending
        });

        if (requests.isEmpty)
          return _buildEmptyState(theme, 'No history found');

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: requests.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final request = requests[index];
            return _buildIssueCard(theme, request, isHistory: true);
          },
        );
      },
    );
  }

  Widget _buildEmptyState(ThemeData theme, String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 48,
            color: theme.disabledColor.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(color: theme.disabledColor, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildIssueCard(
    ThemeData theme,
    ProcurementRequest request, {
    required bool isHistory,
  }) {
    final currencyFormat = NumberFormat.currency(
      locale: 'en_PK',
      symbol: 'Rs. ',
      decimalDigits: 0,
    );

    Color statusColor = Colors.orange;
    IconData statusIcon = Icons.warning_amber_rounded;
    String statusLabel = (request.issueType ?? 'Unknown').toUpperCase();

    if (isHistory) {
      if (request.status == ProcurementStatus.written_off) {
        statusColor = Colors.red;
        statusIcon = Icons.remove_circle_outline;
        statusLabel = 'WRITTEN OFF';
      } else {
        statusColor = Colors.green;
        statusIcon = Icons.check_circle_outline;
        statusLabel = 'DISMISSED';
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Reporter & Time
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: theme.colorScheme.primary.withValues(
                  alpha: 0.1,
                ),
                child: Text(
                  (request.issueReportedBy ?? 'U')[0].toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.issueReportedBy ?? 'Unknown User',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      _getTimeAgo(request.issueReportedAt ?? DateTime.now()),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.hintColor,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              // Risk Value
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  currencyFormat.format(request.totalSpent),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),

          // Body: Issue Details
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(statusIcon, color: statusColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.5),
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            request.packName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      request.issueReason ?? "No reason provided",
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Footer: Actions or Resolution Info
          if (!isHistory) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _resolveIssue(request, 'ignore'),
                  style: TextButton.styleFrom(foregroundColor: theme.hintColor),
                  child: const Text('Dismiss'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _showWriteOffConfirmation(request),
                  icon: const Icon(Icons.delete_forever, size: 16),
                  label: const Text('Write Off'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(Icons.history, size: 14, color: theme.hintColor),
                  const SizedBox(width: 6),
                  Text(
                    'Resolved ${_getTimeAgo(request.resolvedAt ?? DateTime.now())}',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.hintColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showWriteOffConfirmation(ProcurementRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Write-off'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to write off this stock?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'This action cannot be undone and will record a financial loss.',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Loss Value: Rs ${request.totalSpent.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Resolution Note (Optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (value) {
                // Store note logic if needed, simplify for now
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirm Write-off'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _resolveIssue(request, 'write_off');
    }
  }

  Future<void> _resolveIssue(ProcurementRequest request, String action) async {
    try {
      if (action == 'write_off') {
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
        await _firestore
            .collection('procurement_requests')
            .doc(request.id)
            .update({
              'status': 'verified',
              'reviewStatus': 'issue_ignored',
              'resolvedAt': FieldValue.serverTimestamp(),
              'resolutionAction': 'ignored',
            });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'write_off' ? 'Stock Written Off' : 'Issue Dismissed',
            ),
            backgroundColor: action == 'write_off' ? Colors.red : Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  String _getTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inDays > 7) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}
