import 'package:flutter/material.dart';
import '../../../core/ui/copy_fallback.dart';
import '../../../core/ui/category_glyph.dart';
import '../../../core/ui/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/date_formatter.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/shimmer_loading.dart';
import '../../../shared/widgets/error_display.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../features/ocr/providers/ocr_provider.dart';
import '../providers/transaction_provider.dart';
import 'widgets/transaction_tile.dart';

class TransactionListScreen extends ConsumerStatefulWidget {
  final int? preSelectedCategoryId;
  const TransactionListScreen({super.key, this.preSelectedCategoryId});
  @override
  ConsumerState<TransactionListScreen> createState() => _TransactionListScreenState();
}

class _TransactionListScreenState extends ConsumerState<TransactionListScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounceTimer;
  Timer? _ocrPollTimer;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final notifier = ref.read(transactionListProvider.notifier);
      if (widget.preSelectedCategoryId != null) {
        notifier.setCategoryFilter([widget.preSelectedCategoryId!]);
      } else {
        notifier.load();
      }
    });
    _scrollController.addListener(_onScroll);
    Future.microtask(() => ref.read(ocrPendingCountProvider.notifier).load());

    // Poll OCR status every 8s while pending items exist
    _ocrPollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (ref.read(ocrPendingCountProvider).pendingCount > 0) {
        ref.read(ocrPendingCountProvider.notifier).load();
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _ocrPollTimer?.cancel();
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      ref.read(transactionListProvider.notifier).setSearchQuery(q);
    });
  }

  Future<void> _onRefresh() async {
    await ref.read(transactionListProvider.notifier).load();
  }

  void _onScroll() {
    final state = ref.read(transactionListProvider);
    if (state.isLoading || state.isLoadingMore) return;
    if (state.page >= state.totalPages) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (currentScroll >= maxScroll - 300) {
      ref.read(transactionListProvider.notifier).loadNextPage();
    }
  }

  void _showSortSheet() {
    final currentSort = ref.read(transactionListProvider).sortBy;
    ref.read(isCategoryFilterSheetOpenProvider.notifier).state = true;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final options = [
          {'value': '-date', 'label': t('sort.newest')},
          {'value': 'date', 'label': t('sort.oldest')},
          {'value': '-amount', 'label': t('sort.highest')},
          {'value': 'amount', 'label': t('sort.lowest')},
          {'value': 'name', 'label': t('sort.name_az')},
          {'value': '-name', 'label': t('sort.name_za')},
        ];
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(t('tx.sort_title'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 12),
              ...options.map((opt) {
                final selected = opt['value'] == currentSort;
                return ListTile(
                  leading: AppIcon(
                    selected ? AppIcons.check : AppIcons.more,
                    size: 20,
                    color: selected ? AppColors.accent : AppColors.textSecondary,
                  ),
                  title: Text(opt['label'] as String),
                  onTap: () {
                    Navigator.pop(ctx);
                    ref.read(transactionListProvider.notifier).setSortBy(opt['value'] as String);
                  },
                );
              }),
            ],
          ),
        );
      },
    ).whenComplete(() {
      ref.read(isCategoryFilterSheetOpenProvider.notifier).state = false;
    });
  }

  void _showCategoryFilterSheet() {
    final notifier = ref.read(transactionListProvider.notifier);
    final cats = notifier.categories;
    final state = ref.read(transactionListProvider);
    final selected = List<int>.from(state.selectedCategoryIds);
    // Always start with a populated list — empty means "no filter" (all selected)
    if (selected.isEmpty && cats.isNotEmpty) {
      selected.addAll(cats.map((c) => c['id'] as int));
    }

    // Notify MainShell to hide FAB
    ref.read(isCategoryFilterSheetOpenProvider.notifier).state = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final allSelected = selected.length == cats.length;
            final theme = Theme.of(ctx);
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(t('common.filter_cat'),
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      TextButton(
                        onPressed: () {
                          setSheetState(() {
                            selected.clear();
                          });
                        },
                        child: Text(t('common.clear_all'),
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.accent,
                            )),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Select All toggle
                  CheckboxListTile(
                    value: allSelected,
                    title: Text(t('common.all_cat'),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: allSelected
                              ? AppColors.textSecondary.withOpacity(0.4)
                              : AppColors.textPrimary,
                        )),
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: AppColors.accent,
                    checkColor: AppColors.surface,
                    onChanged: allSelected
                        ? null
                        : (_) {
                            setSheetState(() {
                              selected
                                ..clear()
                                ..addAll(cats.map((c) => c['id'] as int));
                            });
                          },
                  ),
                  Divider(
                    height: 24,
                    color: AppColors.divider,
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.4),
                    child: ListView(
                      shrinkWrap: true,
                      children: cats.map((cat) {
                        final catId = cat['id'] as int;
                        final label = catLabel(name: cat['name'] as String? ?? '', copyKey: cat['copy_key'] as String?);
                        return CheckboxListTile(
                          dense: false,
                          value: selected.contains(catId),
                          title: Text(label, style: const TextStyle(fontSize: 15)),
                          secondary: CategoryGlyph(icon: cat['icon'] as String? ?? '', size: 28),
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: AppColors.accent,
                          checkColor: AppColors.surface,
                          onChanged: (_) {
                            setSheetState(() {
                              if (selected.contains(catId)) {
                                selected.remove(catId);
                              } else {
                                selected.add(catId);
                              }
                            });
                          },
                        );
                      }).cast<Widget>().toList(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.onAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        // Notify MainShell to show FAB again
                        ref.read(isCategoryFilterSheetOpenProvider.notifier).state = false;
                        // Pass empty list = all (no filter)
                        notifier.setCategoryFilter(allSelected ? [] : selected);
                      },
                      child: Text(t('common.apply'), style: TextStyle(color: AppColors.onAccent, fontSize: 15, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      // Ensure FAB shows again even if dismissed without pressing Apply
      ref.read(isCategoryFilterSheetOpenProvider.notifier).state = false;
    });
  }

  String _dateChipLabel(TransactionListState state) {
    if (state.dateFrom == null || state.dateTo == null) return t('tx.date');
    final from = DateTime.tryParse(state.dateFrom!);
    final to = DateTime.tryParse(state.dateTo!);
    if (from == null || to == null) return t('tx.date');
    if (state.dateFrom == state.dateTo) return formatDayMonth(from);
    return '${formatDayMonth(from)} – ${formatDayMonth(to)}';
  }

  Future<void> _showDateFilterSheet() async {
    final state = ref.read(transactionListProvider);
    ref.read(isCategoryFilterSheetOpenProvider.notifier).state = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppColors.surface,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: AppIcon(AppIcons.calendar, color: AppColors.textPrimary),
                title: Text(t('tx.date_specific')),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickSpecificDate();
                },
              ),
              ListTile(
                leading: AppIcon(AppIcons.calendar, color: AppColors.textPrimary),
                title: Text(t('tx.date_range')),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickDateRange();
                },
              ),
              if (state.dateFrom != null)
                ListTile(
                  leading: AppIcon(AppIcons.close, color: AppColors.highlight),
                  title: Text(t('tx.date_clear'), style: TextStyle(color: AppColors.highlight)),
                  onTap: () {
                    Navigator.pop(ctx);
                    ref.read(transactionListProvider.notifier).clearDateFilter();
                  },
                ),
            ],
          ),
        ),
      );
    } finally {
      if (mounted) {
        ref.read(isCategoryFilterSheetOpenProvider.notifier).state = false;
      }
    }
  }

  Future<void> _pickSpecificDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      helpText: t('tx.date_specific'),
      cancelText: t('common.cancel'),
      confirmText: t('common.save'),
      fieldLabelText: t('tx.date'),
    );
    if (picked == null || !mounted) return;
    final day = DateFormat('yyyy-MM-dd').format(picked);
    await ref.read(transactionListProvider.notifier).setDateFilter(from: day, to: day);
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      helpText: t('tx.date_range'),
      cancelText: t('common.cancel'),
      confirmText: t('common.save'),
      saveText: t('common.save'),
    );
    if (picked == null || !mounted) return;
    final from = DateFormat('yyyy-MM-dd').format(picked.start);
    final to = DateFormat('yyyy-MM-dd').format(picked.end);
    await ref.read(transactionListProvider.notifier).setDateFilter(from: from, to: to);
  }

  Future<void> _showChangeOwnerSheet(int txnId, int currentOwnerId) async {
    final notifier = ref.read(transactionListProvider.notifier);
    final members = await notifier.getHouseholdMembers();
    final available = members.where((m) => m['user_id'] != currentOwnerId).toList();

    if (!mounted || available.isEmpty) {
      if (mounted && available.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('tx.no_other_member'))),
        );
      }
      return;
    }

    // Notify MainShell to hide FAB
    ref.read(isCategoryFilterSheetOpenProvider.notifier).state = true;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(t('tx.owner_change'),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(t('common.select_owner'), style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ),
              const SizedBox(height: 16),
              ...available.map((member) {
                final name = member['display_name'] as String? ?? t('common.user_n').replaceAll('{n}', '${member['user_id']}');
                final role = member['role'] as String? ?? 'member';
                
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.avatarBackground(name),
                    child: Text(name[0].toUpperCase(),
                      style: TextStyle(
                        color: AppColors.avatarText(name),
                        fontWeight: FontWeight.w600),
                    ),
                  ),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text(role == 'admin' ? t('hh.role_admin') : t('hh.role_member'),
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final success = await notifier.transferOwner(txnId, member['user_id'] as int);
                    if (!mounted) return;
                    if (success) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(t('common.owner_changed').replaceAll('{name}', name))),
                      );
                    } else {
                      final s = ref.read(transactionListProvider);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(s.transferError ?? t('tx.owner_fail'))),
                      );
                    }
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    ).whenComplete(() {
      // Ensure FAB shows again — fires even if dismissed without selecting
      ref.read(isCategoryFilterSheetOpenProvider.notifier).state = false;
    });
  }

  Future<void> _confirmDelete(int txnId, String description) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(t('tx.delete')),
        content: Text(
          t('tx.delete_confirm').replaceAll('{label}', description.isEmpty ? t('tx.this_note') : description),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('common.cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('common.delete'), style: TextStyle(color: AppColors.highlight)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await ref.read(transactionListProvider.notifier).delete(txnId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success ? t('tx.deleted') : t('tx.del_fail'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transactionListProvider);
    final notifier = ref.read(transactionListProvider.notifier);
    final ocrState = ref.watch(ocrPendingCountProvider);

    // Auto-refresh when OCR pending drops to 0
    ref.listen<OcrState>(ocrPendingCountProvider, (previous, next) {
      if (previous != null && next.pendingCount < previous.pendingCount) {
        ref.read(transactionListProvider.notifier).load();
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(t('tx.title')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: IconButton(
              icon: AppIcon(AppIcons.swap),
              tooltip: t('transfer.title'),
              onPressed: () async {
                final result = await context.push<bool>('/transactions/transfer');
                if (result == true && mounted) {
                  ref.read(transactionListProvider.notifier).load();
                }
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // OCR processing banner
          if (ocrState.pendingCount > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: AppColors.warning.withOpacity(0.1),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    ocrState.pendingCount == 1
                        ? t('home.ocr_processing').replaceAll('{count}', '1')
                        : t('home.ocr_processing').replaceAll('{count}', '${ocrState.pendingCount}'),
                    style: TextStyle(fontSize: 13, color: AppColors.warning),
                  ),
                ],
              ),
            ),
          // OCR error banner
          if (ocrState.hasFailure)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: AppColors.highlight.withOpacity(0.1),
              child: Row(
                children: [
                   AppIcon(AppIcons.alert, size: 16, color: AppColors.highlight),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ocrState.error ?? t('ocr.fail'),
                      style: TextStyle(fontSize: 13, color: AppColors.highlight),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => ref.read(ocrPendingCountProvider.notifier).dismissError(),
                    child: AppIcon(AppIcons.close, size: 16, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),

          // Search + type (C) — category/date/sort stay below
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: t('tx.search'),
                    prefixIcon: const AppFieldIcon(AppIcons.search),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 32, minHeight: 20, maxWidth: 40, maxHeight: 32),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const AppIcon(AppIcons.close, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              _onSearch('');
                              setState(() {});
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  ),
                  onChanged: (q) {
                    setState(() {});
                    _onSearch(q);
                  },
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.heroFill,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      _TypeSeg(
                        label: t('tx.filter_all'),
                        selected: state.typeFilter == 'all',
                        onTap: () => notifier.setTypeFilter('all'),
                      ),
                      _TypeSeg(
                        label: t('tx.filter_out'),
                        selected: state.typeFilter == 'expense',
                        onTap: () => notifier.setTypeFilter('expense'),
                      ),
                      _TypeSeg(
                        label: t('tx.filter_in'),
                        selected: state.typeFilter == 'income',
                        onTap: () => notifier.setTypeFilter('income'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Existing extra filters: category, date, sort
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ActionChip(
                    avatar: AppIcon(AppIcons.filter, size: 16,
                        color: state.selectedCategoryIds.isNotEmpty
                            ? AppColors.accent
                            : AppColors.textSecondary),
                    label: Text(
                      state.selectedCategoryIds.isNotEmpty
                          ? '${state.selectedCategoryIds.length} ${t('tx.categories').toLowerCase()}'
                          : t('tx.categories'),
                      style: TextStyle(fontSize: 12,
                          color: state.selectedCategoryIds.isNotEmpty
                              ? AppColors.accent
                              : AppColors.textSecondary),
                    ),
                    backgroundColor: AppColors.surface,
                    onPressed: _showCategoryFilterSheet,
                    side: BorderSide(
                      color: state.selectedCategoryIds.isNotEmpty
                          ? AppColors.accent
                          : AppColors.divider,
                    ),
                  ),
                  const SizedBox(width: 8),

                  ActionChip(
                    avatar: AppIcon(AppIcons.calendar, size: 16,
                        color: state.dateFrom != null
                            ? AppColors.accent
                            : AppColors.textSecondary),
                    label: Text(
                      _dateChipLabel(state),
                      style: TextStyle(fontSize: 12,
                          color: state.dateFrom != null
                              ? AppColors.accent
                              : AppColors.textSecondary),
                    ),
                    backgroundColor: AppColors.surface,
                    onPressed: _showDateFilterSheet,
                    side: BorderSide(
                      color: state.dateFrom != null
                          ? AppColors.accent
                          : AppColors.divider,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Sort button
                  ActionChip(
                    avatar: AppIcon(AppIcons.filter, size: 16, color: AppColors.textSecondary),
                    label: Text(_sortLabel(state.sortBy),
                        style: const TextStyle(fontSize: 12)),
                    backgroundColor: AppColors.surface,
                    onPressed: _showSortSheet,
                    side: BorderSide(color: AppColors.divider),
                  ),
                ],
              ),
            ),
          ),

          // Content
          Expanded(
            child: state.isLoading
                ? const ShimmerLoading()
                : state.error != null
                    ? ErrorDisplay(
                        message: state.error!,
                        onRetry: () => notifier.load(),
                      )
                    : state.transactions.isEmpty
                        ? RefreshIndicator(
                            onRefresh: _onRefresh,
                            child: CustomScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              slivers: [
                                SliverFillRemaining(
                                  child: EmptyState(message: t('tx.empty')),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _onRefresh,
                            child: ListView.separated(
                              padding: const EdgeInsets.only(
                                left: 16, right: 16, top: 4, bottom: 88,
                              ),
                              controller: _scrollController,
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: state.transactions.length + (state.isLoadingMore ? 1 : 0),
                              separatorBuilder: (_, index) {
                                return const SizedBox(height: 1);
                              },
                              itemBuilder: (context, i) {
                                // Loading shimmer at the bottom for infinite scroll
                                if (state.isLoadingMore && i == state.transactions.length) {
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                  );
                                }
                                final txn = state.transactions[i];
                                return Card(
                                  elevation: 0,
                                  child: TransactionTile(
                                    transaction: txn,
                                    showActions: true,
                                    onTransferOwner: () => _showChangeOwnerSheet(txn.id, txn.user?.id ?? 0),
                                    onDelete: () => _confirmDelete(txn.id, txn.description),
                                  ),
                                );
                              },
                            ),
                          ),
          ),

        ],
      ),
    );
  }

  String _sortLabel(String sort) {
    switch (sort) {
      case '-date': return t('tx.sort_newest');
      case 'date': return t('tx.sort_oldest');
      case '-amount': return t('tx.sort_high');
      case 'amount': return t('tx.sort_low');
      case 'name': return t('sort.name_az');
      case '-name': return t('sort.name_za');
      default: return t('tx.sort');
    }
  }
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

class _PaginationRow extends StatelessWidget {
  final int page;
  final int totalPages;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  const _PaginationRow({
    required this.page,
    required this.totalPages,
    this.onPrev,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: AppIcon(AppIcons.back, size: 20),
            onPressed: onPrev,
          ),
          const SizedBox(width: 8),
          Text(
            t('tx.page_n').replaceAll('{page}', '$page').replaceAll('{total}', '$totalPages'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: AppIcon(AppIcons.next, size: 20),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}
