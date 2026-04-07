import 'package:flutter/material.dart';

import 'package:ration_aid/models/procurement_model.dart';
import 'package:ration_aid/services/procurement_service.dart';
import 'package:ration_aid/screens/Admin/widgets/frosted_panel.dart';
import 'package:intl/intl.dart';
import 'package:ration_aid/screens/Admin/utils/admin_cache.dart';
import 'package:ration_aid/screens/Purchaser/widgets/receipt_viewer_screen.dart';

import 'package:ration_aid/theme/app_colors.dart';

enum PurchaseFilter { toVerify, pending, completed, rejected }

class PurchaseApprovalScreen extends StatefulWidget {
  const PurchaseApprovalScreen({super.key});

  @override
  State<PurchaseApprovalScreen> createState() => _PurchaseApprovalScreenState();
}

class _PurchaseApprovalScreenState extends State<PurchaseApprovalScreen> {
  bool _isProcessing = false;

  PurchaseFilter _currentFilter = PurchaseFilter.toVerify;
  String _searchQuery = '';
  late final Stream<List<ProcurementRequest>> _requestsStream;

  @override
  void initState() {
    super.initState();
    _requestsStream = ProcurementService.getAllRequestsStream()
        .asBroadcastStream();
  }

  final currencyFormat = NumberFormat.currency(
    locale: 'en_PK',
    symbol: 'Rs. ',
    decimalDigits: 0,
  );

