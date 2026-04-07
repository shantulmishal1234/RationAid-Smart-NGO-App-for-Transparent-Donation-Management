import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ration_aid/services/audit_service.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:ration_aid/screens/Admin/widgets/frosted_panel.dart';
import 'package:ration_aid/screens/Admin/widgets/admin_scaffold.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODEL
// ─────────────────────────────────────────────────────────────────────────────
class _ReportData {
  // Procurement
  final int totalOrders;
  final double totalBudgetLimit;
  final double totalSpent;
  final int totalClaimed;
  final int totalPool;
  final Map<String, int> spendByStatusCount;
  final Map<String, double> spendByStatusAmount;
  final Map<String, double> spendByMonth; // e.g. "Apr 2026"
  final Map<String, _PurchaserMetrics> topPurchasers;

  // Warehouse (In-Kind & Processed)
  final int warehouseTotalItems;
  final double warehouseTotalValue;
  final int warehousePendingCount;
  final int warehouseStockedCount;
  final int warehouseDispatchedCount;
  final List<_WarehouseEntry> warehouseActiveInventory;
  final List<_ProcuredPackEntry> procuredPacks;

  final DateTime lastLoaded;

  const _ReportData({
    required this.totalOrders,
    required this.totalBudgetLimit,
    required this.totalSpent,
    required this.totalClaimed,
    required this.totalPool,
    required this.spendByStatusCount,
    required this.spendByStatusAmount,
    required this.spendByMonth,
    required this.topPurchasers,
    required this.warehouseTotalItems,
    required this.warehouseTotalValue,
    required this.warehousePendingCount,
    required this.warehouseStockedCount,
    required this.warehouseDispatchedCount,
    required this.warehouseActiveInventory,
    required this.procuredPacks,
    required this.lastLoaded,
  });
}

class _PurchaserMetrics {
  final String name;
  int ordersHandled = 0;
  double amountSpent = 0;
  double budgetSaved = 0; // budgetLimit - totalSpent for completed orders
  _PurchaserMetrics({required this.name});
}

class _ProcuredPackEntry {
  final String id;
  final String familyId;
  final String familyName;
  final String familyAddress;
  final String packName;
  final double totalSpent;
  final String status;
  final String purchaserName;
  final DateTime date;
  const _ProcuredPackEntry({
    required this.id,
    required this.familyId,
    required this.familyName,
    required this.familyAddress,
    required this.packName,
    required this.totalSpent,
    required this.status,
    required this.purchaserName,
    required this.date,
  });
}

