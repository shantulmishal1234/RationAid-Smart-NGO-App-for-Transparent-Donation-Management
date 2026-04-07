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
// Warehouse item detail
class _ItemDetail {
  final num qty;
  final String unit;
  final double pkrValue;
  const _ItemDetail({required this.qty, required this.unit, required this.pkrValue});
}

// One stocked donation entry (for warehouse view)
class _StockedEntry {
  final String donationId;
  final String familyId;
  final String familyLabel; // display name or ID
  final String donorName;
  final String type; // 'cash' | 'inKind'
  final double value;
  final Map<String, _ItemDetail> items; // only for inKind
  const _StockedEntry({
    required this.donationId,
    required this.familyId,
    required this.familyLabel,
    required this.donorName,
    required this.type,
    required this.value,
    required this.items,
  });
}

class _ReportData {
  final int total;
  final int cashCount, inKindCount, grfCashCount, grfInKindCount;
  final double cashTotal, cashVerified, cashPending;
  final double grfCashTotal, grfOverflow;
  final double inKindTotal, inKindDirect, inKindGrf;
  final int directCount, smartCount;
  final Map<String, int> statusCounts;
  final Map<String, double> statusAmounts;
  final List<_Donor> donors;
  final List<_StockedEntry> stockedEntries; // warehouse inventory
  final DateTime lastLoaded;

  const _ReportData({
    required this.total,
    required this.cashCount,
    required this.inKindCount,
    required this.grfCashCount,
    required this.grfInKindCount,
    required this.cashTotal,
    required this.cashVerified,
    required this.cashPending,
    required this.grfCashTotal,
    required this.grfOverflow,
    required this.inKindTotal,
    required this.inKindDirect,
    required this.inKindGrf,
    required this.directCount,
    required this.smartCount,
    required this.statusCounts,
    required this.statusAmounts,
    required this.donors,
    required this.stockedEntries,
    required this.lastLoaded,
  });

  double get grandTotal => cashTotal + inKindTotal;
}

class _Donor {
  final String name;
  final String email;
  final double cash, cashVerified, inKind;
  final int count;
  final DateTime lastAt;
  double get total => cash + inKind;

