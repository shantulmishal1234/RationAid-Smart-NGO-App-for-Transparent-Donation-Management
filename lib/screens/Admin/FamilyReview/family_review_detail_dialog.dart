import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:ration_aid/models/family_model.dart';
import 'package:ration_aid/models/family_review_model.dart';
import 'package:ration_aid/services/family_review_service.dart';

/// Dialog showing family details with voting interface
class FamilyReviewDetailDialog extends StatefulWidget {
  final Family family;

  const FamilyReviewDetailDialog({super.key, required this.family});

  @override
  State<FamilyReviewDetailDialog> createState() =>
      _FamilyReviewDetailDialogState();
}

class _FamilyReviewDetailDialogState extends State<FamilyReviewDetailDialog> {
  final _commentController = TextEditingController();
  String? _selectedDecision;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitVote() async {
    if (_selectedDecision == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select Approve or Reject'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_selectedDecision == 'reject' &&
        _commentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Comment is required for rejection'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final success = await FamilyReviewService.submitVote(
        familyId: widget.family.id,
        decision: _selectedDecision!,
        comment: _commentController.text.trim().isEmpty
            ? null
            : _commentController.text.trim(),
      );

      if (!mounted) return;

      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You have already voted on this family'),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.pop(context);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Vote submitted: ${_selectedDecision == 'approve' ? 'Approved' : 'Rejected'}',
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error submitting vote: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 700, maxWidth: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.family_restroom,
                    color: Colors.white,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Family Review',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          widget.family.id,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Family Details
                    _buildSection(
                      title: 'Family Information',
                      child: Column(
                        children: [
                          _buildDetailRow('City', widget.family.city),
                          _buildDetailRow('Area', widget.family.area),
                          _buildDetailRow(
                            'Family Size',
                            widget.family.familySize.toString(),
                          ),
                          _buildDetailRow(
                            'Adults',
                            widget.family.numberOfAdults.toString(),
                          ),
                          _buildDetailRow(
                            'Children',
                            widget.family.numberOfChildren.toString(),
                          ),
                          if (widget.family.assistanceNeeds.isNotEmpty)
                            _buildDetailRow(
                              'Assistance Needs',
                              widget.family.assistanceNeeds.join(', '),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Location Map
                    if (widget.family.unverifiedLocation != null)
                      _buildSection(
                        title: 'Captured Location',
                        child: Column(
                          children: [
                            Container(
                              height: 200,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: theme.dividerColor),
                              ),
                              clipBehavior: Clip.hardEdge,
                              child: FlutterMap(
                                options: MapOptions(
                                  initialCenter: LatLng(
                                    widget.family.unverifiedLocation!.latitude,
                                    widget.family.unverifiedLocation!.longitude,
                                  ),
                                  initialZoom: 14.0,
                                  interactionOptions: const InteractionOptions(
                                    flags:
                                        InteractiveFlag.pinchZoom |
                                        InteractiveFlag.drag,
                                  ),
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate:
                                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                    userAgentPackageName: 'com.rationaid.app',
                                  ),
                                  MarkerLayer(
                                    markers: [
                                      Marker(
                                        point: LatLng(
                                          widget
                                              .family
                                              .unverifiedLocation!
                                              .latitude,
                                          widget
                                              .family
                                              .unverifiedLocation!
                                              .longitude,
                                        ),
                                        width: 50,
                                        height: 50,
                                        child: const Icon(
                                          Icons.location_pin,
                                          size: 40,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.family.locationAddress ??
                                  'Lat: ${widget.family.unverifiedLocation!.latitude.toStringAsFixed(6)}, Lng: ${widget.family.unverifiedLocation!.longitude.toStringAsFixed(6)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface.withOpacity(
                                  0.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),

                    // Existing Votes
                    _buildSection(
                      title: 'Admin Votes',
                      child: FutureBuilder<List<FamilyReview>>(
                        future: FamilyReviewService.getFamilyReviews(
                          widget.family.id,
                        ),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          if (snapshot.data!.isEmpty) {
                            return const Text(
                              'No votes yet. Be the first to vote!',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            );
                          }

                          return Column(
                            children: snapshot.data!.map((review) {
                              return _buildVoteItem(review, theme);
                            }).toList(),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Voting Section
                    FutureBuilder<bool>(
                      future: FamilyReviewService.hasUserVoted(
                        widget.family.id,
                        currentUserId ?? '',
                      ),
                      builder: (context, snapshot) {
                        final hasVoted = snapshot.data ?? false;

                        if (hasVoted) {
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.green.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: Colors.green[700],
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'You have already submitted your vote for this family',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.green[700],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return _buildVotingInterface(theme);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildVoteItem(FamilyReview review, ThemeData theme) {
    final isApproval = review.isApproval;
    final color = isApproval ? Colors.green : Colors.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isApproval ? Icons.thumb_up : Icons.thumb_down,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  review.reviewerName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  isApproval ? 'Approved' : 'Rejected',
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (review.comment != null && review.comment!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    review.comment!,
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVotingInterface(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your Vote',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),

        // Vote Buttons
        Row(
          children: [
            Expanded(
              child: _buildVoteButton(
                label: 'Approve',
                icon: Icons.thumb_up,
                color: Colors.green,
                decision: 'approve',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildVoteButton(
                label: 'Reject',
                icon: Icons.thumb_down,
                color: Colors.red,
                decision: 'reject',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Comment Field
        TextFormField(
          controller: _commentController,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: _selectedDecision == 'reject'
                ? 'Comment (Required)*'
                : 'Comment (Optional)',
            hintText: 'Add your review comments...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            filled: true,
            fillColor: theme.scaffoldBackgroundColor,
          ),
        ),
        const SizedBox(height: 16),

        // Submit Button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _submitVote,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Submit Vote',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildVoteButton({
    required String label,
    required IconData icon,
    required Color color,
    required String decision,
  }) {
    final isSelected = _selectedDecision == decision;

    return OutlinedButton.icon(
      onPressed: () {
        setState(() {
          _selectedDecision = decision;
        });
      },
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: isSelected ? Colors.white : color,
        backgroundColor: isSelected ? color : Colors.transparent,
        side: BorderSide(color: color, width: 2),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }
}
