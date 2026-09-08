import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wealthtrack/core/theme/app_theme.dart';
import 'package:wealthtrack/features/categories/providers/category_provider.dart';
import '../../../core/ui/app_icons.dart';
import '../../../core/ui/category_glyph.dart';
import '../../../core/ui/category_icons.dart';
import '../../../core/ui/copy_fallback.dart';

class CategoryManagementScreen extends ConsumerStatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  ConsumerState<CategoryManagementScreen> createState() =>
      _CategoryManagementScreenState();
}

class _CategoryManagementScreenState
    extends ConsumerState<CategoryManagementScreen> {
  final _searchCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _keywordsCtrl = TextEditingController();
  final _iconScrollCtrl = ScrollController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(categoryManagementProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _nameCtrl.dispose();
    _keywordsCtrl.dispose();
    _iconScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _showAddEditSheet({Map<String, dynamic>? category}) async {
    final isEdit = category != null;
    _nameCtrl.text = category?['name'] ?? '';
    _keywordsCtrl.text =
        (category?['keywords'] as List?)?.join(', ') ?? '';
    String iconKey = (category?['icon'] as String?)?.trim().isNotEmpty == true
        ? category!['icon'] as String
        : kDefaultCategoryIcon;
    String type = category?['type'] ?? 'expense';
    final isDefault = category?['is_default'] == true;
    bool saving = false;
    String iconQuery = '';

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.textSecondary.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isEdit ? t('cat.edit') : t('cat.add'),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nameCtrl,
                      decoration: InputDecoration(labelText: t('cat.name')),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      t('cat.icon'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: InputDecoration(
                        labelText: t('cat.icon_search'),
                        hintText: 'strokeRounded…',
                      ),
                      onChanged: (v) => setSheetState(() => iconQuery = v),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: ListView(
                          controller: _iconScrollCtrl,
                          clipBehavior: Clip.hardEdge,
                          shrinkWrap: true,
                          children: [
                            for (final item in kCategoryIconCatalog.where((i) {
                              final q = iconQuery.trim().toLowerCase();
                              if (q.isEmpty) return true;
                              return i.key.toLowerCase().contains(q) ||
                                  i.label.toLowerCase().contains(q);
                            }))
                              Material(
                                color: iconKey == item.key
                                    ? AppColors.highlight.withOpacity(0.18)
                                    : Colors.transparent,
                                child: ListTile(
                                  dense: true,
                                  leading: CategoryGlyph(
                                    icon: item.key,
                                    expense: type != 'income',
                                    size: 32,
                                    selected: iconKey == item.key,
                                  ),
                                  title: Text(item.key, style: const TextStyle(fontSize: 12)),
                                  subtitle: Text(item.label, style: const TextStyle(fontSize: 11)),
                                  onTap: isDefault
                                      ? null
                                      : () => setSheetState(() => iconKey = item.key),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _keywordsCtrl,
                      decoration: InputDecoration(
                        labelText: t('cat.keywords'),
                        hintText: t('cat.keywords_hint'),
                      ),
                    ),
                    if (!isEdit) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: type,
                        decoration: InputDecoration(labelText: t('cat.type')),
                        items: [
                          DropdownMenuItem(
                              value: 'expense', child: Text(t('tx.filter_out'))),
                          DropdownMenuItem(
                              value: 'income', child: Text(t('tx.filter_in'))),
                        ],
                        onChanged: (v) =>
                            setSheetState(() => type = v ?? 'expense'),
                      ),
                    ],
                    if (isDefault)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          t('cat.default_locked'),
                          style: TextStyle(
                              color: AppColors.warning, fontSize: 12),
                        ),
                      ),
                    if (isEdit && !isDefault) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: saving
                              ? null
                              : () async {
                                  final confirmed = await showDialog<bool>(
                                    context: ctx,
                                    builder: (confirmCtx) => AlertDialog(
                                      title: Text(t('common.delete')),
                                      content: Text(t('cat.delete_confirm')),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(confirmCtx, false),
                                          child: Text(t('common.cancel')),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.pop(confirmCtx, true),
                                          child: Text(t('common.delete')),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed != true || !ctx.mounted) return;
                                  setSheetState(() => saving = true);
                                  final success = await ref
                                      .read(categoryManagementProvider.notifier)
                                      .delete(category!['id'] as int);
                                  if (!ctx.mounted) return;
                                  if (success) {
                                    Navigator.pop(ctx, true);
                                  } else {
                                    setSheetState(() => saving = false);
                                  }
                                },
                          icon: AppIcon(AppIcons.trash, size: 18, color: AppColors.highlight),
                          label: Text(t('common.delete')),
                          style: TextButton.styleFrom(foregroundColor: AppColors.highlight),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: saving || isDefault
                            ? null
                            : () async {
                                if (_nameCtrl.text.trim().isEmpty) return;
                                setSheetState(() => saving = true);
                                final data = <String, dynamic>{
                                  'name': _nameCtrl.text.trim(),
                                  'icon': iconKey,
                                };
                                if (_keywordsCtrl.text.trim().isNotEmpty) {
                                  data['keywords'] = _keywordsCtrl.text
                                      .split(',')
                                      .map((k) => k.trim())
                                      .where((k) => k.isNotEmpty)
                                      .toList();
                                }
                                if (!isEdit) {
                                  data['type'] = type;
                                }
                                final success = isEdit
                                    ? await ref
                                        .read(
                                            categoryManagementProvider.notifier)
                                        .update(
                                            category!['id'] as int, data)
                                    : await ref
                                        .read(
                                            categoryManagementProvider.notifier)
                                        .create(data);
                                if (!ctx.mounted) return;
                                if (success) {
                                  Navigator.pop(ctx, true);
                                } else {
                                  setSheetState(() => saving = false);
                                }
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: AppColors.onAccent,
                        ),
                        child: saving
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.onAccent,
                                ),
                              )
                            : Text(isEdit ? t('cat.save') : t('cat.create')),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (saved == true) {
      ref.read(categoryManagementProvider.notifier).load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(categoryManagementProvider);
    final query = _query.trim().toLowerCase();
    final filtered = state.categories.where((c) {
      if (query.isEmpty) return true;
      final name = (c['name'] as String? ?? '').toLowerCase();
      final keywords = (c['keywords'] as List? ?? const [])
          .join(' ')
          .toLowerCase();
      return name.contains(query) || keywords.contains(query);
    }).toList();
    final expense =
        filtered.where((c) => c['type'] == 'expense').toList();
    final income =
        filtered.where((c) => c['type'] == 'income').toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(t('cat.manage')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditSheet(),
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        child: AppIcon(AppIcons.add, size: 22, color: AppColors.onAccent),
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.error != null
              ? Center(child: Text('${t('cat.fail')}: ${state.error}'))
              : RefreshIndicator(
                  onRefresh: () =>
                      ref.read(categoryManagementProvider.notifier).load(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                    children: [
                      TextField(
                        controller: _searchCtrl,
                        onChanged: (value) => setState(() => _query = value),
                        decoration: InputDecoration(
                          hintText: t('cat.search'),
                          prefixIcon: const AppIcon(AppIcons.search, size: 18),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  icon: const AppIcon(AppIcons.close, size: 18),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _query = '');
                                  },
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildSection(t('tx.filter_out'), expense, true),
                      const SizedBox(height: 24),
                      _buildSection(t('tx.filter_in'), income, false),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSection(
      String title, List<Map<String, dynamic>> cats, bool expense) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        ...cats.map((cat) => _buildCategoryTile(cat, expense)),
        if (cats.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                t('cat.empty'),
                style: TextStyle(
                    color: AppColors.textSecondary.withOpacity(0.5)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCategoryTile(Map<String, dynamic> cat, bool expense) {
    final icon = cat['icon'] as String? ?? kDefaultCategoryIcon;
    final isDefault = cat['is_default'] == true;
    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CategoryGlyph(icon: icon, expense: expense, size: 36),
        title: Text(
          cat['name'] as String? ?? '',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        trailing: isDefault
            ? AppIcon(AppIcons.shield,
                size: 16, color: AppColors.textSecondary.withOpacity(0.4))
            : AppIcon(AppIcons.next, color: AppColors.textSecondary),
        onTap: isDefault ? null : () => _showAddEditSheet(category: cat),
      ),
    );
  }
}
