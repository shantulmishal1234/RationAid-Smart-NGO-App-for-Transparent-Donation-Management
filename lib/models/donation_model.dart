import 'package:cloud_firestore/cloud_firestore.dart';

/// Donation status enum - all 11 states from the workflow
enum DonationStatus {
  draft,
  pending,
  underVerification,
  verified,
  inProcess,
  outForDelivery,
  delivered,
  closed,
  rejected;

  String get displayName {
    switch (this) {
      case DonationStatus.draft:
        return 'Draft';
      case DonationStatus.pending:
        return 'Pending'; // Legacy status, not used in current donor flow
      case DonationStatus.underVerification:
        return 'Under Verification';
      case DonationStatus.verified:
        return 'Verified';
      case DonationStatus.inProcess:
        return 'In Process';
      case DonationStatus.outForDelivery:
        return 'Out for Delivery';
      case DonationStatus.delivered:
        return 'Delivered';
      case DonationStatus.closed:
        return 'Closed';
      case DonationStatus.rejected:
        return 'Rejected';
    }
  }

  String toFirestore() {
    switch (this) {
      case DonationStatus.draft:
        return 'draft';
      case DonationStatus.pending:
        return 'pending';
      case DonationStatus.underVerification:
        return 'under_verification';
      case DonationStatus.verified:
        return 'verified';
      case DonationStatus.inProcess:
        return 'in_process';
      case DonationStatus.outForDelivery:
        return 'out_for_delivery';
      case DonationStatus.delivered:
        return 'delivered';
      case DonationStatus.closed:
        return 'closed';
      case DonationStatus.rejected:
        return 'rejected';
    }
  }

  static DonationStatus fromFirestore(String value) {
    switch (value) {
      case 'draft':
        return DonationStatus.draft;
      case 'pending':
        return DonationStatus.pending;
      case 'under_verification':
        return DonationStatus.underVerification;
      case 'verified':
        return DonationStatus.verified;
      case 'in_process':
        return DonationStatus.inProcess;
      case 'out_for_delivery':
        return DonationStatus.outForDelivery;
      case 'delivered':
        return DonationStatus.delivered;
      case 'closed':
        return DonationStatus.closed;
      case 'rejected':
        return DonationStatus.rejected;
      default:
        return DonationStatus.draft;
    }
  }
}

/// Donation type enum
enum DonationType {
  cash,
  inKind;

  String get displayName {
    switch (this) {
      case DonationType.cash:
        return 'Cash';
      case DonationType.inKind:
        return 'In-Kind';
    }
  }

  String toFirestore() {
    return name;
  }

  static DonationType fromFirestore(String value) {
    return value == 'cash' ? DonationType.cash : DonationType.inKind;
  }
}

/// Status history entry for tracking
class StatusHistoryEntry {
  final DonationStatus status;
  final DateTime timestamp;
  final String note;

  StatusHistoryEntry({
    required this.status,
    required this.timestamp,
    required this.note,
  });

  Map<String, dynamic> toMap() {
    return {
      'status': status.toFirestore(),
      'timestamp': Timestamp.fromDate(timestamp),
      'note': note,
    };
  }

  static StatusHistoryEntry fromMap(Map<String, dynamic> map) {
    return StatusHistoryEntry(
      status: DonationStatus.fromFirestore(map['status'] ?? 'draft'),
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      note: map['note'] ?? '',
    );
  }
}

/// Donation model class
class Donation {
  final String id;
  final String donorId;
  final String? donorName; // Donor's name for display
  final String? donorEmail; // Donor's email for display
  final String familyId;
  final DonationType donationType;
  final double? amount; // nullable for in-kind or when not specified
  final Map<String, int>? items; // nullable for cash donations
  final bool anonymous;
  final DonationStatus status;
  final String? rejectionReason; // nullable
  final String? paymentProofUrl; // nullable
  final String? receiptUrl; // nullable
  final String? donationNote; // optional note from donor
  final DateTime createdAt;
  final DateTime updatedAt;

  // Tracking fields
  final List<StatusHistoryEntry> statusHistory;
  final DateTime? estimatedDelivery;
  final String? driverName;
  final String? driverPhone;
  final String? vehicleNumber;
  final List<String> deliveryPhotos;
  final DateTime? deliveredAt;
  final String? receivedBy;

  Donation({
    required this.id,
    required this.donorId,
    this.donorName,
    this.donorEmail,
    required this.familyId,
    required this.donationType,
    this.amount,
    this.items,
    this.anonymous = false,
    required this.status,
    this.rejectionReason,
    this.paymentProofUrl,
    this.receiptUrl,
    this.donationNote,
    required this.createdAt,
    required this.updatedAt,
    this.statusHistory = const [],
    this.estimatedDelivery,
    this.driverName,
    this.driverPhone,
    this.vehicleNumber,
    this.deliveryPhotos = const [],
    this.deliveredAt,
    this.receivedBy,
  });