  const _Donor({
    required this.name,
    required this.email,
    required this.cash,
    required this.cashVerified,
    required this.inKind,
    required this.count,
    required this.lastAt,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// STATUS METADATA
// ─────────────────────────────────────────────────────────────────────────────
class _SMeta {
  final String label;
  final Color color;
  final IconData icon;
  final bool isTerminal; // grouping
  const _SMeta(this.label, this.color, this.icon, {this.isTerminal = false});
}

const _statuses = <String, _SMeta>{
  'pending':            _SMeta('Pending',             Color(0xFFE65100),  Icons.schedule_rounded),
  'under_verification': _SMeta('Under Verification',  Color(0xFF1565C0),  Icons.manage_search_rounded),
  'pending_assignment': _SMeta('Pending Assignment',  Color(0xFFF57F17),  Icons.assignment_late_rounded),
  'stocked':            _SMeta('In Warehouse',         Color(0xFF00838F),  Icons.inventory_rounded),
  'in_process':         _SMeta('In Process',           Color(0xFF6A1B9A),  Icons.sync_rounded),
  'out_for_delivery':   _SMeta('Out for Delivery',    Color(0xFF4527A0),  Icons.delivery_dining_rounded),
  'draft':              _SMeta('Draft',                Color(0xFF616161),  Icons.edit_rounded),
  // Terminal
  'verified':           _SMeta('Verified',             Color(0xFF2E7D32),  Icons.check_circle_rounded,    isTerminal: true),
  'delivered':          _SMeta('Delivered',            Color(0xFF00796B),  Icons.local_shipping_rounded,  isTerminal: true),
  'closed':             _SMeta('Closed',               Color(0xFF546E7A),  Icons.done_all_rounded,        isTerminal: true),
  'rejected':           _SMeta('Rejected',             Color(0xFFC62828),  Icons.cancel_rounded,          isTerminal: true),
};

_SMeta _sm(String k) =>
    _statuses[k] ?? _SMeta(k, const Color(0xFF78909C), Icons.circle_outlined);

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class DonationsReportScreen extends StatefulWidget {
  const DonationsReportScreen({super.key});

  @override
  State<DonationsReportScreen> createState() => _DonationsReportScreenState();
}

class _DonationsReportScreenState extends State<DonationsReportScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  late Future<_ReportData> _future;
  bool _exporting = false;

  static const _tabs = ['Summary', 'Status', 'Donors'];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _tabs.length, vsync: this);
    _future = _load();
    AuditService.logSystemAction(
      action: 'Donations Report viewed',
      details: 'Admin opened donations analytics report',
    );
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  // ── Data engine ──────────────────────────────────────────────────────────────
  Future<_ReportData> _load() async {
    final docs = await FirebaseFirestore.instance
        .collection('donations')
        .orderBy('createdAt', descending: false)
        .get();

    final now = DateTime.now();
    int cashCount = 0, inKindCount = 0, grfCashCount = 0, grfInKindCount = 0;
    int directCount = 0, smartCount = 0;
    double cashTotal = 0, cashVerified = 0, cashPending = 0;
    double grfCashTotal = 0, grfOverflow = 0;
    double inKindTotal = 0, inKindDirect = 0, inKindGrf = 0;
    final Map<String, int>    statusCounts  = {};
    final Map<String, double>  statusAmounts = {};
    final Map<String, _MutableDonor> donorMap = {};
    final List<_StockedEntry> stockedEntries = [];

    for (final doc in docs.docs) {
      final d = doc.data();
      final String type   = d['donationType'] ?? 'cash';
      final String fid    = d['familyId'] ?? '';
      final String status = d['status'] ?? 'pending';
      final String mode   = d['allocationMode'] ?? 'direct';
      final double amt    = (d['amount'] as num?)?.toDouble() ?? 0.0;
      final double ovfl   = (d['overflowAmount'] as num?)?.toDouble() ?? 0.0;
      final bool isGrf    = fid == 'general_relief_fund' || fid.isEmpty;
      final String donorId = d['donorId'] ?? doc.id;
      final bool anon     = d['anonymous'] == true;
      final String name   = anon ? 'Anonymous' : (d['donorName'] ?? 'Unknown');
      final String email  = d['donorEmail'] ?? '';
      final DateTime createdAt =
          (d['createdAt'] as Timestamp?)?.toDate() ?? now;

      // In-kind PKR value
      double ikVal = 0;
      if (type == 'inKind') {
        final vs = d['itemValueSnapshot'];
        if (vs is Map) {
          for (final v in vs.values) {
            ikVal += (v as num?)?.toDouble() ?? 0;
          }
        }
        if (ikVal == 0) ikVal = amt;
      }

      final contribution = type == 'cash' ? amt : ikVal;

      // Cash
      if (type == 'cash') {
        cashCount++;
        cashTotal += amt;
        grfOverflow += ovfl;
        if (isGrf) { grfCashCount++; grfCashTotal += amt; }
        if (status == 'verified' || status == 'delivered' || status == 'closed') {
          cashVerified += amt;
        } else if (status == 'pending' || status == 'under_verification') {
          cashPending += amt;
        }
      } else {
        inKindCount++;
        inKindTotal += ikVal;
        if (isGrf) { grfInKindCount++; inKindGrf += ikVal; }
        else { inKindDirect += ikVal; }
      }

      if (mode == 'smart') { smartCount++; } else { directCount++; }
      statusCounts[status]  = (statusCounts[status] ?? 0) + 1;
      statusAmounts[status] = (statusAmounts[status] ?? 0) + contribution;

      // ── Warehouse inventory (stocked only) ──────────────────────────────
      if (status == 'stocked') {
        final rawItems  = d['items']             as Map? ?? {};
        final rawUnits  = d['itemUnits']          as Map? ?? {};
        final rawValues = d['itemValueSnapshot']  as Map? ?? {};
        final Map<String, _ItemDetail> itemMap = {};
        for (final k in rawItems.keys) {
          final ks = k.toString();
          itemMap[ks] = _ItemDetail(
            qty:      (rawItems[k]  as num?)    ?? 0,
            unit:     rawUnits[k]?.toString()   ?? 'unit',
            pkrValue: (rawValues[k] as num?)?.toDouble() ?? 0,
          );
        }
        final bool grfEntry = fid == 'general_relief_fund' || fid.isEmpty;
        stockedEntries.add(_StockedEntry(
          donationId:  doc.id,
          familyId:    fid,
          familyLabel: grfEntry
              ? 'GRF Pool'
              : (d['familyName']?.toString() ?? 'Family ${fid.substring(0, fid.length.clamp(0, 8))}…'),
          donorName: name,
          type:  type,
          value: type == 'cash' ? amt : ikVal,
          items: itemMap,
        ));
      }

      final acc = donorMap.putIfAbsent(
          donorId, () => _MutableDonor(name: name, email: email));
      if (type == 'cash') {
        acc.cash += amt;
        if (status == 'verified' || status == 'delivered' || status == 'closed') {
          acc.cashVerified += amt;
        }
      } else {
        acc.inKind += ikVal;
      }
      acc.count++;
      if (createdAt.isAfter(acc.lastAt)) acc.lastAt = createdAt;
    }

    final sorted = donorMap.values
        .map((a) => _Donor(
              name: a.name,
              email: a.email,
              cash: a.cash,
              cashVerified: a.cashVerified,
              inKind: a.inKind,
              count: a.count,
              lastAt: a.lastAt,
            ))
        .toList()
      ..sort((x, y) => y.total.compareTo(x.total));

    return _ReportData(
      total: docs.docs.length,
      cashCount: cashCount,
      inKindCount: inKindCount,
      grfCashCount: grfCashCount,
      grfInKindCount: grfInKindCount,
      cashTotal: cashTotal,
      cashVerified: cashVerified,
      cashPending: cashPending,
      grfCashTotal: grfCashTotal,
      grfOverflow: grfOverflow,
      inKindTotal: inKindTotal,
      inKindDirect: inKindDirect,
      inKindGrf: inKindGrf,
      directCount: directCount,
      smartCount: smartCount,
      statusCounts: statusCounts,
      statusAmounts: statusAmounts,
      donors: sorted,
      stockedEntries: stockedEntries,
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

      rows.add(['Ration Aid — Donations Analytics Report']);
      rows.add(['Generated', dateFmt.format(DateTime.now())]);
      rows.add([]);

      rows.add(['MASTER SUMMARY']);
      rows.add(['Metric', 'PKR / Count']);
      rows.add(['Grand Total (Cash + In-Kind)', fmt.format(r.grandTotal)]);
      rows.add([]);
      rows.add(['CASH']);
      rows.add(['Total Cash', fmt.format(r.cashTotal)]);
      rows.add(['Verified Cash', fmt.format(r.cashVerified)]);
      rows.add(['Pending / Under-Review', fmt.format(r.cashPending)]);
      rows.add(['GRF Direct Cash', fmt.format(r.grfCashTotal)]);
      rows.add(['GRF Overflow (Surplus)', fmt.format(r.grfOverflow)]);
      rows.add(['Cash Donation Count', r.cashCount]);
      rows.add(['GRF Cash Count', r.grfCashCount]);
      rows.add([]);
      rows.add(['IN-KIND']);
      rows.add(['Total In-Kind Value', fmt.format(r.inKindTotal)]);
      rows.add(['In-Kind → Specific Family', fmt.format(r.inKindDirect)]);
      rows.add(['In-Kind → GRF Pool', fmt.format(r.inKindGrf)]);
      rows.add(['In-Kind Donation Count', r.inKindCount]);
      rows.add(['GRF In-Kind Count', r.grfInKindCount]);
      rows.add([]);
      rows.add(['STATUS BREAKDOWN']);
      rows.add(['Status', 'Count', '%', 'Amount PKR']);
      final sByCount = r.statusCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in sByCount) {
        final pct = r.total > 0
            ? (e.value / r.total * 100).toStringAsFixed(1)
            : '0.0';
        rows.add([
          _sm(e.key).label,
          e.value,
          '$pct%',
          fmt.format(r.statusAmounts[e.key] ?? 0),
        ]);
      }
      rows.add([]);

      rows.add(['ALL DONORS (by total impact)']);
      rows.add([
        'Rank', 'Donor', 'Email', 'Cash', 'Verified Cash',
        'In-Kind', 'Transactions', 'Last Donation', 'Total Impact',
      ]);
      for (var i = 0; i < r.donors.length; i++) {
        final d = r.donors[i];
        rows.add([
          i + 1, d.name, d.email,
          fmt.format(d.cash), fmt.format(d.cashVerified), fmt.format(d.inKind),
          d.count, DateFormat('dd-MMM-yyyy').format(d.lastAt), fmt.format(d.total),
        ]);
      }
      rows.add([]);

      rows.add(['RAW TRANSACTION LEDGER']);
      rows.add([
        'ID', 'Donor', 'Email', 'Type', 'Family ID',
        'Mode', 'Amount PKR', 'Status', 'Created', 'Verified By',
      ]);
      final all = await FirebaseFirestore.instance
          .collection('donations')
          .orderBy('createdAt', descending: true)
          .get();
      for (final doc in all.docs) {
        final d = doc.data();
        double val = (d['amount'] as num?)?.toDouble() ?? 0;
        if (d['donationType'] == 'inKind') {
          final vs = d['itemValueSnapshot'];
          if (vs is Map) {
            val = vs.values
                .fold(0.0, (s, v) => s + ((v as num?)?.toDouble() ?? 0));
          }
        }
        final dt = (d['createdAt'] as Timestamp?)?.toDate();
        rows.add([
          doc.id, d['donorName'] ?? '', d['donorEmail'] ?? '',
          d['donationType'] ?? 'cash', d['familyId'] ?? '',
          d['allocationMode'] ?? 'direct', fmt.format(val),
          d['status'] ?? '',
          dt != null ? DateFormat('dd-MMM-yyyy HH:mm').format(dt) : '',
          d['verifiedBy'] ?? '',
        ]);
      }

      final csv  = const ListToCsvConverter().convert(rows);
      final dir  = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/Donations_Report_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString(csv);
      await OpenFile.open(file.path);

      await AuditService.logSystemAction(
        action: 'Donations Report exported',
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
          title: 'Donations Report',
          actions: [
            if (r != null)
              _exporting
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)),
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
                        _StatusTab(r: r),
                        _DonorsTab(r: r),
                      ],
                    ),
        );
      },
    );
  }
}

