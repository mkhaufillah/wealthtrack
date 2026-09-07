import '../../../../shared/utils/currency_formatter.dart';
import 'package:flutter/material.dart';
import '../../../../core/ui/copy_fallback.dart';
import '../../../../core/ui/money.dart';
import '../../../../core/ui/app_icons.dart';
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
String _formatIdrDisplay(String digits) => formatIdrInput(digits);

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
      helpText: 'Pilih bulan mulai',
    );
    if (picked != null) {
      final formatted = '${picked.year}-${picked.month.toString().padLeft(2, '0')}';
      _startMonthCtrl.text = formatted;
    }
  }

  String? _validateRequired(String? value) {
    if (value == null || value.trim().isEmpty) return t('common.required');
    return null;
  }

  String? _validateMonths(String? value) {
    if (value == null || value.trim().isEmpty) return t('common.required');
    final months = int.tryParse(value);
    if (months == null || months <= 0) return t('common.positive');
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final totalAmount = _getTotalAmount();
    final monthlyAmount = _getMonthlyAmount();

    if (totalAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('cc.total_positive'))),
      );
      return;
    }

    if (monthlyAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('cc.monthly_positive'))),
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
        SnackBar(content: Text(t('cc.inst_saved'))),
      );
      if (mounted) context.pop();
    } else {
      final err = ref.read(creditCardProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err ?? 'Gagal nambah cicilan')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(t('cc.inst_add')),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            // ─── Description ──────────────────────────
            _sectionLabel('Keterangan'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _descriptionCtrl,
              decoration: InputDecoration(
                hintText: t('cc.inst_hint'),
                prefixIcon: AppFieldIcon(AppIcons.edit),
              ),
              validator: _validateRequired,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 20),

            // ─── Total Amount ─────────────────────────
            _sectionLabel('Total'),
            const SizedBox(height: 6),
            TextField(
              controller: _totalAmountCtrl,
              focusNode: _totalAmountFocus,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: '${MoneyFormat.prefix} 0',
                prefixIcon: AppFieldIcon(AppIcons.money),
              ),
            ),
            const SizedBox(height: 20),

            // ─── Monthly Amount ───────────────────────
            _sectionLabel('Cicilan / bulan'),
            const SizedBox(height: 6),
            TextField(
              controller: _monthlyAmountCtrl,
              focusNode: _monthlyAmountFocus,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: '${MoneyFormat.prefix} 0',
                prefixIcon: AppFieldIcon(AppIcons.refresh),
              ),
            ),
            const SizedBox(height: 20),

            // ─── Total Months ─────────────────────────
            _sectionLabel('Jumlah bulan'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _totalMonthsCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: t('cc.months_hint'),
                prefixIcon: AppFieldIcon(AppIcons.calendar),
              ),
              validator: _validateMonths,
            ),
            const SizedBox(height: 20),

            // ─── Start Month ──────────────────────────
            _sectionLabel('Bulan mulai'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _startMonthCtrl,
              readOnly: true,
              decoration: InputDecoration(
                hintText: t('cc.months_hint'),
                prefixIcon: AppFieldIcon(AppIcons.calendar),
                suffixIcon: AppIcon(AppIcons.next, size: 20, color: AppColors.textSecondary),
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
                  : AppIcon(AppIcons.check, size: 18),
              label: Text(t('common.save')),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.onAccent,
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
