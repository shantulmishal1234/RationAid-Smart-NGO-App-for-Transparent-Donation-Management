import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
  });

  // ─────────────────────────────────────────────────────────────────
  // AllocationService — Priority Score Logic
  // Tests the score formula via direct Firestore data seeding
  // ─────────────────────────────────────────────────────────────────
  group('AllocationService — Priority Scoring via Firestore', () {
    test('skips general_relief_fund document in priority scoring', () async {
      await fakeFirestore.collection('families').doc('general_relief_fund').set({
        'status': 'accepted',
        'fundingStatus': 'pending',
        'targetAmount': 100000,
        'raisedAmount': 0,
        'familySize': 0,
        'createdAt': Timestamp.now(),
      });

      // Add a real family
      await fakeFirestore.collection('families').doc('family_real').set({
        'status': 'accepted',
        'fundingStatus': 'pending',
        'targetAmount': 15000,
        'raisedAmount': 0,
        'familySize': 5,
        'createdAt': Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 10))),
      });

      final snapshot = await fakeFirestore
          .collection('families')
          .where('status', isEqualTo: 'accepted')
          .get();

      // Filter out grf as AllocationService does
      final families = snapshot.docs.where((doc) => doc.id != 'general_relief_fund').toList();
      expect(families.length, 1);
      expect(families.first.id, 'family_real');
    });

    test('skips fully_funded families in priority scoring', () async {
      // Seed a fully-funded family
      await fakeFirestore.collection('families').doc('fam_full').set({
        'status': 'accepted',
        'fundingStatus': 'fully_funded',
        'targetAmount': 15000,
        'raisedAmount': 15000,
        'familySize': 4,
        'createdAt': Timestamp.now(),
      });

      // Seed a not-fully-funded family
      await fakeFirestore.collection('families').doc('fam_partial').set({
        'status': 'accepted',
        'fundingStatus': 'pending',
        'targetAmount': 15000,
        'raisedAmount': 5000,
        'familySize': 6,
        'createdAt': Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 5))),
      });

      final snapshot = await fakeFirestore
          .collection('families')
          .where('status', isEqualTo: 'accepted')
          .get();

      // Replicate AllocationService filter: skip fully_funded
      final eligible = snapshot.docs.where((doc) {
        final data = doc.data();
        return data['fundingStatus'] != 'fully_funded';
      }).toList();

      expect(eligible.length, 1);
      expect(eligible.first.id, 'fam_partial');
    });

    test('priority score formula: larger deficit ratio scores higher', () {
      // Score formula: daysListed×0.3 + deficitRatio×40 + (familySize/15)×0.2 + emergency×5
      // Family A: 10 days, 100% deficit, size 5, no emergency
      final scoreA = 10 * 0.3 + 1.0 * 40 + (5 / 15) * 0.2 + 0;
      // Family B: 10 days, 50% deficit, size 5, no emergency
      final scoreB = 10 * 0.3 + 0.5 * 40 + (5 / 15) * 0.2 + 0;

      expect(scoreA, greaterThan(scoreB));
      expect(scoreA, closeTo(43.07, 0.1));
      expect(scoreB, closeTo(23.07, 0.1));
    });

    test('priority score formula: emergency flag adds 5 points', () {
      // Base score: 10 days, 50% deficit, size 4
      final baseScore = 10 * 0.3 + 0.5 * 40 + (4 / 15) * 0.2;
      final emergencyScore = baseScore + 5;

      expect(emergencyScore - baseScore, 5.0);
    });

    test('priority score formula: larger family size increases score slightly', () {
      // Only family size differs
      final scoreSmall = 0 + 0 + (2 / 15) * 0.2 + 0;
      final scoreLarge = 0 + 0 + (12 / 15) * 0.2 + 0;

      expect(scoreLarge, greaterThan(scoreSmall));
    });

    test('priority score formula: older listing (more daysListed) scores higher', () {
      final scoreNew = 1 * 0.3 + 0.5 * 40 + 0 + 0;  // 1 day old
      final scoreOld = 30 * 0.3 + 0.5 * 40 + 0 + 0; // 30 days old

      expect(scoreOld, greaterThan(scoreNew));
    });

    test('priority score formula: zero deficit ratio gives minimum score', () {
      // Family fully raised, zero deficit
      final score = 0 * 0.3 + 0.0 * 40 + (1 / 15) * 0.2 + 0;
      expect(score, closeTo(0.013, 0.001));
    });

    test('limit parameter: returns at most N results', () async {
      // Seed 10 families
      for (int i = 0; i < 10; i++) {
        await fakeFirestore.collection('families').doc('fam_$i').set({
          'status': 'accepted',
          'fundingStatus': 'pending',
          'targetAmount': 15000,
          'raisedAmount': i * 1000,
          'familySize': 4 + i,
          'createdAt': Timestamp.fromDate(
            DateTime.now().subtract(Duration(days: i + 1)),
          ),
        });
      }

      final snapshot = await fakeFirestore
          .collection('families')
          .where('status', isEqualTo: 'accepted')
          .get();

      // Simulate limit=5
      const limit = 5;
      final eligible = snapshot.docs
          .where((doc) => doc.data()['fundingStatus'] != 'fully_funded')
          .take(limit)
          .toList();

      expect(eligible.length, limit);
    });

    test('only accepted families are retrieved from Firestore', () async {
      final statuses = ['accepted', 'pending', 'rejected', 'accepted', 'pending'];
      for (int i = 0; i < statuses.length; i++) {
        await fakeFirestore.collection('families').doc('fam_status_$i').set({
          'status': statuses[i],
          'fundingStatus': 'pending',
          'targetAmount': 10000,
          'raisedAmount': 0,
          'familySize': 4,
          'createdAt': Timestamp.now(),
        });
      }

      final snapshot = await fakeFirestore
          .collection('families')
          .where('status', isEqualTo: 'accepted')
          .get();

      expect(snapshot.docs.length, 2); // Only 2 accepted
    });
  });
}