// Mutable accumulator ─────────────────────────────────────────────────────────
class _MutableDonor {
  final String name, email;
  double cash = 0, cashVerified = 0, inKind = 0;
  int count = 0;
  DateTime lastAt = DateTime(2000);
  _MutableDonor({required this.name, required this.email});
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 1 — SUMMARY
// ─────────────────────────────────────────────────────────────────────────────
class _SummaryTab extends StatelessWidget {
  const _SummaryTab({required this.r});
  final _ReportData r;

  @override
  Widget build(BuildContext ctx) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Hero card ──────────────────────────────────────────────────
          _HeroCard(r: r),
          const SizedBox(height: 16),

          // ── 4-KPI quick-glance grid ────────────────────────────────────
          _KpiGrid(r: r),
          const SizedBox(height: 22),

          // ── Cash section ───────────────────────────────────────────────
          _SecHeader(
              icon: Icons.payments_rounded, title: 'Cash Donations', color: Colors.green),
          const SizedBox(height: 10),
          _InfoTable(rows: [
            _Row('Total Cash Received',    _rs(r.cashTotal),    Colors.green),
            _Row('Verified & Cleared',     _rs(r.cashVerified), const Color(0xFF00796B)),
            _Row('Pending / Under Review', _rs(r.cashPending),  Colors.orange),
            _Row('GRF Direct Donations',   _rs(r.grfCashTotal), Colors.indigo,
                sub: '${r.grfCashCount} donations'),
            _Row('GRF Overflow (Surplus)', _rs(r.grfOverflow),  Colors.deepPurple),
          ]),
          const SizedBox(height: 22),

