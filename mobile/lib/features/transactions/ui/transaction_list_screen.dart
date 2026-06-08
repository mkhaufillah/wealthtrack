import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
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
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
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
          {'value': '-date', 'label': 'Newest first'},
          {'value': 'date', 'label': 'Oldest first'},
          {'value': '-amount', 'label': 'Highest amount'},
          {'value': 'amount', 'label': 'Lowest amount'},
          {'value': 'name', 'label': 'Name A\u2013Z'},
          {'value': '-name', 'label': 'Name Z\u2013A'},
        ];
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Text('Sort by', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 12),
              ...options.map((opt) {
                final selected = opt['value'] == currentSort;
                return ListTile(
                  leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: selected ? AppColors.accent : AppColors.textSecondary),
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
            final isDarkSheet = theme.brightness == Brightness.dark;
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Filter by Category',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      TextButton(
                        onPressed: () {
                          setSheetState(() {
                            selected.clear();
                          });
                        },
                        child: Text('Clear',
                            style: TextStyle(
                              fontSize: 14,
                              color: selected.isEmpty
                                  ? AppColors.textSecondary.withOpacity(0.4)
                                  : (isDarkSheet ? Colors.white : AppColors.accent),
                            )),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Select All toggle
                  CheckboxListTile(
                    value: allSelected,
                    title: Text('All Categories',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: allSelected
                              ? AppColors.textSecondary.withOpacity(0.4)
                              : AppColors.textPrimary,
                        )),
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: AppColors.accent,
                    checkColor: Colors.white,
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
                    height: 1,
                    color: theme.dividerColor.withOpacity(0.3),
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.4),
                    child: ListView(
                      shrinkWrap: true,
                      children: cats.map((cat) {
                        final catId = cat['id'] as int;
                        final nameEn = cat['name_en'] as String? ?? '';
                        final name = cat['name'] as String? ?? '';
                        final label = nameEn.isNotEmpty ? nameEn : name;
                        return CheckboxListTile(
                          dense: false,
                          value: selected.contains(catId),
                          title: Text(label, style: const TextStyle(fontSize: 15)),
                          secondary: Text(cat['icon'] as String? ?? '\uD83D\uDCE6',
                              style: const TextStyle(fontSize: 22)),
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: AppColors.accent,
                          checkColor: Colors.white,
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
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        // Notify MainShell to show FAB again
                        ref.read(isCategoryFilterSheetOpenProvider.notifier).state = false;
                        // Pass empty list = all (no filter)
                        notifier.setCategoryFilter(allSelected ? [] : selected);
                      },
                      child: const Text('Apply', style: TextStyle(color: Colors.white, fontSize: 15)),
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

  Future<void> _showChangeOwnerSheet(int txnId, int currentOwnerId) async {
    final notifier = ref.read(transactionListProvider.notifier);
    final members = await notifier.getHouseholdMembers();
    final available = members.where((m) => m['user_id'] != currentOwnerId).toList();

    if (!mounted || available.isEmpty) {
      if (mounted && available.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No other household members available')),
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
              const Center(
                child: Text('Transfer Ownership',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text('Select the new owner', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ),
              const SizedBox(height: 16),
              ...available.map((member) {
                final name = member['display_name'] as String? ?? 'User #${member['user_id']}';
                final role = member['role'] as String? ?? 'member';
                final isDark = Theme.of(ctx).brightness == Brightness.dark;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: () {
                      final hash = name.hashCode;
                      final idx = hash.abs() % Colors.primaries.length;
                      return isDark
                          ? Colors.primaries[idx].shade200.withOpacity(0.3)
                          : Colors.primaries[idx].shade50;
                    }(),
                    child: Text(name[0].toUpperCase(),
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.primaries[name.hashCode.abs() % Colors.primaries.length].shade700,
                        fontWeight: FontWeight.w600),
                    ),
                  ),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text(role == 'admin' ? 'Admin' : 'Member',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final success = await notifier.transferOwner(txnId, member['user_id'] as int);
                    if (!mounted) return;
                    if (success) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Ownership transferred to $name')),
                      );
                    } else {
                      final s = ref.read(transactionListProvider);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(s.transferError ?? 'Failed to transfer ownership')),
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
        title: const Text('Delete Transaction'),
        content: Text(
          'Delete "${description.isEmpty ? 'this transaction' : description}"? This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: AppColors.highlight)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await ref.read(transactionListProvider.notifier).delete(txnId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success ? 'Transaction deleted' : 'Failed to delete transaction')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transactionListProvider);
    final notifier = ref.read(transactionListProvider.notifier);
    final ocrState = ref.watch(ocrPendingCountProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Auto-refresh when OCR pending drops to 0
    ref.listen<OcrState>(ocrPendingCountProvider, (previous, next) {
      if (previous != null && next.pendingCount < previous.pendingCount) {
        ref.read(transactionListProvider.notifier).load();
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: IconButton(
              icon: const Icon(Icons.swap_horiz_rounded),
              tooltip: 'Transfer Balance',
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
                        ? '⏳ 1 transaction being processed...'
                        : '⏳ ${ocrState.pendingCount} transactions being processed...',
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
                   Icon(Icons.error_outline, size: 16, color: AppColors.highlight),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ocrState.error ?? 'OCR processing failed',
                      style: TextStyle(fontSize: 13, color: AppColors.highlight),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => ref.read(ocrPendingCountProvider.notifier).dismissError(),
                    child: Icon(Icons.close, size: 16, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),

          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search transactions...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _onSearch('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              ),
              onChanged: _onSearch,
            ),
          ),

          // Filter row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Type filter chips
                  _FilterChip(
                    label: 'All',
                    selected: state.typeFilter == 'all',
                    onTap: () => notifier.setTypeFilter('all'),
                    isDark: isDark,
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Expense',
                    selected: state.typeFilter == 'expense',
                    onTap: () => notifier.setTypeFilter('expense'),
                    isDark: isDark,
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Income',
                    selected: state.typeFilter == 'income',
                    onTap: () => notifier.setTypeFilter('income'),
                    isDark: isDark,
                  ),
                  const SizedBox(width: 12),

                  // Category filter button
                  ActionChip(
                    avatar: Icon(Icons.category_outlined, size: 16,
                        color: state.selectedCategoryIds.isNotEmpty
                            ? (isDark ? Colors.white : AppColors.accent)
                            : AppColors.textSecondary),
                    label: Text(
                      state.selectedCategoryIds.isNotEmpty
                          ? '${state.selectedCategoryIds.length} categories'
                          : 'Categories',
                      style: TextStyle(fontSize: 12,
                          color: state.selectedCategoryIds.isNotEmpty
                              ? (isDark ? Colors.white : AppColors.accent)
                              : AppColors.textSecondary),
                    ),
                    backgroundColor: isDark && state.selectedCategoryIds.isNotEmpty
                        ? AppColors.surface
                        : AppColors.surface,
                    onPressed: _showCategoryFilterSheet,
                    side: BorderSide(
                      color: state.selectedCategoryIds.isNotEmpty
                          ? (isDark ? Colors.white38 : AppColors.accent)
                          : AppColors.divider,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Sort button
                  ActionChip(
                    avatar: Icon(Icons.sort, size: 16, color: AppColors.textSecondary),
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
                                  child: EmptyState(message: 'No transactions found.'),
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
      case '-date': return 'Newest';
      case 'date': return 'Oldest';
      case '-amount': return 'Highest';
      case 'amount': return 'Lowest';
      case 'name': return 'A\u2013Z';
      case '-name': return 'Z\u2013A';
      default: return 'Sort';
    }
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? (isDark ? AppColors.accent.withOpacity(0.85) : AppColors.accent)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.transparent : AppColors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? Colors.white : AppColors.textSecondary,
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
            icon: const Icon(Icons.chevron_left, size: 20),
            onPressed: onPrev,
          ),
          const SizedBox(width: 8),
          Text(
            'Page $page of $totalPages',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}
