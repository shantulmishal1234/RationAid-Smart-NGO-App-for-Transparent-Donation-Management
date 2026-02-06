import 'package:flutter/material.dart';
import 'package:ration_aid/models/family_model.dart';
import 'package:ration_aid/models/family_review_model.dart';
import 'package:ration_aid/services/family_review_service.dart';
import 'package:ration_aid/services/final_approval_service.dart';

/// Dialog for Final Approver to review and make final decision
class FinalApprovalDialog extends StatefulWidget {
  final Family family;

  const FinalApprovalDialog({super.key, required this.family});

  @override
  State<FinalApprovalDialog> createState() => _FinalApprovalDialogState();
}

class _FinalApprovalDialogState extends State<FinalApprovalDialog> {
  String? _selectedDecision;
  final _commentController = TextEditingController();
  bool _isSubmitting = false;
  List<FamilyReview> _reviews = [];
  bool _loadingReviews = true;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadReviews() async {
    final reviews = await FamilyReviewService.getFamilyReviews(
      widget.family.id,
    );

    if (mounted) {
      setState(() {
        _reviews = reviews;
        _loadingReviews = false;
      });
    }
  }

  Future<void> _makeDecision() async {
    if (_selectedDecision == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select Accept or Reject'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await FinalApprovalService.makeFinalDecision(
        familyId: widget.family.id,
        decision: _selectedDecision!,
        comment: _commentController.text.trim().isEmpty
            ? null
            : _commentController.text.trim(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Family ${_selectedDecision == 'accept' ? 'accepted' : 'rejected'} successfully',
          ),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.of(context).pop(); // Close dialog
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error making decision: $e'),
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
    final totalVotes = widget.family.approveCount + widget.family.rejectCount;

    return Dialog(
      backgroundColor: theme.dialogBackgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.gavel, color: theme.colorScheme.primary, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Final Approval Decision',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          'Family ID: ${widget.family.id.substring(widget.family.id.length - 8)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
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
                    // Quorum Status
                    _buildQuorumStatus(theme, totalVotes),

                    const SizedBox(height: 20),

                    // Vote Summary
                    _buildVoteSummary(theme),

                    const SizedBox(height: 20),

                    // All Reviews
                    if (_loadingReviews)
                      const Center(child: CircularProgressIndicator())
                    else if (_reviews.isNotEmpty) ...[
                      Text(
                        'Admin Votes (${_reviews.length})',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._reviews.map(
                        (review) => _buildReviewCard(theme, review),
                      ),
                      const SizedBox(height: 20),
                    ],

                    const Divider(),
                    const SizedBox(height: 20),

                    // Final Decision Section
                    Text(
                      'Make Final Decision',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Decision Buttons
                    Row(
                      children: [
                        Expanded(
                          child: _buildDecisionButton(
                            theme,
                            'Accept',
                            'accept',
                            Colors.green,
                            Icons.check_circle_outline,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildDecisionButton(
                            theme,
                            'Reject',
                            'reject',
                            Colors.red,
                            Icons.cancel_outlined,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Comment Field
                    TextField(
                      controller: _commentController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Final Decision Comment (Optional)',
                        hintText: 'Add your final decision notes...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _makeDecision,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Submit Final Decision',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
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

  Widget _buildQuorumStatus(ThemeData theme, int totalVotes) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quorum Reached',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.green.shade700,
                  ),
                ),
                Text(
                  '$totalVotes votes cast (threshold: ${widget.family.quorumThreshold})',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoteSummary(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: _buildVoteCount(
            theme,
            'Approve',
            widget.family.approveCount,
            Colors.green,
            Icons.check_circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildVoteCount(
            theme,
            'Reject',
            widget.family.rejectCount,
            Colors.red,
            Icons.cancel,
          ),
        ),
      ],
    );
  }

  Widget _buildVoteCount(
    ThemeData theme,
    String label,
    int count,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(ThemeData theme, FamilyReview review) {
    final isApprove = review.decision == 'approve';
    final color = isApprove ? Colors.green : Colors.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isApprove ? Icons.check_circle : Icons.cancel,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        review.reviewerName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isApprove ? 'APPROVE' : 'REJECT',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                if (review.comment != null && review.comment!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    review.comment!,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDecisionButton(
    ThemeData theme,
    String label,
    String decision,
    Color color,
    IconData icon,
  ) {
    final isSelected = _selectedDecision == decision;

    return OutlinedButton.icon(
      onPressed: _isSubmitting
          ? null
          : () => setState(() => _selectedDecision = decision),
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        backgroundColor: isSelected ? color.withOpacity(0.1) : null,
        foregroundColor: isSelected ? color : theme.colorScheme.onSurface,
        side: BorderSide(
          color: isSelected ? color : theme.dividerColor,
          width: isSelected ? 2 : 1,
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
