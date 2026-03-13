import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/models/master_ledger_model.dart';
import 'package:ration_aid/services/ledger_service.dart';
import 'package:ration_aid/services/allocation_service.dart';
import 'package:ration_aid/theme/app_colors.dart';

/// Admin Funding Control Panel — Phase 5
///
/// Shows the live master ledger, priority queue, auto-allocate, and
/// emergency reserve management in one unified section.
class FundingControlSection extends StatefulWidget {
  const FundingControlSection({super.key});

  @override
  State<FundingControlSection> createState() => _FundingControlSectionState();
}

class _FundingControlSectionState extends State<FundingControlSection>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isAllocating = false;
  AllocationSummary? _lastAllocationResult;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    LedgerService.ensureLedger();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        // ── Tab bar ────────────────────────────────────────────────────
        Container(
          color: isDark ? Colors.grey[900] : Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.primaryBlue,
            unselectedLabelColor: theme.colorScheme.onSurface.withValues(
              alpha: 0.5,
            ),
            indicatorColor: AppColors.primaryBlue,
            tabs: const [
              Tab(text: '📊 Ledger'),
              Tab(text: '🎯 Priority Queue'),
              Tab(text: '📋 Audit Log'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildLedgerTab(isDark, theme),
              _buildPriorityQueueTab(isDark, theme),
              _buildAuditLogTab(isDark, theme),
            ],
          ),
        ),
      ],
    );
  }

  // ── TAB 1: MASTER LEDGER ────────────────────────────────────────────────
  Widget _buildLedgerTab(bool isDark, ThemeData theme) {
    return StreamBuilder<MasterLedger>(
      stream: LedgerService.streamLedger(),
      builder: (context, snap) {
        final ledger = snap.data ?? MasterLedger.empty();
        return RefreshIndicator(
          onRefresh: () async => setState(() {}),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLedgerOverviewCard(ledger, isDark, theme),
                const SizedBox(height: 16),
                _buildLedgerStatRow(ledger, isDark, theme),
                const SizedBox(height: 20),
                _buildAutoAllocateCard(isDark, theme),
                const SizedBox(height: 16),
                _buildEmergencyReserveCard(ledger, isDark, theme),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLedgerOverviewCard(
    MasterLedger ledger,
    bool isDark,
    ThemeData theme,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryBlue,
            AppColors.primaryBlue.withValues(alpha: 0.75),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '💰 Master Fund Overview',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              if (ledger.lastUpdated != null)
                Text(
                  'Updated ${_formatTime(ledger.lastUpdated!)}',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'PKR ${_formatAmount(ledger.totalReceived)}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 32,
            ),
          ),
          const Text(
            'Total Received',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: ledger.totalReceived > 0
                ? (ledger.totalDisbursed / ledger.totalReceived).clamp(0.0, 1.0)
                : 0,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 4),
          Text(
            '${(ledger.utilizationRate * 100).toStringAsFixed(1)}% disbursement rate',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildLedgerStatRow(
    MasterLedger ledger,
    bool isDark,
    ThemeData theme,
  ) {
    final stats = [
      ('Allocated', ledger.totalAllocated, Colors.blue),
      ('Disbursed', ledger.totalDisbursed, Colors.green),
      ('General Pool', ledger.generalPoolBalance, Colors.orange),
      ('Emergency', ledger.emergencyReserve, Colors.red),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.8,
      children: stats.map((s) {
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: s.$3.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: s.$3.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'PKR ${_formatAmount(s.$2)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: s.$3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                s.$1,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAutoAllocateCard(bool isDark, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.blue[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '🤖 Smart Auto-Allocate',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const Spacer(),
              if (_lastAllocationResult != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Last: PKR ${_formatAmount(_lastAllocationResult!.allocated)} to ${_lastAllocationResult!.familiesHelped} families',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Distribute General Pool funds to highest-priority unfunded families.',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _isAllocating ? null : _runAutoAllocate,
              icon: _isAllocating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_fix_high),
              label: Text(
                _isAllocating ? 'Allocating...' : 'Auto-Allocate Now',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyReserveCard(
    MasterLedger ledger,
    bool isDark,
    ThemeData theme,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.red[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '⚡ Emergency Reserve',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            'PKR ${_formatAmount(ledger.emergencyReserve)} available',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Draw from emergency reserve requires mandatory justification.',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.orange),
                    foregroundColor: Colors.orange,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => _showSetReserveDialog(ledger),
                  icon: const Icon(Icons.savings_outlined, size: 16),
                  label: const Text(
                    'Set Reserve',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: ledger.emergencyReserve > 0
                      ? () => _showEmergencyDrawDialog(ledger)
                      : null,
                  icon: const Icon(Icons.flash_on, size: 16),
                  label: const Text(
                    'Draw Reserve',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── TAB 2: PRIORITY QUEUE ───────────────────────────────────────────────
  Widget _buildPriorityQueueTab(bool isDark, ThemeData theme) {
    // Issue #5 Fix: StreamBuilder replaces stale FutureBuilder.
    // Priority queue now updates live when scores are refreshed or
    // a family's funding status changes after auto-allocate runs.
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('families')
          .where('status', isEqualTo: 'accepted')
          .where('fundingStatus', isNotEqualTo: 'fully_funded')
          .orderBy('fundingStatus') // needed for isNotEqualTo compound query
          .orderBy('priorityScore', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final docs = snap.data?.docs ?? [];
        // Exclude archived
        final families = docs
            .where((d) => d.data()['isArchived'] != true)
            .toList();
        if (families.isEmpty) {
          return const Center(child: Text('No unfunded families found 🎉'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: families.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final data = families[i].data();
            final double raised = (data['raisedAmount'] as num? ?? 0)
                .toDouble();
            final double target =
                (data['assignedPackBudget'] ?? data['targetAmount'] ?? 0 as num)
                    .toDouble();
            final double score = (data['priorityScore'] as num? ?? 0)
                .toDouble();
            final double gap = (target - raised).clamp(0.0, double.infinity);
            final double progress = target > 0
                ? (raised / target).clamp(0.0, 1.0)
                : 0.0;
            final bool isEmergency = data['isEmergency'] == true;
            final String area = data['area'] ?? 'Unknown area';
            final String city = data['city'] ?? '';
            final String reason =
                data['priorityReason'] ?? 'Score-based priority';

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isEmergency
                    ? Colors.red.withValues(alpha: 0.06)
                    : (isDark ? Colors.grey[850] : Colors.white),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isEmergency
                      ? Colors.red.withValues(alpha: 0.4)
                      : theme.dividerColor.withValues(alpha: 0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: _scoreColor(score).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '#${i + 1}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _scoreColor(score),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '$area, $city',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                if (isEmergency) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      '⚡ EMERGENCY',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              reason,
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Score: ${score.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _scoreColor(score),
                            ),
                          ),
                          Text(
                            'Gap: PKR ${_formatAmount(gap)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey.withValues(alpha: 0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _scoreColor(score),
                      ),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'PKR ${_formatAmount(raised)} / ${_formatAmount(target)} raised',
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── TAB 3: AUDIT LOG ────────────────────────────────────────────────────
  Widget _buildAuditLogTab(bool isDark, ThemeData theme) {
    return StreamBuilder<List<LedgerAuditEntry>>(
      stream: LedgerService.streamLedgerAuditLog(limit: 50),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snap.data ?? [];
        if (entries.isEmpty) {
          return const Center(child: Text('No audit entries yet'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: entries.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final e = entries[i];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _actionColor(e.action).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    _actionIcon(e.action),
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              title: Text(
                '${e.action.toUpperCase()} • PKR ${_formatAmount(e.amount)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              subtitle: Text(
                '${e.reason ?? ''} · ${_formatTime(e.timestamp)}',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              trailing: e.overflowAmount != null && e.overflowAmount! > 0
                  ? Text(
                      '+GRF ${_formatAmount(e.overflowAmount!)}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.orange,
                      ),
                    )
                  : null,
            );
          },
        );
      },
    );
  }

  // ── DIALOGS ─────────────────────────────────────────────────────────────
  Future<void> _runAutoAllocate() async {
    final adminUid = FirebaseAuth.instance.currentUser?.uid;
    if (adminUid == null) return;
    setState(() => _isAllocating = true);
    try {
      final result = await AllocationService.autoAllocateGeneralFund(
        adminUid: adminUid,
        maxPerFamily: 10000,
      );
      setState(() => _lastAllocationResult = result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text(
              '✅ Allocated PKR ${_formatAmount(result.allocated)} to ${result.familiesHelped} families',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isAllocating = false);
    }
  }

  // Issue #7 Fix: Emergency draw now uses a family picker instead of raw ID input.
  void _showEmergencyDrawDialog(MasterLedger ledger) {
    final adminUid = FirebaseAuth.instance.currentUser?.uid;
    if (adminUid == null) return;
    final amtCtrl = TextEditingController();
    final justCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        String? selectedFamilyId;
        String selectedFamilyName = '';
        List<Map<String, String>> familyOptions = [];
        bool loadingFamilies = true;

        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            // Load accepted families once when dialog opens
            if (loadingFamilies && familyOptions.isEmpty) {
              FirebaseFirestore.instance
                  .collection('families')
                  .where('status', isEqualTo: 'accepted')
                  .where('isArchived', isEqualTo: false)
                  .limit(100)
                  .get()
                  .then((snap) {
                    final list = snap.docs.map((d) {
                      final data = d.data();
                      return {
                        'id': d.id,
                        'name':
                            (data['name'] ??
                                    '${data['area'] ?? 'Unknown'} — ${d.id.substring(0, 6)}')
                                as String,
                      };
                    }).toList();
                    setDlgState(() {
                      familyOptions = list;
                      loadingFamilies = false;
                    });
                  });
            }

            return AlertDialog(
              title: const Text('⚡ Emergency Reserve Draw'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Available: PKR ${_formatAmount(ledger.emergencyReserve)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Family picker (replaces raw ID input)
                  loadingFamilies
                      ? const Center(child: CircularProgressIndicator())
                      : DropdownButtonFormField<String>(
                          hint: const Text('Select target family'),
                          value: selectedFamilyId,
                          isExpanded: true,
                          items: familyOptions
                              .map(
                                (f) => DropdownMenuItem<String>(
                                  value: f['id'],
                                  child: Text(
                                    f['name']!,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            setDlgState(() {
                              selectedFamilyId = val;
                              selectedFamilyName =
                                  familyOptions.firstWhere(
                                    (f) => f['id'] == val,
                                    orElse: () => {'name': ''},
                                  )['name'] ??
                                  '';
                            });
                          },
                          decoration: const InputDecoration(
                            labelText: 'Target Family *',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: amtCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Amount (PKR) *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: justCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Justification (mandatory) *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () async {
                    final amt = double.tryParse(amtCtrl.text) ?? 0;
                    if (amt <= 0 ||
                        selectedFamilyId == null ||
                        justCtrl.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Please fill all fields: family, amount, and justification',
                          ),
                        ),
                      );
                      return;
                    }
                    Navigator.pop(ctx);
                    try {
                      await LedgerService.drawEmergencyReserve(
                        adminUid: adminUid,
                        targetFamilyId: selectedFamilyId!,
                        amount: amt,
                        justification: justCtrl.text.trim(),
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: Colors.green,
                            content: Text(
                              '✅ Emergency reserve drawn for $selectedFamilyName',
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    }
                  },
                  child: const Text(
                    'Confirm Draw',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showSetReserveDialog(MasterLedger ledger) {
    final adminUid = FirebaseAuth.instance.currentUser?.uid;
    if (adminUid == null) return;
    final amtCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set Emergency Reserve'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Pool: PKR ${_formatAmount(ledger.generalPoolBalance)} available',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amtCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount to Reserve (PKR) *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Reason *',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final amt = double.tryParse(amtCtrl.text) ?? 0;
              if (amt <= 0 || reasonCtrl.text.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await LedgerService.setEmergencyReserve(
                  adminUid: adminUid,
                  amount: amt,
                  reason: reasonCtrl.text.trim(),
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: Colors.green,
                      content: Text('✅ Emergency reserve updated'),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text('Set Reserve'),
          ),
        ],
      ),
    );
  }

  // ── HELPERS ──────────────────────────────────────────────────────────────
  String _formatAmount(double amount) {
    if (amount >= 1000000) return '${(amount / 1000000).toStringAsFixed(1)}M';
    if (amount >= 1000) return '${(amount / 1000).toStringAsFixed(1)}K';
    return amount.toStringAsFixed(0);
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Color _scoreColor(double score) {
    if (score >= 8) return Colors.red;
    if (score >= 5) return Colors.orange;
    return Colors.blue;
  }

  String _actionIcon(String action) {
    switch (action) {
      case 'donate':
        return '💰';
      case 'allocate':
        return '📤';
      case 'disburse':
        return '🏪';
      case 'emergency_draw':
        return '⚡';
      case 'surplus_transfer':
        return '🔄';
      case 'reserve_set':
        return '🏦';
      default:
        return '📋';
    }
  }

  Color _actionColor(String action) {
    switch (action) {
      case 'donate':
        return Colors.green;
      case 'allocate':
        return Colors.blue;
      case 'emergency_draw':
        return Colors.red;
      case 'surplus_transfer':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}
