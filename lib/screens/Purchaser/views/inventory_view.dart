import 'package:flutter/material.dart';
import 'package:ration_aid/models/procurement_model.dart';
import 'package:ration_aid/services/procurement_service.dart';
import 'package:ration_aid/theme/app_colors.dart';

class InventoryView extends StatelessWidget {
  const InventoryView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<List<ProcurementRequest>>(
      stream: ProcurementService.getInventoryStream(), // Fetches 'verified'
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final stockRequests = snapshot.data ?? [];

        // Group by Pack Name
        final Map<String, int> packCounts = {};
        for (var req in stockRequests) {
          packCounts[req.packName] = (packCounts[req.packName] ?? 0) + 1;
        }

        // Total Items (Simulated aggregation)
        int totalPacks = stockRequests.length;

        // Separate delivered vs available?
        // getInventoryStream filters for 'verified', which means "Stocked but not delivered".
        // Delivered items would have status 'delivered'.
        // So this view shows CURRENTLY AVAILABLE stock in warehouse.

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Overview Cards
              Row(
                children: [
                  Expanded(
                    child: _buildStockCard(
                      context,
                      'Available Packs',
                      totalPacks.toString(),
                      Icons.inventory_2,
                      Colors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Placeholder for "Reserved" logic if we had it
                  Expanded(
                    child: _buildStockCard(
                      context,
                      'Total Value',
                      'Rs. ${(stockRequests.fold(0.0, (sum, item) => sum + item.totalSpent)).toStringAsFixed(0)}',
                      Icons.monetization_on,
                      Colors.blue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              Text(
                'Stock by Pack Type',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              if (packCounts.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Text('Inventory is empty'),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: packCounts.keys.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final packName = packCounts.keys.elementAt(index);
                    final count = packCounts[packName];

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.dividerColor.withOpacity(0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.purchaserOrange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.shopping_bag_outlined,
                              color: AppColors.purchaserOrange,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  packName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  '$count units in stock',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.green.withOpacity(0.3),
                              ),
                            ),
                            child: const Text(
                              'Available',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStockCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
