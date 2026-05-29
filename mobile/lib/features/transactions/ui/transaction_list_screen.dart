import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/loading_indicator.dart';
import '../../../shared/widgets/error_display.dart';
import '../../../shared/widgets/empty_state.dart';
import '../providers/transaction_provider.dart';
import 'widgets/transaction_tile.dart';

class TransactionListScreen extends ConsumerStatefulWidget {
  const TransactionListScreen({super.key});
  @override
  ConsumerState<TransactionListScreen> createState() => _TransactionListScreenState();
}

class _TransactionListScreenState extends ConsumerState<TransactionListScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(transactionListProvider.notifier).load());
  }

  Future<void> _showChangeOwnerSheet(int txnId, int currentOwnerId) async {
    final notifier = ref.read(transactionListProvider.notifier);
    final members = await notifier.getHouseholdMembers();

    // Filter out current owner from the picker
    final available = members.where((m) => m['user_id'] != currentOwnerId).toList();

    if (!mounted || available.isEmpty) {
      if (mounted && available.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No other household members available')),
        );
      }
      return;
    }

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
                    backgroundColor: name == 'Nahda'
                        ? (isDark ? Colors.pink.shade200 : Colors.pink.shade100)
                        : (isDark ? Colors.blue.shade200 : Colors.blue.shade100),
                    child: Text(name[0].toUpperCase(),
                      style: TextStyle(
                        color: name == 'Nahda'
                            ? (isDark ? Colors.pink.shade200 : Colors.pink.shade700)
                            : (isDark ? Colors.blue.shade200 : Colors.blue.shade700),
                        fontWeight: FontWeight.w600
                      ),
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
                      final state = ref.read(transactionListProvider);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(state.transferError ?? 'Failed to transfer ownership')),
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
    );
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
                  ref.read(transactionListProvider.notifier).load(refresh: true);
                }
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/transactions/add'),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(transactionListProvider.notifier).load(refresh: true),
        child: state.isLoading
            ? const LoadingIndicator()
            : state.error != null
                ? ErrorDisplay(message: state.error!, onRetry: () => ref.read(transactionListProvider.notifier).load())
                : state.transactions.isEmpty
                    ? CustomScrollView(
                        physics: AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverFillRemaining(
                            child: EmptyState(message: 'No transactions yet. Add one now!'),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80),
                        itemCount: state.transactions.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 1),
                        itemBuilder: (context, i) {
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
    );
  }
}
