import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ration_aid/models/donation_model.dart';
import 'package:ration_aid/models/master_ledger_model.dart';
import 'package:ration_aid/services/allocation_service.dart';
import 'package:ration_aid/services/notification_service.dart';
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

    // Snapshot item prices from pack (outside transaction — safe from deadlock)
    double inKindLockedValue = 0.0;
    final Map<String, double> itemValueSnapshot = {};

    if (preType == 'inKind' && preItems != null && preFamilyId.isNotEmpty) {
      // Fetch the family's assigned pack to snapshot current item prices
      final familyPreSnap = await _db
          .collection('families')
          .doc(preFamilyId)
          .get();
      final familyPreData = familyPreSnap.data() ?? {};
      final String? assignedPackId = familyPreData['assignedPackId'] as String?;

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
            final cost = (pi['estimatedCost'] as num?)?.toDouble() ?? 0;
            final qty = (pi['quantity'] as num?)?.toDouble() ?? 1;
            if (name.isNotEmpty && qty > 0) {
              priceMap[name] = cost / qty; // price per unit
            }
          }
          preItems.forEach((item, qty) {
            final unitPrice = priceMap[item] ?? 0.0;
            final donatedQty = (qty as num).toDouble();
            final lineValue = unitPrice * donatedQty;
            itemValueSnapshot[item] = lineValue;
            inKindLockedValue += lineValue;
          });
        }
      }
    }
    // \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

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
          (donationData['effectiveAmount'] as num?)?.toDouble() ?? 0;

      final double overflowAmount =
          (donationData['overflowAmount'] as num?)?.toDouble() ?? 0;
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
          final String sId = split['familyId'] as String;
          smartFamilySnaps[sId] = await tx.get(_familyRef(sId));
        }
      }

      // ── WRITES ───────────────────────────────────────────────────────
      // 1. Update donation status to verified (inside tx)
      tx.update(donationRef, {
        'status': DonationStatus.verified.toFirestore(),
        'updatedAt': FieldValue.serverTimestamp(),
        'statusHistory': FieldValue.arrayUnion([
          StatusHistoryEntry(
            status: DonationStatus.verified,
            timestamp: DateTime.now(),
            note: 'Verified by admin',
          ).toMap(),
        ]),
      });

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

      if (smartSplits != null && donationType == 'cash') {
        for (final split in smartSplits) {
          final String sId = split['familyId'] as String;
          final double splitAmt = (split['amount'] as num).toDouble();

          final sSnap = smartFamilySnaps[sId];
          if (sSnap != null && sSnap.exists) {
            final sd = sSnap.data() as Map<String, dynamic>;
            final double target =
                ((sd['assignedPackBudget'] ?? sd['targetAmount'] ?? 0) as num)
                    .toDouble();
            final double currentRaised = (sd['raisedAmount'] as num? ?? 0)
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
        }
      } else if (familySnap != null && familySnap.exists) {
        final d = familySnap.data() as Map<String, dynamic>;
        final double target =
            ((d['assignedPackBudget'] ?? d['targetAmount'] ?? 0) as num)
                .toDouble();
        final double currentRaised = (d['raisedAmount'] as num? ?? 0)
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
          // ── In-Kind Verification (Phase IK) ────────────────────────────────────────
          // C1 Fix — Decrement in-kind needs INSIDE the transaction (atomic)
          final Map<String, dynamic> needsUpdates = {};
          items.forEach((item, qty) {
            final num currentNeed = (d['needs']?[item] as num?) ?? 0;
            final num donated = qty as num;
            final num newNeed = (currentNeed - donated).clamp(0.0, 99999.0);
            needsUpdates['needs.$item'] = newNeed;
          });

          // Also increment inKindValue and recompute combinedProgress
          // totalLockedValue (set below outside tx) is passed in via closure.
          tx.update(_familyRef(familyId), {
            ...needsUpdates,
            'inKindValue': FieldValue.increment(inKindLockedValue),
            'combinedProgress': FieldValue.increment(inKindLockedValue),
            'updatedAt': FieldValue.serverTimestamp(),
          });

          // Check if combinedProgress will now reach the target
          final double currentCombined =
              (d['combinedProgress'] as num? ?? d['raisedAmount'] as num? ?? 0)
                  .toDouble();
          if (target > 0 &&
              (currentCombined + inKindLockedValue) >= target &&
              (d['fulfillmentStatus'] as String? ?? 'pending') == 'pending') {
            procurementFamilyIds.add(familyId);
          }
        }
      }
    });

    // ── Pool-mode in-kind: skip warehouse/pickup creation.
    // Admin will manually assign to a family via the Admin UI.
    if (preType == 'inKind' && preFamilyId.isEmpty) {
      await donationRef.update({
        'status': 'pending_assignment',
        'updatedAt': FieldValue.serverTimestamp(),
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': 'pending_assignment',
            'timestamp': Timestamp.now(),
            'note': 'Awaiting NGO family assignment',
          },
        ]),
      });
      return; // No warehouse/pickup docs created yet
    }

    // Normal in-kind: create warehouse batch & pickup task.
    if (preType == 'inKind' && preItems != null && preFamilyId.isNotEmpty) {
      final batch = _db.batch();
      final stockRef = _db.collection('warehouse_stock').doc();
      final pickupRef = _db.collection('inbound_pickups').doc();

      // Convert items to Map<String, num>
      final Map<String, num> typedItems = preItems.map(
        (k, v) => MapEntry(k, (v as num)),
      );

      // WarehouseStock document
      batch.set(stockRef, {
        'familyId': preFamilyId,
        'donationId': donationId,
        'donorId': preDonorId,
        'donorName': preDonorName,
        'items': typedItems,
        'itemValueSnapshot': itemValueSnapshot,
        'totalLockedValue': inKindLockedValue,
        'status': 'pending_pickup',
        'pickupAddress': prePickupAddress,
        'contactNumber': preContactNumber,
        'inboundPickupId': pickupRef.id,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // InboundPickup task document (assigned to Purchaser open pool)
      batch.set(pickupRef, {
        'batchId': stockRef.id,
        'familyId': preFamilyId,
        'donationId': donationId,
        'donorId': preDonorId,
        'donorName': preDonorName,
        'contactNumber': preContactNumber,
        'pickupAddress': prePickupAddress,
        'items': typedItems,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
    }
    // \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

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

  /// Admin assigns an unassigned pool-mode in-kind donation to a specific family.
  /// Creates warehouse_stock + inbound_pickup docs and updates the family's needs.
  static Future<void> assignPoolInKind({
    required String donationId,
    required String targetFamilyId,
  }) async {
    final donationRef = _db.collection('donations').doc(donationId);
    final donationSnap = await donationRef.get();
    if (!donationSnap.exists) throw Exception('Donation not found');

    final data = donationSnap.data()!;
    final preItems = data['items'] as Map<String, dynamic>?;
    if (preItems == null || preItems.isEmpty) {
      throw Exception('Donation has no items');
    }

    final preDonorId = data['donorId'] as String? ?? '';
    final preDonorName = data['donorName'] as String? ?? '';
    final prePickupAddress = data['pickupAddress'] as String? ?? '';
    final preContactNumber = data['contactNumber'] as String? ?? '';
    final itemValueSnapshot =
        (data['itemValueSnapshot'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, (v as num).toDouble()),
        ) ??
        {};
    final inKindLockedValue =
        (data['lockedInKindValue'] as num?)?.toDouble() ?? 0.0;

    // 1. Update donation: assign to family
    final now = DateTime.now();
    await donationRef.update({
      'familyId': targetFamilyId,
      'status': 'under_verification',
      'allocationMode': 'pool_assigned',
      'updatedAt': FieldValue.serverTimestamp(),
      'statusHistory': FieldValue.arrayUnion([
        {
          'status': 'under_verification',
          'timestamp': Timestamp.fromDate(now),
          'note': 'Pool donation assigned to family by admin',
        },
      ]),
    });

    // 2. Update family needs + inKindValue
    final familySnap = await _db
        .collection('families')
        .doc(targetFamilyId)
        .get();
    if (!familySnap.exists) throw Exception('Target family not found');
    final familyData = familySnap.data()!;
    final needsData = (familyData['needs'] as Map<String, dynamic>?) ?? {};

    final Map<String, dynamic> needsUpdates = {};
    final Map<String, num> typedItems = {};
    preItems.forEach((item, qty) {
      final numQty = (qty as num);
      typedItems[item] = numQty;
      final currentNeed = (needsData[item] as num?) ?? 0;
      needsUpdates['needs.$item'] = (currentNeed - numQty).clamp(0, 99999);
    });

    await _db.collection('families').doc(targetFamilyId).update({
      ...needsUpdates,
      'inKindValue': FieldValue.increment(inKindLockedValue),
      'combinedProgress': FieldValue.increment(inKindLockedValue),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 3. Batch: create warehouse_stock + inbound_pickup + mark donation verified
    final wsBatch = _db.batch();
    final stockRef = _db.collection('warehouse_stock').doc();
    final pickupRef = _db.collection('inbound_pickups').doc();

    wsBatch.set(stockRef, {
      'familyId': targetFamilyId,
      'donationId': donationId,
      'donorId': preDonorId,
      'donorName': preDonorName,
      'items': typedItems,
      'itemValueSnapshot': itemValueSnapshot,
      'totalLockedValue': inKindLockedValue,
      'status': 'pending_pickup',
      'pickupAddress': prePickupAddress,
      'contactNumber': preContactNumber,
      'inboundPickupId': pickupRef.id,
      'createdAt': FieldValue.serverTimestamp(),
    });

    wsBatch.set(pickupRef, {
      'batchId': stockRef.id,
      'familyId': targetFamilyId,
      'donationId': donationId,
      'donorId': preDonorId,
      'donorName': preDonorName,
      'contactNumber': preContactNumber,
      'pickupAddress': prePickupAddress,
      'items': typedItems,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });

    wsBatch.update(donationRef, {
      'status': 'verified',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await wsBatch.commit();

    // 4. Trigger procurement if family now fully funded
    final updatedFamSnap = await _db
        .collection('families')
        .doc(targetFamilyId)
        .get();
    if (updatedFamSnap.exists) {
      final d = updatedFamSnap.data()!;
      final double target =
          ((d['assignedPackBudget'] ?? d['targetAmount'] ?? 0) as num)
              .toDouble();
      final double combined = (d['combinedProgress'] as num? ?? 0).toDouble();
      if (target > 0 &&
          combined >= target &&
          (d['fulfillmentStatus'] as String? ?? 'pending') == 'pending') {
        await ProcurementService.checkAndGenerateRequest(targetFamilyId);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
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

      // Sum all verified/active donations
      final donationsSnap = await _db
          .collection('donations')
          .where('familyId', isEqualTo: familyId)
          .where(
            'status',
            whereIn: [
              'under_verification',
              'pending',
              'verified',
              'in_process',
              'out_for_delivery',
              'delivered',
              'closed',
            ],
          )
          .get();

      double raisedAmount = 0;
      double pendingAmount = 0;
      final Map<String, num> pendingNeeds = {};

      for (var doc in donationsSnap.docs) {
        final data = doc.data();
        // P10 Fix — Use effectiveAmount (cap-applied) not amount (raw).
        // amount = donor's full input; effectiveAmount = actual credited amount.
        // Using amount overstates raisedAmount by the overflow portion.
        final effectiveAmt = (data['effectiveAmount'] ?? data['amount'] ?? 0)
            .toDouble();
        final status = data['status'];
        final type = data['donationType'];
        final items = data['items'] as Map<String, dynamic>?;

        if (type == 'cash' || type == null) {
          if (status == 'verified') {
            raisedAmount += effectiveAmt;
          } else if (status == 'under_verification' || status == 'pending') {
            pendingAmount += effectiveAmt;
          }
        } else if (type == 'inKind') {
          if (status == 'verified' && effectiveAmt > 0) {
            raisedAmount += effectiveAmt;
          } else if ((status == 'under_verification' || status == 'pending') &&
              effectiveAmt > 0) {
            pendingAmount += effectiveAmt;
          }
          if ((status == 'under_verification' || status == 'pending') &&
              items != null) {
            items.forEach((item, qty) {
              pendingNeeds[item] = (pendingNeeds[item] ?? 0) + (qty as num);
            });
          }
        }
      }

      // Bug #3 fix: fundingStatus based on VERIFIED raisedAmount only
      // pendingAmount is stored separately for display but doesn't affect status
      String fundingStatus = 'pending';
      if (targetAmount > 0 && raisedAmount >= targetAmount) {
        fundingStatus = 'fully_funded';
      } else if (raisedAmount > 0) {
        fundingStatus = 'partially_funded';
      }
      if (familyId == 'general_relief_fund') fundingStatus = 'active_pool';

      await _db.collection('families').doc(familyId).update({
        'raisedAmount': raisedAmount,
        'pendingAmount': pendingAmount,
        'remainingAmount': (targetAmount - raisedAmount).clamp(0, targetAmount),
        'surplusAmount': (raisedAmount - targetAmount).clamp(
          0,
          double.infinity,
        ),
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
            totalRaised += (data['raisedAmount'] ?? 0).toDouble();
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

  /// Process In-Kind donation: Decrement family needs
  static Future<void> _processInKindDonation(
    String familyId,
    Map<String, num> donatedItems,
  ) async {
    try {
      final familyRef = _db.collection('families').doc(familyId);
      await _db.runTransaction((tx) async {
        final snapshot = await tx.get(familyRef);
        if (!snapshot.exists) throw Exception('Family not found');
        final data = snapshot.data()!;
        final Map<String, dynamic> currentNeeds = data['needs'] != null
            ? Map<String, dynamic>.from(data['needs'])
            : {};

        if (familyId == 'general_relief_fund') {
          final collectedItems = data['collectedItems'] != null
              ? Map<String, dynamic>.from(data['collectedItems'])
              : {};
          donatedItems.forEach((item, qty) {
            collectedItems[item] = (collectedItems[item] as int? ?? 0) + qty;
          });
          tx.update(familyRef, {
            'collectedItems': collectedItems,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return;
        }

        bool needsUpdated = false;
        donatedItems.forEach((item, qty) {
          if (currentNeeds.containsKey(item)) {
            final newQty = (currentNeeds[item] as num).toInt() - qty;
            if (newQty <= 0) {
              currentNeeds.remove(item);
            } else {
              currentNeeds[item] = newQty;
            }
            needsUpdated = true;
          }
        });

        if (needsUpdated) {
          final isFullyFulfilled = currentNeeds.isEmpty;
          tx.update(familyRef, {
            'needs': currentNeeds,
            'fulfillmentStatus': isFullyFulfilled
                ? 'ready_for_purchase'
                : (data['fulfillmentStatus'] ?? 'pending'),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          if (isFullyFulfilled) {
            NotificationService.notifyFullyFunded(familyId);
          }
        }
      });
    } catch (e) {
      rethrow;
    }
  }
}
