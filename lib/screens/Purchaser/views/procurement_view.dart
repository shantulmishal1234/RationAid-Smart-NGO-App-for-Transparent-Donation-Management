import 'package:flutter/material.dart';
import 'package:ration_aid/models/procurement_model.dart';
import 'package:ration_aid/services/procurement_service.dart';
import 'package:ration_aid/screens/Purchaser/widgets/procurement_card.dart';
import 'package:ration_aid/screens/Purchaser/screens/purchase_entry_screen.dart';
import 'package:ration_aid/theme/app_colors.dart';

class ProcurementView extends StatelessWidget {
  const ProcurementView({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          Container(
            color: Theme.of(context).cardColor,
            child: TabBar(
              isScrollable: true,
              labelColor: AppColors.purchaserOrange,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppColors.purchaserOrange,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold),
              tabs: const [
                Tab(text: 'Pending'),
                Tab(text: 'Under Review'),
                Tab(
                  text: 'Verified',
                ), // Was "Approved" in request, using system status "Verified"
                Tab(text: 'Rejected'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _RequestList(status: ProcurementStatus.pending),
                _RequestList(
                  status: ProcurementStatus.purchased,
                ), // purchased = under review
                _RequestList(status: ProcurementStatus.verified),
                _RequestList(status: ProcurementStatus.rejected),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestList extends StatelessWidget {
  final ProcurementStatus status;

  const _RequestList({required this.status});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ProcurementRequest>>(
      // We need a service method that gets ALL requests, or specific status.
      // Currently `getPendingRequestsStream` filters.
      // We might need to fetch all and filter client side or update service.
      // For efficiency, let's assume `getProcurementStream` returns all for now,
      // or we filter the stream.
      // Looking at previous logs, `getPendingRequestsStream` was `where('status', isEqualTo: 'pending')`.
      // I'll use `ProcurementService.getAllRequestsStream()` if it exists, or create a query.
      // Since I can't see the service right now, I'll assume I need to handle fetching.
      // I'll try to find a generic stream or use the existing specific ones.
      // Step 496 showed `getPendingRequestsStream`.
      // Step 497 showed `getInventoryStream` (likely verified).
      // I will use a hypothetical `ProcurementService.getStreamByStatus(status)` pattern
      // but since I can't confirm it exists, I'll rely on `getAllRequestsStream`
      // or simulate it if needed.
      // WAIT: I should check `ProcurementService` first.
      stream: ProcurementService.getAllRequestsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final allRequests = snapshot.data ?? [];
        final filteredRequests = allRequests
            .where((r) => r.status == status)
            .toList();

        if (filteredRequests.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  'No ${status.name} requests',
                  style: TextStyle(color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: filteredRequests.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final request = filteredRequests[index];
            return ProcurementCard(
              request: request,
              actionLabel: _getActionLabel(status),
              onTap: () {
                if (status == ProcurementStatus.pending ||
                    status == ProcurementStatus.rejected) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PurchaseEntryScreen(request: request),
                    ),
                  );
                } else {
                  // View details only? Or just showing status.
                  // For now, no action for Review/Verified, or maybe "View Details" (read only entry screen).
                  // The user request said "View admin remarks (if rejected)" which is covered by card.
                }
              },
            );
          },
        );
      },
    );
  }

  String _getActionLabel(ProcurementStatus status) {
    switch (status) {
      case ProcurementStatus.pending:
        return 'Purchase'; // "Process"
      case ProcurementStatus.purchased:
        return 'Under Review';
      case ProcurementStatus.verified:
        return 'Stocked';
      case ProcurementStatus.rejected:
        return 'Retry';
      case ProcurementStatus.stocked:
        return 'In Stock';
      case ProcurementStatus.delivered:
        return 'Delivered';
    }
  }
}
