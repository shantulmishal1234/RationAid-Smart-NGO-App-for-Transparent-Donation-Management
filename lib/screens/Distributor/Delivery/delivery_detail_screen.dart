import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ration_aid/models/delivery_assignment_model.dart';
import 'package:ration_aid/screens/Distributor/Delivery/delivery_map_screen.dart';
import 'package:ration_aid/screens/Distributor/Delivery/failure_report_screen.dart';
import 'package:ration_aid/screens/Distributor/Delivery/proof_of_delivery_screen.dart';
import 'package:ration_aid/services/delivery_service.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:ration_aid/widgets/frosted_panel.dart';

class DeliveryDetailScreen extends StatelessWidget {
  final String assignmentId;

  const DeliveryDetailScreen({super.key, required this.assignmentId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DeliveryAssignment?>(
      stream: DeliveryService.streamAssignment(assignmentId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppColors.volunteerBlue),
            ),
          );
        }
        final assignment = snapshot.data;
        if (assignment == null) {
          return const Scaffold(
            body: Center(child: Text('Delivery not found')),
          );
        }
        return _DeliveryDetailBody(assignment: assignment);
      },
    );
  }
}

class _DeliveryDetailBody extends StatefulWidget {
  final DeliveryAssignment assignment;
  const _DeliveryDetailBody({required this.assignment});

  @override
  State<_DeliveryDetailBody> createState() => _DeliveryDetailBodyState();
}

class _DeliveryDetailBodyState extends State<_DeliveryDetailBody> {
  bool _isProcessing = false;

  DeliveryAssignment get a => widget.assignment;

