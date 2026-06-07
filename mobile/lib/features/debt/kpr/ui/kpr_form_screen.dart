import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/kpr_provider.dart';
import '../../../../shared/utils/currency_formatter.dart';
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

class _RatePeriodRow {
  final TextEditingController fromMonthCtrl;
  final TextEditingController toMonthCtrl;
  final TextEditingController rateCtrl;
  String rateType;

  _RatePeriodRow({
    int fromMonth = 1,
    int toMonth = 12,
    double rate = 5.0,
    this.rateType = 'fixed',
  })  : fromMonthCtrl = TextEditingController(text: fromMonth.toString()),
        toMonthCtrl = TextEditingController(text: toMonth.toString()),
        rateCtrl = TextEditingController(text: rate.toStringAsFixed(1));

  void dispose() {
    fromMonthCtrl.dispose();
    toMonthCtrl.dispose();
    rateCtrl.dispose();
  }
}

class KPRFormScreen extends ConsumerStatefulWidget {
  const KPRFormScreen({super.key});

  @override
  ConsumerState<KPRFormScreen> createState() => _KPRFormScreenState();
}

class _KPRFormScreenState extends ConsumerState<KPRFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _propertyPriceCtrl = TextEditingController();
  final _downPaymentCtrl = TextEditingController();

  int _tenorYears = 15;
  String _interestType = 'fixed';

  // Fixed/Floating fields
  final _baseRateCtrl = TextEditingController(text: '9.0');

  // Graduated fields
  final _gradIncrementCtrl = TextEditingController(text: '0.5');
  final _gradEveryMonthsCtrl = TextEditingController(text: '12');

  // Mix fields
  final List<_RatePeriodRow> _ratePeriods = [];

  bool _isSaving = false;
  bool _isCalculating = false;

  // Focus nodes for amount fields
  final _propertyFocus = FocusNode();
  final _downPaymentFocus = FocusNode();
  bool _propertyFocused = false;
  bool _downPaymentFocused = false;

  @override
  void initState() {
    super.initState();
    _propertyFocus.addListener(_onPropertyFocusChange);
    _downPaymentFocus.addListener(_onDownPaymentFocusChange);
    _propertyPriceCtrl.addListener(_onAmountTextChange);
    _downPaymentCtrl.addListener(_onAmountTextChange);
    // Add initial rate periods for mix
    _ratePeriods.add(_RatePeriodRow(fromMonth: 1, toMonth: 60, rate: 8.0, rateType: 'fixed'));
    _ratePeriods.add(_RatePeriodRow(fromMonth: 61, toMonth: 120, rate: 10.0, rateType: 'floating'));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _propertyPriceCtrl.dispose();
    _downPaymentCtrl.dispose();
    _baseRateCtrl.dispose();
    _gradIncrementCtrl.dispose();
    _gradEveryMonthsCtrl.dispose();
    _propertyFocus.dispose();
    _downPaymentFocus.dispose();
    for (final rp in _ratePeriods) {
      rp.dispose();
    }
    super.dispose();
  }

  void _onPropertyFocusChange() {
    setState(() => _propertyFocused = _propertyFocus.hasFocus);
    _formatAmountOnFocusChange(_propertyPriceCtrl, _propertyFocused);
  }

  void _onDownPaymentFocusChange() {
    setState(() => _downPaymentFocused = _downPaymentFocus.hasFocus);
    _formatAmountOnFocusChange(_downPaymentCtrl, _downPaymentFocused);
  }

  void _formatAmountOnFocusChange(TextEditingController ctrl, bool isFocused) {
    if (isFocused) {
      // Show raw digits when editing
      final raw = ctrl.text.replaceAll(RegExp(r'[^\d]'), '');
      if (raw != ctrl.text) {
        ctrl.value = TextEditingValue(
          text: raw,
          selection: TextSelection.collapsed(offset: raw.length),
        );
      }
    } else {
      // Format on blur
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

  int _getPropertyPrice() => _parseAmount(_propertyPriceCtrl.text);
  int _getDownPayment() => _parseAmount(_downPaymentCtrl.text);
  int _getLoanAmount() => _getPropertyPrice() - _getDownPayment();
  double _getBaseRate() => double.tryParse(_baseRateCtrl.text) ?? 0.0;
  int _getTenorMonths() => _tenorYears * 12;

  String? _validateRequired(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    return null;
  }

  /// Calculate monthly payment for a fixed-rate loan using standard amortization formula.
  double _calcMonthlyPayment(int loanAmount, double annualRate, int months) {
    if (loanAmount <= 0 || months <= 0) return 0;
    if (annualRate <= 0) return loanAmount / months;
    final monthlyRate = annualRate / 12 / 100;
    final factor = pow(1 + monthlyRate, months);
    return (loanAmount * monthlyRate * factor) / (factor - 1);
  }

  void _calculate() {
    final loanAmount = _getLoanAmount();
    final tenorMonths = _getTenorMonths();
    if (loanAmount <= 0 || tenorMonths <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in property price and down payment first')),
      );
      return;
    }

    setState(() => _isCalculating = true);

    double monthlyPayment;
    double totalPayment;
    double totalInterest;

    switch (_interestType) {
      case 'fixed':
      case 'floating':
        final rate = _getBaseRate();
        monthlyPayment = _calcMonthlyPayment(loanAmount, rate, tenorMonths);
        totalPayment = monthlyPayment * tenorMonths;
        totalInterest = totalPayment - loanAmount;
        break;
      case 'graduated':
        // Simplified: average the graduated rates
        final baseRate = _getBaseRate();
        final increment = double.tryParse(_gradIncrementCtrl.text) ?? 0.0;
        final everyMonths = int.tryParse(_gradEveryMonthsCtrl.text) ?? 12;
        // Compute with varying rate per period
        totalPayment = 0;
        int monthsDone = 0;
        int period = 0;
        while (monthsDone < tenorMonths) {
          final periodMonths = everyMonths < 1
              ? tenorMonths - monthsDone
              : everyMonths.clamp(1, tenorMonths - monthsDone);
          final rate = baseRate + period * increment;
          final pmt = _calcMonthlyPayment(loanAmount, rate, tenorMonths);
          totalPayment += pmt * periodMonths;
          monthsDone += periodMonths;
          period++;
        }
        monthlyPayment = totalPayment / tenorMonths;
        totalInterest = totalPayment - loanAmount;
        break;
      case 'mix':
        // Use first rate period as effective rate for estimate
        final rate = _ratePeriods.isNotEmpty
            ? double.tryParse(_ratePeriods.first.rateCtrl.text) ?? 9.0
            : 9.0;
        monthlyPayment = _calcMonthlyPayment(loanAmount, rate, tenorMonths);
        totalPayment = monthlyPayment * tenorMonths;
        totalInterest = totalPayment - loanAmount;
        break;
      default:
        monthlyPayment = 0;
        totalPayment = 0;
        totalInterest = 0;
    }

    setState(() => _isCalculating = false);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.calculate, size: 22, color: AppColors.accent),
            const SizedBox(width: 8),
            const Text('Calculation Result'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _resultRow('Property Price', formatCurrency(loanAmount + _getDownPayment())),
            _resultRow('Down Payment', formatCurrency(_getDownPayment())),
            _resultRow('Loan Amount', formatCurrency(loanAmount)),
            const Divider(height: 20),
            _resultRow('Monthly Payment', formatCurrency(monthlyPayment.round()),
                valueColor: AppColors.accent),
            _resultRow('Total Payment', formatCurrency(totalPayment.round())),
            _resultRow('Total Interest', formatCurrency(totalInterest.round()),
                valueColor: AppColors.highlight),
            const Divider(height: 20),
            _resultRow('Tenor', '$_tenorYears years ($tenorMonths months)'),
            _resultRow('Interest Type', _interestType[0].toUpperCase() + _interestType.substring(1)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _resultRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          Text(value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppColors.textPrimary,
              )),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final loanAmount = _getLoanAmount();
    if (loanAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Loan amount must be greater than 0')),
      );
      return;
    }

    setState(() => _isSaving = true);

    final data = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'property_price': _getPropertyPrice(),
      'down_payment': _getDownPayment(),
      'tenor_months': _getTenorMonths(),
      'interest_type': _interestType,
      'base_interest_rate': _getBaseRate() / 100,
    };

    if (_interestType == 'graduated') {
      data['graduated_increment'] = (double.tryParse(_gradIncrementCtrl.text) ?? 0.0) / 100;
      data['graduated_every_months'] = int.tryParse(_gradEveryMonthsCtrl.text) ?? 12;
    }

    if (_interestType == 'mix') {
      data['rate_periods'] = _ratePeriods.map((rp) => {
        'period_start': int.tryParse(rp.fromMonthCtrl.text) ?? 1,
        'period_end': int.tryParse(rp.toMonthCtrl.text) ?? 12,
        'interest_rate': (double.tryParse(rp.rateCtrl.text) ?? 0.0) / 100,
        'rate_type': rp.rateType,
      }).toList();
    }

    final success = await ref.read(kprProvider.notifier).create(data);

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Simulation saved successfully')),
      );
      if (mounted) context.pop();
    } else {
      final err = ref.read(kprProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err ?? 'Failed to save simulation')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('New KPR Simulation'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            // ─── Simulation Name ─────────────────────
            _sectionLabel('Simulation Name'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                hintText: 'e.g. Rumah Impian',
              ),
              validator: _validateRequired,
            ),
            const SizedBox(height: 20),

            // ─── Property Price ──────────────────────
            _sectionLabel('Property Price'),
            const SizedBox(height: 6),
            TextField(
              controller: _propertyPriceCtrl,
              focusNode: _propertyFocus,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'Rp 0',
                prefixIcon: Icon(Icons.home_outlined, size: 20),
              ),
            ),
            const SizedBox(height: 20),

            // ─── Down Payment ────────────────────────
            _sectionLabel('Down Payment (DP)'),
            const SizedBox(height: 6),
            TextField(
              controller: _downPaymentCtrl,
              focusNode: _downPaymentFocus,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'Rp 0',
                prefixIcon: Icon(Icons.payments_outlined, size: 20),
              ),
            ),
            const SizedBox(height: 20),

            // ─── Loan Amount (read-only) ─────────────
            _sectionLabel('Loan Amount (Auto-calculated)'),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  Icon(Icons.account_balance_outlined, size: 20, color: AppColors.textSecondary),
                  const SizedBox(width: 10),
                  Text(
                    formatCurrency(_getLoanAmount()),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ─── Tenor ──────────────────────────────
            _sectionLabel('Tenor'),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              value: _tenorYears,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.schedule, size: 20),
              ),
              items: [5, 10, 15, 20, 25, 30].map((y) {
                return DropdownMenuItem(value: y, child: Text('$y years'));
              }).toList(),
              onChanged: (v) {
                if (v != null) setState(() => _tenorYears = v);
              },
            ),
            const SizedBox(height: 20),

            // ─── Interest Type ──────────────────────
            _sectionLabel('Interest Type'),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'fixed', label: Text('Fixed', style: TextStyle(fontSize: 12))),
                ButtonSegment(value: 'floating', label: Text('Float', style: TextStyle(fontSize: 12))),
                ButtonSegment(value: 'graduated', label: Text('Grad', style: TextStyle(fontSize: 12))),
                ButtonSegment(value: 'mix', label: Text('Mix', style: TextStyle(fontSize: 12))),
              ],
              selected: {_interestType},
              onSelectionChanged: (v) => setState(() => _interestType = v.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(height: 20),

            // ─── Interest-type-specific fields ──────
            if (_interestType == 'fixed' || _interestType == 'floating')
              ..._buildFixedFloatingFields(),
            if (_interestType == 'graduated')
              ..._buildGraduatedFields(),
            if (_interestType == 'mix')
              ..._buildMixFields(),

            const SizedBox(height: 24),

            // ─── Action Buttons ──────────────────────
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isCalculating ? null : _calculate,
                    icon: _isCalculating
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.calculate_outlined, size: 18),
                    label: const Text('Calculate'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Save'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
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

  // ─── Fixed / Floating Fields ────────────────────────────
  List<Widget> _buildFixedFloatingFields() {
    return [
      _sectionLabel('Base Interest Rate (%)'),
      const SizedBox(height: 6),
      TextField(
        controller: _baseRateCtrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          hintText: 'e.g. 9.0',
          suffixText: '%',
          prefixIcon: Icon(Icons.percent, size: 20),
        ),
      ),
      const SizedBox(height: 16),
    ];
  }

  // ─── Graduated Fields ────────────────────────────────
  List<Widget> _buildGraduatedFields() {
    return [
      _sectionLabel('Base Interest Rate (%)'),
      const SizedBox(height: 6),
      TextField(
        controller: _baseRateCtrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          hintText: 'e.g. 7.0',
          suffixText: '%',
          prefixIcon: Icon(Icons.percent, size: 20),
        ),
      ),
      const SizedBox(height: 16),
      _sectionLabel('Increment per Period (%)'),
      const SizedBox(height: 6),
      TextField(
        controller: _gradIncrementCtrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          hintText: 'e.g. 0.5',
          suffixText: '%',
          prefixIcon: Icon(Icons.trending_up, size: 20),
        ),
      ),
      const SizedBox(height: 16),
      _sectionLabel('Period Length (months)'),
      const SizedBox(height: 6),
      TextField(
        controller: _gradEveryMonthsCtrl,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          hintText: 'e.g. 12',
          suffixText: 'months',
          prefixIcon: Icon(Icons.date_range, size: 20),
        ),
      ),
      const SizedBox(height: 16),
    ];
  }

  // ─── Mix Fields ──────────────────────────────────────
  List<Widget> _buildMixFields() {
    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _sectionLabel('Rate Periods'),
          TextButton.icon(
            onPressed: () {
              setState(() {
                int lastEnd = 1;
                if (_ratePeriods.isNotEmpty) {
                  lastEnd = int.tryParse(_ratePeriods.last.toMonthCtrl.text) ?? 12;
                }
                final nextStart = lastEnd + 1;
                final nextEnd = lastEnd + 60;
                _ratePeriods.add(_RatePeriodRow(
                  fromMonth: nextStart,
                  toMonth: nextEnd,
                  rate: 10.0,
                  rateType: 'floating',
                ));
              });
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Period'),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      ..._ratePeriods.asMap().entries.map((entry) {
        final idx = entry.key;
        final rp = entry.value;
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 0,
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: AppColors.divider.withAlpha(128)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Text('Period ${idx + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        )),
                    const Spacer(),
                    if (_ratePeriods.length > 1)
                      InkWell(
                        onTap: () {
                          setState(() {
                            rp.dispose();
                            _ratePeriods.removeAt(idx);
                          });
                        },
                        child: Icon(Icons.remove_circle_outline,
                            size: 20, color: AppColors.highlight),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: rp.fromMonthCtrl,
                        decoration: const InputDecoration(
                          labelText: 'From (mo)',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: rp.toMonthCtrl,
                        decoration: const InputDecoration(
                          labelText: 'To (mo)',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: rp.rateCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Rate %',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: rp.rateType,
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'fixed', child: Text('Fixed', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'floating', child: Text('Floating', style: TextStyle(fontSize: 13))),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => rp.rateType = v);
                  },
                ),
              ],
            ),
          ),
        );
      }),
    ];
  }
}
