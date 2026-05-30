import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wealthtrack/core/theme/app_theme.dart';
import 'package:wealthtrack/features/categories/providers/category_provider.dart';

class CategoryManagementScreen extends ConsumerStatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  ConsumerState<CategoryManagementScreen> createState() => _CategoryManagementScreenState();
}

class _CategoryManagementScreenState extends ConsumerState<CategoryManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(categoryManagementProvider.notifier).load();
    });
  }

  Future<void> _showAddEditSheet({Map<String, dynamic>? category}) async {
    final isEdit = category != null;
    final nameCtrl = TextEditingController(text: category?['name'] ?? '');
    final nameEnCtrl = TextEditingController(text: category?['name_en'] ?? '');
    final iconCtrl = TextEditingController(text: category?['icon'] ?? '');
    final keywordsCtrl = TextEditingController(
      text: (category?['keywords'] as List?)?.join(', ') ?? '',
    );
    final sortCtrl = TextEditingController(
      text: (category?['sort_order'] ?? 0).toString(),
    );
    String type = category?['type'] ?? 'expense';
    final isDefault = category?['is_default'] == true;
    bool saving = false;

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
                left: 16, right: 16, top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.textSecondary.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isEdit ? 'Edit Category' : 'Add Category',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Name (ID)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameEnCtrl,
                      decoration: const InputDecoration(labelText: 'Name (English)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: iconCtrl,
                      decoration: const InputDecoration(labelText: 'Icon (emoji)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: keywordsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Keywords (comma-separated)',
                        hintText: 'keyword1, keyword2',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: sortCtrl,
                      decoration: const InputDecoration(labelText: 'Sort Order'),
                      keyboardType: TextInputType.number,
                    ),
                    if (!isEdit) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: type,
                        decoration: const InputDecoration(labelText: 'Type'),
                        items: const [
                          DropdownMenuItem(value: 'expense', child: Text('Expense')),
                          DropdownMenuItem(value: 'income', child: Text('Income')),
                        ],
                        onChanged: (v) => setSheetState(() => type = v ?? 'expense'),
                      ),
                    ],
                    if (isDefault)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Default categories cannot be edited.',
                          style: TextStyle(color: AppColors.warning, fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: saving ? null : () async {
                          if (nameCtrl.text.trim().isEmpty) return;
                          setSheetState(() => saving = true);
                          final data = <String, dynamic>{
                            'name': nameCtrl.text.trim(),
                            'name_en': nameEnCtrl.text.trim(),
                            'icon': iconCtrl.text.trim(),
                            'sort_order': int.tryParse(sortCtrl.text) ?? 0,
                          };
                          if (keywordsCtrl.text.trim().isNotEmpty) {
                            data['keywords'] = keywordsCtrl.text
                                .split(',')
                                .map((k) => k.trim())
                                .where((k) => k.isNotEmpty)
                                .toList();
                          }
                          if (!isEdit) {
                            data['type'] = type;
                          }

                          final success = isEdit
                              ? await ref.read(categoryManagementProvider.notifier).update(category!['id'] as int, data)
                              : await ref.read(categoryManagementProvider.notifier).create(data);

                          if (!ctx.mounted) return;
                          if (success) {
                            Navigator.pop(ctx, true);
                          } else {
                            setSheetState(() => saving = false);
                          }
                        },
                        child: saving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(isEdit ? 'Update' : 'Create'),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Group by type
    final expense = state.categories.where((c) => c['type'] == 'expense').toList();
    final income = state.categories.where((c) => c['type'] == 'income').toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Manage Categories'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditSheet(),
        child: const Icon(Icons.add),
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.error != null
              ? Center(child: Text('Error: ${state.error}'))
              : RefreshIndicator(
                  onRefresh: () => ref.read(categoryManagementProvider.notifier).load(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                    children: [
                      _buildSection('Expense', expense, isDark),
                      const SizedBox(height: 24),
                      _buildSection('Income', income, isDark),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSection(String title, List<Map<String, dynamic>> cats, bool isDark) {
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
        ...cats.map((cat) => _buildCategoryTile(cat, isDark)),
        if (cats.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                'No categories',
                style: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCategoryTile(Map<String, dynamic> cat, bool isDark) {
    final nameEn = cat['name_en'] as String? ?? '';
    final icon = cat['icon'] as String? ?? '';
    final isDefault = cat['is_default'] == true;

    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isDark ? AppColors.background : AppColors.primary.withOpacity(0.1),
          child: Text(icon.isNotEmpty ? icon : '📦', style: const TextStyle(fontSize: 20)),
        ),
        title: Text(
          nameEn.isNotEmpty ? nameEn : cat['name'] as String,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          cat['name'] as String,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        trailing: isDefault
            ? Icon(Icons.lock_outline, size: 16, color: AppColors.textSecondary.withOpacity(0.4))
            : Icon(Icons.chevron_right, color: AppColors.textSecondary),
        onTap: isDefault ? null : () => _showAddEditSheet(category: cat),
      ),
    );
  }
}
