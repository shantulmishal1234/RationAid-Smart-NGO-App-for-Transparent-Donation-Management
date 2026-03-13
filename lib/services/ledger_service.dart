import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ration_aid/models/master_ledger_model.dart';

/// Service for managing the Master Financial Ledger.
///
/// The master ledger (`master_ledger/global`) is the single financial
/// source of truth. All monetary counters are maintained by `FundingService`
/// via atomic transactions. This service provides read access and
/// administrative write operations (emergency reserve draws, reconciliation).
class LedgerService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static DocumentReference get _ledgerRef => _db.doc(MasterLedger.docPath);

  // ─────────────────────────────────────────────────────────────────────────
  // INITIALIZATION
  // ─────────────────────────────────────────────────────────────────────────

  /// Ensure the master ledger document exists.
  /// Safe to call multiple times — uses merge write.
  static Future<void> ensureLedger() async {
    final doc = await _ledgerRef.get();
    if (!doc.exists) {
      await _ledgerRef.set(MasterLedger.empty().toFirestore());
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // READ STREAMS
  // ─────────────────────────────────────────────────────────────────────────

  /// Stream the live master ledger for Admin Dashboard.
  static Stream<MasterLedger> streamLedger() {
    return _ledgerRef.snapshots().map((doc) {
      if (!doc.exists) return MasterLedger.empty();
      return MasterLedger.fromFirestore(doc);
    });
  }

  /// Stream the full immutable audit log, newest-first.
  static Stream<List<LedgerAuditEntry>> streamLedgerAuditLog({int limit = 50}) {
    return _db
        .collection('master_ledger_audit')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((doc) => LedgerAuditEntry.fromFirestore(doc))
              .toList(),
        );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // EMERGENCY RESERVE — Admin Only
  // ─────────────────────────────────────────────────────────────────────────

  /// Draw from the emergency reserve to a specific family.
  /// Requires a justification note. Fully audited.
  static Future<void> drawEmergencyReserve({
    required String adminUid,
    required String targetFamilyId,
    required double amount,
    required String justification, // MANDATORY — empty string rejected
  }) async {
    if (amount <= 0) throw Exception('Amount must be greater than 0');
    if (justification.trim().isEmpty) {
      throw Exception('Justification is required to draw emergency reserve');
    }

    await _db.runTransaction<void>((tx) async {
      // ── Read ledger ──────────────────────────────────────────────────
      final ledgerSnap = await tx.get(_ledgerRef);
      if (!ledgerSnap.exists) throw Exception('Master ledger not initialized');
      final ledger = MasterLedger.fromFirestore(ledgerSnap);

      if (ledger.emergencyReserve < amount) {
        throw Exception(
          'Insufficient emergency reserve. Available: PKR ${ledger.emergencyReserve.toStringAsFixed(0)}',
        );
      }

      // ── Read family ──────────────────────────────────────────────────
      final familySnap = await tx.get(
        _db.collection('families').doc(targetFamilyId),
      );
      if (!familySnap.exists) throw Exception('Target family not found');

      // ── Deduct from emergency reserve ─────────────────────────────────
      tx.update(_ledgerRef, {
        'emergencyReserve': FieldValue.increment(-amount),
        'totalAllocated': FieldValue.increment(amount),
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      // ── Credit family ─────────────────────────────────────────────────
      tx.update(_db.collection('families').doc(targetFamilyId), {
        'raisedAmount': FieldValue.increment(amount),
        'fundingStatus': 'partially_funded',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // ── Immutable audit log ────────────────────────────────────────────
      tx.set(_db.collection('master_ledger_audit').doc(), {
        'action': 'emergency_draw',
        'amount': amount,
        'actorId': adminUid,
        'targetFamilyId': targetFamilyId,
        'allocationMode': 'general',
        'reason': justification,
        'timestamp': FieldValue.serverTimestamp(),
      });
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RECONCILIATION — Admin Repair Tool
  // ─────────────────────────────────────────────────────────────────────────

  /// One-time reconciliation to populate master ledger from existing donations.
  /// Call this once after first deployment to initialize `totalReceived`.
  static Future<Map<String, double>> reconcileLedger() async {
    // Sum all verified donations
    final verifiedSnap = await _db
        .collection('donations')
        .where(
          'status',
          whereIn: [
            'verified',
            'in_process',
            'out_for_delivery',
            'delivered',
            'closed',
          ],
        )
        .get();

    double totalReceived = 0;
    double totalAllocated = 0;

    for (final doc in verifiedSnap.docs) {
      final data = doc.data();
      final amount = (data['amount'] as num?)?.toDouble() ?? 0;
      totalReceived += amount;
      if (data['isGrfAllocation'] == true) totalAllocated += amount;
    }

    // Sum GRF current balance
    final grfSnap = await _db
        .collection('families')
        .doc('general_relief_fund')
        .get();
    final grfBalance = grfSnap.exists
        ? (grfSnap.data()?['raisedAmount'] as num?)?.toDouble() ?? 0
        : 0.0;

    // Write reconciled values
    await _ledgerRef.set({
      'totalReceived': totalReceived,
      'totalAllocated': totalAllocated,
      'totalDisbursed': 0,
      'generalPoolBalance': grfBalance,
      'emergencyReserve': 0,
      'lastUpdated': FieldValue.serverTimestamp(),
      'reconciledAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: false));

    return {
      'totalReceived': totalReceived,
      'totalAllocated': totalAllocated,
      'generalPoolBalance': grfBalance,
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // EMERGENCY RESERVE SETUP — Admin sets aside reserve
  // ─────────────────────────────────────────────────────────────────────────

  /// Transfer an amount from the general pool to the emergency reserve.
  static Future<void> setEmergencyReserve({
    required String adminUid,
    required double amount,
    required String reason,
  }) async {
    await _db.runTransaction<void>((tx) async {
      final ledgerSnap = await tx.get(_ledgerRef);
      if (!ledgerSnap.exists) throw Exception('Ledger not initialized');
      final ledger = MasterLedger.fromFirestore(ledgerSnap);

      if (ledger.generalPoolBalance < amount) {
        throw Exception(
          'Insufficient pool balance. Available: PKR ${ledger.generalPoolBalance.toStringAsFixed(0)}',
        );
      }

      tx.update(_ledgerRef, {
        'generalPoolBalance': FieldValue.increment(-amount),
        'emergencyReserve': FieldValue.increment(amount),
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      tx.set(_db.collection('master_ledger_audit').doc(), {
        'action': 'reserve_set',
        'amount': amount,
        'actorId': adminUid,
        'reason': reason,
        'allocationMode': 'general',
        'timestamp': FieldValue.serverTimestamp(),
      });
    });
  }
}
