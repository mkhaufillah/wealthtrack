import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/credit_card_provider.dart';
import '../../../../features/home/providers/dashboard_provider.dart';
import '../../../../core/theme/app_theme.dart';

/// Extracts raw integer amount from a formatted IDR string like "Rp 50.000".
int _parseAmount(String text) {
  final digits = text.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.isEmpty) return 0;
  return int.tryParse(digits) ?? 0;
}

/// Formats raw digits into "Rp XXX.XXX" display format.
String _formatIdrDisplay(String digits) {
  if (digits.isEmpty) return '';
  final buf = StringBuffer();
  int count = 0;
  for (int i = digits.length - 1; i >= 0; i--) {
    if (count > 0 && count % 3 == 0) buf.write('.');
    buf.write(digits[i]);
    count++;
  }
  return 'Rp ${buf.toString().split('').reversed.join('')}';
}

class AddInstallmentScreen extends ConsumerStatefulWidget {
  final int cardId;
  const AddInstallmentScreen({super.key, required this.cardId});

  @override
  ConsumerState<AddInstallmentScreen> createState() => _AddInstallmentScreenState();
}

class _AddInstallmentScreenState extends ConsumerState<AddInstallmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionCtrl = TextEditingController();
  final _totalAmountCtrl = TextEditingController();
  final _monthlyAmountCtrl = TextEditingController();
  final _startMonthCtrl = TextEditingController();
  final _totalMonthsCtrl = TextEditingController(text: '12');

  bool _isSaving = false;

  // Focus nodes for amount fields
  final _totalAmountFocus = FocusNode();
  final _monthlyAmountFocus = FocusNode();
  bool _totalAmountFocused = false;
  bool _monthlyAmountFocused = false;

  @override
  void initState() {
    super.initState();
    _totalAmountFocus.addListener(_onTotalAmountFocusChange);
    _monthlyAmountFocus.addListener(_onMonthlyAmountFocusChange);
    _totalAmountCtrl.addListener(_onAmountTextChange);
    _monthlyAmountCtrl.addListener(_onAmountTextChange);
    // Default start month to current month
    final now = DateTime.now();
    _startMonthCtrl.text = '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    _totalAmountCtrl.dispose();
    _monthlyAmountCtrl.dispose();
    _startMonthCtrl.dispose();
    _totalMonthsCtrl.dispose();
    _totalAmountFocus.dispose();
    _monthlyAmountFocus.dispose();
    super.dispose();
  }

  void _onTotalAmountFocusChange() {
    setState(() => _totalAmountFocused = _totalAmountFocus.hasFocus);
    _formatAmountOnFocusChange(_totalAmountCtrl, _totalAmountFocused);
  }

  void _onMonthlyAmountFocusChange() {
    setState(() => _monthlyAmountFocused = _monthlyAmountFocus.hasFocus);
    _formatAmountOnFocusChange(_monthlyAmountCtrl, _monthlyAmountFocused);
  }

  void _formatAmountOnFocusChange(TextEditingController ctrl, bool isFocused) {
    if (isFocused) {
      final raw = ctrl.text.replaceAll(RegExp(r'[^\d]'), '');
      if (raw != ctrl.text) {
        ctrl.value = TextEditingValue(
          text: raw,
          selection: TextSelection.collapsed(offset: raw.length),
        );
      }
    } else {
      final digits = ctrl.text.replaceAll(RegExp(r'[^\d]'), '');
      if (digits.isNotEmpty) {
        final formatted = _formatIdrDisplay(digits);
        ctrl.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      }
    }
  }

  void _onAmountTextChange() {
    // Keep only digits while editing
  }

  int _getTotalAmount() => _parseAmount(_totalAmountCtrl.text);
  int _getMonthlyAmount() => _parseAmount(_monthlyAmountCtrl.text);
  int _getTotalMonths() => int.tryParse(_totalMonthsCtrl.text) ?? 0;

  Future<void> _pickStartMonth() async {
    final now = DateTime.now();
    final currentParts = _startMonthCtrl.text.split('-');
    int year = now.year;
    int month = now.month;
    if (currentParts.length == 2) {
      year = int.tryParse(currentParts[0]) ?? now.year;
      month = int.tryParse(currentParts[1]) ?? now.month;
      month = month.clamp(1, 12);
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(year, month, 1),
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2035, 12, 31),
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Select Start Month',
    );
    if (picked != null) {
      final formatted = '${picked.year}-${picked.month.toString().padLeft(2, '0')}';
      _startMonthCtrl.text = formatted;
    }
  }

  String? _validateRequired(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    return null;
  }

  String? _validateMonths(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    final months = int.tryParse(value);
    if (months == null || months <= 0) return 'Enter a positive number';
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final totalAmount = _getTotalAmount();
    final monthlyAmount = _getMonthlyAmount();

    if (totalAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Total amount must be greater than 0')),
      );
      return;
    }

    if (monthlyAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Monthly amount must be greater than 0')),
      );
      return;
    }

    setState(() => _isSaving = true);

    final data = <String, dynamic>{
      'description': _descriptionCtrl.text.trim(),
      'total_amount': totalAmount,
      'monthly_amount': monthlyAmount,
      'total_months': _getTotalMonths(),
      'remaining_months': _getTotalMonths(),
      'start_month': _startMonthCtrl.text.trim(),
    };

    final success = await ref.read(creditCardProvider.notifier).addInstallment(
      widget.cardId,
      data,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (success) {
      ref.read(homeRefreshProvider.notifier).state++;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Installment added successfully')),
      );
      if (mounted) context.pop();
    } else {
      final err = ref.read(creditCardProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err ?? 'Failed to add installment')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Add Installment'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            // ─── Description ──────────────────────────
            _sectionLabel('Description'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _descriptionCtrl,
              decoration: const InputDecoration(
                hintText: 'e.g. MacBook Pro Installment',
                prefixIcon: Icon(Icons.description_outlined, size: 20),
              ),
              validator: _validateRequired,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 20),

            // ─── Total Amount ─────────────────────────
            _sectionLabel('Total Amount'),
            const SizedBox(height: 6),
            TextField(
              controller: _totalAmountCtrl,
              focusNode: _totalAmountFocus,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'Rp 0',
                prefixIcon: Icon(Icons.monetization_on_outlined, size: 20),
              ),
            ),
            const SizedBox(height: 20),

            // ─── Monthly Amount ───────────────────────
            _sectionLabel('Monthly Amount'),
            const SizedBox(height: 6),
            TextField(
              controller: _monthlyAmountCtrl,
              focusNode: _monthlyAmountFocus,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'Rp 0',
                prefixIcon: Icon(Icons.repeat_outlined, size: 20),
              ),
            ),
            const SizedBox(height: 20),

            // ─── Total Months ─────────────────────────
            _sectionLabel('Total Months'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _totalMonthsCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'e.g. 12',
                prefixIcon: Icon(Icons.date_range, size: 20),
              ),
              validator: _validateMonths,
            ),
            const SizedBox(height: 20),

            // ─── Start Month ──────────────────────────
            _sectionLabel('Start Month'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _startMonthCtrl,
              readOnly: true,
              decoration: InputDecoration(
                hintText: 'YYYY-MM',
                prefixIcon: const Icon(Icons.calendar_month_outlined, size: 20),
                suffixIcon: Icon(Icons.arrow_drop_down, size: 20, color: AppColors.textSecondary),
              ),
              validator: _validateRequired,
              onTap: _pickStartMonth,
            ),
            const SizedBox(height: 32),

            // ─── Save Button ──────────────────────────
            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surface))
                  : const Icon(Icons.save_outlined, size: 18),
              label: const Text('Save'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );
  }
}