          // ── In-Kind section ────────────────────────────────────────────
          _SecHeader(
              icon: Icons.inventory_2_rounded,
              title: 'In-Kind Donations',
              color: Colors.amber.shade700,
              subtitle: 'PKR-equivalent values'),
          const SizedBox(height: 10),
          _InfoTable(rows: [
            _Row('Total In-Kind Value',       _rs(r.inKindTotal),   Colors.amber.shade700),
            _Row('Direct → Specific Family',  _rs(r.inKindDirect),  Colors.deepOrange,
                sub: '${r.inKindCount - r.grfInKindCount} donations'),
            _Row('GRF Pool (In-Kind)',         _rs(r.inKindGrf),     Colors.brown,
                sub: '${r.grfInKindCount} donations'),
          ]),
          const SizedBox(height: 22),

          // ── Allocation mode ────────────────────────────────────────────
          _SecHeader(
              icon: Icons.alt_route_rounded,
              title: 'Allocation Mode'),
          const SizedBox(height: 10),
          _InfoTable(rows: [
            _Row('Direct (specific family)',   r.directCount.toString(), Colors.lightBlue.shade700),
            _Row('Smart Split (waterfall)',     r.smartCount.toString(),  Colors.cyan.shade700),
          ]),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 2 — STATUS BREAKDOWN
// ─────────────────────────────────────────────────────────────────────────────
class _StatusTab extends StatelessWidget {
  const _StatusTab({required this.r});
  final _ReportData r;

