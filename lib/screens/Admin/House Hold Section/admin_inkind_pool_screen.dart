import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:ration_aid/screens/Admin/widgets/frosted_panel.dart';
import 'package:ration_aid/services/funding_service.dart';
import 'package:ration_aid/theme/app_colors.dart';

class AdminInKindPoolScreen extends StatefulWidget {
  const AdminInKindPoolScreen({super.key});

  @override
  State<AdminInKindPoolScreen> createState() => _AdminInKindPoolScreenState();
}

class _AdminInKindPoolScreenState extends State<AdminInKindPoolScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _db = FirebaseFirestore.instance;

  // ─── ANR FIX ────────────────────────────────────────────────────────────────
  // Streams MUST be cached as state fields (late final, set in initState).
  // If you create them inside a method called from build(), Flutter's
  // StreamBuilder sees a different object reference every frame, cancels the
  // old Firestore listener and starts a new one, Firestore's local cache
  // fires immediately, which triggers another rebuild, ad infinitum →
  // tight synchronous loop on the Dart main isolate → Android ANR.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _pickupStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _warehouseStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _familiesStream;

  // Cached snapshots to solve the Broadcast Stream + Lazy Tab building issue.
  // Firestore streams fire immediately. If Tab 2 or 3 isn't built yet, their
  // StreamBuilders miss the first event and wait forever.
  QuerySnapshot<Map<String, dynamic>>? _pickupSnap;
  QuerySnapshot<Map<String, dynamic>>? _warehouseSnap;
  QuerySnapshot<Map<String, dynamic>>? _familiesSnap;

  late final StreamSubscription _pickupSub;
  late final StreamSubscription _warehouseSub;
  late final StreamSubscription _familiesSub;
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // ───────────────────────────────────────────────────────────────────────
    // Create streams ONCE here; never recreate during the widget's lifetime.
    _pickupStream = _db
        .collection('inbound_pickups')
        .where('familyId', isEqualTo: 'general_relief_fund')
        .where('status', whereIn: ['open', 'in_progress'])
        .snapshots();
    _warehouseStream = _db
        .collection('warehouse_stock')
        .where('familyId', isEqualTo: 'general_relief_fund')
        .where('status', isEqualTo: 'grf_pool')
        .snapshots();
    _familiesStream = _db
        .collection('families')
        .where('status', isEqualTo: 'accepted')
        .snapshots();

    // Start listening immediately so no events are dropped while tabs are lazy-built
    _pickupSub = _pickupStream.listen(
      (snap) => setState(() => _pickupSnap = snap),
    );
    _warehouseSub = _warehouseStream.listen(
      (snap) => setState(() => _warehouseSnap = snap),
    );
    _familiesSub = _familiesStream.listen(
      (snap) => setState(() => _familiesSnap = snap),
    );
  }

  @override
  void dispose() {
    _pickupSub.cancel();
    _warehouseSub.cancel();
    _familiesSub.cancel();
    _tabController.dispose();
    super.dispose();
  }

  String _fmt(double amount) {
    if (amount >= 1000000) return '${(amount / 1000000).toStringAsFixed(1)}M';
    if (amount >= 1000) return '${(amount / 1000).toStringAsFixed(1)}K';
    return amount.toStringAsFixed(0);
  }

  String _fmtTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  // Stream methods kept for _showTargetedAssignDialog one-off .get() calls only.
  // Do NOT call .snapshots() here — only use the cached fields above.

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text(
          'GRF In-Kind Pool',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: AppColors.primaryBlue,
              ),
              labelColor: Colors.white,
              unselectedLabelColor: isDark ? Colors.white60 : Colors.black54,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(
                  child: Text(
                    '🚚 Pickup',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                Tab(
                  child: Text(
                    '📦 Warehouse',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                Tab(
                  child: Text(
                    '🎯 Assign',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _KeepAliveTab(child: _buildAwaitingPickupTab(isDark, theme)),
          _KeepAliveTab(child: _buildWarehouseTab(isDark, theme)),
          _KeepAliveTab(child: _buildAssignTab(isDark, theme)),
        ],
      ),
    );
  }

  // ── TAB 1: Awaiting Pickup ────────────────────────────────────────────

  Widget _buildAwaitingPickupTab(bool isDark, ThemeData theme) {
    if (_pickupSnap == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final docs = _pickupSnap!.docs;
    if (docs.isEmpty) {
      return _emptyState(
        Icons.local_shipping_outlined,
        'No Pending Pickups',
        'When a donor submits an NGO Pool in-kind donation and admin verifies it, '
            'a pickup task appears here for the Purchaser to collect.',
        Colors.teal,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final data = docs[index].data();
        final items = Map<String, num>.from(data['items'] ?? {});
        final itemUnits = Map<String, String>.from(
          (data['itemUnits'] as Map?)?.map(
                (k, v) => MapEntry(k.toString(), v.toString()),
              ) ??
              {},
        );
        final donorName = data['donorName'] as String? ?? 'Anonymous';
        final address = data['pickupAddress'] as String? ?? 'No address';
        final phone = data['donorPhone'] as String? ?? 'No phone';
        final status = data['status'] as String? ?? 'open';
        final createdAt =
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

        return FrostedPanel(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.local_shipping_outlined,
                      color: Colors.teal,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          donorName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          address,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                        if (phone != 'No phone')
                          Text(
                            phone,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.8,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _statusChip(status),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: items.entries.map((e) {
                  final unit = itemUnits[e.key] ?? '';
                  final label = unit.isNotEmpty
                      ? '${e.key}: ${e.value} $unit'
                      : '${e.key}: ${e.value}';
                  return Chip(
                    label: Text(label, style: const TextStyle(fontSize: 10)),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Colors.teal.withValues(alpha: 0.08),
                  );
                }).toList(),
              ),
              const SizedBox(height: 6),
              Text(
                'Created ${_fmtTime(createdAt)}',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── TAB 2: In Warehouse ───────────────────────────────────────────────

  Widget _buildWarehouseTab(bool isDark, ThemeData theme) {
    if (_warehouseSnap == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final docs = _warehouseSnap!.docs;

    // Aggregate total value and items across all GRF pool stock
    double totalValue = 0;
    final Map<String, num> aggregatedItems = {};
    // Aggregate units: first doc that has a unit for an item wins
    final Map<String, String> aggregatedUnits = {};
    for (final doc in docs) {
      final data = doc.data();
      // Fix Bug 3: use lockedInKindValue or totalLockedValue
      totalValue +=
          (data['lockedInKindValue'] ??
                  data['totalLockedValue'] ??
                  data['totalValue'] ??
                  0)
              .toDouble();
      final items = Map<String, num>.from(data['items'] ?? {});
      items.forEach((k, v) {
        aggregatedItems[k] = (aggregatedItems[k] ?? 0) + v;
      });
      final units = Map<String, String>.from(
        (data['itemUnits'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            ) ??
            {},
      );
      units.forEach((k, v) => aggregatedUnits.putIfAbsent(k, () => v));
    }

    return Column(
      children: [
        // Header card (Always visible)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: FrostedPanel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '📦 GRF Physical Inventory',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'PKR ${_fmt(totalValue)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (aggregatedItems.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 4.0),
                    child: Text(
                      'No inventory available in the GRF pool.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: aggregatedItems.entries.map((e) {
                      final unit = aggregatedUnits[e.key] ?? '';
                      final label = unit.isNotEmpty
                          ? '${e.key}: ${e.value} $unit'
                          : '${e.key}: ${e.value}';
                      return Chip(
                        avatar: const Icon(
                          Icons.check_circle,
                          size: 14,
                          color: Colors.green,
                        ),
                        label: Text(
                          label,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        backgroundColor: AppColors.primaryBlue.withValues(
                          alpha: 0.07,
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // List Area
        if (docs.isEmpty)
          Expanded(
            child: _emptyState(
              Icons.inventory_2_outlined,
              'Warehouse Empty',
              'Items appear here once the Purchaser collects them from the donor. '
                  'Go to "🚚 Pickup" tab to see active pickups.',
              Colors.indigo,
            ),
          )
        else ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'Individual Batches',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data();
                final items = Map<String, num>.from(data['items'] ?? {});
                final batchUnits = Map<String, String>.from(
                  (data['itemUnits'] as Map?)?.map(
                        (k, v) => MapEntry(k.toString(), v.toString()),
                      ) ??
                      {},
                );
                final valuation =
                    (data['lockedInKindValue'] ??
                            data['totalLockedValue'] ??
                            data['totalValue'] ??
                            0)
                        .toDouble();
                final donorName =
                    data['donorName'] as String? ?? 'Anonymous Donor';
                final receivedAt = (data['receivedAt'] as Timestamp?)?.toDate();

                return FrostedPanel(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              donorName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Text(
                            'PKR ${_fmt(valuation)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        children: items.entries.map((e) {
                          final unit = batchUnits[e.key] ?? '';
                          final label = unit.isNotEmpty
                              ? '${e.key} × ${e.value} $unit'
                              : '${e.key} × ${e.value}';
                          return Chip(
                            label: Text(
                              label,
                              style: const TextStyle(fontSize: 10),
                            ),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            receivedAt != null
                                ? 'Collected ${_fmtTime(receivedAt)}'
                                : '',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.person_add_alt_1, size: 14),
                            label: const Text(
                              'Assign to Family',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 0,
                              ),
                              minimumSize: const Size(0, 32),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () => _showFamilySelectorForStock(
                              stockDocId: doc.id,
                              donationItems: items,
                              stockItemUnits: batchUnits,
                              stockValue: valuation,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ], // End of the else ...[ block
      ],
    );
  }

  // ── TAB 3: Assign to Family (matching) ────────────────────────────────

  Widget _buildAssignTab(bool isDark, ThemeData theme) {
    if (_warehouseSnap == null || _familiesSnap == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final stockDocs = _warehouseSnap!.docs;

    // Aggregate available pool items
    final Map<String, num> poolItems = {};
    for (final doc in stockDocs) {
      final items = Map<String, num>.from(doc.data()['items'] ?? {});
      items.forEach((k, v) => poolItems[k] = (poolItems[k] ?? 0) + v);
    }

    if (poolItems.isEmpty) {
      return _emptyState(
        Icons.assignment_outlined,
        'No Items to Assign',
        'Items will appear here once collected by the Purchaser. '
            'Check the "📦 Warehouse" tab first.',
        Colors.orange,
      );
    }

    // Only families that have needs matching pool items
    final matchingFamilies = _familiesSnap!.docs.where((fDoc) {
      final needs = Map<String, dynamic>.from(fDoc.data()['needs'] ?? {});
      return needs.entries.any(
        (e) =>
            (num.tryParse(e.value.toString()) ?? 0) > 0 &&
            poolItems.containsKey(e.key),
      );
    }).toList();

    if (matchingFamilies.isEmpty) {
      return _emptyState(
        Icons.search_off_outlined,
        'No Matching Needs',
        'No accepted families currently need the items in the GRF pool.',
        Colors.grey,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: matchingFamilies.length,
      itemBuilder: (context, index) {
        final fDoc = matchingFamilies[index];
        final fData = fDoc.data();
        final fNeeds = Map<String, dynamic>.from(fData['needs'] ?? {});

        final matchingNeeds = fNeeds.entries
            .where(
              (e) =>
                  (num.tryParse(e.value.toString()) ?? 0) > 0 &&
                  poolItems.containsKey(e.key),
            )
            .toList();

        final double famProgress = (fData['combinedProgress'] as num? ?? 0)
            .toDouble();
        final double famTarget = (fData['targetAmount'] as num? ?? 0)
            .toDouble();

        return FrostedPanel(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.family_restroom_rounded,
                      size: 18,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${fData['area']}, ${fData['city']}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        if (famTarget > 0)
                          Text(
                            'Funded: ${(famProgress / famTarget * 100).clamp(0, 100).toInt()}%',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${matchingNeeds.length} Match${matchingNeeds.length != 1 ? 'es' : ''}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: matchingNeeds.map((e) {
                  final famItemUnits = Map<String, String>.from(
                    (fData['itemUnits'] as Map?)?.map(
                          (k, v) => MapEntry(k.toString(), v.toString()),
                        ) ??
                        {},
                  );
                  final unit = famItemUnits[e.key] ?? '';
                  final label = unit.isNotEmpty
                      ? '${e.key} needs: ${e.value} $unit'
                      : '${e.key} needs: ${e.value}';
                  return Chip(
                    label: Text(label, style: const TextStyle(fontSize: 10)),
                    backgroundColor: Colors.teal.withValues(alpha: 0.1),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.assignment_turned_in, size: 16),
                  label: const Text('Resolve Matching Needs'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => _showTargetedAssignDialog(fDoc, poolItems),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _statusChip(String status) {
    Color color;
    switch (status) {
      case 'open':
        color = Colors.blue;
        break;
      case 'in_progress':
        color = Colors.orange;
        break;
      case 'completed':
        color = Colors.green;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _emptyState(
    IconData icon,
    String title,
    String subtitle,
    Color color,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: color.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  // ── Assignment Dialogs ────────────────────────────────────────────────────

  /// Assign a specific warehouse_stock batch to a family.
  Future<void> _showFamilySelectorForStock({
    required String stockDocId,
    required Map<String, num> donationItems,
    required Map<String, String> stockItemUnits,
    required double stockValue,
  }) async {
    final familiesSnap = await _db
        .collection('families')
        .where('status', isEqualTo: 'accepted')
        .get();

    // Sort families by match count
    final families = familiesSnap.docs.toList();
    families.sort((a, b) {
      final aNeeds = Map<String, dynamic>.from(a.data()['needs'] ?? {});
      final bNeeds = Map<String, dynamic>.from(b.data()['needs'] ?? {});

      int aMatches = 0;
      aNeeds.forEach((k, v) {
        if ((num.tryParse(v.toString()) ?? 0) > 0 &&
            donationItems.containsKey(k))
          aMatches++;
      });

      int bMatches = 0;
      bNeeds.forEach((k, v) {
        if ((num.tryParse(v.toString()) ?? 0) > 0 &&
            donationItems.containsKey(k))
          bMatches++;
      });

      return bMatches.compareTo(aMatches);
    });

    if (families.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No accepted families found.')),
        );
      }
      return;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('📦 Assign Batch to Family'),
        content: SizedBox(
          width: double.maxFinite,
          height: 480,
          child: ListView.builder(
            itemCount: families.length,
            itemBuilder: (context, index) {
              final fDoc = families[index];
              final fData = fDoc.data();
              final fNeeds = Map<String, dynamic>.from(fData['needs'] ?? {});

              final matches = donationItems.keys
                  .where(
                    (k) =>
                        (num.tryParse(fNeeds[k]?.toString() ?? '0') ?? 0) > 0,
                  )
                  .toList();

              return _buildFamilyListTile(
                fDoc: fDoc,
                fData: fData,
                fNeeds: fNeeds,
                matches: matches,
                donationItems: donationItems,
                stockItemUnits: stockItemUnits,
                onTap: matches.isEmpty
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        _showAssignmentConfirmationDialog(
                          stockId: stockDocId,
                          familyId: fDoc.id,
                          familyName:
                              fData['name'] as String? ??
                              '${fData['area']} Family',
                          donationItems: donationItems,
                          itemUnits: stockItemUnits,
                          fNeeds: fNeeds,
                          transferValue: stockValue,
                        );
                      },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// Show all pool donations that match this family's needs, pick one to assign.
  Future<void> _showTargetedAssignDialog(
    QueryDocumentSnapshot<Map<String, dynamic>> fDoc,
    Map<String, num> poolItems,
  ) async {
    final fData = fDoc.data();
    final fNeeds = Map<String, dynamic>.from(fData['needs'] ?? {});

    // Find warehouse_stock batches matching this family
    final stockSnap = await _db
        .collection('warehouse_stock')
        .where('familyId', isEqualTo: 'general_relief_fund')
        .where('status', isEqualTo: 'grf_pool')
        .get();

    final List<Map<String, dynamic>> availableBatches = [];
    for (var doc in stockSnap.docs) {
      final data = doc.data();
      final items = Map<String, num>.from(data['items'] ?? {});
      final matches = items.keys.where(
        (k) => (num.tryParse(fNeeds[k]?.toString() ?? '0') ?? 0) > 0,
      );
      if (matches.isNotEmpty) {
        availableBatches.add({
          'donationId': data['donationId'] ?? '',
          'stockId': doc.id,
          'donorName': data['donorName'] ?? 'Anonymous',
          'items': items,
          'itemUnits': Map<String, String>.from(
            (data['itemUnits'] as Map?)?.map(
                  (k, v) => MapEntry(k.toString(), v.toString()),
                ) ??
                {},
          ),
          'value':
              (data['lockedInKindValue'] ??
                      data['totalLockedValue'] ??
                      data['totalValue'] ??
                      0)
                  .toDouble(),
        });
      }
    }

    if (!mounted) return;
    if (availableBatches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No matching batches found in warehouse.'),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('🎯 Satisfy ${fData['area']} Family Needs'),
        content: SizedBox(
          height: 380,
          width: double.maxFinite,
          child: ListView.builder(
            itemCount: availableBatches.length,
            itemBuilder: (ctx, idx) {
              final d = availableBatches[idx];
              final items = d['items'] as Map<String, num>;
              final batchItemUnits = d['itemUnits'] as Map<String, String>;

              return Card(
                elevation: 0,
                color: Colors.teal.withValues(alpha: 0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.teal.withValues(alpha: 0.2)),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  title: Text(
                    d['donorName'] as String,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: items.entries.map((e) {
                          final isNeeded =
                              (num.tryParse(fNeeds[e.key]?.toString() ?? '0') ??
                                  0) >
                              0;
                          final unit = batchItemUnits[e.key] ?? '';
                          final label = unit.isNotEmpty
                              ? '${e.key} × ${e.value} $unit'
                              : '${e.key} × ${e.value}';
                          return Chip(
                            label: Text(
                              label,
                              style: TextStyle(
                                fontSize: 10,
                                color: isNeeded ? Colors.teal : Colors.grey,
                                fontWeight: isNeeded
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            backgroundColor: isNeeded
                                ? Colors.teal.withValues(alpha: 0.1)
                                : Colors.grey.withValues(alpha: 0.1),
                            side: BorderSide.none,
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                  trailing: Text(
                    'PKR ${_fmt(d['value'] as double)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.teal,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showAssignmentConfirmationDialog(
                      stockId: d['stockId'] as String,
                      familyId: fDoc.id,
                      familyName:
                          fData['name'] as String? ?? '${fData['area']} Family',
                      donationItems: items,
                      itemUnits: batchItemUnits,
                      fNeeds: fNeeds,
                      transferValue: d['value'] as double,
                    );
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildFamilyListTile({
    required QueryDocumentSnapshot<Map<String, dynamic>> fDoc,
    required Map<String, dynamic> fData,
    required Map<String, dynamic> fNeeds,
    required List<String> matches,
    required Map<String, num> donationItems,
    required Map<String, String> stockItemUnits,
    required VoidCallback? onTap,
  }) {
    final name = fData['name'] as String? ?? '${fData['area']} Family';
    final area = fData['area'] as String? ?? 'Unknown Area';
    final city = fData['city'] as String? ?? '';
    final adults = fData['adults'] ?? 0;
    final children = fData['children'] ?? 0;
    final isEmergency = fData['isEmergency'] == true;

    final double famProgress = (fData['combinedProgress'] as num? ?? 0)
        .toDouble();
    final double famTarget = (fData['targetAmount'] as num? ?? 0).toDouble();
    final double percent = famTarget > 0
        ? (famProgress / famTarget).clamp(0.0, 1.0)
        : 0.0;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: matches.isEmpty
          ? Colors.grey.withValues(alpha: 0.05)
          : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: matches.isEmpty
              ? Colors.grey.withValues(alpha: 0.2)
              : AppColors.primaryBlue.withValues(alpha: 0.3),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: matches.isEmpty
                                      ? Colors.grey
                                      : Colors.black87,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isEmergency) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'EMERGENCY',
                                  style: TextStyle(
                                    fontSize: 8,
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$area${city.isNotEmpty ? ', $city' : ''} • $adults Adults, $children Children',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (matches.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${matches.length} Match${matches.length > 1 ? 'es' : ''}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  else
                    const Text(
                      'No Match',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                ],
              ),
              if (matches.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: percent,
                          backgroundColor: Colors.grey.withValues(alpha: 0.2),
                          color: AppColors.primaryBlue,
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(percent * 100).toInt()}% • PKR ${_fmt(famProgress)}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: matches.map((k) {
                    final unit = stockItemUnits[k] ?? '';
                    final familyNeed =
                        num.tryParse(fNeeds[k]?.toString() ?? '0') ?? 0;
                    final poolQty = donationItems[k] ?? 0;
                    final label = unit.isNotEmpty
                        ? '$k: Needs $familyNeed $unit (Pool: $poolQty)'
                        : '$k: Needs $familyNeed (Pool: $poolQty)';
                    return Chip(
                      label: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      backgroundColor: AppColors.primaryBlue.withValues(
                        alpha: 0.1,
                      ),
                      side: BorderSide.none,
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAssignmentConfirmationDialog({
    required String stockId,
    required String familyId,
    required String familyName,
    required Map<String, num> donationItems,
    required Map<String, String> itemUnits,
    required Map<String, dynamic> fNeeds,
    required double transferValue,
  }) async {
    final List<Widget> matchingWidgets = [];
    final List<Widget> leftoverWidgets = [];

    donationItems.forEach((key, poolQty) {
      final unit = itemUnits[key] ?? '';
      final familyNeed = num.tryParse(fNeeds[key]?.toString() ?? '0') ?? 0;
      final labelSuffix = unit.isNotEmpty ? ' $unit' : '';

      if (familyNeed > 0) {
        final assignedQty = poolQty > familyNeed ? familyNeed : poolQty;
        final leftoverQty = poolQty > familyNeed ? poolQty - familyNeed : 0;

        matchingWidgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$key: Assigning $assignedQty$labelSuffix (Needs $familyNeed)',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

        if (leftoverQty > 0) {
          leftoverWidgets.add(
            Text(
              '• $leftoverQty$labelSuffix $key stays in pool',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          );
        }
      } else {
        leftoverWidgets.add(
          Text(
            '• $poolQty$labelSuffix $key (Not needed)',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        );
      }
    });

    final bool confirm =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('⚠️ Confirm Assignment'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'You are assigning items to $familyName.',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Items to be assigned:',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  ...matchingWidgets,
                  if (leftoverWidgets.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Items staying in GRF Pool:',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    ...leftoverWidgets,
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.orange,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Total transfer value: PKR ${_fmt(transferValue)}\nThis action cannot be undone.',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.orange,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirm Assignment'),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      _handleAssignment(stockId, familyId);
    }
  }

  Future<void> _handleAssignment(String stockId, String familyId) async {
    if (stockId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No original stock ID linked to this batch.'),
          ),
        );
      }
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await FundingService.assignPoolInKind(
        stockDocId: stockId,
        targetFamilyId: familyId,
      );
      // NOTE: `assignPoolInKind` now automatically handles splitting/updating the warehouse batch.

      if (mounted) {
        Navigator.pop(context); // Dismiss loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text('✅ Items assigned to family successfully'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Dismiss loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Assignment failed: $e'),
          ),
        );
      }
    }
  }
}

/// A wrapper to keep TabBarView children alive, preventing them from being
/// destroyed when swiped away. Crucial for StreamBuilders listening to
/// broadcast streams, as they won't replay the last value upon resubscription.
class _KeepAliveTab extends StatefulWidget {
  final Widget child;
  const _KeepAliveTab({required this.child});

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
