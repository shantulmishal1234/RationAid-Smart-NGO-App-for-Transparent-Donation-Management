import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ration_aid/models/procurement_model.dart';
import 'package:ration_aid/screens/Purchaser/screens/purchase_entry_screen.dart';
import 'package:ration_aid/screens/Purchaser/widgets/procurement_card.dart';
import 'package:ration_aid/services/procurement_service.dart';
import 'package:ration_aid/theme/app_colors.dart';

/// Purchaser Procurement View — Self-Claim Pool Model:
///
/// Tab 1 "📦 Available Orders" — shared real-time pool of unclaimed pending orders.
///   All purchasers see the same pool. First to tap "I'll Buy This" claims it
///   via Firestore transaction. Max 2 concurrent claims per person prevents hoarding.
///
/// Tab 2 "🛒 My Orders" — orders claimed by this purchaser (pending/submitted/rejected).
///   Release button available on claimed-but-not-submitted orders.
///   Supervisor (admin) can also force-release from admin panel.
class ProcurementView extends StatefulWidget {
  final bool isSupervisor;
  const ProcurementView({super.key, this.isSupervisor = false});

  @override
  State<ProcurementView> createState() => _ProcurementViewState();
}

class _ProcurementViewState extends State<ProcurementView>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  String _searchQuery = '';
  Timer? _debounce;
  final _searchController = TextEditingController();

  // Optimized streams
  Stream<User?>? _authStream;
  Stream<List<ProcurementRequest>>? _availablePoolStream;
  Stream<List<ProcurementRequest>>? _myRequestsStream;
  String? _cachedUid;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: widget.isSupervisor ? 3 : 2, vsync: this);
    _authStream = FirebaseAuth.instance.authStateChanges();
    _initUserStreams();
  }

  void _initUserStreams() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.uid != _cachedUid) {
      _cachedUid = user.uid;
      _availablePoolStream = ProcurementService.streamAvailableRequests();
      _myRequestsStream = ProcurementService.streamMyRequests(user.uid);
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String q) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _searchQuery = q.toLowerCase().trim());
    });
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final user = FirebaseAuth.instance.currentUser;
    if (user?.uid != _cachedUid) {
      _initUserStreams();
    }

    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, authSnap) {
        if (!authSnap.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.purchaserOrange),
          );
        }
        final uid = authSnap.data!.uid;
        final displayName =
            authSnap.data!.displayName ?? authSnap.data!.email ?? 'Purchaser';

        return Column(
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.purchaserOrange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.shopping_cart_outlined,
                      color: AppColors.purchaserOrange,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Purchase Orders',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                        Text(
                          'Shared pool · claim any available order',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Tab Bar ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E1E2E)
                      : const Color(0xFFFFF6F0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tab,
                  labelColor: Colors.white,
                  unselectedLabelColor: theme.colorScheme.onSurface.withValues(
                    alpha: 0.6,
                  ),
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                  indicator: BoxDecoration(
                    color: AppColors.purchaserOrange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  tabs: [
                    const Tab(text: '📦 Available Orders'),
                    const Tab(text: '🛒 My Orders'),
                    if (widget.isSupervisor)
                      const Tab(text: '👥 Active Claims'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ── Tab Views ──────────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  _buildAvailablePool(uid, displayName, theme, isDark),
                  _buildMyOrders(uid, displayName, theme, isDark),
                  if (widget.isSupervisor)
                    _buildActiveClaims(uid, displayName, theme, isDark),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Tab 1: Available Pool ─────────────────────────────────────────────────

  Widget _buildAvailablePool(
    String uid,
    String displayName,
    ThemeData theme,
    bool isDark,
  ) {
    return StreamBuilder<List<ProcurementRequest>>(
      stream: _availablePoolStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.purchaserOrange),
          );
        }
        if (snapshot.hasError) {
          return _errorState('${snapshot.error}');
        }

        final pool = snapshot.data ?? [];
        if (pool.isEmpty) return _emptyPoolState();

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: pool.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (ctx, i) =>
              _buildPoolCard(pool[i], uid, displayName, theme, isDark),
        );
      },
    );
  }

  Widget _buildPoolCard(
    ProcurementRequest r,
    String uid,
    String displayName,
    ThemeData theme,
    bool isDark,
  ) {
    final currencyFmt = NumberFormat.currency(
      locale: 'en_PK',
      symbol: 'Rs. ',
      decimalDigits: 0,
    );
    final ageHours = DateTime.now().difference(r.createdAt).inHours;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.purchaserOrange.withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Badges
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 8, color: Colors.green),
                      SizedBox(width: 4),
                      Text(
                        'Open — Unclaimed',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Age badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: ageHours > 48
                        ? Colors.red.withValues(alpha: 0.1)
                        : Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    ageHours < 1
                        ? 'Just added'
                        : ageHours < 24
                        ? '${ageHours}h old'
                        : '${(ageHours / 24).round()}d old',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: ageHours > 48 ? Colors.red : Colors.orange,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Pack name
            Text(
              r.packName,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),

            const SizedBox(height: 4),

            // Address
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 4),
                Text(
                  r.familyAddress,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Items preview
            if (r.items.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  r.items.map((e) => '${e.name} (${e.quantity})').join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),

            const SizedBox(height: 12),

            // Budget + Claim button
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Budget',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    Text(
                      currencyFmt.format(r.budgetLimit),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.purchaserOrange,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => _claimOrder(r, uid, displayName),
                  icon: const Icon(Icons.handshake_outlined, size: 18),
                  label: const Text("I'll Buy This"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.purchaserOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _claimOrder(
    ProcurementRequest r,
    String uid,
    String displayName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Claim This Order?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'You are committing to purchase "${r.packName}" for ${r.familyAddress}.\n\n'
          'You can have a maximum of 2 active orders at a time.\n\n'
          'Are you ready to proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.purchaserOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text("Yes, I'll Handle It"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final success = await ProcurementService.claimRequest(
        requestId: r.id,
        purchaserId: uid,
        purchaserName: displayName,
      );

      if (!mounted) return;

      if (success) {
        _tab.animateTo(1);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Order claimed! Go to My Orders to submit purchase.'),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      } else {
        // Either already claimed or max limit reached
        final active = await ProcurementService.getMyActiveClaimsCount(uid);
        if (!mounted) return;

        final msg = active >= 2
            ? 'You already have 2 active orders. Submit one before claiming another.'
            : 'Just claimed by another purchaser. Choose a different order!';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Tab 2: My Orders ──────────────────────────────────────────────────────

  Widget _buildMyOrders(
    String uid,
    String displayName,
    ThemeData theme,
    bool isDark,
  ) {
    return StreamBuilder<List<ProcurementRequest>>(
      stream: _myRequestsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.purchaserOrange),
          );
        }
        if (snapshot.hasError) {
          return _errorState('${snapshot.error}');
        }

        final all = snapshot.data ?? [];

        // Stats
        final claimedCount = all.where((r) => r.isClaimed).length;
        final purchasedCount = all
            .where((r) => r.status == ProcurementStatus.purchased)
            .length;
        final rejectedCount = all
            .where((r) => r.status == ProcurementStatus.rejected)
            .length;
        final verifiedCount = all
            .where((r) => r.status == ProcurementStatus.verified)
            .length;

        // Apply search filter
        final filtered = _searchQuery.isEmpty
            ? all
            : all.where((r) {
                final s = _searchQuery;
                return r.packName.toLowerCase().contains(s) ||
                    r.familyAddress.toLowerCase().contains(s);
              }).toList();

        return Column(
          children: [
            // ── Stats row ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 8,
                ),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.2 : 0.05,
                      ),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    _statItem(
                      'Claimed',
                      claimedCount,
                      AppColors.purchaserOrange,
                    ),
                    _divider(),
                    _statItem('Submitted', purchasedCount, Colors.blue),
                    _divider(),
                    _statItem('Verified', verifiedCount, Colors.green),
                    _divider(),
                    _statItem('Rejected', rejectedCount, Colors.red),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            // ── Search ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                height: 44,
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search by pack or area...',
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.45,
                      ),
                      fontSize: 14,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 20,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.45,
                      ),
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: theme.dividerColor.withValues(alpha: 0.5),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: theme.dividerColor.withValues(alpha: 0.5),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppColors.purchaserOrange,
                        width: 1.5,
                      ),
                    ),
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
            ),

            const SizedBox(height: 10),

            // ── Max claims warning ────────────────────────────────────────
            if (claimedCount >= 2)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: Colors.orange,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Maximum 2 active claims reached. Submit an order before claiming another.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ── My Order Cards ────────────────────────────────────────────
            Expanded(
              child: filtered.isEmpty
                  ? _emptyMyOrdersState()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (ctx, i) {
                        final r = filtered[i];
                        return ProcurementCard(
                          request: r,
                          actionLabel: _actionLabel(r),
                          onTap: () => _handleCardTap(r, displayName),
                          releaseButton: r.isClaimed
                              ? _buildReleaseButton(r, displayName, isDark)
                              : null,
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  String _actionLabel(ProcurementRequest r) {
    switch (r.status) {
      case ProcurementStatus.pending:
        return r.isClaimed ? 'Submit Purchase' : 'View';
      case ProcurementStatus.purchased:
        return 'View Details';
      case ProcurementStatus.rejected:
        return 'Resubmit';
      case ProcurementStatus.verified:
        return 'Verified ✓';
      default:
        return 'View';
    }
  }

  void _handleCardTap(ProcurementRequest r, String displayName) {
    final readOnly =
        r.status != ProcurementStatus.pending &&
        r.status != ProcurementStatus.rejected;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseEntryScreen(request: r, isReadOnly: readOnly),
      ),
    );
  }

  Widget _buildReleaseButton(
    ProcurementRequest r,
    String displayName,
    bool isDark,
  ) {
    return IconButton(
      icon: const Icon(Icons.undo_rounded, size: 20, color: Colors.orange),
      tooltip: 'Release back to pool',
      onPressed: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Release Order?'),
            content: const Text(
              'This will return the order to the pool so another purchaser can claim it.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Release'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;

        await ProcurementService.releaseRequest(
          requestId: r.id,
          releasedByName: displayName,
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Order released back to pool.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      },
    );
  }

  // ── Tab 3: Active Claims (Supervisors Only) ──────────────────────────────

  Widget _buildActiveClaims(
    String uid,
    String displayName,
    ThemeData theme,
    bool isDark,
  ) {
    return StreamBuilder<List<ProcurementRequest>>(
      stream: ProcurementService.streamAllActiveClaims(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.purchaserOrange),
          );
        }
        if (snapshot.hasError) return _errorState('${snapshot.error}');

        final all = snapshot.data ?? [];
        if (all.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.supervised_user_circle_outlined,
                  size: 64,
                  color: Colors.blue.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No active claims by anyone',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        // Apply search filter
        final filtered = _searchQuery.isEmpty
            ? all
            : all.where((r) {
                final s = _searchQuery;
                return r.packName.toLowerCase().contains(s) ||
                    r.familyAddress.toLowerCase().contains(s) ||
                    (r.claimedByName?.toLowerCase().contains(s) ?? false);
              }).toList();

        return Column(
          children: [
            // ── Search ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: SizedBox(
                height: 44,
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search by pack, area or purchaser...',
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.45,
                      ),
                      fontSize: 14,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 20,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.45,
                      ),
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: theme.dividerColor.withValues(alpha: 0.5),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: theme.dividerColor.withValues(alpha: 0.5),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppColors.purchaserOrange,
                        width: 1.5,
                      ),
                    ),
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
            ),

            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (ctx, i) {
                  final r = filtered[i];
                  return ProcurementCard(
                    request: r,
                    actionLabel: 'Details',
                    onTap: () => _handleCardTap(r, displayName),
                    releaseButton: _buildForceReleaseButton(
                      r,
                      displayName,
                      isDark,
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildForceReleaseButton(
    ProcurementRequest r,
    String displayName,
    bool isDark,
  ) {
    return IconButton(
      icon: const Icon(
        Icons.remove_circle_outline,
        size: 20,
        color: Colors.red,
      ),
      tooltip: 'Force Unassign',
      onPressed: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              'Force Unassign Order?',
              style: TextStyle(color: Colors.red),
            ),
            content: Text(
              'This will forcibly return the order to the pool, unassigning it from ${r.claimedByName ?? 'the purchaser'}.\n\n'
              'Only use this if the purchaser has gone AWOL or abandoned the task.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Force Unassign'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;

        await ProcurementService.forceReleaseRequest(
          requestId: r.id,
          adminName: displayName,
          previousPurchaserName: r.claimedByName ?? 'Unknown',
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Order forcibly returned to pool.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      },
    );
  }

  // ── Helper widgets ────────────────────────────────────────────────────────

  Widget _statItem(String label, int count, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: count > 0 ? color : color.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
    height: 32,
    width: 1,
    color: Colors.grey.withValues(alpha: 0.2),
  );

  Widget _emptyPoolState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 64,
            color: Colors.green.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          const Text(
            'No orders available right now',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'New pack orders appear here when families are fully funded.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _emptyMyOrdersState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shopping_cart_outlined,
            size: 64,
            color: Colors.grey.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          const Text(
            'No active orders',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Claim an order from the Available Orders tab.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _errorState(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: 56,
              color: Colors.red.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              'Could not load orders',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              msg,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