  @override
  Widget build(BuildContext ctx) {
    final theme   = Theme.of(ctx);
    final entries = r.statusCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final active   = entries.where((e) => !_sm(e.key).isTerminal).toList();
    final terminal = entries.where((e) =>  _sm(e.key).isTerminal).toList();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${r.total} total donations  ·  ${entries.length} lifecycle states',
            style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
          ),
          const SizedBox(height: 14),

          if (active.isNotEmpty) ...[
            _SecHeader(
                icon: Icons.pending_actions_rounded,
                title: 'Active Pipeline',
                color: Colors.orange),
            const SizedBox(height: 10),
            _StatusGroup(entries: active, total: r.total, amounts: r.statusAmounts),
            const SizedBox(height: 20),
          ],

          if (terminal.isNotEmpty) ...[
            _SecHeader(
                icon: Icons.task_alt_rounded,
                title: 'Completed / Terminal',
                color: Colors.green),
            const SizedBox(height: 10),
            _StatusGroup(entries: terminal, total: r.total, amounts: r.statusAmounts),
          ],

          // ── Warehouse Inventory ────────────────────────────────────
          if (r.stockedEntries.isNotEmpty) ...[
            const SizedBox(height: 20),
            _SecHeader(
                icon: Icons.warehouse_rounded,
                title: 'Warehouse Inventory',
                color: const Color(0xFF00838F),
                subtitle: '${r.stockedEntries.length} reserved item sets'),
            const SizedBox(height: 10),
            _WarehouseSection(entries: r.stockedEntries),
          ],
        ],
      ),
    );
  }
}

class _StatusGroup extends StatelessWidget {
  const _StatusGroup(
      {required this.entries, required this.total, required this.amounts});
  final List<MapEntry<String, int>> entries;
  final int total;
  final Map<String, double> amounts;