  Color themeModeColor(BuildContext context, Color light, Color dark) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  void _showVerificationDialog(ProcurementRequest request) {
    final difference = request.budgetLimit - request.totalSpent;
    final isUnderBudget = difference >= 0;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.verified_user, color: Colors.green),
            const SizedBox(width: 8),
            const Text(
              'Confirm Stock-In?',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to verify this purchase? This will permanently add the items to warehouse inventory and deduct the final spent amount from the family\'s raised funds.',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: themeModeColor(
                  context,
                  isUnderBudget
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
                  isUnderBudget
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isUnderBudget
                      ? Colors.green.withValues(alpha: 0.3)
                      : Colors.red.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isUnderBudget ? Icons.savings : Icons.warning_amber_rounded,
                    color: isUnderBudget ? Colors.green[700] : Colors.red[700],
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isUnderBudget
                          ? 'Saved ${currencyFormat.format(difference)} (Refunding to GRF Pool)'
                          : 'Deficit of ${currencyFormat.format(difference.abs())} (Deducting from GRF Pool)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isUnderBudget
                            ? Colors.green[800]
                            : Colors.red[800],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: _isProcessing
                ? null
                : () async {
                    setState(() => _isProcessing = true);
                    if (dialogContext.mounted) Navigator.pop(dialogContext);

                    try {
                      await ProcurementService.adminVerifyPurchase(request.id);
                      AdminCache.invalidate(CacheKeys.dashboardStats);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.white),
                              SizedBox(width: 8),
                              Text('Stock successfully verified & added!'),
                            ],
                          ),
                          backgroundColor: Colors.green,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    } finally {
                      if (mounted) setState(() => _isProcessing = false);
                    }
                  },
            icon: const Icon(Icons.check),
            label: const Text('Verify & Stock-In'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showRejectDialog(ProcurementRequest request) {
    final reasonController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.cancel_outlined,
                    color: Colors.red,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Reject Purchase',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Please provide a clear reason for rejecting this purchase. The purchaser will be notified to correct the issue.',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: reasonController,
                autofocus: true,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'Rejection Reason',
                  hintText:
                      'e.g., Receipt image is blurry, costs do not match items.',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red, width: 2),
                  ),
                  filled: true,
                  fillColor: Theme.of(context).cardColor,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final reason = reasonController.text.trim();
                        if (reason.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter a rejection reason.'),
                            ),
                          );
                          return;
                        }

                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                        setState(() => _isProcessing = true);

                        try {
                          await ProcurementService.adminRejectPurchase(
                            request.id,
                            reason,
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(
                                'Purchase rejected and sent back.',
                              ),
                              backgroundColor: Colors.red,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        } finally {
                          if (mounted) setState(() => _isProcessing = false);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Confirm Rejection',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Provide safe top spacing
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Text(
              'Stock Verification',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),

        // ── Collapsible Overview ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FrostedPanel(
            padding: EdgeInsets.zero,
            child: StreamBuilder<List<ProcurementRequest>>(
              stream: _requestsStream,
              builder: (context, snapshot) {
                final requests = snapshot.data ?? [];
                int total = requests.length;
                int pending = requests
                    .where((r) => r.status == ProcurementStatus.pending)
                    .length;
                int toVerify = requests
                    .where((r) => r.status == ProcurementStatus.purchased)
                    .length;
                int rejected = requests
                    .where((r) => r.status == ProcurementStatus.rejected)
                    .length;
                int completed = requests
                    .where(
                      (r) =>
                          r.status != ProcurementStatus.pending &&
                          r.status != ProcurementStatus.purchased &&
                          r.status != ProcurementStatus.rejected,
                    )
                    .length;

                return ExpansionTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  collapsedShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  title: Text(
                    'Overview & Statistics',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                  leading: Icon(
                    Icons.analytics_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: [
                        _statItem(
                          'Total',
                          total.toString(),
                          AppColors.volunteerBlue,
                        ),
                        _statItem(
                          'Pending',
                          pending.toString(),
                          Colors.amber[700]!,
                        ),
                        _statItem(
                          'To Verify',
                          toVerify.toString(),
                          Colors.blue[600]!,
                        ),
                        _statItem(
                          'Rejected',
                          rejected.toString(),
                          Colors.red[600]!,
                        ),
                        _statItem(
                          'Completed',
                          completed.toString(),
                          Colors.green[600]!,
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Search & Filter Row ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search purchases...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      filled: true,
                      fillColor: theme.brightness == Brightness.dark
                          ? const Color(0xFF1E1E1E)
                          : Colors.grey[100],
                    ),
                    onChanged: (val) {
                      setState(() => _searchQuery = val.toLowerCase().trim());
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark
                      ? const Color(0xFF1E1E1E)
                      : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: PopupMenuButton<PurchaseFilter>(
                  icon: Icon(
                    Icons.filter_list,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    size: 22,
                  ),
                  tooltip: 'Filter by Status',
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onSelected: (val) {
                    setState(() {
                      _currentFilter = val;
                    });
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: PurchaseFilter.toVerify,
                      child: Text(
                        'To Verify',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    PopupMenuItem(
                      value: PurchaseFilter.pending,
                      child: Text('Pending'),
                    ),
                    PopupMenuItem(
                      value: PurchaseFilter.completed,
                      child: Text('Completed'),
                    ),
                    PopupMenuItem(
                      value: PurchaseFilter.rejected,
                      child: Text('Rejected'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: FrostedPanel(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: EdgeInsets.zero,
            child: StreamBuilder<List<ProcurementRequest>>(
              stream: _requestsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final rawRequests = snapshot.data ?? [];

                // Filter Logic
                final filtered = rawRequests.where((r) {
                  // 1. Status Filter
                  bool statusMatches = false;
                  switch (_currentFilter) {
                    case PurchaseFilter.toVerify:
                      statusMatches = r.status == ProcurementStatus.purchased;
                      break;
                    case PurchaseFilter.pending:
                      statusMatches = r.status == ProcurementStatus.pending;
                      break;
                    case PurchaseFilter.completed:
                      statusMatches =
                          r.status != ProcurementStatus.pending &&
                          r.status != ProcurementStatus.purchased &&
                          r.status != ProcurementStatus.rejected;
                      break;
                    case PurchaseFilter.rejected:
                      statusMatches = r.status == ProcurementStatus.rejected;
                      break;
                  }
                  if (!statusMatches) return false;

                  // 2. Search Filter
                  if (_searchQuery.isEmpty) return true;
                  final query = _searchQuery.toLowerCase();
                  return r.packName.toLowerCase().contains(query) ||
                      (r.purchaserName ?? '').toLowerCase().contains(query) ||
                      r.familyAddress.toLowerCase().contains(query);
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 64,
                          color: theme.disabledColor.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No purchases found',
                          style: TextStyle(
                            color: theme.disabledColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final request = filtered[index];
                    return VerificationCard(
                      request: request,
                      onVerify: () => _showVerificationDialog(request),
                      onReject: () => _showRejectDialog(request),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

class VerificationCard extends StatelessWidget {
  final ProcurementRequest request;
  final VoidCallback onVerify;
  final VoidCallback onReject;

  const VerificationCard({
    super.key,
    required this.request,
    required this.onVerify,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = request;
    final fmt = DateFormat('MMM dd, hh:mm a');
    final currencyFormat = NumberFormat.currency(
      locale: 'en_PK',
      symbol: 'Rs. ',
      decimalDigits: 0,
    );
    final difference = r.budgetLimit - r.totalSpent;
    final isUnderBudget = difference >= 0;

    return Card(
      elevation: 1,
      shadowColor: Colors.black12,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Purchased: ${r.packName}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'For family in ${r.familyAddress}',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _chip(r.status.name),
              ],
            ),

            const SizedBox(height: 8),

            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _infoChip(
                  icon: Icons.person_outline,
                  label: r.purchaserName ?? 'Unknown Purchaser',
                  theme: theme,
                ),
                _infoChip(
                  icon: Icons.account_balance_wallet_outlined,
                  label: '${currencyFormat.format(r.totalSpent)} Spent',
                  theme: theme,
                ),
                _infoChip(
                  icon: Icons.inventory_2_outlined,
                  label: '${r.items.length} Items',
                  theme: theme,
                ),
                if (r.purchasedAt != null)
                  _infoChip(
                    icon: Icons.event,
                    label: fmt.format(r.purchasedAt!),
                    theme: theme,
                  ),
              ],
            ),

            if ((r.status == ProcurementStatus.purchased ||
                    r.status == ProcurementStatus.verified ||
                    r.status == ProcurementStatus.stocked) &&
                difference != 0) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    isUnderBudget ? Icons.arrow_downward : Icons.arrow_upward,
                    size: 14,
                    color: isUnderBudget ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      isUnderBudget
                          ? '${currencyFormat.format(difference.abs())} Variance Sent to GRF'
                          : '${currencyFormat.format(difference.abs())} Variance Deducted from GRF',
                      style: TextStyle(
                        color: isUnderBudget
                            ? Colors.green[800]
                            : Colors.red[800],
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            // Proof Preview
            if (r.receiptUrl != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ReceiptViewerScreen(networkUrl: r.receiptUrl!),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        r.receiptUrl!,
                        height: 60,
                        width: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 60,
                          width: 80,
                          color: Colors.grey[200],
                          child: const Center(
                            child: Icon(
                              Icons.broken_image,
                              color: Colors.grey,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (r.items.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.list_alt,
                                size: 12,
                                color: Colors.blueGrey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Items List',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blueGrey[700],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            r.items.map((i) => i.name).join(', '),
                            style: TextStyle(
                              fontSize: 10,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],

            if (r.status == ProcurementStatus.purchased) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.close, size: 14),
                    label: const Text('Reject', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 0,
                      ),
                      minimumSize: const Size(0, 32),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: onVerify,
                    icon: const Icon(Icons.check, size: 14),
                    label: const Text('Verify', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 0,
                      ),
                      minimumSize: const Size(0, 32),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(String status) {
    Color bg = Colors.grey;
    if (status == 'pending')
      bg = Colors.amber;
    else if (status == 'purchased')
      bg = Colors.blue;
    else if (status == 'verified' || status == 'stocked')
      bg = Colors.green;
    else if (status == 'rejected')
      bg = Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: bg.withValues(alpha: 0.2)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: bg),
      ),
    );
  }

  Widget _infoChip({
    required IconData icon,
    required String label,
    required ThemeData theme,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}
