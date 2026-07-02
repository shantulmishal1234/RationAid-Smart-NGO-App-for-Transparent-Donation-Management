import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:ration_aid/models/donation_model.dart';

/// Donation Flow Integration Test
///
/// Tests the full donation lifecycle:
///   Donor Creates Donation → Admin Verifies → Status Updates Flow
///
/// Uses FakeFirebaseFirestore — NO real Firebase calls.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore mockFirestore;
  late MockFirebaseAuth mockAuth;

  setUp(() {
    mockFirestore = FakeFirebaseFirestore();
    mockAuth = MockFirebaseAuth();
  });

  // ─────────────────────────────────────────────────────────────────
  // Integration Test 1: Donor Creates Cash Donation
  // ─────────────────────────────────────────────────────────────────
  testWidgets('donation_flow_001: Donor creates a cash donation — document created in Firestore',
      (WidgetTester tester) async {
    // Arrange: donor is logged in
    final mockUser = MockUser(uid: 'donor_001', email: 'donor@test.com');
    final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);
    final now = Timestamp.now();

    // Act: create donation (what CreateDonationScreen triggers)
    await mockFirestore.collection('donations').doc('don_001').set({
      'donorId': auth.currentUser!.uid,
      'donorName': 'Ahmed Ali',
      'donorEmail': 'donor@test.com',
      'familyId': 'family_abc',
      'donationType': 'cash',
      'amount': 5000.0,
      'anonymous': false,
      'status': 'under_verification',
      'allocationMode': 'direct',
      'effectiveAmount': 0.0,
      'overflowAmount': 0.0,
      'allocatedAmount': 0.0,
      'displacedAmount': 0.0,
      'idempotencyKey': 'idp_001',
      'statusHistory': [
        {'status': 'under_verification', 'timestamp': now, 'note': 'Submitted by donor'},
      ],
      'deliveryPhotos': [],
      'createdAt': now,
      'updatedAt': now,
    });

    // Assert: donation document exists
    final doc = await mockFirestore.collection('donations').doc('don_001').get();
    expect(doc.exists, true);
    expect(doc.data()!['donorId'], 'donor_001');
    expect(doc.data()!['status'], 'under_verification');
    expect(doc.data()!['amount'], 5000.0);
    expect(doc.data()!['donationType'], 'cash');

    // Verify the model parses it correctly
    final donation = Donation.fromFirestore(doc);
    expect(donation.status, DonationStatus.underVerification);
    expect(donation.donationType, DonationType.cash);
    expect(donation.effectiveAmount, 0.0);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 64),
                const Text('Donation Submitted Successfully!'),
                Text('Status: ${donation.status.displayName}'),
                Text('Amount: PKR ${donation.amount?.toStringAsFixed(0)}'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Donation Submitted Successfully!'), findsOneWidget);
    expect(find.text('Status: Under Verification'), findsOneWidget);
    expect(find.text('Amount: PKR 5000'), findsOneWidget);
  });

  // ─────────────────────────────────────────────────────────────────
  // Integration Test 2: Admin Verifies Donation
  // ─────────────────────────────────────────────────────────────────
  testWidgets('donation_flow_002: Admin verifies a pending donation',
      (WidgetTester tester) async {
    final now = Timestamp.now();

    // Seed a donation in under_verification state
    await mockFirestore.collection('donations').doc('don_002').set({
      'donorId': 'donor_002',
      'familyId': 'family_xyz',
      'donationType': 'cash',
      'amount': 3000.0,
      'status': 'under_verification',
      'allocationMode': 'direct',
      'effectiveAmount': 0.0,
      'overflowAmount': 0.0,
      'allocatedAmount': 0.0,
      'displacedAmount': 0.0,
      'idempotencyKey': 'idp_002',
      'statusHistory': [],
      'deliveryPhotos': [],
      'createdAt': now,
      'updatedAt': now,
    });

    // Admin verifies: status → verified
    await mockFirestore.collection('donations').doc('don_002').update({
      'status': 'verified',
      'updatedAt': Timestamp.now(),
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'verified', 'timestamp': Timestamp.now(), 'note': 'Verified by admin'},
      ]),
    });

    // Assert: status updated
    final doc = await mockFirestore.collection('donations').doc('don_002').get();
    expect(doc.data()!['status'], 'verified');

    final donation = Donation.fromFirestore(doc);
    expect(donation.status, DonationStatus.verified);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.verified, color: Colors.green, size: 48),
                Text('Donation Status: ${donation.status.displayName}'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Donation Status: Verified'), findsOneWidget);
  });

  // ─────────────────────────────────────────────────────────────────
  // Integration Test 3: Donation Rejection Flow
  // ─────────────────────────────────────────────────────────────────
  testWidgets('donation_flow_003: Admin rejects donation with reason',
      (WidgetTester tester) async {
    final now = Timestamp.now();

    await mockFirestore.collection('donations').doc('don_003').set({
      'donorId': 'donor_003',
      'familyId': 'family_def',
      'donationType': 'cash',
      'amount': 1000.0,
      'status': 'under_verification',
      'allocationMode': 'direct',
      'effectiveAmount': 0.0,
      'overflowAmount': 0.0,
      'allocatedAmount': 0.0,
      'displacedAmount': 0.0,
      'idempotencyKey': 'idp_003',
      'statusHistory': [],
      'deliveryPhotos': [],
      'createdAt': now,
      'updatedAt': now,
    });

    // Admin rejects with reason
    await mockFirestore.collection('donations').doc('don_003').update({
      'status': 'rejected',
      'rejectionReason': 'Insufficient payment proof',
      'updatedAt': Timestamp.now(),
    });

    final doc = await mockFirestore.collection('donations').doc('don_003').get();
    expect(doc.data()!['status'], 'rejected');
    expect(doc.data()!['rejectionReason'], 'Insufficient payment proof');

    final donation = Donation.fromFirestore(doc);
    expect(donation.status, DonationStatus.rejected);
    expect(donation.rejectionReason, 'Insufficient payment proof');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cancel, color: Colors.red, size: 48),
                Text('Status: ${donation.status.displayName}'),
                Text('Reason: ${donation.rejectionReason}'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Status: Rejected'), findsOneWidget);
    expect(find.text('Reason: Insufficient payment proof'), findsOneWidget);
  });

  // ─────────────────────────────────────────────────────────────────
  // Integration Test 4: Donor sees all their donations
  // ─────────────────────────────────────────────────────────────────
  testWidgets('donation_flow_004: Donor can retrieve their donations list',
      (WidgetTester tester) async {
    final now = Timestamp.now();
    const donorId = 'donor_list_test';

    // Create multiple donations for same donor
    for (int i = 1; i <= 3; i++) {
      await mockFirestore.collection('donations').doc('don_list_$i').set({
        'donorId': donorId,
        'familyId': 'family_$i',
        'donationType': 'cash',
        'amount': i * 1000.0,
        'status': 'under_verification',
        'allocationMode': 'direct',
        'effectiveAmount': 0.0,
        'overflowAmount': 0.0,
        'allocatedAmount': 0.0,
        'displacedAmount': 0.0,
        'idempotencyKey': 'idp_list_$i',
        'statusHistory': [],
        'deliveryPhotos': [],
        'createdAt': now,
        'updatedAt': now,
      });
    }

    // Other donor's donation (should NOT appear in filter)
    await mockFirestore.collection('donations').doc('don_other').set({
      'donorId': 'other_donor',
      'familyId': 'family_other',
      'donationType': 'cash',
      'amount': 500.0,
      'status': 'verified',
      'allocationMode': 'direct',
      'effectiveAmount': 0.0,
      'overflowAmount': 0.0,
      'allocatedAmount': 0.0,
      'displacedAmount': 0.0,
      'idempotencyKey': 'idp_other',
      'statusHistory': [],
      'deliveryPhotos': [],
      'createdAt': now,
      'updatedAt': now,
    });

    // Query donations for this donor only
    final snapshot = await mockFirestore
        .collection('donations')
        .where('donorId', isEqualTo: donorId)
        .get();

    expect(snapshot.docs.length, 3);
    for (final doc in snapshot.docs) {
      expect(doc.data()['donorId'], donorId);
    }

    // Parse and verify models
    final donations = snapshot.docs.map(Donation.fromFirestore).toList();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView.builder(
            itemCount: donations.length,
            itemBuilder: (context, index) {
              final d = donations[index];
              return ListTile(
                title: Text('Donation ${index + 1}'),
                subtitle: Text(d.status.displayName),
                trailing: Text('PKR ${d.amount?.toStringAsFixed(0)}'),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Donation 1'), findsOneWidget);
    expect(find.text('Donation 2'), findsOneWidget);
    expect(find.text('Donation 3'), findsOneWidget);
  });

  // ─────────────────────────────────────────────────────────────────
  // Integration Test 5: In-Kind Donation Full Status Flow
  // ─────────────────────────────────────────────────────────────────
  testWidgets('donation_flow_005: In-kind donation goes through full status lifecycle',
      (WidgetTester tester) async {
    final now = Timestamp.now();

    // Create in-kind donation
    await mockFirestore.collection('donations').doc('don_inkind').set({
      'donorId': 'donor_inkind',
      'familyId': 'family_abc',
      'donationType': 'inKind',
      'items': {'Rice': 10, 'Flour': 5},
      'itemUnits': {'Rice': 'kg', 'Flour': 'kg'},
      'pickupAddress': '123 Main St',
      'contactNumber': '03001234567',
      'anonymous': false,
      'status': 'under_verification',
      'allocationMode': 'direct',
      'effectiveAmount': 0.0,
      'overflowAmount': 0.0,
      'allocatedAmount': 0.0,
      'displacedAmount': 0.0,
      'idempotencyKey': 'idp_inkind',
      'statusHistory': [],
      'deliveryPhotos': [],
      'createdAt': now,
      'updatedAt': now,
    });

    // Admin verifies → stocked (in warehouse)
    await mockFirestore.collection('donations').doc('don_inkind').update({
      'status': 'stocked',
      'updatedAt': Timestamp.now(),
    });

    // → in_process
    await mockFirestore.collection('donations').doc('don_inkind').update({
      'status': 'in_process',
      'updatedAt': Timestamp.now(),
    });

    // → out_for_delivery
    await mockFirestore.collection('donations').doc('don_inkind').update({
      'status': 'out_for_delivery',
      'updatedAt': Timestamp.now(),
    });

    // → delivered
    await mockFirestore.collection('donations').doc('don_inkind').update({
      'status': 'delivered',
      'deliveredAt': Timestamp.now(),
      'receivedBy': 'Family Head Name',
      'updatedAt': Timestamp.now(),
    });

    final doc = await mockFirestore.collection('donations').doc('don_inkind').get();
    final donation = Donation.fromFirestore(doc);

    expect(donation.status, DonationStatus.delivered);
    expect(donation.donationType, DonationType.inKind);
    expect(doc.data()!['receivedBy'], 'Family Head Name');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.local_shipping_rounded, size: 64, color: Colors.green),
                const Text('In-Kind Donation Delivered!'),
                Text('Final Status: ${donation.status.displayName}'),
                Text('Type: ${donation.donationType.displayName}'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('In-Kind Donation Delivered!'), findsOneWidget);
    expect(find.text('Final Status: Delivered'), findsOneWidget);
    expect(find.text('Type: In-Kind'), findsOneWidget);
  });
}