  @override
  Widget build(BuildContext ctx) {
    final theme = Theme.of(ctx);
    return FrostedPanel(
      child: Column(
        children: entries.asMap().entries.map((me) {
          final idx = me.key;
          final e   = me.value;
          final m   = _sm(e.key);
          final pct = total > 0 ? e.value / total : 0.0;
          final amt = amounts[e.key] ?? 0;

          return Column(children: [
            if (idx > 0)
              Divider(
                  height: 1,
                  color: theme.dividerColor.withValues(alpha: 0.4)),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                // Icon badge
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: m.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(m.icon, color: m.color, size: 16),
                ),
                const SizedBox(width: 12),
                // Label + progress bar
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(m.label,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: theme.colorScheme.onSurface)),
                          Text(_rs(amt),
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: m.color)),
                        ],
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 4,
                          backgroundColor: m.color.withValues(alpha: 0.08),
                          valueColor:
                              AlwaysStoppedAnimation<Color>(m.color),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Count + %
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${e.value}',
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: m.color)),
                    Text('${(pct * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.45))),
                  ],
                ),
              ]),
            ),
          ]);
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WAREHOUSE SECTION
// ─────────────────────────────────────────────────────────────────────────────
class _WarehouseSection extends StatelessWidget {
  const _WarehouseSection({required this.entries});
  final List<_StockedEntry> entries;

  @override
  Widget build(BuildContext ctx) {
    final theme = Theme.of(ctx);
    // Group entries by familyLabel
    final Map<String, List<_StockedEntry>> grouped = {};
    for (final e in entries) {
      grouped.putIfAbsent(e.familyLabel, () => []).add(e);
    }

    return Column(
      children: grouped.entries.map((g) {
        final familyLabel = g.key;
        final familyEntries = g.value;
        final totalVal = familyEntries.fold(0.0, (s, e) => s + e.value);

        return FrostedPanel(
          padding: const EdgeInsets.all(0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Family header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF00838F).withValues(alpha: 0.08),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                ),
                child: Row(children: [
                  const Icon(Icons.home_work_rounded,
                      color: Color(0xFF00838F), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(familyLabel,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: Color(0xFF00838F))),
                  ),
                  Text(_rs(totalVal),
                      style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: Color(0xFF00838F))),
                ]),
              ),
              // Individual donations for this family
              ...familyEntries.asMap().entries.map((me) {
                final idx = me.key;
                final entry = me.value;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (idx > 0)
                      Divider(height: 1,
                          color: theme.dividerColor.withValues(alpha: 0.4)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Donation header row
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: (entry.type == 'cash'
                                        ? Colors.green
                                        : Colors.amber.shade700)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                entry.type == 'cash' ? 'CASH' : 'IN-KIND',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    color: entry.type == 'cash'
                                        ? Colors.green
                                        : Colors.amber.shade700),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Donor: ${entry.donorName}',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(_rs(entry.value),
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF00838F))),
                          ]),

                          // Item breakdown (in-kind only)
                          if (entry.type == 'inKind' && entry.items.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Column(
                                children: [
                                  // Column headers
                                  Row(children: [
                                    Expanded(
                                        flex: 3,
                                        child: Text('Item',
                                            style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: theme.colorScheme.onSurface
                                                    .withValues(alpha: 0.45)))),
                                    Expanded(
                                        flex: 2,
                                        child: Text('Qty',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: theme.colorScheme.onSurface
                                                    .withValues(alpha: 0.45)))),
                                    Expanded(
                                        flex: 3,
                                        child: Text('Value',
                                            textAlign: TextAlign.right,
                                            style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: theme.colorScheme.onSurface
                                                    .withValues(alpha: 0.45)))),
                                  ]),
                                  const SizedBox(height: 4),
                                  ...entry.items.entries.map((ie) {
                                    final detail = ie.value;
                                    return Padding(
                                      padding:
                                          const EdgeInsets.symmetric(vertical: 3),
                                      child: Row(children: [
                                        Expanded(
                                            flex: 3,
                                            child: Text(ie.key,
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: theme
                                                        .colorScheme.onSurface),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis)),
                                        Expanded(
                                            flex: 2,
                                            child: Text(
                                                '${detail.qty} ${detail.unit}',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: theme.colorScheme
                                                        .onSurface
                                                        .withValues(alpha: 0.7)))),
                                        Expanded(
                                            flex: 3,
                                            child: Text(
                                                _rs(detail.pkrValue),
                                                textAlign: TextAlign.right,
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                    color:
                                                        Color(0xFF00838F)))),
                                      ]),
                                    );
                                  }),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 3 — DONORS
