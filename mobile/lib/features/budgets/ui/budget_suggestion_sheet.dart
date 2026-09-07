import 'package:flutter/material.dart';
import '../../../core/ui/copy_fallback.dart';
import '../../../core/ui/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/category_glyph.dart';
import '../../../shared/utils/currency_formatter.dart';
import '../providers/budget_suggestion_provider.dart';
import '../models/budget_model.dart';

class BudgetSuggestionSheet extends ConsumerStatefulWidget {
  final String month;
  const BudgetSuggestionSheet({super.key, required this.month});

  @override
  ConsumerState<BudgetSuggestionSheet> createState() =>
      _BudgetSuggestionSheetState();
}

class _BudgetSuggestionSheetState
    extends ConsumerState<BudgetSuggestionSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(budgetSuggestionProvider.notifier).load(widget.month);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(budgetSuggestionProvider);
    final notifier = ref.read(budgetSuggestionProvider.notifier);
    final resp = state.response;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t('suggest.title'),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: AppIcon(AppIcons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            if (state.isLoading)
              const Expanded(
                child:
                    Center(child: CircularProgressIndicator()),
              )
            else if (state.error != null)
              Expanded(
                child: Center(
                  child: Text(state.error!,
                      style:
                          TextStyle(color: AppColors.highlight)),
                ),
              )
            else if (resp == null || resp.items.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon(AppIcons.spark,
                          size: 48,
                          color: AppColors.textSecondary
                              .withOpacity(0.5)),
                      const SizedBox(height: 12),
                      Text(
                        t('suggest.empty'),
                        style: TextStyle(
                            fontSize: 16,
                            color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t('suggest.empty_sub'),
                        style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              // Warning if over income
              if (resp.warning.isNotEmpty)
                Container(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      AppIcon(AppIcons.alert,
                          size: 18, color: AppColors.warning),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(resp.warning,
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.warning)),
                      ),
                    ],
                  ),
                ),
              // Summary bar
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Text(
                      '${state.numAccepted} ${t('suggest.picked')}',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () =>
                          notifier.toggleSelectAll(true),
                      child: Text(t('suggest.all'),
                          style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                    ),
                    TextButton(
                      onPressed: () =>
                          notifier.toggleSelectAll(false),
                      child: Text(t('suggest.clear'),
                          style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                    ),
                  ],
                ),
              ),
              // List
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: resp.items.length,
                  itemBuilder: (_, i) =>
                      _buildSuggestionCard(resp.items[i], notifier),
                ),
              ),
              // Apply button
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed:
                          state.isApplying || state.numAccepted == 0
                              ? null
                              : () async {
                                  final ok = await notifier
                                      .applySelected(widget.month);
                                  if (ok && mounted) {
                                    Navigator.pop(context);
                                  }
                                },
                      child: state.isApplying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            )
                          : Text(
                              '${t('suggest.apply')} ${state.numAccepted}',
                              style: TextStyle(
                                color: AppColors.onAccent,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionCard(
      BudgetSuggestion item, BudgetSuggestionNotifier notifier) {
    final isAccepted = item.accepted;
    final isExisting = item.hasBudget;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: isExisting
          ? AppColors.divider.withOpacity(0.3)
          : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isAccepted
              ? AppColors.success.withOpacity(0.5)
              : AppColors.divider,
          width: isAccepted ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: isExisting
            ? null
            : () => notifier.toggleAccept(item.categoryId),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CategoryGlyph(icon: item.categoryIcon, size: 32),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.categoryName,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${t('suggest.avg')} ${formatCurrency(item.historicalAvg)}/bln',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (isExisting)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(t('suggest.existing'),
                          style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary)),
                    )
                  else
                    Checkbox(
                      value: isAccepted,
                      onChanged: (_) =>
                          notifier.toggleAccept(item.categoryId),
                      activeColor: AppColors.success,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(4)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                children: [
                  Text(t('suggest.amount'),
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary)),
                  Text(
                    formatCurrency(item.suggestedAmount),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
