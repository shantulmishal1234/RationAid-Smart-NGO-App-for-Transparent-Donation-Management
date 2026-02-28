import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:ration_aid/models/family_model.dart';
import 'package:ration_aid/screens/Admin/widgets/frosted_panel.dart';
import 'package:ration_aid/services/final_approval_service.dart';
import 'package:ration_aid/screens/Admin/FinalApprover/final_approval_dialog.dart';

/// Screen for Final Approver to review families that reached quorum
class FinalApproverScreen extends StatelessWidget {
  const FinalApproverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Check if current user is final approver
    return FutureBuilder<bool>(
      future: FinalApprovalService.isCurrentUserFinalApprover(),
      builder: (context, snapshot) {
        // Loading state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // Not authorized
        if (!snapshot.hasData || snapshot.data != true) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 64,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Access Denied',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You are not authorized to access Final Approval',
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        // User is authorized - show screen
        return _buildScreen(context, theme);
      },
    );
  }

  Widget _buildScreen(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Text(
              'Final Approval',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),

        // Description
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Review families that have reached quorum and make final approval decisions',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),

        // Stats Overview (New - to match Household style)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FrostedPanel(
            child: StreamBuilder<QuerySnapshot>(
              stream: FinalApprovalService.getFamiliesAwaitingApprovalStream(),
              builder: (context, snapshot) {
                final families = snapshot.data?.docs ?? [];

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem(
                      theme,
                      'Pending Review',
                      families.length.toString(),
                      Colors.orange,
                    ),
                    _buildStatItem(
                      theme,
                      'Quorum Reached',
                      families.length
                          .toString(), // All here have reached quorum
                      Colors.green,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),

        // List of families
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FinalApprovalService.getFamiliesAwaitingApprovalStream(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Error loading families',
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 64,
                        color: theme.colorScheme.primary.withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No families awaiting final approval',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                );
              }

              final families = snapshot.data!.docs
                  .map((doc) => Family.fromFirestore(doc))
                  .toList();

              // Sort by newest first
              families.sort((a, b) {
                if (a.createdAt == null && b.createdAt == null) return 0;
                if (a.createdAt == null) return 1;
                if (b.createdAt == null) return -1;
                return b.createdAt!.compareTo(a.createdAt!);
              });

              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: families.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final family = families[index];
                  return _buildFamilyCard(context, theme, family);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(
    ThemeData theme,
    String label,
    String value,
    Color color,
  ) {
    return Column(
      children: [
        Text(
          value,
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
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildFamilyCard(
    BuildContext context,
    ThemeData theme,
    Family family,
  ) {
    final totalVotes = family.approveCount + family.rejectCount;
    final approvePercentage = totalVotes > 0
        ? (family.approveCount / totalVotes * 100).toInt()
        : 0;

    return FrostedPanel(
      child: InkWell(
        onTap: () {
          showDialog(
            context: context,
            builder: (context) => FinalApprovalDialog(family: family),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Family Name and Quorum Badge
              Row(
                children: [
                  Expanded(
                    child: Text(
                      family
                          .id, // Using ID as name is typical if name not available
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, size: 14, color: Colors.green),
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
              ),

              const SizedBox(height: 12),

              // Vote Summary
              Row(
                children: [
                  Icon(
                    Icons.how_to_vote,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$totalVotes votes cast',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${family.approveCount} Approve',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${family.rejectCount} Reject',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Vote Percentage Bar
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Approval Rate',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      Text(
                        '$approvePercentage%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: approvePercentage / 100,
                      minHeight: 6,
                      backgroundColor: Colors.red.withValues(alpha: 0.2),
                      valueColor: AlwaysStoppedAnimation(Colors.green),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Action hint
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Tap to review and decide',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.primary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 12,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
