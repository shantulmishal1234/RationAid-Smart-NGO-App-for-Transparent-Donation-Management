import 'package:flutter/material.dart';
import 'package:ration_aid/models/family_model.dart';
import 'package:ration_aid/services/family_service.dart';
import 'package:ration_aid/theme/app_colors.dart';

/// Family Selection Screen - Modal screen for selecting a family to donate to
class FamilySelectionScreen extends StatefulWidget {
  const FamilySelectionScreen({super.key});

  @override
  State<FamilySelectionScreen> createState() => _FamilySelectionScreenState();
}

class _FamilySelectionScreenState extends State<FamilySelectionScreen> {
  final FamilyService _familyService = FamilyService();
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        title: const Text(
          'Select Family',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.donorGreen, AppColors.accentGreen],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by area...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),

          // Family list
          Expanded(
            child: StreamBuilder<List<Family>>(
              stream: _familyService.streamAcceptedFamilies(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                var families = snapshot.data ?? [];

                // Filter by search query
                if (_searchQuery.isNotEmpty) {
                  families = families.where((family) {
                    return family.area.toLowerCase().contains(
                      _searchQuery.toLowerCase(),
                    );
                  }).toList();
                }

                if (families.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.family_restroom,
                          size: 80,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isEmpty
                              ? 'No families available'
                              : 'No families found',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: families.length,
                  itemBuilder: (context, index) {
                    return _FamilySelectionCard(
                      family: families[index],
                      onSelect: () {
                        // Return selected family and close screen
                        Navigator.pop(context, families[index]);
                      },
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

/// Family selection card widget
class _FamilySelectionCard extends StatelessWidget {
  final Family family;
  final VoidCallback onSelect;

  const _FamilySelectionCard({required this.family, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.donorGreen.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.family_restroom,
                  color: AppColors.donorGreen,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),

              // Family info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      family.area,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Family of ${family.familySize} • ${family.needs.length} items needed',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                    if (family.targetAmount > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value:
                                    (family.raisedAmount / family.targetAmount)
                                        .clamp(0.0, 1.0),
                                backgroundColor: Colors.grey[200],
                                color: AppColors.donorGreen,
                                minHeight: 4,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${((family.raisedAmount / family.targetAmount) * 100).toInt()}%',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.donorGreen,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Select arrow
              const Icon(
                Icons.arrow_forward_ios,
                size: 18,
                color: AppColors.donorGreen,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
