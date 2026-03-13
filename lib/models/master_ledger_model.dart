import 'package:cloud_firestore/cloud_firestore.dart';

/// Model for the single `master_ledger/global` Firestore document.
/// This is the authoritative financial source of truth for the entire system.
/// All monetary counters are updated atomically via Firestore transactions.
class MasterLedger {
  /// Total amount received from all verified donor contributions.
  final double totalReceived;

  /// Total amount allocated from General Pool to specific families.
  final double totalAllocated;

  /// Total amount disbursed to the Purchaser module for procurement.
  final double totalDisbursed;

  /// Current available balance in the General Relief Pool.
  final double generalPoolBalance;

  /// Emergency reserve — 5% held back, admin-unlockable with justification.
  final double emergencyReserve;

  /// Last time this document was updated (server timestamp).
  final DateTime? lastUpdated;

  const MasterLedger({
    this.totalReceived = 0,
    this.totalAllocated = 0,
    this.totalDisbursed = 0,
    this.generalPoolBalance = 0,
    this.emergencyReserve = 0,
    this.lastUpdated,
  });

  /// Creates a zeroed-out default ledger for first-time initialization.
  factory MasterLedger.empty() => const MasterLedger();

  /// Firestore path: `master_ledger/global`
  static const String docPath = 'master_ledger/global';

  factory MasterLedger.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return MasterLedger(
      totalReceived: (data['totalReceived'] ?? 0).toDouble(),
      totalAllocated: (data['totalAllocated'] ?? 0).toDouble(),
      totalDisbursed: (data['totalDisbursed'] ?? 0).toDouble(),
      generalPoolBalance: (data['generalPoolBalance'] ?? 0).toDouble(),
      emergencyReserve: (data['emergencyReserve'] ?? 0).toDouble(),
      lastUpdated: (data['lastUpdated'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'totalReceived': totalReceived,
    'totalAllocated': totalAllocated,
    'totalDisbursed': totalDisbursed,
    'generalPoolBalance': generalPoolBalance,
    'emergencyReserve': emergencyReserve,
    'lastUpdated': FieldValue.serverTimestamp(),
  };

  /// Derived: funds still unallocated and available for spending
  double get availableBalance => generalPoolBalance - emergencyReserve;

  /// Derived: overall system utilization rate
  double get utilizationRate =>
      totalReceived > 0 ? (totalDisbursed / totalReceived) : 0;

  MasterLedger copyWith({
    double? totalReceived,
    double? totalAllocated,
    double? totalDisbursed,
    double? generalPoolBalance,
    double? emergencyReserve,
    DateTime? lastUpdated,
  }) {
    return MasterLedger(
      totalReceived: totalReceived ?? this.totalReceived,
      totalAllocated: totalAllocated ?? this.totalAllocated,
      totalDisbursed: totalDisbursed ?? this.totalDisbursed,
      generalPoolBalance: generalPoolBalance ?? this.generalPoolBalance,
      emergencyReserve: emergencyReserve ?? this.emergencyReserve,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

/// Represents a single entry in the immutable ledger audit log.
/// Stored in `master_ledger_audit/{id}` — never updated or deleted.
class LedgerAuditEntry {
  final String id;
  final String
  action; // 'donate' | 'allocate' | 'disburse' | 'refund' | 'emergency_draw'
  final double amount;
  final String actorId; // donorId or adminUid
  final String? targetFamilyId;
  final String? reason;
  final String allocationMode; // 'direct' | 'smart' | 'general'
  final double? overflowAmount;
  final DateTime timestamp;

  const LedgerAuditEntry({
    required this.id,
    required this.action,
    required this.amount,
    required this.actorId,
    this.targetFamilyId,
    this.reason,
    this.allocationMode = 'direct',
    this.overflowAmount,
    required this.timestamp,
  });

  factory LedgerAuditEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return LedgerAuditEntry(
      id: doc.id,
      action: data['action'] ?? '',
      amount: (data['amount'] ?? 0).toDouble(),
      actorId: data['actorId'] ?? '',
      targetFamilyId: data['targetFamilyId'],
      reason: data['reason'],
      allocationMode: data['allocationMode'] ?? 'direct',
      overflowAmount: (data['overflowAmount'] as num?)?.toDouble(),
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'action': action,
    'amount': amount,
    'actorId': actorId,
    'targetFamilyId': targetFamilyId,
    'reason': reason,
    'allocationMode': allocationMode,
    'overflowAmount': overflowAmount,
    'timestamp': FieldValue.serverTimestamp(),
  };
}

/// Result returned by `submitAtomicDonation`
class DonationSubmitResult {
  final String donationId;
  final double effectiveAmount; // amount actually credited to family
  final double overflowAmount; // amount rerouted to GRF
  final String targetFamilyId; // where effective amount went

  const DonationSubmitResult({
    required this.donationId,
    required this.effectiveAmount,
    required this.overflowAmount,
    required this.targetFamilyId,
  });

  bool get hadOverflow => overflowAmount > 0;
}
