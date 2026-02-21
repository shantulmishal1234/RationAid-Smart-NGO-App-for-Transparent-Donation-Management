import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ration_aid/models/delivery_assignment_model.dart';
import 'package:ration_aid/screens/Distributor/Delivery/delivery_map_screen.dart';
import 'package:ration_aid/screens/Distributor/Delivery/failure_report_screen.dart';
import 'package:ration_aid/screens/Distributor/Delivery/proof_of_delivery_screen.dart';
import 'package:ration_aid/services/delivery_service.dart';
import 'package:ration_aid/theme/app_colors.dart';

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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fmt = DateFormat('MMM dd, yyyy · hh:mm a');

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          '${a.familyArea} Delivery',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: AppColors.volunteerBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status banner
            _StatusBanner(status: a.status),
            const SizedBox(height: 20),

            // Family info card (masked)
            _SectionCard(
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle(
                    context,
                    Icons.location_on,
                    'Delivery Location',
                  ),
                  const SizedBox(height: 12),
                  _infoRow(context, 'Area', '${a.familyArea}, ${a.familyCity}'),
                  _infoRow(
                    context,
                    'Address',
                    a.familyAddress.isEmpty ? 'Not specified' : a.familyAddress,
                  ),
                  if (a.familyPhone != null)
                    _infoRow(context, 'Contact', a.familyPhone!),
                  _infoRow(context, 'Family Size', '${a.familySize} members'),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Pack & Items
            _SectionCard(
              isDark: isDark,
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
            _SectionCard(
              isDark: isDark,
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
                  color: Colors.red.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
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
                      _infoRow(context, 'Reason', a.failureReason!.displayName),
                    if (a.failureNotes?.isNotEmpty == true)
                      _infoRow(context, 'Notes', a.failureNotes!),
                    if (a.failedAt != null)
                      _infoRow(context, 'Reported At', fmt.format(a.failedAt!)),
                  ],
                ),
              ),
            ],

            // Proof info
            if (a.proofPhotoUrl != null) ...[
              const SizedBox(height: 14),
              _SectionCard(
                isDark: isDark,
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
                            child: Icon(Icons.broken_image, color: Colors.grey),
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
              if (a.status == DeliveryStatus.notStarted)
                _actionButton(
                  label: 'Confirm Pickup',
                  icon: Icons.shopping_bag_outlined,
                  color: Colors.orange,
                  onTap: _isProcessing ? null : _markPickedUp,
                ),
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
                  color: Colors.purple.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.purple.withOpacity(0.3)),
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
                color: isCompleted ? color.withOpacity(0.4) : Colors.grey[200],
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
                          ).colorScheme.onSurface.withOpacity(0.4),
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
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
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
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
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

class _SectionCard extends StatelessWidget {
  final Widget child;
  final bool isDark;
  const _SectionCard({required this.child, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}
