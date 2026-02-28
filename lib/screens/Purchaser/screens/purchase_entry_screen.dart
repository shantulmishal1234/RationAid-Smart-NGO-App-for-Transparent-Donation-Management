import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ration_aid/models/procurement_model.dart';
import 'package:ration_aid/services/procurement_service.dart';
import 'package:ration_aid/services/cloudinary_service.dart';
import 'package:ration_aid/screens/Purchaser/widgets/purchaser_scaffold.dart';
import 'package:ration_aid/screens/Purchaser/widgets/receipt_viewer_screen.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';

class PurchaseEntryScreen extends StatefulWidget {
  final ProcurementRequest request;
  final bool isReadOnly;

  const PurchaseEntryScreen({
    super.key,
    required this.request,
    this.isReadOnly = false,
  });

  @override
  State<PurchaseEntryScreen> createState() => _PurchaseEntryScreenState();
}

class _PurchaseEntryScreenState extends State<PurchaseEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  File? _receiptImage;

  // Track costs for each item
  late List<ProcurementItem> _items;
  double _totalSpent = 0.0;

  @override
  void initState() {
    super.initState();
    _items = widget.request.items.map((e) => e.copyWith()).toList();
    // Calculate total if viewing existing purchase
    if (widget.isReadOnly) {
      _totalSpent = widget.request.totalSpent;
    }
  }

  Future<void> _pickReceipt() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _receiptImage = File(pickedFile.path);
      });
    }
  }

  void _calculateTotal() {
    double total = 0;
    for (var item in _items) {
      total += item.actualCost;
    }
    setState(() {
      _totalSpent = total;
    });
  }

  Future<void> _submitPurchase() async {
    if (!_formKey.currentState!.validate()) return;
    if (_receiptImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload a receipt image'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_totalSpent > widget.request.budgetLimit) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Total spent (Rs. $_totalSpent) exceeds budget limit (Rs. ${widget.request.budgetLimit})',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final receiptUrl = await CloudinaryService.uploadImage(_receiptImage!);

      if (receiptUrl == null) throw Exception('Receipt upload failed');

      final user = FirebaseAuth.instance.currentUser;

      await ProcurementService.submitPurchase(
        requestId: widget.request.id,
        purchaserId: user?.uid ?? 'unknown',
        purchaserName: user?.displayName ?? 'Purchaser',
        receiptUrl: receiptUrl,
        totalSpent: _totalSpent,
        updatedItems: _items,
        packName: widget.request.packName,
      );

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Purchase submitted for review!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isEditable = !widget.isReadOnly;

    return PurchaserScaffold(
      title: widget.isReadOnly ? 'Purchase Details' : 'Enter Purchase Details',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status Banner for read-only mode
              if (widget.isReadOnly)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _getStatusColor(
                      widget.request.status,
                    ).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _getStatusColor(
                        widget.request.status,
                      ).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _getStatusIcon(widget.request.status),
                        color: _getStatusColor(widget.request.status),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getStatusTitle(widget.request.status),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _getStatusColor(widget.request.status),
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _getStatusMessage(widget.request.status),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              // Summary Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.3 : 0.05,
                      ),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.request.packName,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.account_balance_wallet_outlined,
                          size: 18,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Budget Limit: Rs. ${widget.request.budgetLimit.toStringAsFixed(0)}',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.7,
                            ),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Items Section Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Itemized Costs',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Items List
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.dividerColor.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Qty: ${item.quantity}  •  Est: Rs. ${item.estimatedCost}',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.5,
                                  ),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: isEditable
                              ? TextFormField(
                                  initialValue: item.actualCost > 0
                                      ? item.actualCost.toString()
                                      : '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: 'Cost',
                                    prefixText: 'Rs. ',
                                    isDense: true,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                        color: theme.dividerColor,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                        color: AppColors.purchaserOrange,
                                        width: 2,
                                      ),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                  ),
                                  keyboardType: TextInputType.number,
                                  onChanged: (val) {
                                    final cost = double.tryParse(val) ?? 0.0;
                                    _items[index] = item.copyWith(
                                      actualCost: cost,
                                      isPurchased: cost > 0,
                                    );
                                    _calculateTotal();
                                  },
                                  validator: (val) =>
                                      (val == null || val.isEmpty)
                                      ? 'Req'
                                      : null,
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Actual Cost',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.6),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Rs. ${item.actualCost.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 24),

              // Total & Receipt Section
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.3 : 0.05,
                      ),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Spent',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Rs. ${_totalSpent.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: _totalSpent > widget.request.budgetLimit
                                ? Colors.red
                                : Colors.green,
                          ),
                        ),
                      ],
                    ),

                    // Budget Utilization Bar
                    const SizedBox(height: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Budget Utilization',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                            Text(
                              '${widget.request.budgetLimit > 0 ? (_totalSpent / widget.request.budgetLimit * 100).toStringAsFixed(0) : 0}%',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _totalSpent > widget.request.budgetLimit
                                    ? Colors.red
                                    : _totalSpent >
                                          widget.request.budgetLimit * 0.9
                                    ? Colors.orange
                                    : Colors.green,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (_totalSpent / widget.request.budgetLimit)
                                .clamp(0.0, 1.0),
                            minHeight: 8,
                            backgroundColor: theme.dividerColor.withValues(
                              alpha: 0.2,
                            ),
                            valueColor: AlwaysStoppedAnimation(
                              _totalSpent > widget.request.budgetLimit
                                  ? Colors.red
                                  : _totalSpent >
                                        widget.request.budgetLimit * 0.9
                                  ? Colors.orange
                                  : Colors.green,
                            ),
                          ),
                        ),
                        if (_totalSpent > widget.request.budgetLimit)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  size: 14,
                                  color: Colors.red,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Over budget by Rs ${(_totalSpent - widget.request.budgetLimit).toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.red,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const Divider(height: 32),
                    const Text(
                      'Upload Receipt',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (isEditable)
                      _receiptImage == null
                          ? InkWell(
                              onTap: _pickReceipt,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                height: 180,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: theme.scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: theme.dividerColor,
                                    style: BorderStyle.solid,
                                    width: 1.5,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.cloud_upload_outlined,
                                      size: 40,
                                      color: AppColors.purchaserOrange
                                          .withValues(alpha: 0.7),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Tap to upload receipt image',
                                      style: TextStyle(
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : Column(
                              children: [
                                Stack(
                                  children: [
                                    InkWell(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ReceiptViewerScreen(
                                              localImage: _receiptImage,
                                              title: 'Receipt Preview',
                                            ),
                                          ),
                                        );
                                      },
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        height: 180,
                                        width: double.infinity,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: AppColors.purchaserOrange,
                                            width: 2,
                                          ),
                                          image: DecorationImage(
                                            image: FileImage(_receiptImage!),
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Gradient overlay for better button visibility
                                    Positioned.fill(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          gradient: LinearGradient(
                                            begin: Alignment.topRight,
                                            end: Alignment.bottomLeft,
                                            colors: [
                                              Colors.black.withValues(
                                                alpha: 0.4,
                                              ),
                                              Colors.transparent,
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Action buttons
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Row(
                                        children: [
                                          // View full screen
                                          Container(
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(
                                                alpha: 0.6,
                                              ),
                                              shape: BoxShape.circle,
                                            ),
                                            child: IconButton(
                                              icon: const Icon(
                                                Icons.fullscreen,
                                                color: Colors.white,
                                              ),
                                              onPressed: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        ReceiptViewerScreen(
                                                          localImage:
                                                              _receiptImage,
                                                          title:
                                                              'Receipt Preview',
                                                        ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          // Remove
                                          Container(
                                            decoration: BoxDecoration(
                                              color: Colors.red.withValues(
                                                alpha: 0.8,
                                              ),
                                              shape: BoxShape.circle,
                                            ),
                                            child: IconButton(
                                              icon: const Icon(
                                                Icons.close,
                                                color: Colors.white,
                                              ),
                                              onPressed: () => setState(
                                                () => _receiptImage = null,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Tap to view hint
                                    Positioned(
                                      bottom: 12,
                                      left: 0,
                                      right: 0,
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(
                                              alpha: 0.7,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.touch_app,
                                                size: 14,
                                                color: Colors.white,
                                              ),
                                              SizedBox(width: 6),
                                              Text(
                                                'Tap to view full screen',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                // Change receipt button
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: _pickReceipt,
                                    icon: const Icon(
                                      Icons.image_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('Change Receipt'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor:
                                          AppColors.purchaserOrange,
                                      side: const BorderSide(
                                        color: AppColors.purchaserOrange,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                    else if (widget.request.receiptUrl != null)
                      InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ReceiptViewerScreen(
                                networkUrl: widget.request.receiptUrl,
                                title: 'Submitted Receipt',
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          children: [
                            Container(
                              height: 180,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: theme.scaffoldBackgroundColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.green,
                                  width: 2,
                                ),
                                image: DecorationImage(
                                  image: NetworkImage(
                                    widget.request.receiptUrl!,
                                  ),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            // Verified badge
                            Positioned(
                              top: 8,
                              left: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.check_circle,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'SUBMITTED',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Tap to view hint
                            Positioned(
                              bottom: 12,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.touch_app,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        'Tap to view full screen',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        height: 180,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: theme.scaffoldBackgroundColor.withValues(
                            alpha: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.receipt_outlined,
                              size: 40,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.3,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No receipt uploaded',
                              style: TextStyle(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Submit Button (only in editable mode)
              if (isEditable)
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submitPurchase,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.purchaserOrange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                      shadowColor: AppColors.purchaserOrange.withValues(
                        alpha: 0.4,
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'Submit for Review',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(ProcurementStatus status) {
    switch (status) {
      case ProcurementStatus.purchased:
        return Colors.blue;
      case ProcurementStatus.verified:
      case ProcurementStatus.stocked:
      case ProcurementStatus.in_transit:
      case ProcurementStatus.delivered:
        return Colors.green;
      case ProcurementStatus.rejected:
        return Colors.red;
      default:
        return AppColors.purchaserOrange;
    }
  }

  IconData _getStatusIcon(ProcurementStatus status) {
    switch (status) {
      case ProcurementStatus.purchased:
        return Icons.hourglass_empty;
      case ProcurementStatus.verified:
      case ProcurementStatus.stocked:
      case ProcurementStatus.in_transit:
      case ProcurementStatus.delivered:
        return Icons.check_circle;
      case ProcurementStatus.rejected:
        return Icons.cancel;
      default:
        return Icons.shopping_cart;
    }
  }

  String _getStatusTitle(ProcurementStatus status) {
    switch (status) {
      case ProcurementStatus.purchased:
        return '⏳ Under Admin Review';
      case ProcurementStatus.verified:
      case ProcurementStatus.stocked:
      case ProcurementStatus.in_transit:
      case ProcurementStatus.delivered:
        return '✓ Verified & Approved';
      case ProcurementStatus.rejected:
        return '✗ Rejected';
      default:
        return 'Purchase Required';
    }
  }

  String _getStatusMessage(ProcurementStatus status) {
    switch (status) {
      case ProcurementStatus.purchased:
        return 'Your purchase is being reviewed by admin. You cannot edit this submission.';
      case ProcurementStatus.verified:
      case ProcurementStatus.stocked:
      case ProcurementStatus.in_transit:
      case ProcurementStatus.delivered:
        return 'This purchase has been approved by admin and added to inventory.';
      case ProcurementStatus.rejected:
        return widget.request.adminRemarks ?? 'This purchase was rejected.';
      default:
        return '';
    }
  }
}
