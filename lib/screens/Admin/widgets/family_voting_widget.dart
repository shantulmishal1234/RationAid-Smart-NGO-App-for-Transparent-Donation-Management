import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/models/family_model.dart';
import 'package:ration_aid/models/family_review_model.dart';
import 'package:ration_aid/services/family_review_service.dart';

/// Widget for voting on pending families
/// Shows quorum progress, existing votes, and voting interface
class FamilyVotingWidget extends StatefulWidget {
  final Family family;
  final VoidCallback? onVoteSubmitted;

  const FamilyVotingWidget({
    super.key,
    required this.family,
    this.onVoteSubmitted,
  });

  @override
  State<FamilyVotingWidget> createState() => _FamilyVotingWidgetState();
}

class _FamilyVotingWidgetState extends State<FamilyVotingWidget> {
  String? _selectedDecision;
  final _commentController = TextEditingController();
  bool _isSubmitting = false;
  bool _hasVoted = false;
  List<FamilyReview> _reviews = [];
  bool _loadingReviews = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    // Check if user voted
    final hasVoted = await FamilyReviewService.hasUserVoted(
      widget.family.id,
      currentUser.uid,
    );

    // Get all reviews
    final reviews = await FamilyReviewService.getFamilyReviews(
      widget.family.id,
    );

    if (mounted) {
      setState(() {
        _hasVoted = hasVoted;
        _reviews = reviews;
        _loadingReviews = false;
      });

      // AUTO-HEAL: If the family mathematically met quorum but the DB is stuck
      if (!widget.family.quorumReached &&
          (widget.family.approveCount >= widget.family.quorumThreshold ||
              widget.family.rejectCount >= widget.family.quorumThreshold)) {
        try {
          // Immediately fix the DB boolean so it proceeds to Final Approver queue
          FirebaseFirestore.instance
              .collection('families')
              .doc(widget.family.id)
              .update({'quorumReached': true});
        } catch (e) {
          debugPrint('Error auto-healing family: $e');
        }
      }
    }
  }

  Future<void> _submitVote() async {
    if (_selectedDecision == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select Approve or Reject'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Require comment for rejection
    if (_selectedDecision == 'reject' &&
        _commentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide a comment explaining why you reject'),
          backgroundColor: Colors.red,
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

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vote submitted successfully'),
            backgroundColor: Colors.green,
          ),
        );

        // Reload data
        await _loadData();

        // Notify parent
        widget.onVoteSubmitted?.call();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You have already voted on this family'),
            backgroundColor: Colors.orange,
          ),
        );
      }
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
    final totalVotes = widget.family.approveCount + widget.family.rejectCount;
    final quorumProgress = totalVotes / widget.family.quorumThreshold;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Quorum Progress
        _buildQuorumProgress(theme, totalVotes, quorumProgress),

        const SizedBox(height: 20),

        // Vote Counts
        Row(
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
        ),

        const SizedBox(height: 20),

        // Existing Votes
        if (_loadingReviews)
          const Center(child: CircularProgressIndicator())
        else if (_reviews.isNotEmpty) ...[
          Text(
            'Admin Votes (${_reviews.length})',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 12),
          ..._reviews.map((review) => _buildReviewCard(theme, review)),
          const SizedBox(height: 20),
        ],

        // Voting Interface (if not voted)
        if (!_hasVoted) ...[
          const Divider(),
          const SizedBox(height: 16),
          Text(
            'Cast Your Vote',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),

          // Approve/Reject Buttons
          Row(
            children: [
              Expanded(
                child: _buildVoteButton(
                  theme,
                  'Approve',
                  'approve',
                  Colors.green,
                  Icons.check_circle_outline,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildVoteButton(
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
              labelText: _selectedDecision == 'reject'
                  ? 'Comment (Required for rejection)'
                  : 'Comment (Optional)',
              hintText: 'Add your comments here...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Submit Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submitVote,
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
                      'Submit Vote',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Text(
                  'You have already voted on this family',
                  style: TextStyle(
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildQuorumProgress(
    ThemeData theme,
    int totalVotes,
    double progress,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Quorum Progress',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            Text(
              '$totalVotes / ${widget.family.quorumThreshold} votes',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation(
              progress >= 1.0 ? Colors.green : theme.colorScheme.primary,
            ),
          ),
        ),
        if (widget.family.quorumReached) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 16),
                const SizedBox(width: 4),
                Text(
                  'Quorum Reached',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
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
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
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
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
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
                        color: color.withValues(alpha: 0.15),
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
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
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

  Widget _buildVoteButton(
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
        backgroundColor: isSelected ? color.withValues(alpha: 0.1) : null,
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
