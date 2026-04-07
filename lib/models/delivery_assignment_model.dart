import 'package:cloud_firestore/cloud_firestore.dart';

// ─── Delivery Status Enum ────────────────────────────────────────────────────

enum DeliveryStatus {
  notStarted,
  pickedUp,
  inTransit,
  delivered,
  failed,
  adminVerified,
  reassigned;

  String toFirestore() {
    switch (this) {
      case DeliveryStatus.notStarted:
        return 'not_started';
      case DeliveryStatus.pickedUp:
        return 'picked_up';
      case DeliveryStatus.inTransit:
        return 'in_transit';
      case DeliveryStatus.delivered:
        return 'delivered';
      case DeliveryStatus.failed:
        return 'failed';
      case DeliveryStatus.adminVerified:
        return 'admin_verified';
      case DeliveryStatus.reassigned:
        return 'reassigned';
    }
  }

  static DeliveryStatus fromFirestore(String value) {
    switch (value) {
      case 'not_started':
        return DeliveryStatus.notStarted;
      case 'picked_up':
        return DeliveryStatus.pickedUp;
      case 'in_transit':
        return DeliveryStatus.inTransit;
      case 'delivered':
        return DeliveryStatus.delivered;
      case 'failed':
        return DeliveryStatus.failed;
      case 'admin_verified':
        return DeliveryStatus.adminVerified;
      case 'reassigned':
        return DeliveryStatus.reassigned;
      default:
        return DeliveryStatus.notStarted;
    }
  }

  String get displayName {
    switch (this) {
      case DeliveryStatus.notStarted:
        return 'Not Started';
      case DeliveryStatus.pickedUp:
        return 'Picked Up';
      case DeliveryStatus.inTransit:
        return 'In Transit';
      case DeliveryStatus.delivered:
        return 'Delivered';
      case DeliveryStatus.failed:
        return 'Failed';
      case DeliveryStatus.adminVerified:
        return 'Verified';
      case DeliveryStatus.reassigned:
        return 'Reassigned';
    }
  }
}

// ─── Failure Reason Enum ─────────────────────────────────────────────────────

enum DeliveryFailureReason {
  familyUnavailable,
  addressIncorrect,
  safetyConcern,
  other;

  String toFirestore() {
    switch (this) {
      case DeliveryFailureReason.familyUnavailable:
        return 'family_unavailable';
      case DeliveryFailureReason.addressIncorrect:
        return 'address_incorrect';
      case DeliveryFailureReason.safetyConcern:
        return 'safety_concern';
      case DeliveryFailureReason.other:
        return 'other';
    }
  }

  static DeliveryFailureReason fromFirestore(String value) {
    switch (value) {
      case 'family_unavailable':
        return DeliveryFailureReason.familyUnavailable;
      case 'address_incorrect':
        return DeliveryFailureReason.addressIncorrect;
      case 'safety_concern':
        return DeliveryFailureReason.safetyConcern;
      default:
        return DeliveryFailureReason.other;
    }
  }

  String get displayName {
    switch (this) {
      case DeliveryFailureReason.familyUnavailable:
        return 'Family Unavailable';
      case DeliveryFailureReason.addressIncorrect:
        return 'Address Incorrect';
      case DeliveryFailureReason.safetyConcern:
        return 'Safety Concern';
      case DeliveryFailureReason.other:
        return 'Other';
    }
  }
}

// ─── Delivery Assignment Model ───────────────────────────────────────────────

class DeliveryAssignment {
  final String id;
  final String familyId;

  // Family info (masked for privacy — area + city only shown on list)
  final String familyArea;
  final String familyCity;
  final String familyAddress; // Full address shown to assigned distributor only
  final String? familyPhone;
  final int familySize;

  // Family verified GPS location (from household form — for OSM map navigation)
  final double? familyGeoLat;
  final double? familyGeoLng;
  final bool
  familyLocationVerified; // true = admin verified location (reliable)

  // Pack/items info
  final String? assignedPackId;
  final String? assignedPackName;
  final Map<String, num> items; // item name → quantity

  // Distributor assignment
  final String? assignedDistributorId;
  final String? assignedDistributorName;

  // Status tracking
  final DeliveryStatus status;
  final DateTime? scheduledAt;
  final DateTime? pickedUpAt;
  final DateTime? inTransitAt;
  final DateTime? deliveredAt;
  final DateTime? failedAt;

  // Proof of delivery
  final String? proofPhotoUrl;
  final double? proofGeoLat;
  final double? proofGeoLng;
  final DateTime? proofTimestamp;
  final String? proofAddress; // reverse-geocoded address

  // Failure info
  final DeliveryFailureReason? failureReason;
  final String? failureNotes;

  // Admin verification
  final bool adminVerified;
  final DateTime? adminVerifiedAt;
  final String? adminVerifiedBy;
  final String? adminVerifiedByName;

  // Linked donations
  final List<String> donationIds;

  // Procurement link
  final String? procurementRequestId;

  // In-Kind items reserved from warehouse
  final List<String> inKindCoveredItems;

  // Admin notes
  final String? adminNote;

  final DateTime createdAt;
  final DateTime updatedAt;

