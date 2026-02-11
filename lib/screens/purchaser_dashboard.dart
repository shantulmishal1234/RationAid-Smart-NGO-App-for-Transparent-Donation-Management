import 'package:flutter/material.dart';
import 'package:ration_aid/screens/Purchaser/models/purchaser_enums.dart';
import 'package:ration_aid/screens/Purchaser/sections/purchaser_profile_section.dart';
import 'package:ration_aid/screens/Purchaser/widgets/purchaser_bottom_nav.dart';
import 'package:ration_aid/screens/Purchaser/widgets/purchaser_scaffold.dart';
import 'package:ration_aid/screens/Purchaser/views/home_view.dart';
import 'package:ration_aid/screens/Purchaser/views/procurement_view.dart';
import 'package:ration_aid/screens/Purchaser/views/inventory_view.dart';
import 'package:ration_aid/screens/Purchaser/views/history_view.dart'; // Ensure this matches filename

class PurchaserDashboard extends StatefulWidget {
  const PurchaserDashboard({super.key});

  @override
  State<PurchaserDashboard> createState() => _PurchaserDashboardState();
}

class _PurchaserDashboardState extends State<PurchaserDashboard> {
  PurchaserSection _currentSection = PurchaserSection.dashboard;

  final Map<PurchaserSection, String> _titles = {
    PurchaserSection.dashboard: 'Purchaser Dashboard',
    PurchaserSection.procurement: 'Procurement',
    PurchaserSection.inventory: 'Inventory & Stock',
    PurchaserSection.history: 'Purchase History',
    PurchaserSection.profile: 'My Profile',
  };

  @override
  Widget build(BuildContext context) {
    return PurchaserScaffold(
      title: _titles[_currentSection]!,
      showBackButton: false,
      useSafeArea: false,
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 80), // Nav bar spacing
            child: _buildBody(),
          ),
        ],
      ),
      bottomNavigationBar: PurchaserBottomNav(
        currentSection: _currentSection,
        onSectionChanged: (section) {
          setState(() {
            _currentSection = section;
          });
        },
      ),
    );
  }

  Widget _buildBody() {
    return SafeArea(bottom: false, child: _buildSectionView());
  }

  Widget _buildSectionView() {
    switch (_currentSection) {
      case PurchaserSection.dashboard:
        return PurchaserHomeView(
          onSectionChange: (section) =>
              setState(() => _currentSection = section),
        );
      case PurchaserSection.procurement:
        return const ProcurementView();
      case PurchaserSection.inventory:
        return const InventoryView();
      case PurchaserSection.history:
        return const HistoryView();
      case PurchaserSection.profile:
        return const PurchaserProfileSection();
    }
  }
}
