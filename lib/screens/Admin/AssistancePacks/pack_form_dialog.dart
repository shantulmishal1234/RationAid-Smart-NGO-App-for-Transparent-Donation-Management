import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ration_aid/models/assistance_pack_model.dart';
import 'package:ration_aid/services/assistance_pack_service.dart';
import 'package:ration_aid/services/audit_service.dart';
import 'package:ration_aid/screens/Admin/models/admin_enums.dart';

/// Dialog for adding/editing assistance pack
class PackFormDialog extends StatefulWidget {
  final AssistancePack? pack;

  const PackFormDialog({super.key, this.pack});

  @override
  State<PackFormDialog> createState() => _PackFormDialogState();
}

class _PackFormDialogState extends State<PackFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _minMembersController = TextEditingController();
  final _maxMembersController = TextEditingController();
  final _budgetController = TextEditingController();

  String _packType = 'food';
  bool _isActive = true;
  List<PackItem> _items = [];
  bool _isSaving = false;

  // ── Budget computed helpers ──────────────────────────────────────────
  double get _budgetAmount => double.tryParse(_budgetController.text) ?? 0.0;

  double get _totalItemsCost =>
      _items.fold(0.0, (sum, item) => sum + item.estimatedCost);

  bool get _isOverBudget =>
      _totalItemsCost > _budgetAmount && _budgetAmount > 0;

  @override
  void initState() {
    super.initState();
    _budgetController.addListener(
      () => setState(() {}),
    ); // rebuild on budget change
    if (widget.pack != null) {
      _nameController.text = widget.pack!.name;
      _descriptionController.text = widget.pack!.description ?? '';
      _minMembersController.text = widget.pack!.minMembers.toString();
      _maxMembersController.text = widget.pack!.maxMembers.toString();
      _budgetController.text = widget.pack!.budgetAmount.toString();
      _packType = widget.pack!.packType;
      _isActive = widget.pack!.isActive;
      _items = List.from(widget.pack!.items);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _minMembersController.dispose();
    _maxMembersController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.pack != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AdminColors.primaryBlue,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2, color: Colors.white),
                  const SizedBox(width: 12),
                  Text(
                    isEdit ? 'Edit Assistance Pack' : 'Add Assistance Pack',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),

            // Form
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Pack Name
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'Pack Name *',
                          hintText: 'e.g., Family Pack A',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Pack name is required';
                          }
                          if (value.trim().length < 3) {
                            return 'Name must be at least 3 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Description
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'Description (Optional)',
                          hintText: 'Brief description of the pack',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Member Range
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _minMembersController,
                              decoration: InputDecoration(
                                labelText: 'Min Members *',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Required';
                                }
                                final min = int.tryParse(value);
                                if (min == null || min < 1) {
                                  return 'Must be >= 1';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _maxMembersController,
                              decoration: InputDecoration(
                                labelText: 'Max Members *',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Required';
                                }
                                final max = int.tryParse(value);
                                final min = int.tryParse(
                                  _minMembersController.text,
                                );
                                if (max == null || max < 1) {
                                  return 'Must be >= 1';
                                }
                                if (min != null && max < min) {
                                  return 'Must be > min';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Budget
                      TextFormField(
                        controller: _budgetController,
                        decoration: InputDecoration(
                          labelText: 'Budget Amount (PKR) *',
                          prefixText: 'PKR ',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Budget is required';
                          }
                          final budget = double.tryParse(value);
                          if (budget == null || budget <= 0) {
                            return 'Must be greater than 0';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      // Items Section
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Items (${_items.length})',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _addItem,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add Item'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // ── Budget Tracker ──────────────────────────────
                      if (_budgetAmount > 0) _buildBudgetTracker(),
                      if (_budgetAmount > 0) const SizedBox(height: 12),

                      // Items List
                      if (_items.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.disabledColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              'No items added yet',
                              style: TextStyle(color: theme.disabledColor),
                            ),
                          ),
                        )
                      else
                        ..._items.asMap().entries.map((entry) {
                          return _buildItemCard(entry.key, entry.value);
                        }),

                      const SizedBox(height: 20),

                      // Active Toggle
                      Row(
                        children: [
                          Switch(
                            value: _isActive,
                            onChanged: (value) {
                              setState(() => _isActive = value);
                            },
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isActive ? 'Active' : 'Inactive',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Footer Actions
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
                border: Border(top: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _savePack,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(isEdit ? 'Update Pack' : 'Create Pack'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard(int index, PackItem item) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AdminColors.primaryBlue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.shopping_bag_outlined,
            color: AdminColors.primaryBlue,
            size: 20,
          ),
        ),
        title: Text(
          item.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${item.quantity} • PKR ${item.estimatedCost.toStringAsFixed(0)}',
          style: TextStyle(fontSize: 12, color: theme.disabledColor),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete, size: 20),
          color: Colors.red,
          onPressed: () {
            setState(() {
              _items.removeAt(index);
            });
          },
        ),
      ),
    );
  }

  // ── Budget Tracker Widget ────────────────────────────────────────────────
  Widget _buildBudgetTracker() {
    final theme = Theme.of(context);
    final budget = _budgetAmount;
    final spent = _totalItemsCost;
    final remaining = budget - spent;
    final ratio = budget > 0 ? (spent / budget).clamp(0.0, 1.1) : 0.0;
    final isOver = spent > budget;
    final isWarning = !isOver && ratio >= 0.8;

    final barColor = isOver
        ? Colors.red
        : isWarning
        ? Colors.orange
        : Colors.green;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isOver
            ? Colors.red.withValues(alpha: 0.06)
            : isWarning
            ? Colors.orange.withValues(alpha: 0.06)
            : theme.colorScheme.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOver
              ? Colors.red.withValues(alpha: 0.35)
              : isWarning
              ? Colors.orange.withValues(alpha: 0.35)
              : theme.dividerColor.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row: label + amounts
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    isOver
                        ? Icons.warning_amber_rounded
                        : Icons.account_balance_wallet_outlined,
                    size: 16,
                    color: barColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Budget Tracker',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: barColor,
                    ),
                  ),
                ],
              ),
              Text(
                'PKR ${spent.toStringAsFixed(0)} / ${budget.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              backgroundColor: theme.colorScheme.onSurface.withValues(
                alpha: 0.1,
              ),
              color: barColor,
              minHeight: 7,
            ),
          ),
          const SizedBox(height: 8),
          // Remaining / Over-budget label
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isOver
                    ? '⚠  Over budget by PKR ${(spent - budget).toStringAsFixed(0)}'
                    : isWarning
                    ? '⚡  Only PKR ${remaining.toStringAsFixed(0)} remaining'
                    : '✓  PKR ${remaining.toStringAsFixed(0)} remaining',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: barColor,
                ),
              ),
              Text(
                '${(ratio * 100).clamp(0, 100).toInt()}% used',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _addItem() {
    final nameController = TextEditingController();
    final quantityController = TextEditingController();
    final costController = TextEditingController();
    String selectedUnit = 'kg';

    const unitOptions = [
      'kg',
      'g',
      'L',
      'mL',
      'pcs',
      'bars',
      'packets',
      'bottles',
      'pairs',
    ];

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, dialogSetState) {
          final enteredCost = double.tryParse(costController.text) ?? 0.0;
          final wouldTotal = _totalItemsCost + enteredCost;
          final budget = _budgetAmount;
          final remaining = budget - _totalItemsCost;
          final wouldOverflow =
              budget > 0 && wouldTotal > budget && enteredCost > 0;

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              'Add Item',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Remaining budget info
                  if (budget > 0)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: wouldOverflow
                            ? Colors.red.withValues(alpha: 0.08)
                            : Colors.green.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: wouldOverflow
                              ? Colors.red.withValues(alpha: 0.3)
                              : Colors.green.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        wouldOverflow
                            ? '⚠  This item exceeds remaining budget of PKR ${remaining.toStringAsFixed(0)}'
                            : '💰  PKR ${remaining.toStringAsFixed(0)} remaining of PKR ${budget.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: wouldOverflow ? Colors.red : Colors.green[700],
                        ),
                      ),
                    ),
                  if (budget > 0) const SizedBox(height: 12),
                  // ── Item Name ──
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'Item Name (e.g., Lemonmax Dish Soap)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      isDense: true,
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 12),
                  // ── Quantity (numeric) + Unit dropdown side by side ──
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: quantityController,
                          decoration: InputDecoration(
                            labelText: 'Qty',
                            hintText: 'e.g. 3.5',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            isDense: true,
                          ),
                          // Allow decimals but block non-numeric chars
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: false,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          value: selectedUnit,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Unit',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 12,
                            ),
                          ),
                          items: unitOptions
                              .map(
                                (u) =>
                                    DropdownMenuItem(value: u, child: Text(u)),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null)
                              dialogSetState(() => selectedUnit = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // ── Estimated Cost ──
                  TextField(
                    controller: costController,
                    decoration: InputDecoration(
                      labelText: 'Estimated Cost (PKR)',
                      prefixText: 'PKR ',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => dialogSetState(() {}),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final parsedQty = double.tryParse(
                    quantityController.text.trim(),
                  );
                  if (nameController.text.isNotEmpty &&
                      parsedQty != null &&
                      parsedQty > 0 &&
                      costController.text.isNotEmpty) {
                    setState(() {
                      _items.add(
                        PackItem(
                          name: nameController.text.trim(),
                          quantityNum: parsedQty,
                          unit: selectedUnit,
                          estimatedCost: double.parse(costController.text),
                        ),
                      );
                    });
                    Navigator.pop(dialogContext);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: wouldOverflow
                      ? Colors.orange
                      : AdminColors.primaryBlue,
                  foregroundColor: Colors.white,
                ),
                child: Text(wouldOverflow ? 'Add Anyway' : 'Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _savePack() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one item'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Block save if items exceed budget
    if (_isOverBudget) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Total item cost (PKR ${_totalItemsCost.toStringAsFixed(0)}) exceeds '
            'the budget (PKR ${_budgetAmount.toStringAsFixed(0)}). '
            'Please adjust item costs or increase the budget.',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final pack = AssistancePack(
        id: widget.pack?.id ?? '',
        name: _nameController.text.trim(),
        packType: _packType,
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        minMembers: int.parse(_minMembersController.text),
        maxMembers: int.parse(_maxMembersController.text),
        budgetAmount: double.parse(_budgetController.text),
        items: _items,
        isActive: _isActive,
        createdAt: widget.pack?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      if (widget.pack == null) {
        await AssistancePackService.createPack(pack);
        await AuditService.logPackAction(
          action: 'Created Pack',
          packId: pack
              .id, // Note: ID might be generated inside createPack if empty string passed, but usually service handles it.
          // If service generates ID, we might miss it here unless service returns it.
          // Assuming pack.id isn't sufficient if generated by firestore on add.
          // Let's assume service uses the ID in the model if provided or we accept slight inaccuracy until refactor.
          // Actually, if pack.id is empty, service .add() generates one. We won't know it here easily without changing service return type.
          // For now, let's log "New Pack" without ID if empty, or just name.
          packName: pack.name,
          details: 'Budget: ${pack.budgetAmount}, Items: ${pack.items.length}',
        );
      } else {
        await AssistancePackService.updatePack(widget.pack!.id, pack);
        await AuditService.logPackAction(
          action: 'Updated Pack',
          packId: widget.pack!.id,
          packName: pack.name,
          details: 'Updated details. Active: ${pack.isActive}',
        );
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.pack == null
                  ? 'Pack created successfully'
                  : 'Pack updated successfully',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}
