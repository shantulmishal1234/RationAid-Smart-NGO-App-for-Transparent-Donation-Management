import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ration_aid/models/master_ledger_model.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────
  // MasterLedger
  // ─────────────────────────────────────────────────────────────────
  group('MasterLedger', () {
    late FakeFirebaseFirestore fakeFirestore;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
    });

    test('MasterLedger.empty() creates zeroed-out ledger', () {
      final ledger = MasterLedger.empty();
      expect(ledger.totalReceived, 0.0);
      expect(ledger.totalAllocated, 0.0);
      expect(ledger.totalDisbursed, 0.0);
      expect(ledger.generalPoolBalance, 0.0);
      expect(ledger.emergencyReserve, 0.0);
      expect(ledger.lastUpdated, isNull);
    });

    test('docPath constant is correct Firestore path', () {
      expect(MasterLedger.docPath, 'master_ledger/global');
    });

    test('fromFirestore correctly parses all financial fields', () async {
      await fakeFirestore
          .doc('master_ledger/global')
          .set({
        'totalReceived': 100000.0,
        'totalAllocated': 60000.0,
        'totalDisbursed': 50000.0,
        'generalPoolBalance': 40000.0,
        'emergencyReserve': 2000.0,
        'lastUpdated': Timestamp.fromDate(DateTime(2024, 6, 15)),
      });

      final doc = await fakeFirestore.doc('master_ledger/global').get();
      final ledger = MasterLedger.fromFirestore(doc);

      expect(ledger.totalReceived, 100000.0);
      expect(ledger.totalAllocated, 60000.0);
      expect(ledger.totalDisbursed, 50000.0);
      expect(ledger.generalPoolBalance, 40000.0);
      expect(ledger.emergencyReserve, 2000.0);
      expect(ledger.lastUpdated, isNotNull);
      expect(ledger.lastUpdated!.year, 2024);
    });

    test('fromFirestore handles missing fields with zero defaults', () async {
      await fakeFirestore.doc('master_ledger/global').set({});

      final doc = await fakeFirestore.doc('master_ledger/global').get();
      final ledger = MasterLedger.fromFirestore(doc);

      expect(ledger.totalReceived, 0.0);
      expect(ledger.totalAllocated, 0.0);
      expect(ledger.totalDisbursed, 0.0);
      expect(ledger.generalPoolBalance, 0.0);
      expect(ledger.emergencyReserve, 0.0);
    });

    test('toFirestore serializes all fields correctly', () {
      final ledger = MasterLedger(
        totalReceived: 100000.0,
        totalAllocated: 60000.0,
        totalDisbursed: 50000.0,
        generalPoolBalance: 40000.0,
        emergencyReserve: 2000.0,
      );

      final map = ledger.toFirestore();

      expect(map['totalReceived'], 100000.0);
      expect(map['totalAllocated'], 60000.0);
      expect(map['totalDisbursed'], 50000.0);
      expect(map['generalPoolBalance'], 40000.0);
      expect(map['emergencyReserve'], 2000.0);
      expect(map['lastUpdated'], isNotNull); // FieldValue.serverTimestamp()
    });

    // ─────────────────────────────────────────────────────────────────
    // Computed Properties
    // ─────────────────────────────────────────────────────────────────
    test('availableBalance is generalPoolBalance minus emergencyReserve', () {
      final ledger = MasterLedger(
        generalPoolBalance: 40000.0,
        emergencyReserve: 2000.0,
      );
      expect(ledger.availableBalance, 38000.0);
    });

    test('utilizationRate is 0 when totalReceived is 0 (no division by zero)', () {
      final ledger = MasterLedger(totalReceived: 0, totalDisbursed: 0);
      expect(ledger.utilizationRate, 0.0);
    });

    test('utilizationRate calculates correctly when totalReceived > 0', () {
      final ledger = MasterLedger(totalReceived: 100000, totalDisbursed: 75000);
      expect(ledger.utilizationRate, closeTo(0.75, 0.001));
    });

    test('utilizationRate is 1.0 (100%) when fully disbursed', () {
      final ledger = MasterLedger(totalReceived: 50000, totalDisbursed: 50000);
      expect(ledger.utilizationRate, 1.0);
    });

    // ─────────────────────────────────────────────────────────────────
    // copyWith
    // ─────────────────────────────────────────────────────────────────
    test('copyWith updates only specified fields', () {
      final original = MasterLedger(
        totalReceived: 100000.0,
        totalAllocated: 60000.0,
        totalDisbursed: 50000.0,
        generalPoolBalance: 40000.0,
        emergencyReserve: 2000.0,
      );

      final updated = original.copyWith(
        generalPoolBalance: 45000.0,
        totalDisbursed: 55000.0,
      );

      expect(updated.generalPoolBalance, 45000.0);
      expect(updated.totalDisbursed, 55000.0);
      // Unchanged fields preserved
      expect(updated.totalReceived, 100000.0);
      expect(updated.totalAllocated, 60000.0);
      expect(updated.emergencyReserve, 2000.0);
    });
  });

  // ─────────────────────────────────────────────────────────────────
  // LedgerAuditEntry
  // ─────────────────────────────────────────────────────────────────
  group('LedgerAuditEntry', () {
    late FakeFirebaseFirestore fakeFirestore;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
    });

    test('fromFirestore correctly parses a donation audit entry', () async {
      final now = Timestamp.fromDate(DateTime(2024, 6, 15));

      await fakeFirestore.collection('master_ledger_audit').doc('audit_001').set({
        'action': 'donate',
        'amount': 5000.0,
        'actorId': 'donor_abc',
        'targetFamilyId': 'family_xyz',
        'reason': 'Monthly donation',
        'allocationMode': 'direct',
        'overflowAmount': 500.0,
        'timestamp': now,
      });

      final doc =
          await fakeFirestore.collection('master_ledger_audit').doc('audit_001').get();
      final entry = LedgerAuditEntry.fromFirestore(doc);

      expect(entry.id, 'audit_001');
      expect(entry.action, 'donate');
      expect(entry.amount, 5000.0);
      expect(entry.actorId, 'donor_abc');
      expect(entry.targetFamilyId, 'family_xyz');
      expect(entry.reason, 'Monthly donation');
      expect(entry.allocationMode, 'direct');
      expect(entry.overflowAmount, 500.0);
      expect(entry.timestamp.year, 2024);
    });

    test('fromFirestore uses "direct" as default allocationMode', () async {
      final now = Timestamp.now();
      await fakeFirestore.collection('master_ledger_audit').doc('audit_002').set({
        'action': 'allocate',
        'amount': 2000.0,
        'actorId': 'admin_001',
        'timestamp': now,
      });

      final doc =
          await fakeFirestore.collection('master_ledger_audit').doc('audit_002').get();
      final entry = LedgerAuditEntry.fromFirestore(doc);

      expect(entry.allocationMode, 'direct');
      expect(entry.targetFamilyId, isNull);
      expect(entry.reason, isNull);
      expect(entry.overflowAmount, isNull);
    });

    test('toFirestore serializes all fields correctly', () {
      final now = DateTime(2024, 6, 15);
      final entry = LedgerAuditEntry(
        id: 'audit_001',
        action: 'disburse',
        amount: 10000.0,
        actorId: 'admin_xyz',
        targetFamilyId: 'family_abc',
        reason: 'Emergency disbursement',
        allocationMode: 'general',
        overflowAmount: 0.0,
        timestamp: now,
      );

      final map = entry.toFirestore();

      expect(map['action'], 'disburse');
      expect(map['amount'], 10000.0);
      expect(map['actorId'], 'admin_xyz');
      expect(map['targetFamilyId'], 'family_abc');
      expect(map['reason'], 'Emergency disbursement');
      expect(map['allocationMode'], 'general');
      expect(map['overflowAmount'], 0.0);
      expect(map['timestamp'], isNotNull); // FieldValue.serverTimestamp()
    });
  });

  // ─────────────────────────────────────────────────────────────────
  // DonationSubmitResult
  // ─────────────────────────────────────────────────────────────────
  group('DonationSubmitResult', () {
    test('hadOverflow is true when overflowAmount > 0', () {
      const result = DonationSubmitResult(
        donationId: 'don_001',
        effectiveAmount: 4000,
        overflowAmount: 1000,
        targetFamilyId: 'fam_001',
      );
      expect(result.hadOverflow, true);
    });

    test('hadOverflow is false when overflowAmount is exactly 0', () {
      const result = DonationSubmitResult(
        donationId: 'don_002',
        effectiveAmount: 5000,
        overflowAmount: 0,
        targetFamilyId: 'fam_001',
      );
      expect(result.hadOverflow, false);
    });
  });
}
