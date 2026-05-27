import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../../home/providers/dashboard_provider.dart';
import '../providers/transaction_provider.dart';
import '../models/transaction_model.dart';
import 'widgets/amount_field.dart';
import 'widgets/category_picker.dart';

class AddTransactionScreen extends ConsumerStatefulWidget {
  final TransactionModel? editTransaction;
  const AddTransactionScreen({super.key, this.editTransaction});
  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _isExpense = true;
  int? _selectedCategoryId;
  late DateTime _selectedDate;
  bool _isSaving = false;

  List<CategoryChip> _categories = [];
  List<CategoryChip> _expenseCategories = [];
  List<CategoryChip> _incomeCategories = [];

  bool get _isEditing => widget.editTransaction != null;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _loadAllCategories();
    if (_isEditing) _prefillFields();
  }

  void _prefillFields() {
    final txn = widget.editTransaction!;
    _amountCtrl.text = txn.amount.toString();
    _descCtrl.text = txn.description;
    _noteCtrl.text = txn.note;
    _isExpense = txn.type == 'expense';
    _selectedCategoryId = txn.category.id;
    _selectedDate = DateTime.tryParse(txn.date) ?? DateTime.now();
  }

  Future<void> _loadAllCategories() async {
    try {
      final api = ref.read(apiClientProvider);
      final expenseRes = await api.get('/categories', queryParams: {'type': 'expense'});
      final incomeRes = await api.get('/categories', queryParams: {'type': 'income'});
      setState(() {
        _expenseCategories = (List<Map<String, dynamic>>.from(expenseRes.data)).map((e) => CategoryChip(
          id: e['id'] as int, name: e['name'] as String, icon: e['icon'] as String? ?? '📦',
        )).toList();
        _incomeCategories = (List<Map<String, dynamic>>.from(incomeRes.data)).map((e) => CategoryChip(
          id: e['id'] as int, name: e['name'] as String, icon: e['icon'] as String? ?? '📦',
        )).toList();
        _categories = _isExpense ? _expenseCategories : _incomeCategories;
      });
    } catch (_) {}
  }

  void _toggleType(bool isExpense) {
    if (isExpense == _isExpense) return;
    setState(() {
      _isExpense = isExpense;
      _categories = isExpense ? _expenseCategories : _incomeCategories;
      _selectedCategoryId = null;
    });
  }

  @override
  void dispose() { _amountCtrl.dispose(); _descCtrl.dispose(); _noteCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    final amountText = _amountCtrl.text.replaceAll('Rp', '').replaceAll('.', '').replaceAll(',', '').trim();
    final amount = int.tryParse(amountText);
    if (amount == null || amount <= 0) { _showError('Amount must be greater than 0'); return; }
    if (_selectedCategoryId == null) { _showError('Please select a category'); return; }

    setState(() => _isSaving = true);
    final notifier = ref.read(transactionListProvider.notifier);
    final data = {
      'type': _isExpense ? 'expense' : 'income',
      'category_id': _selectedCategoryId,
      'amount': amount,
      'description': _descCtrl.text.trim(),
      'note': _noteCtrl.text.trim(),
      'date': '${_selectedDate.toIso8601String().substring(0, 10)}',
    };

    final success = _isEditing
        ? await notifier.update(widget.editTransaction!.id, data)
        : await notifier.create(data);

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (success) {
      ref.read(homeRefreshProvider.notifier).state++;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(_isEditing ? 'Transaction updated' : 'Transaction recorded',
                  style: const TextStyle(color: Colors.white)),
            ],
          ),
          backgroundColor: AppColors.success,
        ),
      );
      context.pop();
    } else {
      _showError('Failed to save. Try again.');
    }
  }

  void _showError(String msg) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(msg, style: const TextStyle(color: Colors.white)),
            ],
          ),
          backgroundColor: AppColors.highlight,
        ),
      );
    }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate = '${_selectedDate.day} ${_monthName(_selectedDate.month)} ${_selectedDate.year}';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(_isEditing ? 'Edit Transaction' : 'Add Transaction')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type toggle
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface, borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(child: _TypeButton(
                    label: 'Expense', isSelected: _isExpense, color: AppColors.highlight,
                    onTap: () => _toggleType(true),
                  )),
                  Expanded(child: _TypeButton(
                    label: 'Income', isSelected: !_isExpense, color: AppColors.success,
                    onTap: () => _toggleType(false),
                  )),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Amount
            AmountField(controller: _amountCtrl),
            const SizedBox(height: 20),
            // Category
            const Text('Category', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            CategoryPicker(
              categories: _categories,
              selectedId: _selectedCategoryId,
              onSelected: (id) => setState(() => _selectedCategoryId = id),
            ),
            const SizedBox(height: 20),
            // Description
            const Text('Description', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(hintText: 'What was this for?'),
            ),
            const SizedBox(height: 20),
            // Date
            const Text('Date', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickDate,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Text(formattedDate, style: const TextStyle(fontSize: 14)),
                    const Spacer(),
                    const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Note
            const Text('Note (optional)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _noteCtrl,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Add a note...'),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_isEditing ? 'Update' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _monthName(int m) => ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m - 1];
}

class _TypeButton extends StatelessWidget {
  final String label; final bool isSelected; final Color color; final VoidCallback onTap;
  const _TypeButton({required this.label, required this.isSelected, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label, textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w600, color: isSelected ? color : AppColors.textSecondary)),
      ),
    );
  }
}
