import 'package:flutter/material.dart';
import 'package:ration_aid/models/procurement_model.dart';
import 'package:ration_aid/services/procurement_service.dart';
import 'package:ration_aid/screens/Admin/widgets/stat_card.dart';
import 'package:ration_aid/screens/Purchaser/models/purchaser_enums.dart'; // Ensure correct import if needed

class PurchaserHomeView extends StatelessWidget {
  final ValueChanged<PurchaserSection> onSectionChange;

  const PurchaserHomeView({super.key, required this.onSectionChange});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ProcurementRequest>>(
      stream:
          ProcurementService.getPendingRequestsStream(), // Get all actionable requests
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final requests = snapshot.data ?? [];

        // Calculate Stats
        final pendingCount = requests
            .where((r) => r.status == ProcurementStatus.pending)
            .length;
        final underReviewCount = requests
            .where((r) => r.status == ProcurementStatus.purchased)
            .length;
        final rejectedCount = requests
            .where((r) => r.status == ProcurementStatus.rejected)
            .length;

        // Find Urgent Items (Example logic: Pending > 3 days old or marked urgent if field existed)
        // For now, let's say rejected items are "Urgent" to retry, or oldest pending.
        final urgentItems = requests
            .where(
              (r) =>
                  r.status == ProcurementStatus.rejected ||
                  (r.status == ProcurementStatus.pending &&
                      DateTime.now().difference(r.createdAt).inDays > 3),
            )
            .take(3)
            .toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome Header
              Text(
                'Dashboard',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              // Stats Grid
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                shrinkWrap: true,
                childAspectRatio: 1.4,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  StatCard(
                    title: 'Pending',
                    value: pendingCount.toString(),
                    subtitle: 'To Purchase',
                    icon: Icons.shopping_cart_outlined,
                    color: Colors.orange,
                  ),
                  StatCard(
                    title: 'Under Review',
                    value: underReviewCount.toString(),
                    subtitle: 'Awaiting Approval',
                    icon: Icons.hourglass_top_outlined,
                    color: Colors.blue,
                  ),
                  StatCard(
                    title: 'Action Needed',
                    value: rejectedCount.toString(),
                    subtitle: 'Rejected / Retry',
                    icon: Icons.report_problem_outlined,
                    color: Colors.red,
                  ),
                  StatCard(
                    title: 'Budget Limit',
                    value: 'View', // Placeholder as budget is per request
                    subtitle: 'See details in tasks',
                    icon: Icons.attach_money,
                    color: Colors.green,
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // High Priority / Action Needed
              if (urgentItems.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.stars_rounded, color: Colors.orange),
                    const SizedBox(width: 8),
                    Text(
                      'Action Required',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: urgentItems.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = urgentItems[index];
                    return _buildUrgentItemCard(context, item);
                  },
                ),
                const SizedBox(height: 24),
              ],

              // Quick Actions
              Text(
                'Quick Actions',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildQuickActionButton(
                      context,
                      'View Pending Requests',
                      Icons.list_alt,
                      Colors.blue,
                      () => onSectionChange(PurchaserSection.procurement),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildQuickActionButton(
                      context,
                      'Check Inventory',
                      Icons.inventory_2_outlined,
                      Colors.green,
                      () => onSectionChange(PurchaserSection.inventory),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUrgentItemCard(
    BuildContext context,
    ProcurementRequest request,
  ) {
    final theme = Theme.of(context);
    final isRejected = request.status == ProcurementStatus.rejected;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRejected
              ? Colors.red.withOpacity(0.3)
              : Colors.orange.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isRejected
                  ? Colors.red.withOpacity(0.1)
                  : Colors.orange.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isRejected ? Icons.report_problem : Icons.access_time_filled,
              color: isRejected ? Colors.red : Colors.orange,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.packName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  isRejected ? 'Declined by Admin' : 'Overdue Pending',
                  style: TextStyle(
                    fontSize: 12,
                    color: isRejected ? Colors.red : Colors.orange[800],
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: theme.dividerColor),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