  DeliveryAssignment({
    required this.id,
    required this.familyId,
    required this.familyArea,
    required this.familyCity,
    this.familyAddress = '',
    this.familyPhone,
    this.familySize = 0,
    this.familyGeoLat,
    this.familyGeoLng,
    this.familyLocationVerified = false,
    this.assignedPackId,
    this.assignedPackName,
    this.items = const {},
    this.assignedDistributorId,
    this.assignedDistributorName,
    this.status = DeliveryStatus.notStarted,
    this.scheduledAt,
    this.pickedUpAt,
    this.inTransitAt,
    this.deliveredAt,
    this.failedAt,
    this.proofPhotoUrl,
    this.proofGeoLat,
    this.proofGeoLng,
    this.proofTimestamp,
    this.proofAddress,
    this.failureReason,
    this.failureNotes,
    this.adminVerified = false,
    this.adminVerifiedAt,
    this.adminVerifiedBy,
    this.adminVerifiedByName,
    this.donationIds = const [],
    this.procurementRequestId,
    this.inKindCoveredItems = const [],
    this.adminNote,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DeliveryAssignment.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return DeliveryAssignment(
      id: doc.id,
      familyId: d['familyId'] ?? '',
      familyArea: d['familyArea'] ?? '',
      familyCity: d['familyCity'] ?? '',
      familyAddress: d['familyAddress'] ?? '',
      familyPhone: d['familyPhone'],
      familySize: d['familySize'] ?? 0,
      familyGeoLat: (d['familyGeoLat'] as num?)?.toDouble(),
      familyGeoLng: (d['familyGeoLng'] as num?)?.toDouble(),
      familyLocationVerified: d['familyLocationVerified'] ?? false,
      assignedPackId: d['assignedPackId'],
      assignedPackName: d['assignedPackName'],
      items: d['items'] != null ? Map<String, num>.from(d['items']) : {},
      assignedDistributorId: d['assignedDistributorId'],
      assignedDistributorName: d['assignedDistributorName'],
      status: DeliveryStatus.fromFirestore(d['status'] ?? 'not_started'),
      scheduledAt: (d['scheduledAt'] as Timestamp?)?.toDate(),
      pickedUpAt: (d['pickedUpAt'] as Timestamp?)?.toDate(),
      inTransitAt: (d['inTransitAt'] as Timestamp?)?.toDate(),
      deliveredAt: (d['deliveredAt'] as Timestamp?)?.toDate(),
      failedAt: (d['failedAt'] as Timestamp?)?.toDate(),
      proofPhotoUrl: d['proofPhotoUrl'],
      proofGeoLat: (d['proofGeoLat'] as num?)?.toDouble(),
      proofGeoLng: (d['proofGeoLng'] as num?)?.toDouble(),
      proofTimestamp: (d['proofTimestamp'] as Timestamp?)?.toDate(),
      proofAddress: d['proofAddress'],
      failureReason: d['failureReason'] != null
          ? DeliveryFailureReason.fromFirestore(d['failureReason'])
          : null,
      failureNotes: d['failureNotes'],
      adminVerified: d['adminVerified'] ?? false,
      adminVerifiedAt: (d['adminVerifiedAt'] as Timestamp?)?.toDate(),
      adminVerifiedBy: d['adminVerifiedBy'],
      adminVerifiedByName: d['adminVerifiedByName'],
      donationIds: d['donationIds'] != null
          ? List<String>.from(d['donationIds'])
          : [],
      procurementRequestId: d['procurementRequestId'],
      inKindCoveredItems: d['inKindCoveredItems'] != null
          ? List<String>.from(d['inKindCoveredItems'])
          : [],
      adminNote: d['adminNote'],
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'familyId': familyId,
      'familyArea': familyArea,
      'familyCity': familyCity,
      'familyAddress': familyAddress,
      'familyPhone': familyPhone,
      'familySize': familySize,
      'familyGeoLat': familyGeoLat,
      'familyGeoLng': familyGeoLng,
      'familyLocationVerified': familyLocationVerified,
      'assignedPackId': assignedPackId,
      'assignedPackName': assignedPackName,
      'items': items,
      'assignedDistributorId': assignedDistributorId,
      'assignedDistributorName': assignedDistributorName,
      'status': status.toFirestore(),
      'scheduledAt': scheduledAt != null
          ? Timestamp.fromDate(scheduledAt!)
          : null,
      'pickedUpAt': pickedUpAt != null ? Timestamp.fromDate(pickedUpAt!) : null,
      'inTransitAt': inTransitAt != null
          ? Timestamp.fromDate(inTransitAt!)
          : null,
      'deliveredAt': deliveredAt != null
          ? Timestamp.fromDate(deliveredAt!)
          : null,
      'failedAt': failedAt != null ? Timestamp.fromDate(failedAt!) : null,
      'proofPhotoUrl': proofPhotoUrl,
      'proofGeoLat': proofGeoLat,
      'proofGeoLng': proofGeoLng,
      'proofTimestamp': proofTimestamp != null
          ? Timestamp.fromDate(proofTimestamp!)
          : null,
      'proofAddress': proofAddress,
      'failureReason': failureReason?.toFirestore(),
      'failureNotes': failureNotes,
      'adminVerified': adminVerified,
      'adminVerifiedAt': adminVerifiedAt != null
          ? Timestamp.fromDate(adminVerifiedAt!)
          : null,
      'adminVerifiedBy': adminVerifiedBy,
      'adminVerifiedByName': adminVerifiedByName,
      'donationIds': donationIds,
      'procurementRequestId': procurementRequestId,
      if (inKindCoveredItems.isNotEmpty) 'inKindCoveredItems': inKindCoveredItems,
      'adminNote': adminNote,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  bool get isActive =>
      status == DeliveryStatus.pickedUp || status == DeliveryStatus.inTransit;

  bool get isPending => status == DeliveryStatus.notStarted;

  bool get isCompleted =>
      status == DeliveryStatus.delivered ||
      status == DeliveryStatus.adminVerified;

  bool get isFailed =>
      status == DeliveryStatus.failed || status == DeliveryStatus.reassigned;

  bool get needsAdminVerification =>
      status == DeliveryStatus.delivered && !adminVerified;
}
