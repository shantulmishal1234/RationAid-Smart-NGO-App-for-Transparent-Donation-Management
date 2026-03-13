import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents one in-kind batch received from a donor and stored in warehouse.
/// Created automatically when Admin verifies an in-kind donation.
class WarehouseStock {
  final String id;
  final String familyId;
  final String donationId;
  final String donorId;
  final String donorName;

  /// Physical items in this batch. { "Rice": 10, "Flour": 20 }
  final Map<String, int> items;

  /// Monetary value per item LOCKED at admin-approval time from the pack price.
  /// { "Rice": 800.0, "Flour": 1200.0 }
  final Map<String, double> itemValueSnapshot;

  /// Sum of all item values at snapshot prices. Never updated after creation.
  final double totalLockedValue;

  /// pending_pickup → in_transit → received → dispatched
  final String status;

  final String pickupAddress;
  final String contactNumber;

  /// ID of the InboundPickup task assigned to a Purchaser.
  final String? inboundPickupId;

  /// Cloudinary URL uploaded by the Purchaser as proof of collection.
  final String? pickupProofUrl;

  final DateTime? receivedAt;
  final DateTime? dispatchedAt;
  final DateTime createdAt;

  const WarehouseStock({
    required this.id,
    required this.familyId,
    required this.donationId,
    required this.donorId,
    required this.donorName,
    required this.items,
    required this.itemValueSnapshot,
    required this.totalLockedValue,
    required this.status,
    required this.pickupAddress,
    required this.contactNumber,
    required this.createdAt,
    this.inboundPickupId,
    this.pickupProofUrl,
    this.receivedAt,
    this.dispatchedAt,
  });

  factory WarehouseStock.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return WarehouseStock(
      id: doc.id,
      familyId: data['familyId'] ?? '',
      donationId: data['donationId'] ?? '',
      donorId: data['donorId'] ?? '',
      donorName: data['donorName'] ?? '',
      items: Map<String, int>.from(
        (data['items'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, (v as num).toInt()),
        ),
      ),
      itemValueSnapshot: Map<String, double>.from(
        (data['itemValueSnapshot'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, (v as num).toDouble()),
        ),
      ),
      totalLockedValue: (data['totalLockedValue'] as num? ?? 0).toDouble(),
      status: data['status'] ?? 'pending_pickup',
      pickupAddress: data['pickupAddress'] ?? '',
      contactNumber: data['contactNumber'] ?? '',
      inboundPickupId: data['inboundPickupId'],
      pickupProofUrl: data['pickupProofUrl'],
      receivedAt: (data['receivedAt'] as Timestamp?)?.toDate(),
      dispatchedAt: (data['dispatchedAt'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'familyId': familyId,
      'donationId': donationId,
      'donorId': donorId,
      'donorName': donorName,
      'items': items,
      'itemValueSnapshot': itemValueSnapshot,
      'totalLockedValue': totalLockedValue,
      'status': status,
      'pickupAddress': pickupAddress,
      'contactNumber': contactNumber,
      if (inboundPickupId != null) 'inboundPickupId': inboundPickupId,
      if (pickupProofUrl != null) 'pickupProofUrl': pickupProofUrl,
      if (receivedAt != null) 'receivedAt': Timestamp.fromDate(receivedAt!),
      if (dispatchedAt != null)
        'dispatchedAt': Timestamp.fromDate(dispatchedAt!),
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  WarehouseStock copyWith({
    String? status,
    String? inboundPickupId,
    String? pickupProofUrl,
    DateTime? receivedAt,
    DateTime? dispatchedAt,
  }) {
    return WarehouseStock(
      id: id,
      familyId: familyId,
      donationId: donationId,
      donorId: donorId,
      donorName: donorName,
      items: items,
      itemValueSnapshot: itemValueSnapshot,
      totalLockedValue: totalLockedValue,
      status: status ?? this.status,
      pickupAddress: pickupAddress,
      contactNumber: contactNumber,
      createdAt: createdAt,
      inboundPickupId: inboundPickupId ?? this.inboundPickupId,
      pickupProofUrl: pickupProofUrl ?? this.pickupProofUrl,
      receivedAt: receivedAt ?? this.receivedAt,
      dispatchedAt: dispatchedAt ?? this.dispatchedAt,
    );
  }
}