class _WarehouseEntry {
  final String id;
  final String donationId;
  final String familyId;
  final String familyName;
  final String familyAddress;
  final String donorName;
  final double totalValue;
  final String status;
  final Map<String, dynamic> items; // the raw items map
  const _WarehouseEntry({
    required this.id,
    required this.donationId,
    required this.familyId,
    required this.familyName,
    required this.familyAddress,
    required this.donorName,
    required this.totalValue,
    required this.status,
    required this.items,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class PurchasingReportScreen extends StatefulWidget {
  const PurchasingReportScreen({super.key});

  @override
  State<PurchasingReportScreen> createState() => _PurchasingReportScreenState();
}

class _PurchasingReportScreenState extends State<PurchasingReportScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  late Future<_ReportData> _future;
  bool _exporting = false;

  static const _tabs = ['Summary', 'Procurement', 'Warehouse'];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _tabs.length, vsync: this);
    _future = _load();
    AuditService.logSystemAction(
      action: 'Purchasing Report viewed',
      details: 'Admin opened purchasing & warehouse analytics report',
    );
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  // ── Data engine ──────────────────────────────────────────────────────────────
  Future<_ReportData> _load() async {
    final now = DateTime.now();

    // 1. Process Procurement Requests
    final procDocs = await FirebaseFirestore.instance
        .collection('procurement_requests')
        .orderBy('createdAt', descending: false)
        .get();

    int totalOrders = procDocs.docs.length;
    double totalBudget = 0;
    double totalSpent = 0;
    int claimed = 0, pool = 0;
    final Map<String, int> sCount = {};
    final Map<String, double> sAmount = {};
    final Map<String, double> monthSpend = {};
    final Map<String, _PurchaserMetrics> purchasers = {};

    for (final doc in procDocs.docs) {
      final d = doc.data();
      final status = d['status'] ?? 'pending';
      final spent = (d['totalSpent'] ?? 0).toDouble();
      final budget = (d['budgetLimit'] ?? 0).toDouble();
      final claimedId = d['claimedById'];
      final pId = d['purchaserId'] ?? claimedId;
      final pName = d['purchaserName'] ?? d['claimedByName'] ?? 'Unknown Purchaser';

      totalBudget += budget;
      totalSpent += spent;

      if (claimedId == null && status == 'pending') {
        pool++;
      } else if (claimedId != null && status == 'pending') {
        claimed++;
      }

      sCount[status] = (sCount[status] ?? 0) + 1;
      sAmount[status] = (sAmount[status] ?? 0) + spent;

      // Group by month based on purchasedAt or verifiedAt or createdAt
      final dt = (d['purchasedAt'] as Timestamp?)?.toDate() ??
          (d['createdAt'] as Timestamp?)?.toDate() ??
          now;
      final monthStr = DateFormat('MMM yyyy').format(dt);
      monthSpend[monthStr] = (monthSpend[monthStr] ?? 0) + spent;

      if (pId != null && pId.toString().isNotEmpty) {
        final pm = purchasers.putIfAbsent(pId, () => _PurchaserMetrics(name: pName));
        pm.ordersHandled++;
        pm.amountSpent += spent;
        if (status == 'verified' || status == 'delivered' || status == 'stocked') {
          pm.budgetSaved += (budget - spent).clamp(0.0, double.infinity);
        }
      }
    }

    // 2. Process Warehouse Stock
    final whDocs = await FirebaseFirestore.instance
        .collection('warehouse_stock')
        .orderBy('createdAt', descending: false)
        .get();

    // 2a. Batch fetch Family details for accurate Name and Address
    final familyIdsToFetch = <String>{};
    for (final d in procDocs.docs) {
      final fId = d.data()['familyId'];
      if (fId is String && fId.isNotEmpty && fId != 'general_relief_fund') {
        familyIdsToFetch.add(fId);
      }
    }
    for (final d in whDocs.docs) {
       final fId = d.data()['familyId'];
       if (fId is String && fId.isNotEmpty && fId != 'general_relief_fund') {
         familyIdsToFetch.add(fId);
       }
    }

    final Map<String, Map<String, dynamic>> familyCache = {};
    if (familyIdsToFetch.isNotEmpty) {
      final List<String> fIds = familyIdsToFetch.toList();
      for (int i = 0; i < fIds.length; i += 10) {
        final chunk = fIds.sublist(i, (i + 10) > fIds.length ? fIds.length : i + 10);
        final snap = await FirebaseFirestore.instance
            .collection('families')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          familyCache[doc.id] = doc.data();
        }
      }
    }

    final List<_ProcuredPackEntry> procuredPacks = [];
    for (final doc in procDocs.docs) {
      final d = doc.data();
      final status = d['status'] ?? 'pending';
      // Only show recently procured packs
      if (status == 'verified' || status == 'stocked' || status == 'delivered' || status == 'dispatched') {
        final fId = d['familyId'] ?? '';
        final fData = familyCache[fId];
        String addr = fData?['address'] ?? '';
        if (fData?['area'] != null) {
           addr = '${fData!['area']} - $addr';
        }
        final pName = d['purchaserName'] ?? d['claimedByName'] ?? 'Unknown Purchaser';
        final dt = (d['purchasedAt'] as Timestamp?)?.toDate() ??
            (d['createdAt'] as Timestamp?)?.toDate() ??
            now;

        procuredPacks.add(_ProcuredPackEntry(
          id: doc.id,
          familyId: fId,
          familyName: fData?['name'] ?? 'Unknown Family',
          familyAddress: addr.trim().isEmpty ? 'Address not provided' : addr,
          packName: d['packName'] ?? d['category'] ?? 'Assistance Pack',
          totalSpent: (d['totalSpent'] ?? 0).toDouble(),
          status: status,
          purchaserName: pName,
          date: dt,
        ));
      }
    }

    int whTotalItems = 0;
    double whTotalValue = 0;
    int pendingPickup = 0, stocked = 0, dispatched = 0;
    final List<_WarehouseEntry> activeInventory = [];

    for (final doc in whDocs.docs) {
      final d = doc.data();
      final status = d['status'] ?? 'pending';

      // Skip historical parent docs that were decomposed into splits
      if (status == 'split_source') continue;

      whTotalItems++;
      final val = (d['totalLockedValue'] ?? 0).toDouble();
      whTotalValue += val;

      if (status == 'pending_pickup') {
        pendingPickup++;
      } else if (status == 'stocked' || status == 'received' || status == 'in_transit' || status == 'grf_pool') {
         stocked++;
      } else if (status == 'dispatched') {
        dispatched++;
      }

      // Active items meaning they haven't been dispatched / fully consumed yet
      if (status != 'dispatched') {
        final fId = d['familyId'] ?? '';
        final isGrf = fId == 'general_relief_fund' || fId.isEmpty;
        final fData = familyCache[fId];
        
        // Extract area correctly if it exists
        String addr = fData?['address'] ?? '';
        if (fData?['area'] != null) {
           addr = '${fData!['area']} - $addr';
        }

        activeInventory.add(_WarehouseEntry(
          id: doc.id,
          donationId: d['donationId'] ?? doc.id,
          familyId: fId,
          familyName: isGrf ? 'GRF Pool' : (fData?['name'] ?? 'Unknown Family'),
          familyAddress: isGrf ? 'Organization Warehouse' : (addr.trim().isEmpty ? 'Address not provided' : addr),
          donorName: d['donorName'] ?? 'Unknown',
          totalValue: val,
          status: status,
          items: (d['items'] as Map?)?.cast<String, dynamic>() ?? {},
        ));
      }
    }

    return _ReportData(
      totalOrders: totalOrders,
      totalBudgetLimit: totalBudget,
      totalSpent: totalSpent,
      totalClaimed: claimed,
      totalPool: pool,
      spendByStatusCount: sCount,
      spendByStatusAmount: sAmount,
      spendByMonth: monthSpend,
      topPurchasers: purchasers,
      warehouseTotalItems: whTotalItems,
      warehouseTotalValue: whTotalValue,
      warehousePendingCount: pendingPickup,
      warehouseStockedCount: stocked,
      warehouseDispatchedCount: dispatched,
      warehouseActiveInventory: activeInventory,
      procuredPacks: procuredPacks,
      lastLoaded: now,
    );
  }

