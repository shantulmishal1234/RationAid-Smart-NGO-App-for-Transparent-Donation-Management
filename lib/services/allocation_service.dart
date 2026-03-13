import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ration_aid/models/family_model.dart';
import 'package:ration_aid/services/funding_service.dart';

/// Represents a family scored for smart allocation priority.
class FamilyScore {
  final String familyId;
  final Family family;
  final double score;
  final String scoreReason; // Human-readable explanation

  const FamilyScore({
    required this.familyId,
    required this.family,
    required this.score,
    required this.scoreReason,
  });
}

/// Service for smart fund allocation — priority scoring and auto-distribution.
class AllocationService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─────────────────────────────────────────────────────────────────────────
  // PRIORITY SCORING
  // ─────────────────────────────────────────────────────────────────────────

  /// Compute and return priority-scored families for Smart Give.
  ///
  /// Score formula:
  ///   score = daysListed×0.3 + deficitRatio×40 + (familySize/15)×0.2 + emergency×5
  static Future<List<FamilyScore>> getTopPriorityFamilies({
    int limit = 10,
  }) async {
    final snapshot = await _db
        .collection('families')
        .where('status', isEqualTo: 'accepted')
        .get();

    final scores = <FamilyScore>[];
    final now = DateTime.now();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final fundingStatus = data['fundingStatus'] ?? 'pending';
      if (fundingStatus == 'fully_funded') continue; // Skip complete families

      final double target =
          ((data['assignedPackBudget'] ?? data['targetAmount'] ?? 0) as num)
              .toDouble();
      final double raised = (data['raisedAmount'] as num? ?? 0).toDouble();

      if (target <= 0) continue;

      final double deficitRatio = (target - raised) / target;
      final double gap = target - raised;
      if (gap <= 0) continue;

      final DateTime createdAt = data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : now.subtract(const Duration(days: 1));
      final int daysListed = now.difference(createdAt).inDays;

      final int familySize = (data['familySize'] as num? ?? 1).toInt();
      final bool isEmergency = data['isEmergency'] ?? false;

      // Issue #13 Fix: Normalized scoring formula.
      // All terms now produce values in comparable ranges [0..1] before weighting.
      //   w_time     = 0.20  (days waiting, capped at 180)
      //   w_deficit  = 0.55  (% still unfunded — main signal)
      //   w_size     = 0.10  (family size normalized to typical max of 12)
      //   w_emergency = 0.15 (binary emergency flag)
      final double normalizedDays = (daysListed / 180.0).clamp(0.0, 1.0);
      final double normalizedSize = (familySize / 12.0).clamp(0.0, 1.0);
      final double score =
          (normalizedDays * 0.20) +
          (deficitRatio * 0.55) +
          (normalizedSize * 0.10) +
          (isEmergency ? 0.15 : 0.0);

      // Human-readable reason for Smart Give UI display
      String reason;
      if (isEmergency) {
        reason = '⚡ Emergency — ${data['emergencyNote'] ?? 'Critical need'}';
      } else if (daysListed > 60) {
        reason = '$daysListed days without full funding';
      } else if (deficitRatio > 0.8) {
        reason = '${(deficitRatio * 100).toInt()}% still needed';
      } else if (familySize > 8) {
        reason = 'Large family of $familySize members';
      } else {
        reason = 'PKR ${gap.toStringAsFixed(0)} gap remaining';
      }

      final family = Family.fromFirestore(doc);
      scores.add(
        FamilyScore(
          familyId: doc.id,
          family: family,
          score: score,
          scoreReason: reason,
        ),
      );
    }

    scores.sort((a, b) => b.score.compareTo(a.score));
    return scores.take(limit).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SMART GIVE — Split donation across top-priority families
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns which families would receive funds in a Smart Give donation
  /// and how much each would get. Used to preview before confirming.
  static Future<List<Map<String, dynamic>>> previewSmartAllocation(
    double amount,
  ) async {
    final top = await getTopPriorityFamilies(limit: 10);
    if (top.isEmpty) return [];

    final result = <Map<String, dynamic>>[];
    double remaining = amount;

    for (final fs in top) {
      if (remaining <= 0) break;
      final gap = (fs.family.targetAmount - fs.family.raisedAmount).clamp(
        0.0,
        double.infinity,
      );
      final contribution = min(remaining, gap);
      if (contribution <= 0) continue;

      result.add({
        'familyId': fs.familyId,
        'family': fs.family,
        'contribution': contribution,
        'reason': fs.scoreReason,
        'score': fs.score,
      });
      remaining -= contribution;
    }

    // Any remaining after all families capped → GRF
    if (remaining > 0) {
      result.add({
        'familyId': 'general_relief_fund',
        'family': null,
        'contribution': remaining,
        'reason': 'General Relief Fund',
        'score': 0,
      });
    }

    return result;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SMART IN-KIND — Filter families by offered items
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns priority-scored families that need at least ONE of the donor's
  /// offered items. Used by Smart In-Kind and Multi-Family In-Kind modes.
  ///
  /// [offeredItems] — map of {itemName: quantity} the donor wants to donate.
  /// Only families whose `needs` map contains at least one matching key are
  /// included in the result. Within that set, families are ranked by the
  /// same composite score as getTopPriorityFamilies.
  static Future<List<FamilyScore>> getItemFilteredFamilies(
    Map<String, num> offeredItems, {
    int limit = 10,
  }) async {
    if (offeredItems.isEmpty) return [];

    final snapshot = await _db
        .collection('families')
        .where('status', isEqualTo: 'accepted')
        .get();

    final scores = <FamilyScore>[];
    final now = DateTime.now();
    final offeredKeys = offeredItems.keys.map((k) => k.toLowerCase()).toSet();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final fundingStatus = data['fundingStatus'] ?? 'pending';
      if (fundingStatus == 'fully_funded') continue;

      // Only food families (have a needs map)
      final needsRaw = data['needs'] as Map<String, dynamic>? ?? {};
      if (needsRaw.isEmpty) continue;

      // Check if this family needs any item the donor is offering
      final hasMatch = needsRaw.keys.any(
        (k) => offeredKeys.contains(k.toLowerCase()),
      );
      if (!hasMatch) continue;

      final double target =
          ((data['assignedPackBudget'] ?? data['targetAmount'] ?? 0) as num)
              .toDouble();
      if (target <= 0) continue;

      final double raised = (data['raisedAmount'] as num? ?? 0).toDouble();
      final double deficitRatio = (target - raised) / target;
      if (deficitRatio <= 0) continue;

      final DateTime createdAt = data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : now.subtract(const Duration(days: 1));
      final int daysListed = now.difference(createdAt).inDays;
      final int familySize = (data['familySize'] as num? ?? 1).toInt();
      final bool isEmergency = data['isEmergency'] ?? false;

      final double normalizedDays = (daysListed / 180.0).clamp(0.0, 1.0);
      final double normalizedSize = (familySize / 12.0).clamp(0.0, 1.0);
      final double score =
          (normalizedDays * 0.20) +
          (deficitRatio * 0.55) +
          (normalizedSize * 0.10) +
          (isEmergency ? 0.15 : 0.0);

      String reason;
      if (isEmergency) {
        reason = '⚡ Emergency need';
      } else {
        // Show which offered items this family needs
        final matchedItems = needsRaw.keys
            .where((k) => offeredKeys.contains(k.toLowerCase()))
            .take(2)
            .join(' & ');
        reason = 'Needs $matchedItems';
      }

      scores.add(
        FamilyScore(
          familyId: doc.id,
          family: Family.fromFirestore(doc),
          score: score,
          scoreReason: reason,
        ),
      );
    }

    scores.sort((a, b) => b.score.compareTo(a.score));
    return scores.take(limit).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MULTI-FAMILY IN-KIND WATERFALL
  // ─────────────────────────────────────────────────────────────────────────

  /// Splits donor's offered items across multiple families by need priority.
  ///
  /// Returns a list of splits, each with:
  ///   { 'familyId', 'family', 'items': Map<String,int>, 'reason' }
  /// Any unmatched items that no family needs are returned in a final entry
  /// with familyId = '' (pool/unassigned).
  static Future<List<InKindSplit>> previewInKindWaterfall(
    Map<String, num> offeredItems,
  ) async {
    if (offeredItems.isEmpty) return [];

    final families = await getItemFilteredFamilies(offeredItems, limit: 20);
    if (families.isEmpty) {
      // No matching family — everything goes to pool
      return [
        InKindSplit(
          familyId: '',
          family: null,
          items: Map.from(offeredItems),
          reason: 'No matching family — NGO Pool',
        ),
      ];
    }

    // Remaining quantities to distribute
    final remaining = Map<String, num>.from(offeredItems);
    final splits = <InKindSplit>[];

    for (final fs in families) {
      if (remaining.isEmpty || remaining.values.every((v) => v <= 0)) break;

      final needsRaw = (fs.family.needs) as Map<String, num>? ?? {};
      final Map<String, num> thisShare = {};

      for (final offeredItem in List<String>.from(remaining.keys)) {
        final offeredQty = remaining[offeredItem] ?? 0;
        if (offeredQty <= 0) continue;

        // Find matching need (case-insensitive)
        final matchKey = needsRaw.keys.firstWhere(
          (k) => k.toLowerCase() == offeredItem.toLowerCase(),
          orElse: () => '',
        );
        if (matchKey.isEmpty) continue;

        final needed = needsRaw[matchKey] ?? 0;
        if (needed <= 0) continue;

        final give = offeredQty < needed ? offeredQty : needed;
        thisShare[offeredItem] = give;
        remaining[offeredItem] = offeredQty - give;
        if (remaining[offeredItem]! <= 0) remaining.remove(offeredItem);
      }

      if (thisShare.isNotEmpty) {
        splits.add(
          InKindSplit(
            familyId: fs.familyId,
            family: fs.family,
            items: thisShare,
            reason: fs.scoreReason,
          ),
        );
      }
    }

    // Any leftover → pool
    final leftover = {
      for (final e in remaining.entries)
        if (e.value > 0) e.key: e.value,
    };
    if (leftover.isNotEmpty) {
      splits.add(
        InKindSplit(
          familyId: '',
          family: null,
          items: leftover,
          reason: 'NGO Pool — no matching family',
        ),
      );
    }

    return splits;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AUTO-ALLOCATE GRF — Admin batch action
  // ─────────────────────────────────────────────────────────────────────────

  /// Automatically distribute GRF balance to top-priority families.
  /// Admin calls this from the funding panel.
  ///
  /// [maxPerFamily] caps how much any one family can receive per run.
  /// Issue #6 Fix: Uses a Firestore-based distributed lock (isAllocating flag)
  /// to prevent two admins from running auto-allocate concurrently.
  static Future<AllocationSummary> autoAllocateGeneralFund({
    required String adminUid,
    double maxPerFamily = 10000,
  }) async {
    final ledgerRef = _db.doc(
      'master_ledger/main',
    ); // same as MasterLedger.docPath typically

    // ── Acquire distributed lock ────────────────────────────────────────
    bool lockAcquired = false;
    try {
      await _db.runTransaction<void>((tx) async {
        final snap = await tx.get(ledgerRef);
        final data = snap.data() ?? {};
        if (data['isAllocating'] == true) {
          throw Exception('already_allocating');
        }
        tx.set(ledgerRef, {
          'isAllocating': true,
          'allocationStartedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
      lockAcquired = true;
    } catch (e) {
      if (e.toString().contains('already_allocating')) {
        // Another admin is running allocation — return empty to UI
        return AllocationSummary(allocated: 0, familiesHelped: 0, entries: []);
      }
      rethrow;
    }

    // ── Run allocation (lock is held) ────────────────────────────────────
    try {
      // Read current GRF balance
      final grfSnap = await _db
          .collection('families')
          .doc('general_relief_fund')
          .get();

      if (!grfSnap.exists) {
        return AllocationSummary(allocated: 0, familiesHelped: 0, entries: []);
      }

      double grfBalance = (grfSnap.data()?['raisedAmount'] as num? ?? 0)
          .toDouble();
      if (grfBalance <= 0) {
        return AllocationSummary(allocated: 0, familiesHelped: 0, entries: []);
      }

      final top = await getTopPriorityFamilies(limit: 10);
      double totalAllocated = 0;
      int familiesHelped = 0;
      final entries = <Map<String, dynamic>>[];

      for (final fs in top) {
        if (grfBalance <= 0) break;
        final gap = (fs.family.targetAmount - fs.family.raisedAmount).clamp(
          0.0,
          double.infinity,
        );
        if (gap <= 0) continue;

        final allocation = min(min(grfBalance, gap), maxPerFamily);
        if (allocation <= 0) continue;

        await FundingService.allocateFromGRF(
          targetFamilyId: fs.familyId,
          amount: allocation,
          adminNote:
              'Auto-allocation by system (score: ${fs.score.toStringAsFixed(2)})',
          adminUid: adminUid,
        );

        grfBalance -= allocation;
        totalAllocated += allocation;
        familiesHelped++;
        entries.add({
          'familyId': fs.familyId,
          'amount': allocation,
          'reason': fs.scoreReason,
        });
      }

      return AllocationSummary(
        allocated: totalAllocated,
        familiesHelped: familiesHelped,
        entries: entries,
      );
    } finally {
      // ── Release distributed lock (always) ────────────────────────────
      if (lockAcquired) {
        try {
          await ledgerRef.update({
            'isAllocating': false,
            'allocationEndedAt': FieldValue.serverTimestamp(),
          });
        } catch (_) {
          // Best-effort unlock — ignore error to avoid masking real errors
        }
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // WRITE PRIORITY SCORES — Admin or scheduler refreshes scores
  // ─────────────────────────────────────────────────────────────────────────

  /// Compute and persist priority scores to all open family docs.
  /// Call periodically (e.g., daily) or when admin clicks "Refresh Scores".
  static Future<void> refreshPriorityScores() async {
    final scored = await getTopPriorityFamilies(limit: 200);
    final batch = _db.batch();
    for (final fs in scored) {
      batch.update(_db.collection('families').doc(fs.familyId), {
        'priorityScore': fs.score,
        'lastScoredAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}

/// Summary returned by [AllocationService.autoAllocateGeneralFund]
class AllocationSummary {
  final double allocated;
  final int familiesHelped;
  final List<Map<String, dynamic>> entries;

  const AllocationSummary({
    required this.allocated,
    required this.familiesHelped,
    required this.entries,
  });
}

/// A single family's share in an in-kind waterfall split.
class InKindSplit {
  /// Empty string means "NGO Pool" (unassigned).
  final String familyId;
  final Family? family;

  /// Items allocated to this family. { itemName: quantity }
  final Map<String, num> items;

  /// Human-readable reason (e.g., "Needs Rice & Flour").
  final String reason;

  const InKindSplit({
    required this.familyId,
    required this.family,
    required this.items,
    required this.reason,
  });

  bool get isPool => familyId.isEmpty;
}
