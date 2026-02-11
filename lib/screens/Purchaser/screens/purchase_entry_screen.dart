import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ration_aid/models/procurement_model.dart';
import 'package:ration_aid/services/procurement_service.dart';
import 'package:ration_aid/services/cloudinary_service.dart';
import 'package:ration_aid/screens/Purchaser/widgets/purchaser_scaffold.dart';
import 'package:ration_aid/theme/app_colors.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';

class PurchaseEntryScreen extends StatefulWidget {
  final ProcurementRequest request;

  const PurchaseEntryScreen({super.key, required this.request});

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

    return PurchaserScaffold(
      title: 'Enter Purchase Details',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
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
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Budget Limit: Rs. ${widget.request.budgetLimit.toStringAsFixed(0)}',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
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
                    color: theme.colorScheme.onSurface.withOpacity(0.8),
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
                        color: theme.dividerColor.withOpacity(0.5),
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
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.5),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            initialValue: item.actualCost > 0
                                ? item.actualCost.toString()
                                : '',
                            style: const TextStyle(fontWeight: FontWeight.bold),
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
                                (val == null || val.isEmpty) ? 'Req' : null,
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
                      color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
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
                    const Divider(height: 32),
                    const Text(
                      'Upload Receipt',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: _pickReceipt,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        height: 180,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: theme.scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _receiptImage == null
                                ? theme.dividerColor
                                : AppColors.purchaserOrange,
                            style: _receiptImage == null
                                ? BorderStyle.solid
                                : BorderStyle.solid,
                            width: 1.5,
                          ),
                          image: _receiptImage != null
                              ? DecorationImage(
                                  image: FileImage(_receiptImage!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: _receiptImage == null
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.cloud_upload_outlined,
                                    size: 40,
                                    color: AppColors.purchaserOrange
                                        .withOpacity(0.7),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Tap to upload receipt image',
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.5),
                                    ),
                                  ),
                                ],
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Submit Button
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
                    shadowColor: AppColors.purchaserOrange.withOpacity(0.4),
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
}