  // ── CSV Export ───────────────────────────────────────────────────────────────
  Future<void> _export(_ReportData r) async {
    if (_exporting) return;
    setState(() => _exporting = true);

    try {
      final fmt     = NumberFormat('#,##0.00');
      final dateFmt = DateFormat('dd MMM yyyy HH:mm');
      final rows    = <List<dynamic>>[];

      rows.add(['Ration Aid — Purchasing & Warehouse Analytics Report']);
      rows.add(['Generated', dateFmt.format(DateTime.now())]);
      rows.add([]);

      rows.add(['MASTER PROCUREMENT SUMMARY']);
      rows.add(['Total Orders', r.totalOrders]);
      rows.add(['Total Budget Reserved', fmt.format(r.totalBudgetLimit)]);
      rows.add(['Total Actual Spend', fmt.format(r.totalSpent)]);
      rows.add(['Orders in Pool (Unclaimed)', r.totalPool]);
      rows.add(['Orders Claimed (Processing)', r.totalClaimed]);
      rows.add([]);

      rows.add(['SPEND BY STATUS']);
      rows.add(['Status', 'Count', 'Spent PKR']);
      for (final e in r.spendByStatusCount.entries) {
        rows.add([
          e.key.toUpperCase(),
          e.value,
          fmt.format(r.spendByStatusAmount[e.key] ?? 0),
        ]);
      }
      rows.add([]);

      rows.add(['PURCHASER PERFORMANCE']);
      rows.add(['Purchaser Name', 'Orders', 'Amount Spent', 'Budget Saved']);
      final sortedPurchasers = r.topPurchasers.values.toList()
        ..sort((a, b) => b.amountSpent.compareTo(a.amountSpent)); // Top spenders first
      for (final p in sortedPurchasers) {
        rows.add([
          p.name, p.ordersHandled, fmt.format(p.amountSpent), fmt.format(p.budgetSaved),
        ]);
      }
      rows.add([]);

      rows.add(['WAREHOUSE METRICS']);
      rows.add(['Total Stocked Entries (All Time)', r.warehouseTotalItems]);
      rows.add(['Total Value Processed', fmt.format(r.warehouseTotalValue)]);
      rows.add(['Active in Warehouse', r.warehouseStockedCount]);
      rows.add(['Pending Pickup', r.warehousePendingCount]);
      rows.add(['Dispatched/Completed', r.warehouseDispatchedCount]);
      rows.add([]);

      rows.add(['RAW PROCUREMENT LEDGER']);
      rows.add([
        'ID', 'Family ID', 'Category', 'Budget Liimit', 'Total Spent',
        'Status', 'Purchaser', 'Created At', 'Verified At',
      ]);
      final p = await FirebaseFirestore.instance
          .collection('procurement_requests')
          .orderBy('createdAt', descending: true)
          .get();
      for (final doc in p.docs) {
        final d = doc.data();
        rows.add([
          doc.id, d['familyId'] ?? '', d['category'] ?? '',
          fmt.format(d['budgetLimit'] ?? 0), fmt.format(d['totalSpent'] ?? 0),
          d['status'] ?? '', d['purchaserName'] ?? d['claimedByName'] ?? '',
          (d['createdAt'] as Timestamp?)?.toDate().toIso8601String() ?? '',
          (d['verifiedAt'] as Timestamp?)?.toDate().toIso8601String() ?? '',
        ]);
      }

      final csv  = const ListToCsvConverter().convert(rows);
      final dir  = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/Purchasing_Report_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString(csv);
      await OpenFile.open(file.path);

      await AuditService.logSystemAction(
        action: 'Purchasing Report exported',
        details: 'CSV: ${file.path}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Export failed: $e'),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ── BUILD ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ReportData>(
      future: _future,
      builder: (_, snap) {
        final r       = snap.data;
        final loading = snap.connectionState == ConnectionState.waiting;

        return AdminScaffold(
          title: 'Purchasing & Warehouse',
          actions: [
            if (r != null)
              _exporting
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                    )
                  : IconButton(
                      icon: const Icon(Icons.download_rounded),
                      tooltip: 'Export CSV',
                      onPressed: () => _export(r),
                    ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh',
              onPressed: () => setState(() { _future = _load(); }),
            ),
          ],
          appBarBottom: TabBar(
            controller: _tab,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            labelStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            dividerColor: Colors.transparent,
            tabs: _tabs.map((t) => Tab(text: t)).toList(),
          ),
          body: loading
              ? const _LoadingView()
              : snap.hasError
                  ? _ErrorView(error: snap.error.toString())
                  : TabBarView(
                      controller: _tab,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _SummaryTab(r: r!),
                        _ProcurementTab(r: r),
                        _WarehouseTab(r: r),
                      ],
                    ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 1 — SUMMARY
// ─────────────────────────────────────────────────────────────────────────────
class _SummaryTab extends StatelessWidget {
  const _SummaryTab({required this.r});
  final _ReportData r;

  @override
  Widget build(BuildContext ctx) {
    // Sort months strictly by date descending
    final sortedMonths = r.spendByMonth.entries.toList()
      ..sort((a, b) {
        try {
          final da = DateFormat('MMM yyyy').parse(a.key);
          final db = DateFormat('MMM yyyy').parse(b.key);
          return db.compareTo(da);
        } catch (_) {
          return 0;
        }
      });

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Total Spend Hero
          _HeroCard(
            title: 'Total Actual Spend',
            amount: r.totalSpent,
            timestamp: r.lastLoaded,
            pills: [
              _HeroPill('${r.totalOrders} Orders', Colors.orange),
              _HeroPill('${r.warehouseActiveInventory.length} Warehouse', Colors.teal),
            ],
            gradient: const [Color(0xFF00838F), Color(0xFF006064)],
          ),
          const SizedBox(height: 16),

          // 4 KPI Grid
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.7,
            children: [
              _KpiCard('Reserved Budget', _rs(r.totalBudgetLimit), Icons.account_balance_wallet, Colors.blue),
              _KpiCard('Stock Value', _rs(r.warehouseTotalValue), Icons.inventory, Colors.teal),
              _KpiCard('Orders In Pool', r.totalPool.toString(), Icons.pending_actions, Colors.orange),
              _KpiCard('Orders Claimed', r.totalClaimed.toString(), Icons.assignment_turned_in, Colors.indigo),
            ],
          ),
          const SizedBox(height: 22),

          // Monthly Spend 
          _SecHeader(icon: Icons.calendar_month, title: 'Spend by Month'),
          const SizedBox(height: 10),
          _InfoTable(
            rows: sortedMonths.map((e) => _Row(e.key, _rs(e.value), Colors.deepPurple)).toList().isNotEmpty
                ? sortedMonths.map((e) => _Row(e.key, _rs(e.value), Colors.deepPurple)).toList()
                : [const _Row('No spend recorded', '-', Colors.grey)],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 2 — PROCUREMENT
// ─────────────────────────────────────────────────────────────────────────────
class _ProcurementTab extends StatelessWidget {
  const _ProcurementTab({required this.r});
  final _ReportData r;

  @override
  Widget build(BuildContext ctx) {
    final sortedStatuses = r.spendByStatusCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
      
    final sortedPurchasers = r.topPurchasers.values.toList()
      ..sort((a, b) => b.amountSpent.compareTo(a.amountSpent));

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SecHeader(icon: Icons.pie_chart, title: 'Spend by Order Status'),
          const SizedBox(height: 10),
          _InfoTable(
            rows: sortedStatuses.map((e) {
              final amt = r.spendByStatusAmount[e.key] ?? 0;
              return _Row(e.key.toUpperCase(), _rs(amt), Colors.blue, sub: '${e.value} orders');
            }).toList(),
          ),
          const SizedBox(height: 24),

          _SecHeader(icon: Icons.group, title: 'Purchaser Performance', color: Colors.indigo),
          const SizedBox(height: 10),
          _InfoTable(
            rows: sortedPurchasers.map((p) {
              return _Row(p.name, _rs(p.amountSpent), Colors.indigo, sub: '${p.ordersHandled} orders handled · Saved: ${_rs(p.budgetSaved)}');
            }).toList(),
          ),
          const SizedBox(height: 24),

          _SecHeader(icon: Icons.shopping_bag, title: 'Procured Packs', color: Colors.blueGrey, subtitle: '${r.procuredPacks.length} active or recent orders'),
          const SizedBox(height: 10),
          
          if (r.procuredPacks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No recent procurements.', style: TextStyle(color: Colors.grey)),
            ),
          
          ...r.procuredPacks.map((pack) {
            final isGrf = pack.familyId == 'general_relief_fund' || pack.familyId.isEmpty;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Theme.of(ctx).dividerColor.withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                       Container(
                         padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                         decoration: BoxDecoration(
                           color: Colors.blueGrey.withValues(alpha: 0.15),
                           borderRadius: BorderRadius.circular(6),
                         ),
                         child: Text(pack.packName.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                       ),
                       Text(_rs(pack.totalSpent), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(isGrf ? Icons.corporate_fare : Icons.family_restroom, size: 16, color: isGrf ? Colors.purple : Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          pack.familyName,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isGrf ? Colors.purple : Colors.blue),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                       Icon(Icons.location_on, size: 14, color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.5)),
                       const SizedBox(width: 8),
                       Expanded(
                         child: Text(pack.familyAddress, style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.8)),
                           maxLines: 2, overflow: TextOverflow.ellipsis,
                         ),
                       ),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    children: [
                       Icon(Icons.person, size: 14, color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.5)),
                       const SizedBox(width: 6),
                       Text('Purchaser: ${pack.purchaserName}', style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.7))),
                       const Spacer(),
                       Text('STATUS: ${pack.status.toUpperCase()}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: pack.status == 'stocked' ? Colors.green : Colors.orange)),
                    ]
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 3 — WAREHOUSE
// ─────────────────────────────────────────────────────────────────────────────
class _WarehouseTab extends StatelessWidget {
  const _WarehouseTab({required this.r});
  final _ReportData r;

  @override
  Widget build(BuildContext ctx) {
     final theme = Theme.of(ctx);
     
     // 1. Group active inventory by donationId
     final Map<String, List<_WarehouseEntry>> groupedByDonation = {};
     for (final e in r.warehouseActiveInventory) {
       groupedByDonation.putIfAbsent(e.donationId, () => []).add(e);
     }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // KPI mini-row
          Row(
            children: [
               Expanded(child: _KpiCard('Pending Pickup', r.warehousePendingCount.toString(), Icons.airport_shuttle, Colors.deepOrange)),
               const SizedBox(width: 10),
               Expanded(child: _KpiCard('Dispatched', r.warehouseDispatchedCount.toString(), Icons.local_shipping, Colors.green)),
            ],
          ),
          const SizedBox(height: 24),

          _SecHeader(
            icon: Icons.inventory_2, 
            title: 'Active Warehouse Stock', 
            color: Colors.teal,
            subtitle: '${groupedByDonation.length} original donations (${r.warehouseActiveInventory.length} splits in warehouse)'
          ),
          const SizedBox(height: 10),

          ...groupedByDonation.entries.map((group) {
             final donationId = group.key;
             final splits = group.value;
             final double totalDonationValue = splits.fold(0.0, (s, e) => s + e.totalValue);
             final String donorName = splits.isNotEmpty ? splits.first.donorName : 'Unknown';
             
             // Combine items simply for the header
             final Map<String, int> combinedItems = {};
             for (final split in splits) {
                split.items.forEach((k, v) {
                   if (v != null && v.toString() != '0') {
                      final val = (num.tryParse(v.toString()) ?? 0).toInt();
                      combinedItems[k] = (combinedItems[k] ?? 0) + val;
                   }
                });
             }

             return Padding(
               padding: const EdgeInsets.only(bottom: 12),
               child: FrostedPanel(
                  padding: EdgeInsets.zero, // We use ExpansionTile padding
                  child: Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      childrenPadding: const EdgeInsets.only(bottom: 12),
                      title: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                            Row(
                               children: [
                                  Container(
                                     padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                     decoration: BoxDecoration(
                                        color: Colors.teal.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                     ),
                                     child: Text('DONATION: ${donationId.substring(0, donationId.length.clamp(0, 5)).toUpperCase()}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.teal)),
                                  ),
                                  const Spacer(),
                                  Text(_rs(totalDonationValue), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.teal)),
                               ]
                            ),
                            const SizedBox(height: 8),
                            Text('Donor: $donorName', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(
                              combinedItems.entries.map((e) => '${e.value} ${e.key}').join(' • '),
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                            ),
                         ],
                      ),
                      children: splits.map((split) {
                        final isGrf = split.familyId == 'general_relief_fund' || split.familyId.isEmpty;
                        
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Icon(isGrf ? Icons.corporate_fare : Icons.family_restroom, 
                                          size: 14, color: isGrf ? Colors.purple : Colors.blue),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            split.familyName,
                                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: isGrf ? Colors.purple : Colors.blue),
                                            maxLines: 1, overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(_rs(split.totalValue), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.location_on, size: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      split.familyAddress,
                                      style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                                      maxLines: 2, overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: split.items.entries.where((e) => e.value.toString() != '0').map((e) => Container(
                                   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                   decoration: BoxDecoration(
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(6),
                                   ),
                                   child: Text('${e.key}: ${e.value}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                                )).toList(),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
               ),
             );
          }),
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// SHARED UI COMPONENTS
// ─────────────────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.title, required this.amount, required this.timestamp, required this.pills, required this.gradient});
  final String title;
  final double amount;
  final DateTime timestamp;
  final List<Widget> pills;
  final List<Color> gradient;

  @override
  Widget build(BuildContext ctx) {
    final timeFmt = DateFormat('d MMM yyyy  h:mm a');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: gradient.first.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.stacked_bar_chart_rounded, color: Colors.white70, size: 16),
          const SizedBox(width: 6),
          Text(title,
              style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('Live',
                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(_rs(amount),
            style: const TextStyle(
                color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        const SizedBox(height: 8),
        Row(children: [
           for (int i=0; i<pills.length; i++) ...[
              pills[i],
              if (i < pills.length - 1) const SizedBox(width: 6),
           ]
        ]),
        const SizedBox(height: 8),
        Text('As of ${timeFmt.format(timestamp)}',
            style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ]),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill(this.label, this.color);
  final String label;
  final Color color;
  @override
  Widget build(BuildContext ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
      );
}

class _KpiCard extends StatelessWidget {
  const _KpiCard(this.label, this.value, this.icon, this.color);
  final String label, value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext ctx) {
    final theme = Theme.of(ctx);
    return FrostedPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, color: color, size: 15),
          ),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w900, color: color, letterSpacing: -0.3),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 1),
          Text(label,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface.withValues(alpha: 0.65)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _SecHeader extends StatelessWidget {
  const _SecHeader({required this.icon, required this.title, this.color, this.subtitle});
  final IconData icon;
  final String title;
  final Color? color;
  final String? subtitle;

  @override
  Widget build(BuildContext ctx) {
    final theme = Theme.of(ctx);
    final accentColor = color ?? AppColors.primaryBlue;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Container(
        width: 4,
        height: subtitle != null ? 32 : 18,
        decoration: BoxDecoration(color: accentColor, borderRadius: BorderRadius.circular(8)),
      ),
      const SizedBox(width: 10),
      Icon(icon, color: accentColor, size: 16),
      const SizedBox(width: 6),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface)),
          if (subtitle != null)
            Text(subtitle!, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
        ],
      ),
    ]);
  }
}

class _Row {
  final String label, value;
  final Color color;
  final String? sub;
  const _Row(this.label, this.value, this.color, {this.sub});
}

class _InfoTable extends StatelessWidget {
  const _InfoTable({required this.rows});
  final List<_Row> rows;

  @override
  Widget build(BuildContext ctx) {
    final theme = Theme.of(ctx);
    return FrostedPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: rows.asMap().entries.map((e) {
          final idx = e.key;
          final row = e.value;
          return Column(children: [
            if (idx > 0) Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.45)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(children: [
                Container(
                  width: 3,
                  height: row.sub != null ? 30 : 16,
                  decoration: BoxDecoration(color: row.color.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(4)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface)),
                      if (row.sub != null)
                        Text(row.sub!, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
                    ],
                  ),
                ),
                Text(row.value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: row.color)),
              ]),
            ),
          ]);
        }).toList(),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();
  @override
  Widget build(BuildContext ctx) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Aggregating spend data…', style: TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
      );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});
  final String error;
  @override
  Widget build(BuildContext ctx) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Failed to load: $error',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.55))),
        ),
      );
}

String _rs(double v) => 'Rs ${NumberFormat('#,##0').format(v)}';
