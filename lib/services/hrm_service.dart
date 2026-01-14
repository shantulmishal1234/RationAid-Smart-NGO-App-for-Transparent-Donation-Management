import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HrmService {
  static Future<void> recordDistributorAction({
    bool incrementDeliveryCount = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

    final updates = <String, dynamic>{
      'lastActionAt': FieldValue.serverTimestamp(),
    };

    if (incrementDeliveryCount) {
      updates['deliveryCount'] = FieldValue.increment(1);
    }

    await docRef.update(updates);
  }
}
