import 'package:flutter/material.dart';
import '../../../../core/ui/copy_fallback.dart';
import '../../../../core/ui/money.dart';
import '../../../../core/ui/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../features/home/providers/dashboard_provider.dart';
import '../providers/kpr_provider.dart';
import '../../models/kpr_model.dart';
import '../../../../shared/utils/currency_formatter.dart';
import '../../../../shared/utils/date_formatter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/auth/providers/auth_provider.dart';
import '../../../../shared/providers/app_providers.dart';

/// Extracts raw integer amount from a formatted IDR string like "Rp 50.000".
int _parseAmount(String text) {
  final digits = text.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.isEmpty) return 0;
  return int.tryParse(digits) ?? 0;
}

/// Formats raw digits into "Rp XXX.XXX" display format.
String _formatIdrDisplay(String digits) => formatIdrInput(digits);

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
  int _startMonth = DateTime.now().month;
  int _startYear = DateTime.now().year;
  int? _dueDate;

  // Fixed/Floating fields
  final _baseRateCtrl = TextEditingController(text: '9.0');

  // Graduated fields
  final _gradIncrementCtrl = TextEditingController(text: '0.5');
  final _gradEveryMonthsCtrl = TextEditingController(text: '12');

  // Mix fields
  final List<_RatePeriodRow> _ratePeriods = [];

  bool _isSaving = false;
  bool _isCalculating = false;

  // Share toggle
  bool _shareWithHousehold = false;
  bool _hasHousehold = false;
  bool _householdCheckDone = false;
  int? _householdId;

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
    // Extend last rate period to full tenor after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncLastRatePeriodToTenor();
    });

    // Check if user has a household
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkHousehold();
    });
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
    if (value == null || value.trim().isEmpty) return t('common.required');
    return null;
  }

  void _syncLastRatePeriodToTenor() {
    if (_ratePeriods.isNotEmpty && mounted) {
      final totalMonths = _getTenorMonths();
      final last = _ratePeriods.last;
      last.toMonthCtrl.text = totalMonths.toString();
    }
  }

  Future<void> _checkHousehold() async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get('/households/me');
      if (mounted) {
        final data = res.data as Map<String, dynamic>?;
        final household = data?['household'] as Map<String, dynamic>?;
        setState(() {
          _hasHousehold = true;
          _householdCheckDone = true;
          _householdId = household?['id'] as int?;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasHousehold = false;
          _householdCheckDone = true;
        });
      }
    }
  }

  Future<void> _calculate() async {
    final loanAmount = _getLoanAmount();
    final tenorMonths = _getTenorMonths();
    if (loanAmount <= 0 || tenorMonths <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('kpr.fill_price_dp'))),
      );
      return;
    }

    setState(() => _isCalculating = true);

    double monthlyPayment = 0;
    double totalPayment = 0;
    double totalInterest = 0;

    try {
      final api = ref.read(apiClientProvider);
      final data = <String, dynamic>{
        'property_price': _getPropertyPrice(),
        'down_payment': _getDownPayment(),
        'tenor_months': tenorMonths,
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

      final res = await api.post('/kpr/calculate', data: data);
      final result = res.data as Map<String, dynamic>?;
      monthlyPayment = (result?['monthly_payment'] as num?)?.toDouble() ?? 0;
      totalPayment = (result?['total_payment'] as num?)?.toDouble() ?? 0;
      totalInterest = (result?['total_interest'] as num?)?.toDouble() ?? 0;
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('kpr.calc_failed'))),
      );
      if (!mounted) return;
      setState(() => _isCalculating = false);
      return;
    }

    if (!mounted) return;
    setState(() => _isCalculating = false);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            AppIcon(AppIcons.chart, size: 22, color: AppColors.accent),
            const SizedBox(width: 8),
            Text(t('common.result')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _resultRow('Harga rumah', formatCurrency(loanAmount + _getDownPayment())),
            _resultRow('Uang muka', formatCurrency(_getDownPayment())),
            _resultRow('Pinjaman', formatCurrency(loanAmount)),
            Divider(height: 24, color: AppColors.divider),
            _resultRow('Cicilan / bulan', formatCurrency(monthlyPayment.round()),
                valueColor: AppColors.accent),
            _resultRow('Total bayar', formatCurrency(totalPayment.round())),
            _resultRow('Total bunga', formatCurrency(totalInterest.round()),
                valueColor: AppColors.highlight),
            Divider(height: 24, color: AppColors.divider),
            _resultRow('Tenor', '$_tenorYears tahun ($tenorMonths bulan)'),
            _resultRow('Tipe bunga', kprInterestLabel(_interestType)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('common.close')),
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
        SnackBar(content: Text(t('kpr.loan_positive'))),
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
      'start_month': _startMonth,
      'start_year': _startYear,
      if (_dueDate != null) 'due_date': _dueDate,
      if (_shareWithHousehold && _householdId != null) 'household_id': _householdId,
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
        SnackBar(content: Text(t('kpr.sim_saved'))),
      );
      ref.read(homeRefreshProvider.notifier).state++;
      if (mounted) context.pop();
    } else {
      final err = ref.read(kprProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err ?? 'Gagal simpan simulasi')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(t('kpr.new')),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            // ─── Simulation Name ─────────────────────
            _sectionLabel(t('kpr.name_label')),
            const SizedBox(height: 6),
            TextFormField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                hintText: t('kpr.name_hint'),
              ),
              validator: _validateRequired,
            ),
            const SizedBox(height: 20),

            // ─── Property Price ──────────────────────
            _sectionLabel(t('kpr.house_price')),
            const SizedBox(height: 6),
            TextField(
              controller: _propertyPriceCtrl,
              focusNode: _propertyFocus,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: '${MoneyFormat.prefix} 0',
                prefixIcon: AppFieldIcon(AppIcons.home),
              ),
            ),
            const SizedBox(height: 20),

            // ─── Down Payment ────────────────────────
            _sectionLabel(t('kpr.dp_label')),
            const SizedBox(height: 6),
            TextField(
              controller: _downPaymentCtrl,
              focusNode: _downPaymentFocus,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: '${MoneyFormat.prefix} 0',
                prefixIcon: AppFieldIcon(AppIcons.money),
              ),
            ),
            const SizedBox(height: 20),

            // ─── Loan Amount (read-only) ─────────────
            _sectionLabel(t('kpr.loan_auto')),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  AppIcon(AppIcons.bank, size: 20, color: AppColors.textSecondary),
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
            _sectionLabel(t('kpr.tenor_label')),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              value: _tenorYears,
              decoration: InputDecoration(
                prefixIcon: AppFieldIcon(AppIcons.calendar),
              ),
              items: [5, 10, 15, 20, 25, 30].map((y) {
                return DropdownMenuItem(value: y, child: Text(t('common.year_n').replaceAll('{n}', y.toString())));
              }).toList(),
              onChanged: (v) {
                if (v != null) setState(() => _tenorYears = v);
              },
            ),
            const SizedBox(height: 20),

            // ─── Start Month & Year ──────────────────
            _sectionLabel(t('kpr.first_label')),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _startMonth,
                    decoration: InputDecoration(
                      prefixIcon: AppFieldIcon(AppIcons.calendar),
                    ),
                    items: List.generate(12, (i) => i + 1).map((m) {
                      final months = idMonthShort;
                      return DropdownMenuItem(
                        value: m,
                        child: Text(months[m - 1]),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _startMonth = v);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _startYear,
                    decoration: InputDecoration(
                      prefixIcon: AppFieldIcon(AppIcons.calendar),
                    ),
                    items: List.generate(31, (i) => 2020 + i).map((y) {
                      return DropdownMenuItem(value: y, child: Text('$y'));
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _startYear = v);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ─── Due Date ───────────────────────────
            _sectionLabel(t('kpr.due_date_label')),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              value: _dueDate,
              decoration: InputDecoration(
                prefixIcon: AppFieldIcon(AppIcons.calendar),
                hintText: t('kpr.date_in_month'),
              ),
              items: List.generate(28, (i) => i + 1).map((d) {
                return DropdownMenuItem(value: d, child: Text(t('common.day_n_short').replaceAll('{n}', d.toString())));
              }).toList(),
              onChanged: (v) {
                if (v != null) setState(() => _dueDate = v);
              },
            ),
            const SizedBox(height: 20),

            // ─── Interest Type ──────────────────────
            _sectionLabel(t('kpr.type_label')),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'fixed', label: Text(t('kpr.interest_fixed'), style: TextStyle(fontSize: 12))),
                ButtonSegment(value: 'floating', label: Text(t('kpr.interest_floating'), style: TextStyle(fontSize: 11))),
                ButtonSegment(value: 'graduated', label: Text(t('kpr.interest_graduated'), style: TextStyle(fontSize: 12))),
                ButtonSegment(value: 'mix', label: Text(t('kpr.interest_mix'), style: TextStyle(fontSize: 12))),
              ],
              selected: {_interestType},
              onSelectionChanged: (v) => setState(() => _interestType = v.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) return AppColors.accent;
                  return AppColors.surface;
                }),
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) return AppColors.onAccent;
                  return AppColors.textPrimary;
                }),
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

            // ─── Share with Household Toggle ─────────
            if (_householdCheckDone && _hasHousehold)
              SwitchListTile(
                title: Text(t('common.share_hh')),
                subtitle: Text(t('common.share_hh_sub')),
                value: _shareWithHousehold,
                onChanged: (v) => setState(() => _shareWithHousehold = v),
                contentPadding: EdgeInsets.zero,
              ),
            if (_householdCheckDone && _hasHousehold)
              const SizedBox(height: 8),

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
                        : AppIcon(AppIcons.chart, size: 18),
                    label: Text(t('common.calculate')),
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
      _sectionLabel(t('kpr.base_rate_label')),
      const SizedBox(height: 6),
      TextField(
        controller: _baseRateCtrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          hintText: t('kpr.rate_hint'),
          suffixText: '%',
          prefixIcon: AppFieldIcon(AppIcons.money),
        ),
      ),
      const SizedBox(height: 16),
    ];
  }

  // ─── Graduated Fields ────────────────────────────────
  List<Widget> _buildGraduatedFields() {
    return [
      _sectionLabel(t('kpr.base_rate_label')),
      const SizedBox(height: 6),
      TextField(
        controller: _baseRateCtrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          hintText: t('kpr.rate_low_hint'),
          suffixText: '%',
          prefixIcon: AppFieldIcon(AppIcons.money),
        ),
      ),
      const SizedBox(height: 16),
      _sectionLabel(t('kpr.incr_label')),
      const SizedBox(height: 6),
      TextField(
        controller: _gradIncrementCtrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          hintText: t('kpr.increment_hint'),
          suffixText: '%',
          prefixIcon: AppFieldIcon(AppIcons.chartUp),
        ),
      ),
      const SizedBox(height: 16),
      _sectionLabel(t('kpr.period_months_label')),
      const SizedBox(height: 6),
      TextField(
        controller: _gradEveryMonthsCtrl,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          hintText: t('kpr.months_hint'),
          suffixText: 'bulan',
          prefixIcon: AppFieldIcon(AppIcons.calendar),
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
          _sectionLabel(t('kpr.periods_label')),
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
            icon: AppIcon(AppIcons.add, size: 18),
            label: Text(t('common.add_period')),
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
                    Text(t('kpr.period_n').replaceAll('{n}', (idx + 1).toString()),
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
                        child: AppIcon(AppIcons.close,
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
                        decoration: InputDecoration(
                          labelText: t('common.from_month'),
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
                        decoration: InputDecoration(
                          labelText: t('common.to_month'),
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
                        decoration: InputDecoration(
                          labelText: t('common.rate_pct'),
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
                  decoration: InputDecoration(
                    labelText: t('common.type'),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  items: [
                    DropdownMenuItem(value: 'fixed', child: Text(t('kpr.interest_fixed'), style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'floating', child: Text(t('kpr.interest_floating'), style: TextStyle(fontSize: 13))),
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
