import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/kpr_provider.dart';
import '../../models/kpr_model.dart';
import '../../../../shared/utils/currency_formatter.dart';
import '../../../../shared/widgets/loading_indicator.dart';
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

enum ExtraStep { form, preview, confirm }

class KPRExtraPaymentScreen extends ConsumerStatefulWidget {
  final int simulationId;
  const KPRExtraPaymentScreen({super.key, required this.simulationId});

  @override
  ConsumerState<KPRExtraPaymentScreen> createState() =>
      _KPRExtraPaymentScreenState();
}

class _KPRExtraPaymentScreenState
    extends ConsumerState<KPRExtraPaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _monthController = TextEditingController();
  final _amountFocusNode = FocusNode();
  bool _amountFocused = false;

  ExtraStep _step = ExtraStep.form;
  int? _selectedOption;

  int _minMonth = 1;
  int _maxMonth = 600;

  @override
  void initState() {
    super.initState();
    _amountFocusNode.addListener(_onAmountFocusChange);
    _amountController.addListener(_onAmountTextChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(kprProvider.notifier).loadDetail(widget.simulationId);
      ref.read(kprProvider.notifier).loadExtraPayments(widget.simulationId);
    });
  }

  @override
  void dispose() {
    _amountController.removeListener(_onAmountTextChange);
    _amountFocusNode.removeListener(_onAmountFocusChange);
    _amountController.dispose();
    _monthController.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  void _onAmountFocusChange() {
    setState(() => _amountFocused = _amountFocusNode.hasFocus);
    _formatAmountOnFocusChange(_amountController, _amountFocused);
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

  void _updateValidationBounds(KPRState state) {
    final extras = state.extraPayments;
    if (extras.isNotEmpty) {
      _minMonth = extras.map((e) => e.applyMonth).reduce((a, b) => a > b ? a : b);
    } else {
      _minMonth = 1;
    }
    _maxMonth = state.selectedSimulation?.tenorMonths ?? 600;
  }

  Future<void> _preview() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = _parseAmount(_amountController.text);
    final month = int.parse(_monthController.text);

    final preview = await ref.read(kprProvider.notifier).previewExtraPayment(
          simId: widget.simulationId,
          amount: amount,
          applyMonth: month,
        );

    if (mounted && preview != null) {
      setState(() => _step = ExtraStep.preview);
    }
  }

  Future<void> _confirm() async {
    if (_selectedOption == null) return;

    final amount = _parseAmount(_amountController.text);
    final month = int.parse(_monthController.text);
    final type = _selectedOption == 0 ? 'installment' : 'tenor';

    final success = await ref
        .read(kprProvider.notifier)
        .createExtraPayment(
          simId: widget.simulationId,
          amount: amount,
          applyMonth: month,
          reductionType: type,
        );

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Extra payment applied successfully!')),
        );
        context.pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to apply extra payment')),
        );
      }
    }
  }

  void _goBackToForm() {
    setState(() {
      _step = ExtraStep.form;
      _selectedOption = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(kprProvider);
    final preview = state.extraPreview;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    _updateValidationBounds(state);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Extra Payment'),
        actions: [
          if (_step == ExtraStep.preview)
            TextButton(
              onPressed: _goBackToForm,
              child: const Text('Edit'),
            ),
        ],
      ),
      body: state.isLoading
          ? const LoadingIndicator()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _step == ExtraStep.form
                  ? _buildForm(isDark)
                  : _buildPreview(isDark, preview, state),
            ),
    );
  }

  Widget _buildForm(bool isDark) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Extra Payment Details',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Extra payment reduces your loan principal directly. '
            'You can choose to reduce the monthly installment or shorten the tenor.',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),

          // Amount
          TextFormField(
            controller: _amountController,
            focusNode: _amountFocusNode,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Extra Payment Amount (Rp)',
              prefixText: 'Rp ',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: AppColors.surface,
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Enter amount';
              final n = _parseAmount(v);
              if (n == 0 || n < 1000) return 'Minimum Rp1,000';
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Apply Month
          TextFormField(
            controller: _monthController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Apply at Month Number',
              hintText: '$_minMonth — $_maxMonth',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: AppColors.surface,
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Enter month number';
              final n = int.tryParse(v);
              if (n == null || n < _minMonth) {
                return _minMonth == 1
                    ? 'Must be 1 or more'
                    : 'Must be $_minMonth or more (after existing extra payments)';
              }
              if (n > _maxMonth) return 'Cannot exceed $_maxMonth (tenor end)';
              return null;
            },
          ),
          const SizedBox(height: 24),

          // Preview button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _preview,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Preview Comparison',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(
      bool isDark, ExtraPaymentPreview? preview, KPRState state) {
    if (preview == null) {
      return Center(
        child: Text(
          state.error ?? 'Preview not available',
          style: TextStyle(color: AppColors.highlight),
        ),
      );
    }

    final optA = preview.optionInstallment;
    final optB = preview.optionTenor;

    final installmentDiff = formatCurrency(
        (preview.comparison['installment_difference'] as num?)?.toInt() ?? 0);
    final monthsSaved =
        (preview.comparison['months_saved_difference'] as num?)?.toInt() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose Your Preference',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Both options reduce your remaining loan. Pick the one that '
          'fits your financial goals.',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),

        _buildOptionCard(
          title: 'A. Reduce Installment',
          subtitle: 'Fixed tenor, lower monthly payment',
          isSelected: _selectedOption == 0,
          isDark: isDark,
          fields: {
            'New Installment': formatCurrency(optA.newInstallment),
            'New Tenor': '${optA.newTenor} mo',
            'Total Interest': formatCurrency(optA.totalInterestPaid),
            'Interest Saved': formatCurrency(optA.interestSaved),
            'End Date': optA.endDate,
          },
          onTap: () => setState(() => _selectedOption = 0),
        ),
        const SizedBox(height: 12),

        _buildOptionCard(
          title: 'B. Shorten Tenor',
          subtitle: 'Fixed payment, pay off faster',
          isSelected: _selectedOption == 1,
          isDark: isDark,
          fields: {
            'New Installment': formatCurrency(optB.newInstallment),
            'New Tenor': '${optB.newTenor} mo',
            'Total Interest': formatCurrency(optB.totalInterestPaid),
            'Interest Saved': formatCurrency(optB.interestSaved),
            'End Date': optB.endDate,
          },
          onTap: () => setState(() => _selectedOption = 1),
        ),

        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.accent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.accent.withOpacity(0.2),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.compare_arrows,
                  size: 20, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Difference',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Installment: $installmentDiff/month lower (Option A)\n'
                      'Tenor: $monthsSaved months faster (Option B)',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _selectedOption != null ? _confirm : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.textSecondary.withOpacity(0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              _selectedOption != null
                  ? 'Confirm & Apply Extra Payment'
                  : 'Select an Option Above',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOptionCard({
    required String title,
    required String subtitle,
    required bool isSelected,
    required bool isDark,
    required Map<String, String> fields,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.accent
                : AppColors.divider.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? AppColors.accent
                              : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.check,
                        size: 16, color: Colors.white),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ...fields.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        e.key,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        e.value,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
