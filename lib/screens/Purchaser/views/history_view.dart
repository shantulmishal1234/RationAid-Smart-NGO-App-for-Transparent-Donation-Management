import 'package:flutter/material.dart';
import 'package:ration_aid/models/procurement_model.dart';
import 'package:ration_aid/services/procurement_service.dart';
import 'package:ration_aid/screens/Purchaser/widgets/procurement_card.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:intl/intl.dart';

class HistoryView extends StatefulWidget {
  const HistoryView({super.key});

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  String _filterStatus = 'All'; // All, Verified, Rejected
  final List<String> _filters = ['All', 'Verified', 'Rejected'];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filter Chips
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Theme.of(context).cardColor,
          child: Row(
            children: _filters.map((filter) {
              final isSelected = _filterStatus == filter;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(filter),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      _filterStatus = filter;
                    });
                  },
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  selectedColor: AppColors.purchaserOrange.withOpacity(0.2),
                  labelStyle: TextStyle(
                    color: isSelected
                        ? AppColors.purchaserOrange
                        : Colors.grey[600],
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSelected
                          ? AppColors.purchaserOrange
                          : Colors.grey[300]!,
                    ),
                  ),
                  showCheckmark: false,
                ),
              );
            }).toList(),
          ),
        ),

        Expanded(
          child: StreamBuilder<List<ProcurementRequest>>(
            stream: ProcurementService.getAllRequestsStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final allRequests = snapshot.data ?? [];

              // Filter logic for History: show only finalized items (Verified, Rejected)
              // Or maybe show everything?
              // Request says "Past purchases".
              // "Pending" and "Purchased" (Under Review) are active, not history.
              // So history = verified or rejected (final states).

              final historyRequests = allRequests.where((r) {
                final isFinal =
                    r.status == ProcurementStatus.verified ||
                    r.status == ProcurementStatus.rejected;
                if (!isFinal) return false;

                if (_filterStatus == 'All') return true;
                if (_filterStatus == 'Verified')
                  return r.status == ProcurementStatus.verified;
                if (_filterStatus == 'Rejected')
                  return r.status == ProcurementStatus.rejected;
                return true;
              }).toList();

              if (historyRequests.isEmpty) {
                return const Center(child: Text('No history found'));
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: historyRequests.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final request = historyRequests[index];
                  return ProcurementCard(
                    request: request,
                    actionLabel: 'Details',
                    onTap: () {
                      // Show details dialog or screen
                      _showDetailsDialog(context, request);
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showDetailsDialog(BuildContext context, ProcurementRequest request) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(request.packName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (request.verifiedAt != null)
              Text(
                'Verified: ${DateFormat.yMMMd().format(request.verifiedAt!)}',
              ),
            if (request.totalSpent > 0)
              Text('Total Spent: Rs. ${request.totalSpent.toStringAsFixed(0)}'),
            if (request.adminRemarks != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Admin Note: ${request.adminRemarks}',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
