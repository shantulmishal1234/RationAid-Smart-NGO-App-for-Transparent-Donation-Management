import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ration_aid/models/donation_model.dart';
import 'package:ration_aid/models/master_ledger_model.dart';
import 'package:ration_aid/services/allocation_service.dart';

import 'package:ration_aid/services/procurement_service.dart';

class FundingService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static DocumentReference get _masterLedgerRef =>
      _db.doc(MasterLedger.docPath);

  static DocumentReference _familyRef(String familyId) =>
      _db.collection('families').doc(familyId);

  static DocumentReference get _grfRef =>
      _db.collection('families').doc('general_relief_fund');

  // ─────────────────────────────────────────────────────────────────────────
  // PHASE 2 — ATOMIC DONATION ENGINE
  // ─────────────────────────────────────────────────────────────────────────

  /// **Primary donation entry point.**
  ///
  /// Everything happens inside a single Firestore transaction:
  /// 1. Idempotency check — duplicate submissions silently return same result.
  /// 2. Reads family gap — caps effective donation to prevent overfunding.
  /// 3. Overflow auto-routes to General Relief Fund.
  /// 4. Increments master ledger atomically.
  /// 5. Writes immutable donation document.
  ///
  /// Use [allocationMode]:
  ///   - 'direct'  → donor picked a specific family (may overflow to GRF)
  ///   - 'smart'   → system selected family by priority score
  ///   - 'general' → donor chose General Relief Fund directly
  static Future<DonationSubmitResult> submitAtomicDonation({
    required String donorId,
    required String donorName,
    required String donorEmail,
    required String targetFamilyId,
    required double amount,
    required String allocationMode,
    required String idempotencyKey,
    bool anonymous = false,
    String? donationNote,
    String? paymentProofUrl,
  }) async {
    if (amount <= 0) throw Exception('Donation amount must be greater than 0.');

    // ── 0. RESOLVE SMART ALLOCATION ─────────────────────────────────────
    // If the donor chose Smart Give, load the top 10 priority families.
    // We will funnel their donation through a 'waterfall' allocating across these.
    String resolvedFamilyId = targetFamilyId;
    List<FamilyScore> topFamilies = [];
    if (targetFamilyId == 'smart_allocation') {
      topFamilies = await AllocationService.getTopPriorityFamilies(limit: 10);
      if (topFamilies.isEmpty) {
        // No unfunded families — route to GRF perfectly as fallback
        resolvedFamilyId = 'general_relief_fund';
      } else {
        // Flag to trigger the Waterfall algorithm in the tx
        resolvedFamilyId = 'smart_allocation';
      }
    }

    // Ensure master ledger exists before transaction
    await _ensureLedger();

    // P12 Fix — Dedicated idempotency doc used inside the transaction.
    // Collection queries (.where(...).get()) are NOT supported inside Firestore
    // transactions and don't have atomic consistency. A dedicated keyed document
    // (idempotency_keys/{key}) is read via tx.get() — fully atomic.
    final idempotencyRef = _db
        .collection('idempotency_keys')
        .doc(idempotencyKey);

    return await _db.runTransaction<DonationSubmitResult>((tx) async {
      // ── 1. IDEMPOTENCY CHECK (atomic doc read inside tx) ──────────────────
      final existingKey = await tx.get(idempotencyRef);
      if (existingKey.exists) {
        final cached = existingKey.data() as Map<String, dynamic>;
        return DonationSubmitResult(
          donationId: cached['donationId'] as String? ?? '',
          effectiveAmount: (cached['effectiveAmount'] as num?)?.toDouble() ?? 0,
          overflowAmount: (cached['overflowAmount'] as num?)?.toDouble() ?? 0,
          targetFamilyId: cached['familyId'] ?? resolvedFamilyId,
        );
      }

      // ── 2. CALCULATE EFFECTIVE AMOUNT (CAP AT FAMILY GAP) ──────────────
      double effectiveAmount = amount;
      double overflowAmount = 0.0;
      String effectiveFamilyId = resolvedFamilyId;
      List<Map<String, dynamic>>? smartSplits;

      if (allocationMode == 'smart' && resolvedFamilyId == 'smart_allocation') {
        double remainingAmount = amount;
        smartSplits = [];

        for (final fs in topFamilies) {
          if (remainingAmount <= 0) break;

          final familySnap = await tx.get(_familyRef(fs.familyId));
          if (!familySnap.exists) continue;

          final familyData = familySnap.data() as Map<String, dynamic>;
          final double target =
              ((familyData['assignedPackBudget'] ??
                          familyData['targetAmount'] ??
                          0)
                      as num)
                  .toDouble();
          final double raised = (familyData['raisedAmount'] as num? ?? 0)
              .toDouble();

          // TOCTOU Guard: Evaluate live gap inside the atomic lock
          final double gap = (target - raised).clamp(0.0, double.infinity);
          if (gap <= 0) continue;

          final double splitAmount = min(remainingAmount, gap);

          smartSplits.add({'familyId': fs.familyId, 'amount': splitAmount});

          // ── 3. WRITE TO FAMILY WALLET — pending only ──────────────────
          tx.update(_familyRef(fs.familyId), {
            'pendingRaisedAmount': FieldValue.increment(splitAmount),
            'updatedAt': FieldValue.serverTimestamp(),
          });

          remainingAmount -= splitAmount;
        }

        effectiveAmount = amount - remainingAmount; // Successful portion
        overflowAmount = remainingAmount; // GRF gets the rest
      } else if (resolvedFamilyId != 'general_relief_fund') {
        final familySnap = await tx.get(_familyRef(resolvedFamilyId));
        if (!familySnap.exists) {
          throw Exception('Target family not found: $resolvedFamilyId');
        }
        final familyData = familySnap.data() as Map<String, dynamic>;
        final double target =
            ((familyData['assignedPackBudget'] ??
                        familyData['targetAmount'] ??
                        0)
                    as num)
                .toDouble();
        final double raised = (familyData['raisedAmount'] as num? ?? 0)
            .toDouble();
        final double gap = (target - raised).clamp(0.0, double.infinity);

        effectiveAmount = min(amount, gap); // Hard cap — no overfunding
        overflowAmount = amount - effectiveAmount;

        // ── 3. WRITE TO FAMILY WALLET — pending only ──────────────────
        if (effectiveAmount > 0) {
          tx.update(_familyRef(resolvedFamilyId), {
            'pendingRaisedAmount': FieldValue.increment(effectiveAmount),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      // ── 4. OVERFLOW + GENERAL FUND → GRF (ATOMIC) ────────────────────
      final double grfContribution =
          overflowAmount +
          (resolvedFamilyId == 'general_relief_fund' ? amount : 0);

      if (grfContribution > 0) {
        // Ensure GRF doc exists (create if needed inside tx update)
        tx.set(_grfRef, {
          'pendingRaisedAmount': FieldValue.increment(grfContribution),
          'area': 'General Relief Fund',
          'city': 'All',
          'targetAmount': 10000000.0,
          'status': 'accepted',
          'familySize': 0,
          'fundingStatus': 'active_pool',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // ── 5. INCREMENT MASTER LEDGER (ATOMIC) ──────────────────────────
      tx.set(_masterLedgerRef, {
        'totalReceived': FieldValue.increment(amount), // Track total intent
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // ── 6. WRITE IMMUTABLE DONATION RECORD ───────────────────────────
      final donationRef = _db.collection('donations').doc();
      tx.set(donationRef, {
        'donorId': donorId,
        'donorName': anonymous ? null : donorName,
        'donorEmail': anonymous ? null : donorEmail,
        'familyId': effectiveFamilyId,
        'allocationMode': allocationMode,
        'donationType': 'cash',
        'amount': amount,
        'effectiveAmount': effectiveAmount > 0 ? effectiveAmount : amount,
        'overflowAmount': overflowAmount,
        'status': 'under_verification',
        'anonymous': anonymous,
        'donationNote': donationNote,
        'paymentProofUrl': paymentProofUrl,
        'idempotencyKey': idempotencyKey,
        'isGrfAllocation': false,
        'isSurplusTransfer': false,
        if (smartSplits != null) 'smartSplits': smartSplits,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'statusHistory': [
          {
            'status': 'under_verification',
            'timestamp': Timestamp.now(),
            'note': 'Submitted by donor',
          },
        ],
      });

      // ── 7. WRITE AUDIT LOG (IMMUTABLE) ───────────────────────────────
      final auditRef = _db.collection('master_ledger_audit').doc();
      tx.set(auditRef, {
        'action': 'donate',
        'amount': amount,
        'effectiveAmount': effectiveAmount > 0 ? effectiveAmount : amount,
        'overflowAmount': overflowAmount,
        'actorId': donorId,
        'targetFamilyId': effectiveFamilyId,
        'allocationMode': allocationMode,
        'reason': donationNote ?? 'Donor contribution',
        'timestamp': FieldValue.serverTimestamp(),
      });

      // P12 Fix — Write idempotency doc atomically so concurrent calls with
      // the same key see it on next tx.get() and return the cached result.
      final submitResult = DonationSubmitResult(
        donationId: donationRef.id,
        effectiveAmount: effectiveAmount > 0 ? effectiveAmount : amount,
        overflowAmount: overflowAmount,
        targetFamilyId: effectiveFamilyId,
      );
      tx.set(idempotencyRef, {
        'donationId': submitResult.donationId,
        'effectiveAmount': submitResult.effectiveAmount,
        'overflowAmount': submitResult.overflowAmount,
        'familyId': submitResult.targetFamilyId,
        'createdAt': FieldValue.serverTimestamp(),
        // TTL: clean up after 7 days via Firestore TTL policy on 'expiresAt'
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 7)),
        ),
      });
      return submitResult;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // GRF ALLOCATION — ATOMIC (Admin action)
  // ─────────────────────────────────────────────────────────────────────────

  /// Allocate funds from the General Relief Fund to a specific family.
  /// Fully atomic — reads and writes GRF balance in a single transaction.
  static Future<void> allocateFromGRF({
    required String targetFamilyId,
    required double amount,
    String adminNote = 'Allocated from General Relief Fund',
    String? adminUid,
  }) async {
    if (amount <= 0) {
      throw Exception('Allocation amount must be greater than 0');
    }
    if (targetFamilyId == 'general_relief_fund') {
      throw Exception('Cannot allocate GRF funds to itself');
    }

    // ── Fetch FIFO Donations (Outside Transaction to prevent deadlocks) ──
    // Firebase SDK explicitly forbids running non-transaction queries inside runTransaction.
    final grfDonationsQuery = await _db
        .collection('donations')
        .where('status', isEqualTo: 'verified')
        .get();

    final grfDocs = grfDonationsQuery.docs.where((doc) {
      final d = doc.data();
      final famId = d['familyId'] as String? ?? '';
      final allocMode = d['allocationMode'] as String? ?? '';
      final overflow = (d['overflowAmount'] as num?)?.toDouble() ?? 0;
      return famId == 'general_relief_fund' ||
          allocMode == 'general' ||
          overflow > 0;
    }).toList();

    grfDocs.sort((a, b) {
      final aTime =
          (a.data()['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bTime =
          (b.data()['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return aTime.compareTo(bTime);
    });

    await _db.runTransaction<void>((tx) async {
      // ── Read GRF balance ─────────────────────────────────────────────
      final grfSnap = await tx.get(_grfRef);
      if (!grfSnap.exists) throw Exception('General Relief Fund not found');
      final grfData = grfSnap.data() as Map<String, dynamic>;
      final double grfBalance = (grfData['raisedAmount'] as num? ?? 0)
          .toDouble();

      if (grfBalance < amount) {
        throw Exception(
          'Insufficient GRF balance. Available: PKR ${grfBalance.toStringAsFixed(0)}',
        );
      }

      // ── Read target family to check gap ─────────────────────────────
      final familySnap = await tx.get(_familyRef(targetFamilyId));
      if (!familySnap.exists) throw Exception('Target family not found');
      final familyData = familySnap.data() as Map<String, dynamic>;
      final double target =
          ((familyData['assignedPackBudget'] ?? familyData['targetAmount'] ?? 0)
                  as num)
              .toDouble();
      final double raised = (familyData['raisedAmount'] as num? ?? 0)
          .toDouble();
      final double gap = (target - raised).clamp(0.0, double.infinity);
      final double effective = min(amount, gap); // never over-allocate

      // ── Fetch fresh snapshots of ALL queued FIFO donations first (Read Phase) ──
      // Firebase strictly requires ALL reads to execute before ANY writes begin!
      final List<DocumentSnapshot> fifoSnaps = [];
      for (var doc in grfDocs) {
        final snap = await tx.get(doc.reference);
        if (snap.exists) fifoSnaps.add(snap);
      }

      // ── Deduct from GRF ──────────────────────────────────────────────
      tx.update(_grfRef, {
        'raisedAmount': FieldValue.increment(-effective),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // ── Credit to family ─────────────────────────────────────────────
      if (effective > 0) {
        final isFull = target > 0 && (raised + effective) >= target;
        tx.update(_familyRef(targetFamilyId), {
          'raisedAmount': FieldValue.increment(effective),
          'fundingStatus': isFull ? 'fully_funded' : 'partially_funded',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // ── Update master ledger ─────────────────────────────────────────
      tx.update(_masterLedgerRef, {
        'totalAllocated': FieldValue.increment(effective),
        'generalPoolBalance': FieldValue.increment(-effective),
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      // ── Create verified pseudo-donation record ───────────────────────
      final donationRef = _db.collection('donations').doc();
      tx.set(donationRef, {
        'donorId': 'grf_allocation',
        'donorName': 'General Relief Fund',
        'donorEmail': null,
        'familyId': targetFamilyId,
        'allocationMode': 'general',
        'donationType': 'cash',
        'amount': effective,
        'effectiveAmount': effective,
        'overflowAmount': 0,
        'status': 'verified',
        'anonymous': false,
        'donationNote': adminNote,
        'allocatedByUid': adminUid,
        'isGrfAllocation': true,
        // Fix #3 — deterministic idempotency key: adminUid+family+amount+minute-slot.
        // Makes admin allocation retries safe; timestamp-based keys could diverge
        // if two identical allocations were submitted within the same millisecond.
        'idempotencyKey':
            'grf_${adminUid ?? 'sys'}_${targetFamilyId}_${amount.toInt()}_${(DateTime.now().millisecondsSinceEpoch ~/ 60000)}',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'statusHistory': [
          {
            'status': 'verified',
            'timestamp': Timestamp.now(),
            'note': 'GRF allocation by admin: $adminNote',
          },
        ],
      });

      // ── FIFO Consumption of Donor GRF Contributions ──────────────────
      // Consume the pre-fetched FIFO queue snapshots safely.
      double remainingToConsume = effective;

      for (var freshSnap in fifoSnaps) {
        if (remainingToConsume <= 0) break;

        final data = freshSnap.data() as Map<String, dynamic>;

        // Target the correct metric based on whether this was a direct GRF donation or an overflow
        final bool isDirectGrf =
            data['familyId'] == 'general_relief_fund' ||
            data['allocationMode'] == 'general';
        final double donationEffective = isDirectGrf
            ? ((data['effectiveAmount'] as num?)?.toDouble() ?? 0)
            : ((data['overflowAmount'] as num?)?.toDouble() ?? 0);

        final double donationAllocated =
            (data['allocatedAmount'] as num?)?.toDouble() ?? 0;

        final double unconsumed = donationEffective - donationAllocated;
        if (unconsumed <= 0) continue;

        final double consumption = min(unconsumed, remainingToConsume);
        remainingToConsume -= consumption;

        final bool isFullyConsumed =
            (donationAllocated + consumption) >= donationEffective;

        final updatePayload = <String, dynamic>{
          'allocatedAmount': FieldValue.increment(consumption),
          'grfAllocations': FieldValue.arrayUnion([
            {
              'familyId': targetFamilyId,
              'amount': consumption,
              'date': Timestamp.now(),
            },
          ]),
          'updatedAt': FieldValue.serverTimestamp(),
        };

        if (isFullyConsumed) {
          updatePayload['status'] = 'closed'; // Becomes 'Completed' on UI
          updatePayload['statusHistory'] = FieldValue.arrayUnion([
            {
              'status': 'closed',
              'timestamp': Timestamp.now(),
              'note': 'Funds successfully deployed to a family in need.',
            },
          ]);
        }

        tx.update(freshSnap.reference, updatePayload);
      }
      // ─────────────────────────────────────────────────────────────────

      // ── Audit log ────────────────────────────────────────────────────
      tx.set(_db.collection('master_ledger_audit').doc(), {
        'action': 'allocate',
        'amount': effective,
        'actorId': adminUid ?? 'system',
        'targetFamilyId': targetFamilyId,
        'allocationMode': 'general',
        'reason': adminNote,
        'timestamp': FieldValue.serverTimestamp(),
      });
    });

    // Post-transaction: trigger procurement if now fully funded
    final familyDoc = await _familyRef(targetFamilyId).get();
    if (familyDoc.exists) {
      final d = familyDoc.data() as Map<String, dynamic>;
      if (d['fundingStatus'] == 'fully_funded' &&
          (d['fulfillmentStatus'] ?? 'pending') == 'pending') {
        await ProcurementService.checkAndGenerateRequest(targetFamilyId);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SURPLUS TRANSFER — ATOMIC (Admin action)
  // ─────────────────────────────────────────────────────────────────────────

  /// Transfer surplus from an over-funded family to another family or GRF.
  /// Fully atomic — prevents double-spend via transaction.
  static Future<void> transferSurplus({
    required String fromFamilyId,
    required String toFamilyId,
    required double amount,
    String adminNote = 'Surplus transfer',
    String? adminUid,
  }) async {
    if (amount <= 0) throw Exception('Transfer amount must be greater than 0');
    if (fromFamilyId == toFamilyId) {
      throw Exception('Cannot transfer to same family');
    }

    await _db.runTransaction<void>((tx) async {
      // ── Read source family ───────────────────────────────────────────
      final srcSnap = await tx.get(_familyRef(fromFamilyId));
      if (!srcSnap.exists) throw Exception('Source family not found');
      final srcData = srcSnap.data() as Map<String, dynamic>;
      final double srcTarget =
          ((srcData['assignedPackBudget'] ?? srcData['targetAmount'] ?? 0)
                  as num)
              .toDouble();
      final double srcRaised = (srcData['raisedAmount'] as num? ?? 0)
          .toDouble();
      final double srcSurplus = (srcRaised - srcTarget).clamp(
        0.0,
        double.infinity,
      );

      if (srcSurplus < amount) {
        throw Exception(
          'Insufficient surplus. Available: PKR ${srcSurplus.toStringAsFixed(0)}',
        );
      }

      // ── Deduct from source ───────────────────────────────────────────
      tx.update(_familyRef(fromFamilyId), {
        'raisedAmount': FieldValue.increment(-amount),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // ── Credit to destination ────────────────────────────────────────
      if (toFamilyId == 'general_relief_fund') {
        tx.set(_grfRef, {
          'raisedAmount': FieldValue.increment(amount),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        // P14 Fix — Also increment totalAllocated to keep master ledger accurate.
        // Previously only generalPoolBalance was updated, undercounting allocations.
        tx.set(_masterLedgerRef, {
          'generalPoolBalance': FieldValue.increment(amount),
          'totalAllocated': FieldValue.increment(amount),
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        // Issue #10 Fix: read destination to recalculate fundingStatus atomically
        final destSnap = await tx.get(_familyRef(toFamilyId));
        final destData = destSnap.data() as Map<String, dynamic>? ?? {};
        final double destTarget =
            ((destData['assignedPackBudget'] ?? destData['targetAmount'] ?? 0)
                    as num)
                .toDouble();
        final double destRaised = (destData['raisedAmount'] as num? ?? 0)
            .toDouble();
        final double newDestRaised = destRaised + amount;
        final bool destFull = destTarget > 0 && newDestRaised >= destTarget;

        tx.update(_familyRef(toFamilyId), {
          'raisedAmount': FieldValue.increment(amount),
          'fundingStatus': destFull ? 'fully_funded' : 'partially_funded',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // ── Audit record ─────────────────────────────────────────────────
      tx.set(_db.collection('pool_transfers').doc(), {
        'fromFamilyId': fromFamilyId,
        'toFamilyId': toFamilyId,
        'amount': amount,
        'note': adminNote,
        'adminUid': adminUid,
        'createdAt': FieldValue.serverTimestamp(),
        'type': 'surplus_transfer',
      });

      // ── Immutable audit log ──────────────────────────────────────────
      tx.set(_db.collection('master_ledger_audit').doc(), {
        'action': 'surplus_transfer',
        'amount': amount,
        'actorId': adminUid ?? 'system',
        'targetFamilyId': toFamilyId,
        'sourceFamilyId': fromFamilyId,
        'allocationMode': 'general',
        'reason': adminNote,
        'timestamp': FieldValue.serverTimestamp(),
      });
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // VERIFY DONATION (Admin action)
  // ─────────────────────────────────────────────────────────────────────────

  /// C3 Fix — Verify a donation inside a SINGLE atomic transaction that:
  ///   1. Guards against double-verification (precondition status check)
  ///   2. Moves cash from pendingRaisedAmount → raisedAmount (atomic)
  ///   3. Decrements in-kind needs atomically (C1 Fix)
  ///   4. Sets a `pendingProcurement` flag if newly fully funded (P9 Fix)
  static Future<void> verifyDonation(String donationId) async {
    final donationRef = _db.collection('donations').doc(donationId);

    List<String> procurementFamilyIds = [];

    // \u2500\u2500 Phase IK: Pre-Transaction In-Kind Setup \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
    // Fetch donation data outside the transaction to compute in-kind values
    // and build the warehouse batch. This avoids the Android/iOS platform-channel
    // deadlock from running non-transactional queries inside runTransaction.
    final donationPreSnap = await donationRef.get();
    if (!donationPreSnap.exists) throw Exception('Donation not found');
    final donationPreData = donationPreSnap.data()!;

    final String preType = donationPreData['donationType'] as String? ?? 'cash';
    final Map<String, dynamic>? preItems =
        donationPreData['items'] as Map<String, dynamic>?;
    final String preFamilyId = donationPreData['familyId'] as String? ?? '';
    final String preDonorId = donationPreData['donorId'] as String? ?? '';
    final String preDonorName = donationPreData['donorName'] as String? ?? '';
    final String prePickupAddress =
        donationPreData['pickupAddress'] as String? ?? '';
    final String preContactNumber =
        donationPreData['contactNumber'] as String? ?? '';
    final Map<String, String>? preItemUnits;
    Map<String, String> packUnitsMap = {}; // will be populated from pack lookup
    if (donationPreData['itemUnits'] != null) {
      preItemUnits = Map<String, String>.from(
        donationPreData['itemUnits'] as Map,
      );
    } else {
      preItemUnits = null; // will be derived from pack below
    }

    // Snapshot item prices from pack (outside transaction — safe from deadlock)
    double inKindLockedValue = 0.0;
    final Map<String, double> itemValueSnapshot = {};

    if (preType == 'inKind' && preItems != null) {
      // Find a pack to get prices from. If preFamilyId is provided, use its pack.
      // Else, find ANY pack to provide a reasonable valuation for Pool mode.
      String? assignedPackId;
      if (preFamilyId.isNotEmpty && preFamilyId != 'general_relief_fund') {
        final familyPreSnap = await _db
            .collection('families')
            .doc(preFamilyId)
            .get();
        final familyPreData = familyPreSnap.data() ?? {};
        assignedPackId = familyPreData['assignedPackId'] as String?;
      }

      // Fallback: If no pack assigned (Pool mode), take the first available pack for pricing
      if (assignedPackId == null || assignedPackId.isEmpty) {
        final anyPackSnap = await _db
            .collection('assistance_packs')
            .limit(1)
            .get();
        if (anyPackSnap.docs.isNotEmpty) {
          assignedPackId = anyPackSnap.docs.first.id;
        }
      }

      if (assignedPackId != null && assignedPackId.isNotEmpty) {
        final packSnap = await _db
            .collection('assistance_packs')
            .doc(assignedPackId)
            .get();
        if (packSnap.exists) {
          final packData = packSnap.data()!;
          final List<dynamic> packItems =
              packData['items'] as List<dynamic>? ?? [];
          final Map<String, double> priceMap = {};
          for (final pi in packItems) {
            final name = pi['name'] as String? ?? '';
            final cost =
                (num.tryParse(pi['estimatedCost']?.toString() ?? '0') ?? 0)
                    .toDouble();
            // P12 Fix — Use quantityNum for accurate price-per-unit calculation.
            // Legacy 'quantity' string (e.g. "15 kg") fails num.tryParse and defaults to 1,
            // causing 15x or 0.5x valuation errors.
            final qtyNum =
                (num.tryParse(pi['quantityNum']?.toString() ?? '') ??
                        num.tryParse(pi['quantity']?.toString() ?? '1') ??
                        1)
                    .toDouble();
            final unit = pi['unit'] as String? ?? '';
            if (name.isNotEmpty && qtyNum > 0) {
              priceMap[name] = cost / qtyNum; // price per unit (e.g. per kg)
              if (unit.isNotEmpty) packUnitsMap[name] = unit;
            }
          }
          preItems.forEach((item, qty) {
            final unitPrice = priceMap[item] ?? 0.0;
            final donatedQty = num.tryParse(qty.toString())?.toDouble() ?? 0.0;
            final lineValue = unitPrice * donatedQty;
            itemValueSnapshot[item] = lineValue;
            inKindLockedValue += lineValue;
          });
        }
      }
      // Merge packUnitsMap as fallback into preItemUnits if not already set
      if (preItemUnits != null && packUnitsMap.isNotEmpty) {
        // Backfill any missing units from pack
        for (final entry in packUnitsMap.entries) {
          preItemUnits.putIfAbsent(entry.key, () => entry.value);
        }
      }
    }
    // ─────────────────────────────────────────────────────────────────────────

    // ── Phase Overlap: Pre-fetch Potential Overlapped Cash Donors ──
    // Fetch verified cash donors so we can seamlessly shift their surplus to GRF
    // if this in-kind donation pushes the family over 100% funding.
    List<DocumentSnapshot> overlapCandidates = [];
    if (preType == 'inKind' &&
        preFamilyId.isNotEmpty &&
        preFamilyId != 'general_relief_fund') {
      final overrideQuery = await _db
          .collection('donations')
          .where('familyId', isEqualTo: preFamilyId)
          .where('donationType', isEqualTo: 'cash')
          .where('status', isEqualTo: 'verified')
          .get();

      overlapCandidates = overrideQuery.docs;
      // Sort LIFO (Newest first)
      overlapCandidates.sort((a, b) {
        final aMap = a.data() as Map<String, dynamic>? ?? {};
        final bMap = b.data() as Map<String, dynamic>? ?? {};
        final aTime = aMap['createdAt'] as Timestamp? ?? Timestamp.now();
        final bTime = bMap['createdAt'] as Timestamp? ?? Timestamp.now();
        return bTime.compareTo(aTime); // Descending
      });
    }

    await _db.runTransaction<void>((tx) async {
      // C3 — Read donation INSIDE tx for precondition check
      final donationSnap = await tx.get(donationRef);
      if (!donationSnap.exists) throw Exception('Donation not found');
      final donationData = donationSnap.data()!;

      // C3 — Precondition: only verify if still under_verification
      final currentStatus = donationData['status'] as String? ?? '';
      if (currentStatus == DonationStatus.verified.toFirestore()) {
        // Already verified — idempotent no-op
        return;
      }
      if (currentStatus != 'under_verification' && currentStatus != 'pending') {
        throw Exception('Cannot verify donation in "$currentStatus" state.');
      }

      final String familyId = donationData['familyId'] as String? ?? '';
      final String donationType =
          donationData['donationType'] as String? ?? 'cash';
      final Map<String, dynamic>? items =
          donationData['items'] as Map<String, dynamic>?;
      final double effectiveAmount =
          (num.tryParse(donationData['effectiveAmount']?.toString() ?? '0') ??
                  0)
              .toDouble();

      final double overflowAmount =
          (num.tryParse(donationData['overflowAmount']?.toString() ?? '0') ?? 0)
              .toDouble();
      final List<dynamic>? smartSplits =
          donationData['smartSplits'] as List<dynamic>?;

      // ── READS ────────────────────────────────────────────────────────
      DocumentSnapshot? familySnap;
      if (familyId.isNotEmpty &&
          familyId != 'general_relief_fund' &&
          familyId != 'smart_allocation') {
        familySnap = await tx.get(_familyRef(familyId));
      }

      Map<String, DocumentSnapshot> smartFamilySnaps = {};
      if (smartSplits != null) {
        for (final split in smartSplits) {
          final String sId = split['familyId'] as String? ?? '';
          // Skip pool entries (empty ID) and GRF — they have no family doc to read
          if (sId.isEmpty || sId == 'general_relief_fund') continue;
          smartFamilySnaps[sId] = await tx.get(_familyRef(sId));
        }
      }

      // Read overlap candidates inside tx to ensure data integrity
      List<DocumentSnapshot> freshOverlapCandidates = [];
      for (final doc in overlapCandidates) {
        final snap = await tx.get(doc.reference);
        if (snap.exists) freshOverlapCandidates.add(snap);
      }

      // ── WRITES ───────────────────────────────────────────────────────
      // 1. Update donation status to verified (inside tx)
      final donationUpdate = <String, dynamic>{
        'status': DonationStatus.verified.toFirestore(),
        'updatedAt': FieldValue.serverTimestamp(),
        'statusHistory': FieldValue.arrayUnion([
          StatusHistoryEntry(
            status: DonationStatus.verified,
            timestamp: DateTime.now(),
            note: 'Verified by admin',
          ).toMap(),
        ]),
      };

      if (donationType == 'inKind' && inKindLockedValue > 0) {
        donationUpdate['amount'] = inKindLockedValue;
        donationUpdate['effectiveAmount'] = inKindLockedValue;
        donationUpdate['declaredValue'] = inKindLockedValue;
        donationUpdate['itemValueSnapshot'] = itemValueSnapshot;
        donationUpdate['lockedInKindValue'] = inKindLockedValue;
        // P12 Fix — Ensure itemUnits are captured even if missing from submission.
        // Prefer actual units from the pack catalogue; fall back to empty strings.
        if (donationData['itemUnits'] == null) {
          final fallbackUnits = packUnitsMap.isNotEmpty ? packUnitsMap : {};
          donationUpdate['itemUnits'] =
              (donationData['items'] as Map<String, dynamic>? ?? {}).map(
                (k, v) => MapEntry(k, (fallbackUnits[k] as String?) ?? ''),
              );
        }
      }

      tx.update(donationRef, donationUpdate);

      // 1b. If there is an overflow, route it to the General Relief Fund (GRF).
      // Or if the entire donation was originally destined for GRF.
      final bool isGrfDirect = familyId == 'general_relief_fund';
      final double amountToGrf = isGrfDirect ? effectiveAmount : overflowAmount;

      if (amountToGrf > 0) {
        tx.set(_grfRef, {
          'raisedAmount': FieldValue.increment(amountToGrf),
          'pendingRaisedAmount': FieldValue.increment(-amountToGrf),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // P15 Fix — Additionally track overflow additions in the Master Ledger
        // to ensure the general pool balance reflects the overflow.
        tx.set(_masterLedgerRef, {
          'generalPoolBalance': FieldValue.increment(amountToGrf),
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (smartSplits != null) {
        for (final split in smartSplits) {
          final String sId = split['familyId'] as String;
          if (sId.isEmpty || sId == 'general_relief_fund') {
            continue; // Handled by separate GRF logic or warehouse stock
          }

          if (donationType == 'cash') {
            final double splitAmt =
                (num.tryParse(split['amount']?.toString() ?? '0') ?? 0)
                    .toDouble();
            final sSnap = smartFamilySnaps[sId];
            if (sSnap != null && sSnap.exists && splitAmt > 0) {
              final sd = sSnap.data() as Map<String, dynamic>;
              final double target =
                  (num.tryParse(
                            (sd['assignedPackBudget'] ??
                                    sd['targetAmount'] ??
                                    0)
                                .toString(),
                          ) ??
                          0)
                      .toDouble();
              final double currentRaised =
                  (num.tryParse(sd['raisedAmount']?.toString() ?? '0') ?? 0)
                      .toDouble();

              final double newRaised = currentRaised + splitAmt;
              final bool isFull = target > 0 && newRaised >= target;
              final String newFundingStatus = isFull
                  ? 'fully_funded'
                  : 'partially_funded';

              tx.update(_familyRef(sId), {
                'raisedAmount': FieldValue.increment(splitAmt),
                'pendingRaisedAmount': FieldValue.increment(-splitAmt),
                'fundingStatus': newFundingStatus,
                'updatedAt': FieldValue.serverTimestamp(),
              });

              if (isFull &&
                  (sd['fulfillmentStatus'] as String? ?? 'pending') ==
                      'pending') {
                procurementFamilyIds.add(sId);
              }
            }
          } else if (donationType == 'inKind') {
            // ── Smart In-Kind: Process Waterfall Needs Reservation ──
            final splitItems = split['items'] as Map<String, dynamic>? ?? {};
            if (splitItems.isNotEmpty) {
              final sSnap = smartFamilySnaps[sId];
              if (sSnap != null && sSnap.exists) {
                final sd = sSnap.data() as Map<String, dynamic>;
                final Map<String, dynamic> needsUpdates = {};

                splitItems.forEach((item, qty) {
                  final num currentNeed =
                      num.tryParse(sd['needs']?[item]?.toString() ?? '0') ?? 0;
                  final num donated = num.tryParse(qty.toString()) ?? 0;
                  final num newNeed = (currentNeed - donated).clamp(
                    0.0,
                    99999.0,
                  );
                  needsUpdates['needs.$item'] = newNeed;
                  needsUpdates['pendingNeeds.$item'] = FieldValue.delete();
                });

                tx.update(_familyRef(sId), {
                  ...needsUpdates,
                  'updatedAt': FieldValue.serverTimestamp(),
                });
              }
            }
          }
        }
      } else if (familySnap != null && familySnap.exists) {
        final d = familySnap.data() as Map<String, dynamic>;
        final double target =
            (num.tryParse(
                      (d['assignedPackBudget'] ?? d['targetAmount'] ?? 0)
                          .toString(),
                    ) ??
                    0)
                .toDouble();
        final double currentRaised =
            (num.tryParse(d['raisedAmount']?.toString() ?? '0') ?? 0)
                .toDouble();

        if (donationType == 'cash' && effectiveAmount > 0) {
          // 2. Move cash amount from pending → verified atomically
          final double newRaised = currentRaised + effectiveAmount;
          final bool isFull = target > 0 && newRaised >= target;
          final String newFundingStatus = isFull
              ? 'fully_funded'
              : 'partially_funded';

          tx.update(_familyRef(familyId), {
            'raisedAmount': FieldValue.increment(effectiveAmount),
            'pendingRaisedAmount': FieldValue.increment(-effectiveAmount),
            'fundingStatus': newFundingStatus,
            'updatedAt': FieldValue.serverTimestamp(),
          });

          // P9 Fix — Set flag inside tx instead of post-tx read+trigger
          if (isFull &&
              (d['fulfillmentStatus'] as String? ?? 'pending') == 'pending') {
            procurementFamilyIds.add(familyId);
          }
        } else if (donationType == 'inKind' && items != null) {
          // ── In-Kind Verification (Phase IK) ──
          // We reserve the items in 'needs' map, but we DO NOT update monetary fields yet.
          // Recognition of value (inKindValue/combinedProgress) is delayed until the
          // Purchaser module marks the inbound pickup as 'collected' (status: 'stocked').
          final Map<String, dynamic> needsUpdates = {};
          items.forEach((item, qty) {
            final num currentNeed =
                num.tryParse(d['needs']?[item]?.toString() ?? '0') ?? 0;
            final num donated = num.tryParse(qty.toString()) ?? 0;
            final num newNeed = (currentNeed - donated).clamp(0.0, 99999.0);
            needsUpdates['needs.$item'] = newNeed;
            // G6 Fix — clear pendingNeeds so donor screen stops showing "(pending)"
            // once the donation has been admin-verified and the pickup task created.
            needsUpdates['pendingNeeds.$item'] = FieldValue.delete();
          });

          // Write reserved needs only — delayed monetary recognition (Sync Fix)
          tx.update(_db.collection('families').doc(familyId), {
            ...needsUpdates,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
    });

    // ── In-Kind: unified pickup creation for BOTH direct-family, GRF pool, and Smart Split.
    //
    // For Smart Split and GRF Pool (no specific family), we still create a single
    // Purchaser pickup so the donor's items are physically collected first as a single batch.
    // For Smart Split, the actual separation of items into multiple warehouse_stock docs
    // happens LATER when the purchaser marks the items as collected.
    if (preType == 'inKind' && preItems != null) {
      final bool isGrfPool =
          preFamilyId.isEmpty || preFamilyId == 'general_relief_fund';
      final bool isSmartSplit = preFamilyId == 'smart_allocation';
      final String effectiveFamilyIdForPickup = isGrfPool
          ? 'general_relief_fund'
          : preFamilyId;

      final batch = _db.batch();
      final stockRef = _db.collection('warehouse_stock').doc();
      final pickupRef = _db.collection('inbound_pickups').doc();

      final Map<String, num> typedItems = preItems.map(
        (k, v) => MapEntry(k, num.tryParse(v.toString()) ?? 0),
      );

      batch.set(stockRef, {
        'familyId': effectiveFamilyIdForPickup,
        'donationId': donationId,
        'donorId': preDonorId,
        'donorName': preDonorName,
        'items': typedItems,
        'itemValueSnapshot': itemValueSnapshot,
        'totalLockedValue': inKindLockedValue,
        'lockedInKindValue': inKindLockedValue,
        'status': 'pending_pickup',
        'pickupAddress': prePickupAddress,
        'contactNumber': preContactNumber,
        'itemUnits': preItemUnits ?? packUnitsMap,
        'isGrfPool': isGrfPool,
        'isSmartSplit': isSmartSplit,
        'inboundPickupId': pickupRef.id,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // InboundPickup task document (assigned to Purchaser open pool)
      batch.set(pickupRef, {
        'batchId': stockRef.id,
        'familyId': effectiveFamilyIdForPickup,
        'donationId': donationId,
        'donorId': preDonorId,
        'donorName': preDonorName,
        'contactNumber': preContactNumber,
        'pickupAddress': prePickupAddress,
        'items': typedItems,
        'itemUnits': preItemUnits ?? packUnitsMap,
        'isGrfPool': isGrfPool,
        'isSmartSplit': isSmartSplit,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // For GRF Pool mode, update donation status to reflect "awaiting pickup"
      if (isGrfPool) {
        batch.update(donationRef, {
          'status': DonationStatus.pendingAssignment.toFirestore(),
          'updatedAt': FieldValue.serverTimestamp(),
          'statusHistory': FieldValue.arrayUnion([
            {
              'status': DonationStatus.pendingAssignment.toFirestore(),
              'timestamp': Timestamp.now(),
              'note': 'Awaiting pickupfrom donor by Purchaser (GRF Pool)',
            },
          ]),
        });
      }

      await batch.commit();
    }

    // ─────────────────────────────────────────────────────────────────────────

    // P9 Fix — Trigger procurement AFTER tx commits using the flag set inside tx.
    // The flag is a local variable set atomically within the tx's closure,
    // not a separate Firestore read, eliminating the TOCTOU window.
    for (final pId in procurementFamilyIds) {
      await ProcurementService.checkAndGenerateRequest(pId);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ASSIGN POOL IN-KIND DONATION — Admin action
  // ─────────────────────────────────────────────────────────────────────────

  /// Admin assigns a GRF Pool in-kind donation (already collected and in warehouse)
  /// to a specific family.
  ///
  /// New lifecycle (Post Fix): Items are already in warehouse_stock with status='grf_pool'
  /// when this is called. This function:
  /// 1. Updates family needs and inKindValue
  /// 2. Re-assigns the existing warehouse_stock batch to the family
  /// 3. Marks the donation as 'pool_assigned' (closed lifecycle for donor UI)
  /// 4. Triggers procurement if the family is now fully funded
  static Future<void> assignPoolInKind({
    required String stockDocId,
    required String targetFamilyId,
  }) async {
    final stockRef = _db.collection('warehouse_stock').doc(stockDocId);
    final stockSnap = await stockRef.get();
    if (!stockSnap.exists) throw Exception('Warehouse stock not found');

    final stockData = stockSnap.data()!;
    final poolItems = Map<String, dynamic>.from(stockData['items'] ?? {});
    final donationId = stockData['donationId'] as String? ?? '';

    // We calculate proportional value for partial hits
    final totalValue =
        (stockData['totalLockedValue'] ?? stockData['lockedInKindValue'] ?? 0)
            .toDouble();

    // 1. Get family needs
    final familySnap = await _db
        .collection('families')
        .doc(targetFamilyId)
        .get();
    if (!familySnap.exists) throw Exception('Target family not found');
    final familyData = familySnap.data()!;
    final needsData = (familyData['needs'] as Map<String, dynamic>?) ?? {};

    // 2. Calculate Split
    final Map<String, num> assignedItems = {};
    final Map<String, num> remainingItems = {};
    int totalPoolQty = 0;
    int totalAssignedQty = 0;

    poolItems.forEach((item, qty) {
      final poolQty = num.tryParse(qty.toString()) ?? 0;
      final needQty = num.tryParse(needsData[item]?.toString() ?? '0') ?? 0;

      totalPoolQty += poolQty.toInt();

      if (needQty > 0) {
        final taken = min(poolQty, needQty);
        assignedItems[item] = taken;
        totalAssignedQty += taken.toInt();

        if (poolQty > taken) {
          remainingItems[item] = poolQty - taken;
        }
      } else {
        remainingItems[item] = poolQty;
      }
    });

    if (assignedItems.isEmpty) {
      throw Exception('Family does not need any of the items in this batch.');
    }

    // Pro-rate the monetary value based on quantity ratio
    final double assignedProportion = totalPoolQty > 0
        ? (totalAssignedQty / totalPoolQty)
        : 1.0;
    final double assignedValue = totalValue * assignedProportion;
    final double remainingValue = totalValue - assignedValue;

    final wsBatch = _db.batch();

    // 3. Update or split warehouse_stock
    if (remainingItems.isEmpty) {
      // Full batch consumed
      wsBatch.update(stockRef, {
        'status': 'assigned',
        'familyId': targetFamilyId,
        'assignedFamilyId': targetFamilyId,
        'assignedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'items': assignedItems,
        'totalLockedValue': assignedValue,
      });

      // Update donation status only if full batch consumed in one go
      if (donationId.isNotEmpty) {
        wsBatch.update(_db.collection('donations').doc(donationId), {
          'familyId': targetFamilyId, // Point donation to the family
          'status': 'pool_assigned', // Triggers donor UI complete state
          'allocationMode': 'pool_assigned',
          'updatedAt': FieldValue.serverTimestamp(),
          'statusHistory': FieldValue.arrayUnion([
            {
              'status': 'pool_assigned',
              'timestamp': Timestamp.now(),
              'note': 'GRF Pool items fully assigned to family.',
            },
          ]),
        });
      }
    } else {
      // Partial batch consumed -> Split!

      // A. Keep remaining items in the original doc
      wsBatch.update(stockRef, {
        'items': remainingItems,
        'totalLockedValue': remainingValue,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // B. Create a NEW doc for the assigned items
      final newStockRef = _db.collection('warehouse_stock').doc();
      final newStockData = Map<String, dynamic>.from(stockData);
      newStockData['id'] = newStockRef.id;
      newStockData['items'] = assignedItems;
      newStockData['totalLockedValue'] = assignedValue;
      newStockData['status'] = 'assigned';
      newStockData['familyId'] = targetFamilyId;
      newStockData['assignedFamilyId'] = targetFamilyId;
      newStockData['assignedAt'] = FieldValue.serverTimestamp();
      newStockData['createdAt'] = FieldValue.serverTimestamp();
      newStockData['updatedAt'] = FieldValue.serverTimestamp();
      wsBatch.set(newStockRef, newStockData);

      // We don't mark the original donation as 'pool_assigned' yet because some of it is still in the pool.
    }

    // 4. Update family: decrement needs + increment inKindValue + combinedProgress
    final Map<String, dynamic> familyUpdates = {};
    assignedItems.forEach((item, qty) {
      final currentNeed = num.tryParse(needsData[item]?.toString() ?? '0') ?? 0;
      familyUpdates['needs.$item'] = (currentNeed - qty).clamp(0, 99999);
    });

    if (assignedValue > 0) {
      familyUpdates['inKindValue'] = FieldValue.increment(assignedValue);
      familyUpdates['combinedProgress'] = FieldValue.increment(assignedValue);
    }
    familyUpdates['updatedAt'] = FieldValue.serverTimestamp();
    wsBatch.update(
      _db.collection('families').doc(targetFamilyId),
      familyUpdates,
    );

    await wsBatch.commit();

    // 5. Trigger procurement if family now fully funded
    final updatedFamSnap = await _db
        .collection('families')
        .doc(targetFamilyId)
        .get();
    if (updatedFamSnap.exists) {
      final d = updatedFamSnap.data()!;
      final double target =
          (num.tryParse(
                    (d['assignedPackBudget'] ?? d['targetAmount'] ?? 0)
                        .toString(),
                  ) ??
                  0)
              .toDouble();
      final double combined =
          (num.tryParse(d['combinedProgress']?.toString() ?? '0') ?? 0)
              .toDouble();
      if (target > 0 &&
          combined >= target &&
          (d['fulfillmentStatus'] as String? ?? 'pending') == 'pending') {
        await ProcurementService.checkAndGenerateRequest(targetFamilyId);
      }
    }

    // 6. Recalculate family funding for real-time dashboard sync
    await recalculateFamilyFunding(targetFamilyId);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SMART IN-KIND SPLIT FUNDING — called by Purchaser on pickup completion
  // ─────────────────────────────────────────────────────────────────────────

  /// Splits a single Smart In-Kind warehouse_stock document into multiple
  /// (one per assigned family + one for GRF pool) when the Purchaser
  /// completes the pickup batch.
  ///
  /// Returns a Map<familyId, lockedValue> of the family-reserved splits
  /// so the caller can immediately apply inKindValue increments without
  /// a costlier Firestore re-query (which also requires a composite index).
  static Future<Map<String, double>> processSmartSplitCollectionToWarehouse({
    required String pickupId,
    required String batchId,
    required String donationId,
    required String pickupAddress,
    required String contactNumber,
    required String donorId,
    required String donorName,
    required Map<String, dynamic> itemUnits,
    required Map<String, num> pickupItems,
    required String collectorUid,
    required String collectorName,
    required String? proofUrl,
    required WriteBatch batch,
  }) async {
    // 1. Fetch original donation to get smartSplits
    final donationSnap = await _db
        .collection('donations')
        .doc(donationId)
        .get();
    if (!donationSnap.exists) return {};

    final donationData = donationSnap.data()!;
    final List<dynamic> smartSplits =
        donationData['smartSplits'] as List<dynamic>? ?? [];

    final stockRef = _db.collection('warehouse_stock').doc(batchId);
    final stockSnap = await stockRef.get();
    if (!stockSnap.exists) return {};

    final stockData = stockSnap.data()!;
    final itemValueSnapshot =
        stockData['itemValueSnapshot'] as Map<String, dynamic>? ?? {};

    // Compute price per unit
    final Map<String, double> pricePerUnit = {};
    pickupItems.forEach((item, qty) {
      final totalQty = qty.toDouble();
      final totalVal =
          (num.tryParse(itemValueSnapshot[item]?.toString() ?? '0') ?? 0)
              .toDouble();
      if (totalQty > 0) pricePerUnit[item] = totalVal / totalQty;
    });

    // Mark the original warehouse_stock doc as 'split_source'
    batch.update(stockRef, {
      'status': 'split_source',
      'receivedBy': collectorUid,
      'receivedByName': collectorName,
      'receivedAt': FieldValue.serverTimestamp(),
      if (proofUrl != null && proofUrl.isNotEmpty) 'pickupProofUrl': proofUrl,
    });

    // Create a new warehouse_stock doc for each split
    // Also build the return map: {familyId → lockedValue} for family-reserved splits.
    final Map<String, double> familySplitValues = {};

    for (final split in smartSplits) {
      final splitFamilyId = split['familyId'] as String? ?? '';
      final splitItemsRaw = split['items'] as Map<String, dynamic>? ?? {};
      if (splitItemsRaw.isEmpty) continue;

      final Map<String, num> splitItems = splitItemsRaw.map(
        (k, v) => MapEntry(k, num.tryParse(v.toString()) ?? 0),
      );

      double splitLockedValue = 0.0;
      splitItems.forEach((item, qty) {
        splitLockedValue += (pricePerUnit[item] ?? 0.0) * qty.toDouble();
      });

      final bool isSplitPool =
          splitFamilyId.isEmpty || splitFamilyId == 'general_relief_fund';
      final String effectiveFid = isSplitPool
          ? 'general_relief_fund'
          : splitFamilyId;

      final newStockRef = _db.collection('warehouse_stock').doc();
      batch.set(newStockRef, {
        'familyId': effectiveFid,
        'donationId': donationId,
        'donorId': donorId,
        'donorName': donorName,
        'items': splitItems,
        'itemValueSnapshot': itemValueSnapshot,
        'totalLockedValue': splitLockedValue,
        'lockedInKindValue': splitLockedValue,
        'status': isSplitPool ? 'grf_pool' : 'received',
        'pickupAddress': pickupAddress,
        'contactNumber': contactNumber,
        'itemUnits': itemUnits,
        'isGrfPool': isSplitPool,
        'isSmartSplit': true,
        'inboundPickupId': pickupId,
        'createdAt': stockData['createdAt'] ?? FieldValue.serverTimestamp(),
        'receivedBy': collectorUid,
        'receivedByName': collectorName,
        'receivedAt': FieldValue.serverTimestamp(),
        if (proofUrl != null && proofUrl.isNotEmpty) 'pickupProofUrl': proofUrl,
      });

      // Track family-reserved splits for immediate funding update by caller.
      if (!isSplitPool && splitLockedValue > 0) {
        familySplitValues[effectiveFid] =
            (familySplitValues[effectiveFid] ?? 0.0) + splitLockedValue;
      }
    }

    return familySplitValues;
  }

  /// Directly increments `inKindValue` and `combinedProgress` on a specific
  /// family after its Smart In-Kind waterfall pickup is marked as collected.
  ///
  /// Mirrors step 4 of `assignPoolInKind` — skips `recalculateFamilyFunding`
  /// entirely because that tool queries donations by `familyId`, but smart-split
  /// donations carry `familyId = 'smart_allocation'` and would never be found.
  static Future<void> applySmartSplitInKindFunding({
    required String familyId,
    required double lockedValue,
  }) async {
    if (familyId.isEmpty ||
        familyId == 'smart_allocation' ||
        familyId == 'general_relief_fund' ||
        lockedValue <= 0)
      return;

    final familyRef = _familyRef(familyId);
    final famSnap = await familyRef.get();
    if (!famSnap.exists) return;
    final d = famSnap.data() as Map<String, dynamic>;

    final double target =
        (num.tryParse(
                  (d['assignedPackBudget'] ?? d['targetAmount'] ?? 0)
                      .toString(),
                ) ??
                0)
            .toDouble();
    final double combined =
        (num.tryParse(d['combinedProgress']?.toString() ?? '0') ?? 0)
            .toDouble();
    final double newCombined = combined + lockedValue;
    final bool isFull = target > 0 && newCombined >= target;

    await familyRef.update({
      'inKindValue': FieldValue.increment(lockedValue),
      'combinedProgress': FieldValue.increment(lockedValue),
      'fundingStatus': isFull ? 'fully_funded' : 'partially_funded',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Trigger procurement if the family is now fully funded
    if (isFull &&
        (d['fulfillmentStatus'] as String? ?? 'pending') == 'pending') {
      await ProcurementService.checkAndGenerateRequest(familyId);
    }
  }

  // ADMIN REPAIR TOOL — keep for reconciliation only
  // ─────────────────────────────────────────────────────────────────────────

  /// **DO NOT call from normal donation flow.**
  /// Use only as admin repair/reconciliation tool to fix data inconsistencies.

  // ─────────────────────────────────────────────────────────────────────────
  // REVERSE DONATION — ATOMIC (Admin rejection)
  // ─────────────────────────────────────────────────────────────────────────

  /// Atomically reverse all financial effects of a donation.
  /// Issue #2 Fix: unverified donations only touched pendingRaisedAmount,
  /// so we only decrement that — not raisedAmount.
  static Future<void> reverseDonation(String donationId) async {
    final donationDoc = await _db.collection('donations').doc(donationId).get();
    if (!donationDoc.exists) throw Exception('Donation not found: $donationId');

    final data = donationDoc.data()!;
    final String familyId = data['familyId'] ?? '';
    final double effectiveAmount =
        (data['effectiveAmount'] as num?)?.toDouble() ?? 0;
    final double overflowAmount =
        (data['overflowAmount'] as num?)?.toDouble() ?? 0;
    final double fullAmount = (data['amount'] as num?)?.toDouble() ?? 0;
    final List<dynamic>? smartSplits = data['smartSplits'] as List<dynamic>?;
    final bool isGrfDirect = familyId == 'general_relief_fund';
    final String donationStatus = data['status'] ?? 'under_verification';
    // Was this donation already verified? If so, undo raisedAmount; otherwise undo pendingRaisedAmount.
    final bool wasVerified = donationStatus == 'verified';

    // Nothing to reverse if amounts are zero
    if (effectiveAmount <= 0 && overflowAmount <= 0 && fullAmount <= 0) return;

    await _db.runTransaction<void>((tx) async {
      // 1. Reverse family raisedAmount or pendingRaisedAmount
      if (smartSplits != null) {
        for (final split in smartSplits) {
          final String sId = split['familyId'] as String;
          final double splitAmt = (split['amount'] as num).toDouble();

          final sSnap = await tx.get(_familyRef(sId));
          if (sSnap.exists) {
            final sd = sSnap.data() as Map<String, dynamic>;
            final double sTarget =
                ((sd['assignedPackBudget'] ?? sd['targetAmount'] ?? 0) as num)
                    .toDouble();

            if (wasVerified) {
              final double currentRaised = (sd['raisedAmount'] as num? ?? 0)
                  .toDouble();
              final double newRaised = (currentRaised - splitAmt).clamp(
                0.0,
                double.infinity,
              );
              tx.update(_familyRef(sId), {
                'raisedAmount': FieldValue.increment(-splitAmt),
                'fundingStatus': newRaised >= sTarget && sTarget > 0
                    ? 'fully_funded'
                    : newRaised > 0
                    ? 'partially_funded'
                    : 'pending',
                'updatedAt': FieldValue.serverTimestamp(),
              });
            } else {
              tx.update(_familyRef(sId), {
                'pendingRaisedAmount': FieldValue.increment(-splitAmt),
                'updatedAt': FieldValue.serverTimestamp(),
              });
            }
          }
        }
      } else if (effectiveAmount > 0 &&
          familyId.isNotEmpty &&
          familyId != 'general_relief_fund') {
        final familySnap = await tx.get(_familyRef(familyId));
        if (familySnap.exists) {
          final familyData = familySnap.data() as Map<String, dynamic>;
          final double target =
              ((familyData['assignedPackBudget'] ??
                          familyData['targetAmount'] ??
                          0)
                      as num)
                  .toDouble();

          if (wasVerified) {
            // P11 Fix — Use FieldValue.increment instead of absolute set.
            // Absolute set races with concurrent reversals (last writer wins).
            // FieldValue.increment is atomic and works correctly under concurrency.
            final double currentRaised =
                (familyData['raisedAmount'] as num? ?? 0).toDouble();
            final double newRaised = (currentRaised - effectiveAmount).clamp(
              0.0,
              double.infinity,
            );
            tx.update(_familyRef(familyId), {
              'raisedAmount': FieldValue.increment(-effectiveAmount),
              'fundingStatus': newRaised >= target && target > 0
                  ? 'fully_funded'
                  : newRaised > 0
                  ? 'partially_funded'
                  : 'pending',
              'updatedAt': FieldValue.serverTimestamp(),
            });
          } else {
            // Donation was not yet verified — only touched pendingRaisedAmount
            tx.update(_familyRef(familyId), {
              'pendingRaisedAmount': FieldValue.increment(-effectiveAmount),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
      }

      // 2. Reverse GRF (overflow or direct GRF donation)
      final double grfReversal =
          overflowAmount + (isGrfDirect ? fullAmount : 0);
      if (grfReversal > 0) {
        if (wasVerified) {
          tx.update(_grfRef, {
            'raisedAmount': FieldValue.increment(-grfReversal),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          tx.update(_grfRef, {
            'pendingRaisedAmount': FieldValue.increment(-grfReversal),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      // 3. Reverse master ledger
      tx.set(_masterLedgerRef, {
        'totalReceived': FieldValue.increment(-fullAmount),
        if (wasVerified)
          'generalPoolBalance': FieldValue.increment(-grfReversal),
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)); // 4. Audit entry
      tx.set(_db.collection('master_ledger_audit').doc(), {
        'action': 'reverse',
        'donationId': donationId,
        'amount': fullAmount,
        'effectiveAmount': effectiveAmount,
        'overflowAmount': overflowAmount,
        'targetFamilyId': familyId,
        'reason': 'Donation rejected by admin',
        'timestamp': FieldValue.serverTimestamp(),
      });
    });
  }

  /// **DO NOT call from normal donation flow.**
  /// Use only as admin repair/reconciliation tool to fix data inconsistencies.
  /// The primary source of truth is now the atomic `raisedAmount` increments.
  static Future<void> recalculateFamilyFunding(String familyId) async {
    try {
      DocumentSnapshot familyDoc = await _db
          .collection('families')
          .doc(familyId)
          .get();

      if (!familyDoc.exists && familyId == 'general_relief_fund') {
        await _grfRef.set({
          'area': 'General Relief Fund',
          'city': 'All',
          'targetAmount': 10000000.0,
          'raisedAmount': 0.0,
          'status': 'accepted',
          'familySize': 0,
          'fundingStatus': 'active_pool',
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        familyDoc = await _db.collection('families').doc(familyId).get();
      } else if (!familyDoc.exists) {
        return;
      }

      final familyData = familyDoc.data() as Map<String, dynamic>;
      final double targetAmount =
          ((familyData['assignedPackBudget'] ?? familyData['targetAmount'] ?? 0)
                  as num)
              .toDouble();

      final donationsSnap = await _db
          .collection('donations')
          .where('familyId', isEqualTo: familyId)
          .where(
            'status',
            whereIn: [
              'under_verification',
              'pending',
              'verified',
              'stocked', // G3 Fix — include stocked items
              'pool_assigned', // GRF Pool items assigned to family
              'received', // Legacy
              'in_process',
              'out_for_delivery',
              'delivered',
              'closed',
            ],
          )
          .get();

      // ── Physical Needs Reconciliation ────────────────────────────────────
      final Map<String, num> baseNeeds = {};
      final Map<String, String> itemUnits = {};

      if (familyData['assignedPackId'] != null) {
        final packDoc = await _db
            .collection('assistance_packs')
            .doc(familyData['assignedPackId'])
            .get();
        if (packDoc.exists) {
          final packData = packDoc.data() as Map<String, dynamic>;
          final List<dynamic> packItems = packData['items'] ?? [];
          for (var item in packItems) {
            final name = item['name'] as String? ?? '';
            final qtyStr = item['quantity'] as String? ?? '0';
            final unit = item['unit'] as String? ?? '';

            // Extract numeric part from string like "0.5 kg" or just "0.5"
            final numericPart = qtyStr.split(' ')[0];
            final qty = num.tryParse(numericPart) ?? 0;

            baseNeeds[name] = qty;
            itemUnits[name] = unit;
          }
        }
      }

      double raisedAmount = 0;
      double pendingAmount = 0;
      double inKindValue = 0;
      final Map<String, num> pendingNeeds = {};

      final Map<String, num> currentNeeds = Map.from(baseNeeds);

      for (var doc in donationsSnap.docs) {
        final data = doc.data();
        final effectiveAmt =
            (data['effectiveAmount'] ??
                    data['lockedInKindValue'] ??
                    data['amount'] ??
                    0)
                .toDouble();
        final status = data['status'];
        final type = data['donationType'];
        final items = data['items'] as Map<String, dynamic>?;

        // Cash logic
        if (type == 'cash' || type == null) {
          if (status == 'verified' ||
              status == 'stocked' ||
              status == 'pool_assigned' ||
              status == 'delivered' ||
              status == 'closed') {
            raisedAmount += effectiveAmt;
          } else if (status == 'under_verification' || status == 'pending') {
            pendingAmount += effectiveAmt;
          }
        }
        // In-Kind logic
        else if (type == 'inKind') {
          // Add to monetary value if verified
          if ((status == 'verified' ||
                  status == 'stocked' ||
                  status == 'pool_assigned' ||
                  status == 'delivered' ||
                  status == 'closed') &&
              effectiveAmt > 0) {
            inKindValue += effectiveAmt;
          }

          // Reconciliation: Subtract VERIFIED items from needs
          if (items != null) {
            if (status == 'verified' ||
                status == 'stocked' ||
                status == 'pool_assigned' ||
                status == 'delivered' ||
                status == 'closed') {
              items.forEach((item, qty) {
                if (currentNeeds.containsKey(item)) {
                  currentNeeds[item] = (currentNeeds[item]! - (qty as num))
                      .clamp(0, double.infinity);
                }
              });
            }
            // Track Pending items separately
            else if (status == 'under_verification' || status == 'pending') {
              items.forEach((item, qty) {
                pendingNeeds[item] = (pendingNeeds[item] ?? 0) + (qty as num);
              });
            }
          }
        }
      }

      // ── GRF Pool In-Kind Contribution ────────────────────────────────────
      // PROBLEM: donations donated to the GRF pool keep `familyId =
      // 'general_relief_fund'` on their donation doc. For partial batch splits,
      // the donation doc is NEVER reassigned to the target family. So the loop
      // above finds ZERO inKind donations for this family and then OVERWRITES
      // the family's `inKindValue` and `combinedProgress` back to 0 — erasing
      // the correct values that `assignPoolInKind` wrote via FieldValue.increment.
      //
      // FIX: additionally query warehouse_stock assigned to this family so that
      // GRF pool contributions are counted even when the donation doc still
      // points to 'general_relief_fund'.
      if (familyId != 'general_relief_fund') {
        final assignedStockSnap = await _db
            .collection('warehouse_stock')
            .where('assignedFamilyId', isEqualTo: familyId)
            .where('status', isEqualTo: 'assigned')
            .get();

        for (final stockDoc in assignedStockSnap.docs) {
          final sd = stockDoc.data();

          // Skip if the linked donation was already counted in the loop above
          // (this happens in the full-batch path where the donation is
          // reassigned to the target family with status='pool_assigned').
          final linkedDonationId = sd['donationId'] as String? ?? '';
          final alreadyCounted =
              linkedDonationId.isNotEmpty &&
              donationsSnap.docs.any((d) => d.id == linkedDonationId);
          if (alreadyCounted) continue;

          // Add the pro-rated monetary value of the assigned items.
          final stockValue =
              (sd['totalLockedValue'] ?? sd['lockedInKindValue'] ?? 0)
                  .toDouble();
          inKindValue += stockValue;

          // Subtract assigned items from the family's remaining needs.
          final stockItems = Map<String, dynamic>.from(sd['items'] ?? {});
          stockItems.forEach((item, qty) {
            if (currentNeeds.containsKey(item)) {
              currentNeeds[item] =
                  (currentNeeds[item]! - (num.tryParse(qty.toString()) ?? 0))
                      .clamp(0, double.infinity);
            }
          });
        }
      }

      // Bug #3 fix: fundingStatus based on VERIFIED combined progress
      String fundingStatus = 'pending';
      double combinedProgress = raisedAmount + inKindValue;
      if (targetAmount > 0 && combinedProgress >= targetAmount) {
        fundingStatus = 'fully_funded';
      } else if (combinedProgress > 0) {
        fundingStatus = 'partially_funded';
      }
      if (familyId == 'general_relief_fund') fundingStatus = 'active_pool';

      await _db.collection('families').doc(familyId).update({
        'raisedAmount': raisedAmount,
        'pendingAmount': pendingAmount,
        'inKindValue': inKindValue,
        'combinedProgress': combinedProgress,
        'remainingAmount': (targetAmount - combinedProgress).clamp(
          0,
          targetAmount,
        ),
        'surplusAmount': (combinedProgress - targetAmount).clamp(
          0,
          double.infinity,
        ),
        'needs': currentNeeds,
        'originalNeeds':
            baseNeeds, // Component 10: Store original pack quantities
        'itemUnits':
            itemUnits, // Fix: persist units so UI can display them accurately
        'pendingNeeds': pendingNeeds,
        'fundingStatus': fundingStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (familyId != 'general_relief_fund') {
        final currentFulfillment = familyData['fulfillmentStatus'] ?? 'pending';
        if (fundingStatus == 'fully_funded' &&
            currentFulfillment == 'pending') {
          await ProcurementService.checkAndGenerateRequest(familyId);
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FUNDING STATS STREAM
  // ─────────────────────────────────────────────────────────────────────────

  /// Get overall funding statistics for Admin Dashboard
  static Stream<Map<String, double>> getFundingStatsStream() {
    return _db
        .collection('families')
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .map((snapshot) {
          double totalTarget = 0;
          double totalRaised = 0;
          for (var doc in snapshot.docs) {
            final data = doc.data();

            // Explicitly exclude GRF from the Global Funding Progress bar.
            // GRF funds are ONLY tracked in the dedicated GRF Wallet.
            if (doc.id == 'general_relief_fund') continue;

            totalTarget += (data['targetAmount'] ?? 0).toDouble();

            // Use combinedProgress if available (it exists in new/synced docs).
            // Fallback to older sum logic for legacy docs.
            final combined = (data['combinedProgress'] as num?)?.toDouble();
            if (combined != null) {
              totalRaised += combined;
            } else {
              totalRaised += (data['raisedAmount'] ?? 0).toDouble();
              totalRaised += (data['inKindValue'] ?? 0).toDouble();
            }
          }
          return {
            'totalTarget': totalTarget,
            'totalRaised': totalRaised,
            'totalGap': totalTarget - totalRaised,
          };
        });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  /// Ensure master ledger doc exists (idempotent — safe to call multiple times)
  static Future<void> _ensureLedger() async {
    final doc = await _masterLedgerRef.get();
    if (!doc.exists) {
      await _masterLedgerRef.set(MasterLedger.empty().toFirestore());
    }
  }
}