// ─────────────────────────────────────────────────────────────────────────────
class _DonorsTab extends StatefulWidget {
  const _DonorsTab({required this.r});
  final _ReportData r;
  @override
  State<_DonorsTab> createState() => _DonorsTabState();
}

class _DonorsTabState extends State<_DonorsTab> {
  String _q = '';
  // O(1) rank lookup — precomputed once, not on every build item
  late final Map<_Donor, int> _rankMap;

  @override
  void initState() {
    super.initState();
    _rankMap = {
      for (var i = 0; i < widget.r.donors.length; i++)
        widget.r.donors[i]: i + 1,
    };
  }

  @override
  Widget build(BuildContext ctx) {
    final theme    = Theme.of(ctx);
    final qLower   = _q.toLowerCase();
    final filtered = _q.isEmpty
        ? widget.r.donors
        : widget.r.donors
            .where((d) =>
                d.name.toLowerCase().contains(qLower) ||
                d.email.toLowerCase().contains(qLower))
            .toList();

    return Column(children: [
      // Search
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: TextField(
          onChanged: (v) => setState(() => _q = v),
          decoration: InputDecoration(
            hintText: 'Search donor name or email…',
            prefixIcon: const Icon(Icons.search, size: 20),
            isDense: true,
            filled: true,
            fillColor: theme.colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: theme.dividerColor),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Row(children: [
          Text('${filtered.length} donors',
              style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
          const Spacer(),
          Text('Sorted by total impact',
              style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
        ]),
      ),

      Expanded(
        child: ListView.builder(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          itemCount: filtered.length,
          itemBuilder: (_, i) {
            final d    = filtered[i];
            final rank = _rankMap[d] ?? (i + 1);
            final medalColor = rank == 1
                ? const Color(0xFFFFC107)
                : rank == 2
                    ? const Color(0xFFAEAEAE)
                    : rank == 3
                        ? const Color(0xFFCD7F32)
                        : theme.colorScheme.onSurface.withValues(alpha: 0.2);
            final initials = d.name == 'Anonymous'
                ? '?'
                : d.name.trim().isNotEmpty
                    ? d.name.trim()[0].toUpperCase()
                    : '?';

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FrostedPanel(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Avatar with initial + rank badge
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor:
                                AppColors.primaryBlue.withValues(alpha: 0.1),
                            child: Text(initials,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primaryBlue)),
                          ),
                          Positioned(
                            bottom: -4,
                            right: -4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: medalColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('#$rank',
                                  style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 14),
                      // Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d.name,
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: theme.colorScheme.onSurface)),
                            if (d.email.isNotEmpty)
                              Text(d.email,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.5))),
                            const SizedBox(height: 7),
                            Wrap(spacing: 6, runSpacing: 4, children: [
                              _Tag('${d.count} donations',
                                  AppColors.primaryBlue),
                              if (d.cash > 0)
                                _Tag('Cash ${_rs(d.cash)}', Colors.green),
                              if (d.inKind > 0)
                                _Tag('In-Kind ${_rs(d.inKind)}',
                                    Colors.amber.shade700),
                            ]),
                            const SizedBox(height: 5),
                            Text(
                              'Verified: ${_rs(d.cashVerified)}  ·  Last: ${DateFormat('d MMM yyyy').format(d.lastAt)}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.45)),
                            ),
                          ],
                        ),
                      ),
                      // Total
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_rs(d.total),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  color: Color(0xFF2E7D32))),
                          Text('Total',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.4))),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED UI COMPONENTS
// ─────────────────────────────────────────────────────────────────────────────

