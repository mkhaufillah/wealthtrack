import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/utils/currency_formatter.dart';
import '../providers/transaction_provider.dart';
import 'widgets/amount_field.dart';
import 'widgets/category_picker.dart';

class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key});
  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _isExpense = true;
  int? _selectedCategoryId;
  DateTime _selectedDate = DateTime.now();
  bool _isSaving = false;

  List<CategoryChip> _categories = [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get('/categories');
      final data = List<Map<String, dynamic>>.from(res.data);
      setState(() {
        _categories = data.map((e) => CategoryChip(
          id: e['id'] as int, name: e['name'] as String, icon: e['icon'] as String? ?? '📦',
        )).toList();
      });
    } catch (_) {}
  }

  @override
  void dispose() { _amountCtrl.dispose(); _descCtrl.dispose(); _noteCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    final amountText = _amountCtrl.text.replaceAll('.', '').replaceAll(',', '');
    final amount = int.tryParse(amountText);
    if (amount == null || amount <= 0) { _showError('Amount must be greater than 0'); return; }
    if (_selectedCategoryId == null) { _showError('Please select a category'); return; }

    setState(() => _isSaving = true);
    final success = await ref.read(transactionListProvider.notifier).create({
      'type': _isExpense ? 'expense' : 'income',
      'category_id': _selectedCategoryId,
      'amount': amount,
      'description': _descCtrl.text.trim(),
      'note': _noteCtrl.text.trim(),
      'date': '${_selectedDate.toIso8601String().substring(0, 10)}',
    });
    setState(() => _isSaving = false);

    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Transaction recorded'), backgroundColor: AppColors.success),
        );
        context.pop();
      }
    } else {
      _showError('Failed to save. Try again.');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('❌ $msg'), backgroundColor: AppColors.highlight),
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
    final dateStr = '${_selectedDate.toIso8601String().substring(0, 10)}';
    final formattedDate = '${_selectedDate.day} ${_monthName(_selectedDate.month)} ${_selectedDate.year}';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Add Transaction')),
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
                    onTap: () => setState(() => _isExpense = true),
                  )),
                  Expanded(child: _TypeButton(
                    label: 'Income', isSelected: !_isExpense, color: AppColors.success,
                    onTap: () => setState(() => _isExpense = false),
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
                    : const Text('Save'),
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