  /// Factory constructor from Firestore document
  factory Donation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Parse status history
    final List<StatusHistoryEntry> history = [];
    if (data['statusHistory'] != null) {
      for (var entry in data['statusHistory'] as List) {
        history.add(StatusHistoryEntry.fromMap(entry as Map<String, dynamic>));
      }
    }

    // Parse delivery photos
    final List<String> photos = [];
    if (data['deliveryPhotos'] != null) {
      photos.addAll((data['deliveryPhotos'] as List).cast<String>());
    }

    return Donation(
      id: doc.id,
      donorId: data['donorId'] ?? '',
      donorName: data['donorName'],
      donorEmail: data['donorEmail'],
      familyId: data['familyId'] ?? '',
      donationType: DonationType.fromFirestore(data['donationType'] ?? 'cash'),
      amount: data['amount']?.toDouble(),
      items: data['items'] != null
          ? Map<String, int>.from(data['items'] as Map)
          : null,
      anonymous: data['anonymous'] ?? false,
      status: DonationStatus.fromFirestore(data['status'] ?? 'draft'),
      rejectionReason: data['rejectionReason'],
      paymentProofUrl: data['paymentProofUrl'],
      receiptUrl: data['receiptUrl'],
      donationNote: data['donationNote'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      statusHistory: history,
      estimatedDelivery: (data['estimatedDelivery'] as Timestamp?)?.toDate(),
      driverName: data['driverName'],
      driverPhone: data['driverPhone'],
      vehicleNumber: data['vehicleNumber'],
      deliveryPhotos: photos,
      deliveredAt: (data['deliveredAt'] as Timestamp?)?.toDate(),
      receivedBy: data['receivedBy'],
    );
  }

  /// Convert to Firestore map
  Map<String, dynamic> toFirestore() {
    return {
      'donorId': donorId,
      'donorName': donorName,
      'donorEmail': donorEmail,
      'familyId': familyId,
      'donationType': donationType.toFirestore(),
      'amount': amount,
      'items': items,
      'anonymous': anonymous,
      'status': status.toFirestore(),
      'rejectionReason': rejectionReason,
      'paymentProofUrl': paymentProofUrl,
      'receiptUrl': receiptUrl,
      'donationNote': donationNote,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'statusHistory': statusHistory.map((e) => e.toMap()).toList(),
      'estimatedDelivery': estimatedDelivery != null
          ? Timestamp.fromDate(estimatedDelivery!)
          : null,
      'driverName': driverName,
      'driverPhone': driverPhone,
      'vehicleNumber': vehicleNumber,
      'deliveryPhotos': deliveryPhotos,
      'deliveredAt': deliveredAt != null
          ? Timestamp.fromDate(deliveredAt!)
          : null,
      'receivedBy': receivedBy,
    };
  }

  /// Helper: Check if donation is editable
  bool get isEditable {
    return status == DonationStatus.draft || status == DonationStatus.pending;
  }

  /// Helper: Check if donation is deletable
  bool get isDeletable {
    return status == DonationStatus.draft;
  }

  /// Helper: Check if donation can be re-uploaded
  bool get canReupload {
    return status == DonationStatus.rejected;
  }

  /// Helper: Get status color
  /// (Color values will be defined in UI, this returns the name)
  String get statusColor {
    switch (status) {
      case DonationStatus.draft:
        return 'grey';
      case DonationStatus.pending:
      case DonationStatus.underVerification:
        return 'orange';
      case DonationStatus.verified:
      case DonationStatus.inProcess:
        return 'blue';
      case DonationStatus.outForDelivery:
      case DonationStatus.delivered:
        return 'purple';
      case DonationStatus.closed:
        return 'green';
      case DonationStatus.rejected:
        return 'red';
    }
  }

  /// Copy with method for updates
  Donation copyWith({
    String? id,
    String? donorId,
    String? familyId,
    DonationType? donationType,
    double? amount,
    Map<String, int>? items,
    bool? anonymous,
    DonationStatus? status,
    String? rejectionReason,
    String? paymentProofUrl,
    String? receiptUrl,
    String? donationNote,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Donation(
      id: id ?? this.id,
      donorId: donorId ?? this.donorId,
      familyId: familyId ?? this.familyId,
      donationType: donationType ?? this.donationType,
      amount: amount ?? this.amount,
      items: items ?? this.items,
      anonymous: anonymous ?? this.anonymous,
      status: status ?? this.status,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      paymentProofUrl: paymentProofUrl ?? this.paymentProofUrl,
      receiptUrl: receiptUrl ?? this.receiptUrl,
      donationNote: donationNote ?? this.donationNote,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