  Future<void> _markPickedUp() async {
    setState(() => _isProcessing = true);
    try {
      await DeliveryService.markPickedUp(a.id);
      _snack('✅ Marked as Picked Up', Colors.green);
    } catch (e) {
      _snack('Error: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _releaseAssignment() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Release Assignment'),
        content: const Text(
          'Are you sure you want to release this delivery back to the Available Pool? Another distributor will be able to claim it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Release'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (mounted) setState(() => _isProcessing = true);
    try {
      // Get the distributor's name
      // firebase auth currentUser has displayName if it was set
      // Alternatively we can just pass a generic name
      await DeliveryService.releaseAssignment(
        assignmentId: a.id,
        releasedByName:
            'A Distributor', // We don't query Firestore here to save time
      );

      if (mounted) {
        _snack('Delivery released back to the pool.', Colors.green);
        Navigator.pop(context); // Go back to dashboard
      }
    } catch (e) {
      if (mounted) {
        _snack('Error: $e', Colors.red);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _markInTransit() async {
    setState(() => _isProcessing = true);
    try {
      await DeliveryService.markInTransit(a.id);
      _snack('🚚 Marked as In Transit', Colors.blue);
    } catch (e) {
      _snack('Error: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _openProofOfDelivery() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProofOfDeliveryScreen(assignment: a)),
    );
  }

  void _openFailureReport() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FailureReportScreen(assignment: a)),
    );
  }

  void _openMap() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DeliveryMapScreen(assignment: a)),
    );
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM dd, yyyy · hh:mm a');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${a.familyArea} Delivery',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: Theme.of(context).brightness == Brightness.dark
                  ? [
                      AppColors.volunteerBlue.withValues(alpha: 0.1),
                      AppColors.volunteerBlue.withValues(alpha: 0.05),
                    ]
                  : [AppColors.volunteerBlue, Colors.blueAccent],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: Theme.of(context).brightness == Brightness.dark
                ? [const Color(0xFF121212), const Color(0xFF1E1E1E)]
                : [
                    const Color(0xFFE3F2FD),
                    const Color(0xFFBBDEFB),
                  ], // Light blue tint
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status banner
              _StatusBanner(status: a.status),
              const SizedBox(height: 20),

              // Admin Note
              if (a.adminNote != null && a.adminNote!.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Colors.orange,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Admin Note',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.orange,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              a.adminNote!,
                              style: TextStyle(
                                fontSize: 13,
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.orange[200]
                                    : Colors.orange[900],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Family info card (masked)
              FrostedPanel(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle(
                      context,
                      Icons.location_on,
                      'Delivery Location',
                    ),
                    const SizedBox(height: 12),
                    _infoRow(
                      context,
                      'Area',
                      '${a.familyArea}, ${a.familyCity}',
                    ),
                    _infoRow(
                      context,
                      'Address',
                      a.familyAddress.isEmpty
                          ? 'Not specified'
                          : a.familyAddress,
                    ),
                    if (a.familyPhone != null)
                      _infoRow(context, 'Contact', a.familyPhone!),
                    _infoRow(context, 'Family Size', '${a.familySize} members'),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Pack & Items
              FrostedPanel(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle(
                      context,
                      Icons.inventory_2_outlined,
                      'Items to Deliver',
                    ),
                    const SizedBox(height: 12),
                    if (a.assignedPackName != null)
                      _infoRow(context, 'Pack', a.assignedPackName!),
                    const SizedBox(height: 8),
                    if (a.items.isEmpty)
                      Text(
                        'No items specified',
                        style: TextStyle(color: Colors.grey[500]),
                      )
                    else
                      ...a.items.entries.map(
                        (e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: AppColors.volunteerBlue,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  e.key,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              Text(
                                '× ${e.value}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.volunteerBlue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Delivery Timeline
              FrostedPanel(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle(context, Icons.timeline, 'Delivery Timeline'),
                    const SizedBox(height: 16),
                    _timelineStep(
                      context,
                      label: 'Assigned',
                      timestamp: a.createdAt,
                      isCompleted: true,
                      color: AppColors.volunteerBlue,
                    ),
                    _timelineStep(
                      context,
                      label: 'Picked Up',
                      timestamp: a.pickedUpAt,
                      isCompleted: a.pickedUpAt != null,
                      color: Colors.orange,
                    ),
                    _timelineStep(
                      context,
                      label: 'In Transit',
                      timestamp: a.inTransitAt,
                      isCompleted: a.inTransitAt != null,
                      color: Colors.blue,
                    ),
                    _timelineStep(
                      context,
                      label: 'Delivered',
                      timestamp: a.deliveredAt,
                      isCompleted: a.deliveredAt != null,
                      color: Colors.purple,
                    ),
                    // GAP6: Show failure/reassignment event in timeline
                    if (a.isFailed || a.status == DeliveryStatus.reassigned)
                      _timelineStep(
                        context,
                        label: a.status == DeliveryStatus.reassigned
                            ? 'Reassigned'
                            : 'Failed — ${a.failureReason?.displayName ?? 'Reported'}',
                        timestamp: a.failedAt,
                        isCompleted: true,
                        color: a.status == DeliveryStatus.reassigned
                            ? Colors.deepOrange
                            : Colors.red,
                      ),
                    _timelineStep(
                      context,
                      label: 'Admin Verified',
                      timestamp: a.adminVerifiedAt,
                      isCompleted: a.adminVerified,
                      color: Colors.green,
                      isLast: true,
                    ),
                  ],
                ),
              ),

              // Failure info
              if (a.isFailed) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.red,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Failure Details',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (a.failureReason != null)
                        _infoRow(
                          context,
                          'Reason',
                          a.failureReason!.displayName,
                        ),
                      if (a.failureNotes?.isNotEmpty == true)
                        _infoRow(context, 'Notes', a.failureNotes!),
                      if (a.failedAt != null)
                        _infoRow(
                          context,
                          'Reported At',
                          fmt.format(a.failedAt!),
                        ),
                    ],
                  ),
                ),
              ],

              // Proof info
              if (a.proofPhotoUrl != null) ...[
                const SizedBox(height: 14),
                FrostedPanel(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle(
                        context,
                        Icons.photo_camera,
                        'Proof of Delivery',
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          a.proofPhotoUrl!,
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            height: 100,
                            color: Colors.grey[200],
                            child: const Center(
                              child: Icon(
                                Icons.broken_image,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (a.proofGeoLat != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(
                              Icons.gps_fixed,
                              size: 14,
                              color: Colors.green,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${a.proofGeoLat!.toStringAsFixed(5)}, ${a.proofGeoLng!.toStringAsFixed(5)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (a.proofTimestamp != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Captured: ${fmt.format(a.proofTimestamp!)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Action buttons
              if (!a.isFailed &&
                  a.status != DeliveryStatus.delivered &&
                  a.status != DeliveryStatus.adminVerified) ...[
                // Map / Navigate button (always visible when not completed)
                if (a.familyGeoLat != null)
                  _actionButton(
                    label: 'View Map & Navigate 🗺️',
                    icon: Icons.map_outlined,
                    color: const Color(0xFF4CAF50),
                    onTap: _openMap,
                  ),
                if (a.familyGeoLat != null) const SizedBox(height: 10),
                if (a.status == DeliveryStatus.notStarted) ...[
                  _actionButton(
                    label: 'Confirm Pickup',
                    icon: Icons.shopping_bag_outlined,
                    color: Colors.orange,
                    onTap: _isProcessing ? null : _markPickedUp,
                  ),
                  const SizedBox(height: 10),
                  _actionButton(
                    label: 'Release back to Pool',
                    icon: Icons.undo,
                    color: Colors.grey[700]!,
                    outlined: true,
                    onTap: _isProcessing ? null : _releaseAssignment,
                  ),
                ],
                if (a.status == DeliveryStatus.pickedUp)
                  _actionButton(
                    label: 'Start Transit (En Route)',
                    icon: Icons.local_shipping,
                    color: AppColors.volunteerBlue,
                    onTap: _isProcessing ? null : _markInTransit,
                  ),
                if (a.status == DeliveryStatus.inTransit) ...[
                  _actionButton(
                    label: 'Mark Delivered (Upload Proof)',
                    icon: Icons.camera_alt,
                    color: Colors.green,
                    onTap: _isProcessing ? null : _openProofOfDelivery,
                  ),
                  const SizedBox(height: 10),
                  _actionButton(
                    label: 'Report Failure',
                    icon: Icons.report_problem_outlined,
                    color: Colors.red,
                    onTap: _isProcessing ? null : _openFailureReport,
                    outlined: true,
                  ),
                ],
              ],

              if (a.status == DeliveryStatus.delivered && !a.adminVerified) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.purple.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.hourglass_top, color: Colors.purple, size: 18),
                      SizedBox(width: 10),
                      Text(
                        'Awaiting admin verification',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.purple,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
    bool outlined = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: outlined
          ? OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 18),
              label: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            )
          : ElevatedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 18),
              label: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
    );
  }

  Widget _timelineStep(
    BuildContext context, {
    required String label,
    DateTime? timestamp,
    required bool isCompleted,
    required Color color,
    bool isLast = false,
  }) {
    final fmt = DateFormat('MMM dd, hh:mm a');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isCompleted ? color : Colors.grey[300],
                shape: BoxShape.circle,
              ),
              child: Icon(
                isCompleted ? Icons.check : Icons.radio_button_unchecked,
                size: 14,
                color: isCompleted ? Colors.white : Colors.grey[500],
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 32,
                color: isCompleted
                    ? color.withValues(alpha: 0.4)
                    : Colors.grey[200],
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: isCompleted
                        ? color
                        : Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
                if (timestamp != null)
                  Text(
                    fmt.format(timestamp),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.volunteerBlue),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final DeliveryStatus status;
  const _StatusBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _color(status);
    final icon = _icon(status);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Current Status',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              Text(
                status.displayName,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _color(DeliveryStatus s) {
    switch (s) {
      case DeliveryStatus.notStarted:
        return Colors.grey;
      case DeliveryStatus.pickedUp:
        return Colors.orange;
      case DeliveryStatus.inTransit:
        return AppColors.volunteerBlue;
      case DeliveryStatus.delivered:
        return Colors.purple;
      case DeliveryStatus.adminVerified:
        return Colors.green;
      case DeliveryStatus.failed:
        return Colors.red;
      case DeliveryStatus.reassigned:
        return Colors.deepOrange;
    }
  }

  IconData _icon(DeliveryStatus s) {
    switch (s) {
      case DeliveryStatus.notStarted:
        return Icons.hourglass_empty;
      case DeliveryStatus.pickedUp:
        return Icons.shopping_bag;
      case DeliveryStatus.inTransit:
        return Icons.local_shipping;
      case DeliveryStatus.delivered:
        return Icons.check_circle;
      case DeliveryStatus.adminVerified:
        return Icons.verified;
      case DeliveryStatus.failed:
        return Icons.cancel;
      case DeliveryStatus.reassigned:
        return Icons.swap_horiz;
    }
  }
}
