import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ration_aid/services/audit_service.dart';
import 'package:ration_aid/services/assistance_pack_service.dart';
import 'package:ration_aid/services/notification_service.dart';

/// Service for Final Approver to make final decisions on families that reached quorum
class FinalApprovalService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Check if current user is a final approver
  static Future<bool> isCurrentUserFinalApprover() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return false;

      final userDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!userDoc.exists) return false;

      return userDoc.data()?['isFinalApprover'] == true;
    } catch (e) {
      print('Error checking final approver status: $e');
      return false;
    }
  }

  /// Stream of families awaiting final approval (quorum reached but still pending)
  static Stream<QuerySnapshot> getFamiliesAwaitingApprovalStream() {
    return _firestore
        .collection('families')
        .where('status', isEqualTo: 'pending_review')
        .where('quorumReached', isEqualTo: true)
        .snapshots();
  }

  /// Get count of families awaiting final approval
  static Future<int> getAwaitingApprovalCount() async {
    try {
      final snapshot = await _firestore
          .collection('families')
          .where('status', isEqualTo: 'pending_review')
          .where('quorumReached', isEqualTo: true)
          .count()
          .get();

      return snapshot.count ?? 0;
    } catch (e) {
      print('Error getting awaiting approval count: $e');
      return 0;
    }
  }

  /// Make final decision on a family
  static Future<void> makeFinalDecision({
    required String familyId,
    required String decision, // 'accept' or 'reject'
    String? comment,
  }) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      // Verify user is final approver
      final isFinalApprover = await isCurrentUserFinalApprover();
      if (!isFinalApprover) {
        throw Exception('User is not authorized as final approver');
      }

      // Get user name
      final userDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();
      final userName = userDoc.data()?['name'] ?? 'Unknown Admin';

      // Get family data for audit
      final familyDoc = await _firestore
          .collection('families')
          .doc(familyId)
          .get();
      final familyName = familyDoc.data()?['name'] ?? 'Unknown Family';

      // Determine new status
      final newStatus = decision == 'accept' ? 'accepted' : 'rejected';

      // Prepare update data
      Map<String, dynamic> updateData = {
        'status': newStatus,
        'finalApproverUid': currentUser.uid,
        'finalApproverName': userName,
        'finalDecision': decision,
        'finalDecisionComment': comment,
        'finalDecisionAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // If accepting, lock location by copying unverified to verified
      if (decision == 'accept') {
        final familyData = familyDoc.data();
        if (familyData != null && familyData['unverifiedLocation'] != null) {
          updateData['verifiedLocation'] = familyData['unverifiedLocation'];
          updateData['locationVerifiedAt'] = FieldValue.serverTimestamp();
          updateData['locationVerifiedBy'] = userName;
        }

        // Auto-assign assistance pack based on family size
        final familySize = familyData?['familySize'] ?? 0;
        if (familySize > 0) {
          try {
            final matchingPack = await AssistancePackService.findMatchingPack(
              familySize,
            );
            if (matchingPack != null) {
              updateData['assignedPackId'] = matchingPack.id;
              updateData['assignedPackName'] = matchingPack.name;
              updateData['assignedPackBudget'] = matchingPack.budgetAmount;

              // Phase 4 & 6 Fix: Populate target amount and needs from pack
              updateData['targetAmount'] = matchingPack.budgetAmount;
              updateData['remainingAmount'] = matchingPack.budgetAmount;

              // Convert List<PackItem> to Map<String, int> for family needs
              final Map<String, int> packNeeds = {};
              for (var item in matchingPack.items) {
                // Parse quantity string to int (handle "2 kg" -> 2 if needed, or assume int string)
                // For now assuming quantity is numeric string or simple count
                final qty =
                    int.tryParse(
                      item.quantity.replaceAll(RegExp(r'[^0-9]'), ''),
                    ) ??
                    1;
                packNeeds[item.name] = qty;
              }
              updateData['needs'] = packNeeds;

              // Log pack assignment
              await AuditService.logAction(
                action: 'auto_assign_pack',
                entityType: 'family',
                entityId: familyId,
                details:
                    'Auto-assigned assistance pack "${matchingPack.name}" to family',
                metadata: {
                  'packId': matchingPack.id,
                  'packName': matchingPack.name,
                  'packBudget': matchingPack.budgetAmount,
                  'familySize': familySize,
                  'itemsCount': packNeeds.length,
                },
              );
            }
          } catch (e) {
            print('Error auto-assigning pack: $e');
            // Continue with approval even if pack assignment fails
          }
        }
      }

      // Update family document
      await _firestore.collection('families').doc(familyId).update(updateData);

      // Log audit trail
      await AuditService.logAction(
        action: 'final_approval_decision',
        entityType: 'family',
        entityId: familyId,
        details:
            'Final Approver $userName ${decision == 'accept' ? 'accepted' : 'rejected'} family $familyName',
        metadata: {
          'decision': decision,
          'comment': comment,
          'finalApproverUid': currentUser.uid,
          'finalApproverName': userName,
          'familyName': familyName,
        },
      );

      // Notify Admins about the decision
      await NotificationService.sendAdminNotification(
        title: 'Family ${decision == 'accept' ? 'Approved' : 'Rejected'}',
        message:
            'Final Approver $userName has ${decision == 'accept' ? 'accepted' : 'rejected'} family $familyName.',
        type: 'final_decision',
        relatedId: familyId,
      );
    } catch (e) {
      print('Error making final decision: $e');
      rethrow;
    }
  }
}
