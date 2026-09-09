import 'package:flutter/material.dart';
import '../../../core/ui/copy_fallback.dart';
import '../../../core/ui/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/category_icons.dart';
import '../../../shared/providers/app_providers.dart';
import '../../home/providers/dashboard_provider.dart';
import '../../ocr/providers/ocr_provider.dart';
import '../providers/transaction_provider.dart';
import '../models/transaction_model.dart';
import 'widgets/amount_field.dart';
import 'widgets/category_picker.dart';

class AddTransactionScreen extends ConsumerStatefulWidget {
  final TransactionModel? editTransaction;
  /// If true, auto-trigger receipt scanning on load (from home widget)
  final bool autoScan;
  const AddTransactionScreen({super.key, this.editTransaction, this.autoScan = false});
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
  bool _isScanning = false;

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
    if (widget.autoScan) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scanReceipt());
    }
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
          id: e['id'] as int, name: e['name'] as String, icon: e['icon'] as String? ?? kDefaultCategoryIcon,
          copyKey: e['copy_key'] as String? ?? '',
        )).toList();
        _incomeCategories = (List<Map<String, dynamic>>.from(incomeRes.data)).map((e) => CategoryChip(
          id: e['id'] as int, name: e['name'] as String, icon: e['icon'] as String? ?? kDefaultCategoryIcon,
          copyKey: e['copy_key'] as String? ?? '',
        )).toList();
        _categories = _isExpense ? _expenseCategories : _incomeCategories;
      });
    } catch (e) {
      debugPrint('ERROR: $e');
    }
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

  Future<void> _scanReceipt() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Text(t('tx.scan_title'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(t('tx.scan_sub'),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const AppIcon(AppIcons.camera),
              title: Text(t('tx.photo')),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const AppIcon(AppIcons.gallery),
              title: Text(t('tx.gallery')),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, imageQuality: 70, maxWidth: 1920);
      if (picked == null) return;

      final api = ref.read(apiClientProvider);

      ref.read(ocrPendingCountProvider.notifier).clearError();

      await api.uploadFile('/ocr/process-and-save', picked.path);

      if (!mounted) return;

      ref.read(ocrPendingCountProvider.notifier).load();

      context.go('/transactions');
    } catch (e) {
      if (!mounted) return;
      final errMsg = ref.read(apiClientProvider).handleError(e).toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errMsg),
          backgroundColor: AppColors.highlight,
        ),
      );
    }
  }

  Future<void> _save() async {
    final amountText = _amountCtrl.text.replaceAll('Rp', '').replaceAll('.', '').replaceAll(',', '').trim();
    final amount = int.tryParse(amountText);
    if (amount == null || amount <= 0) { _showError(t('tx.amount_err')); return; }
    if (_selectedCategoryId == null) { _showError(t('tx.cat_err')); return; }

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
      ref.read(dashboardProvider.notifier).load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              AppIcon(AppIcons.check, color: AppColors.onAccent, size: 20),
              const SizedBox(width: 8),
              Text(_isEditing ? t('tx.updated') : t('tx.recorded'),
                  style: TextStyle(color: AppColors.onAccent, fontWeight: FontWeight.w700)),
            ],
          ),
          backgroundColor: AppColors.success,
        ),
      );
      context.pop();
    } else {
      _showError(t('tx.save_fail'));
    }
  }

  void _showError(String msg) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              AppIcon(AppIcons.alert, color: AppColors.onAccent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(msg, style: TextStyle(color: AppColors.onAccent, fontWeight: FontWeight.w700)),
              ),
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
      helpText: t('tx.date_specific'),
      cancelText: t('common.cancel'),
      confirmText: t('common.save'),
      fieldLabelText: t('tx.date'),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate = '${_selectedDate.day} ${_monthName(_selectedDate.month)} ${_selectedDate.year}';

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(_isEditing ? t('tx.edit_title') : t('tx.new')),
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const AppIcon(AppIcons.camera, size: 20),
              onPressed: _isScanning ? null : _scanReceipt,
              tooltip: t('tx.photo'),
            ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  children: [
                    Text(
                      _isExpense ? t('tx.kind_out') : t('tx.kind_in'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    AmountField(controller: _amountCtrl, hero: true),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.heroFill,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          _TypeSeg(
                            label: t('tx.filter_out'),
                            selected: _isExpense,
                            onTap: () => _toggleType(true),
                          ),
                          _TypeSeg(
                            label: t('tx.filter_in'),
                            selected: !_isExpense,
                            onTap: () => _toggleType(false),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    _label(t('tx.categories')),
                    CategoryPicker(
                      categories: _categories,
                      selectedId: _selectedCategoryId,
                      isExpense: _isExpense,
                      onSelected: (id) => setState(() => _selectedCategoryId = id),
                    ),
                    const SizedBox(height: 16),
                    _label(t('tx.for')),
                    TextField(
                      controller: _descCtrl,
                      decoration: InputDecoration(
                        hintText: t('tx.for_hint'),
                        fillColor: AppColors.surface,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _label(t('tx.date')),
                    InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: double.infinity,
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            AppIcon(AppIcons.calendar, size: 16, color: AppColors.textSecondary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                formattedDate,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            AppIcon(AppIcons.next, size: 16, color: AppColors.textSecondary),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _label(t('tx.note_opt')),
                    TextField(
                      controller: _noteCtrl,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: t('tx.note_hint'),
                        fillColor: AppColors.surface,
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      child: _isSaving
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.onAccent,
                              ),
                            )
                          : Text(_isEditing ? t('tx.update') : t('common.save')),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_isScanning) _buildScanOverlay(),
        ],
      ),
    );
  }

  Widget _buildScanOverlay() {
    return AbsorbPointer(
      child: Container(
        color: AppColors.textPrimary.withOpacity(0.92),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 48, height: 48,
                child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.surface),
              ),
              const SizedBox(height: 20),
              Text(
                t('tx.processing'),
                style: TextStyle(color: AppColors.surface, fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                t('tx.processing_sub'),
                style: TextStyle(color: AppColors.surface.withOpacity(0.7), fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _monthName(int m) =>
      ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'][m - 1];
}

class _TypeSeg extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TypeSeg({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.surface : AppColors.heroFill,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: selected ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
