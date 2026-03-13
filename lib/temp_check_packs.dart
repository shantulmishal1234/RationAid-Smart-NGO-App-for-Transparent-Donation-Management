import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  final db = FirebaseFirestore.instance;
  final snapshot = await db.collection('assistance_packs').get();

  for (var doc in snapshot.docs) {
    final data = doc.data();
    print('Pack: ${data['name']} (Budget: ${data['budgetAmount']})');
    final items = data['items'] as List<dynamic>? ?? [];
    for (var item in items) {
      print('  - ${item['name']}: ${item['quantity']}');
    }
  }
}
