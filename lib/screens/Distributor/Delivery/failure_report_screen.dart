import 'package:flutter/material.dart';
import 'package:ration_aid/models/delivery_assignment_model.dart';
import 'package:ration_aid/services/delivery_service.dart';
import 'package:ration_aid/theme/app_colors.dart';

class FailureReportScreen extends StatefulWidget {
  final DeliveryAssignment assignment;

  const FailureReportScreen({super.key, required this.assignment});

  @override
  State<FailureReportScreen> createState() => _FailureReportScreenState();
}

class _FailureReportScreenState extends State<FailureReportScreen> {
  DeliveryFailureReason? _selectedReason;
  final _notesController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a failure reason'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await DeliveryService.reportFailure(
        assignmentId: widget.assignment.id,
        familyId: widget.assignment.familyId,
        reason: _selectedReason!,
        notes: _notesController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failure reported. Admin has been notified.'),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Report Delivery Failure',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Warning banner
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Delivery Failure Report',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.red,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'This will notify the admin immediately. Provide as much detail as possible.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Family info
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on,
                    color: AppColors.volunteerBlue,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${widget.assignment.familyArea}, ${widget.assignment.familyCity}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Text(
              'Reason for Failure *',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),

            // Reason selection
            ...DeliveryFailureReason.values.map((reason) {
              final isSelected = _selectedReason == reason;
              return GestureDetector(
                onTap: () => setState(() => _selectedReason = reason),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.red.withValues(alpha: 0.08)
                        : (isDark ? const Color(0xFF1E1E2E) : Colors.white),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? Colors.red
                          : Colors.grey.withValues(alpha: 0.2),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _reasonIcon(reason),
                        color: isSelected ? Colors.red : Colors.grey[500],
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          reason.displayName,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isSelected
                                ? Colors.red
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Radio<DeliveryFailureReason>(
                        value: reason,
                        groupValue: _selectedReason,
                        onChanged: (v) => setState(() => _selectedReason = v),
                        activeColor: Colors.red,
                      ),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 20),

            Text(
              'Additional Notes',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Describe what happened in detail...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.red, width: 2),
                ),
              ),
            ),

            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.report_problem),
                label: Text(
                  _isSubmitting
                      ? 'Reporting...'
                      : 'Report Failure & Notify Admin',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _reasonIcon(DeliveryFailureReason r) {
    switch (r) {
      case DeliveryFailureReason.familyUnavailable:
        return Icons.person_off_outlined;
      case DeliveryFailureReason.addressIncorrect:
        return Icons.wrong_location_outlined;
      case DeliveryFailureReason.safetyConcern:
        return Icons.security_outlined;
      case DeliveryFailureReason.other:
        return Icons.more_horiz;
    }
  }
}