// Hero gradient card with grand total + timestamp
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.r});
  final _ReportData r;

  @override
  Widget build(BuildContext ctx) {
    final timeFmt = DateFormat('d MMM yyyy  h:mm a');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryBlue.withValues(alpha: 0.92),
            AppColors.primaryBlue.withValues(alpha: 0.6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.stacked_bar_chart_rounded,
              color: Colors.white70, size: 16),
          const SizedBox(width: 6),
          const Text('Grand Total Raised — All Time',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('Live',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(_rs(r.grandTotal),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5)),
        const SizedBox(height: 8),
        Row(children: [
          _HeroPill('${r.cashCount} Cash', Colors.green),
          const SizedBox(width: 6),
          _HeroPill('${r.inKindCount} In-Kind', Colors.amber),
          const SizedBox(width: 6),
          _HeroPill('${r.total} Total', Colors.white38),
        ]),
        const SizedBox(height: 8),
        Text('As of ${timeFmt.format(r.lastLoaded)}',
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

// 2×2 KPI grid
class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.r});
  final _ReportData r;

  @override
  Widget build(BuildContext ctx) {
    final items = [
      _Kpi('Total Donations',  r.total.toString(),      Icons.volunteer_activism_rounded, Colors.blue),
      _Kpi('Total Cash',       _rs(r.cashTotal),        Icons.payments_rounded,           Colors.green),
      _Kpi('In-Kind Value',    _rs(r.inKindTotal),      Icons.inventory_2_rounded,        Colors.amber.shade700),
      _Kpi('Verified Cash',    _rs(r.cashVerified),     Icons.verified_rounded,           const Color(0xFF00796B)),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.7,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _KpiCard(kpi: items[i]),
    );
  }
}

class _Kpi {
  final String label, value;
  final IconData icon;
  final Color color;
  const _Kpi(this.label, this.value, this.icon, this.color);
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.kpi});
  final _Kpi kpi;

  @override
  Widget build(BuildContext ctx) {
    final theme = Theme.of(ctx);
    // Use FrostedPanel's built-in padding to avoid double-padding overflow
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
              color: kpi.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(kpi.icon, color: kpi.color, size: 15),
          ),
          const SizedBox(height: 6),
          Text(kpi.value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: kpi.color,
                  letterSpacing: -0.3),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 1),
          Text(kpi.label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// Section header with icon
class _SecHeader extends StatelessWidget {
  const _SecHeader(
      {required this.icon, required this.title, this.color, this.subtitle});
  final IconData icon;
  final String title;
  final Color? color;
  final String? subtitle;

  @override
  Widget build(BuildContext ctx) {
    final theme      = Theme.of(ctx);
    final accentColor = color ?? AppColors.primaryBlue;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Container(
        width: 4,
        height: subtitle != null ? 32 : 18,
        decoration: BoxDecoration(
          color: accentColor,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      const SizedBox(width: 10),
      Icon(icon, color: accentColor, size: 16),
      const SizedBox(width: 6),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface)),
          if (subtitle != null)
            Text(subtitle!,
                style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
        ],
      ),
    ]);
  }
}

// Info table row model
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
      child: Column(
        children: rows.asMap().entries.map((e) {
          final idx = e.key;
          final row = e.value;
          return Column(children: [
            if (idx > 0)
              Divider(
                  height: 1,
                  color: theme.dividerColor.withValues(alpha: 0.45)),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(children: [
                // Thin colour accent on left
                Container(
                  width: 3,
                  height: row.sub != null ? 30 : 16,
                  decoration: BoxDecoration(
                    color: row.color.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row.label,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.onSurface)),
                      if (row.sub != null)
                        Text(row.sub!,
                            style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.5))),
                    ],
                  ),
                ),
                Text(row.value,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: row.color)),
              ]),
            ),
          ]);
        }).toList(),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, this.color);
  final String label;
  final Color color;
  @override
  Widget build(BuildContext ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.bold, color: color)),
      );
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
            Text('Computing analytics…',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
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
              style: TextStyle(
                  color: Theme.of(ctx)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.55))),
        ),
      );
}

// Formatting helpers ───────────────────────────────────────────────────────────
String _rs(double v) => 'Rs ${NumberFormat('#,##0').format(v)}';
