import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
              const Center(
                child: Text('Select the new owner', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ),
              const SizedBox(height: 16),
              ...available.map((member) {
                final name = member['display_name'] as String? ?? 'User #${member['user_id']}';
                final role = member['role'] as String? ?? 'member';
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withOpacity(0.15),
                    child: Text(name[0].toUpperCase(),
                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                  ),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text(role == 'admin' ? 'Admin' : 'Member',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transactionListProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Transactions')),
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
                        padding: const EdgeInsets.all(16),
                        itemCount: state.transactions.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 1),
                        itemBuilder: (context, i) {
                          final txn = state.transactions[i];
                          return Card(
                            child: TransactionTile(
                              transaction: txn,
                              onTransferOwner: () => _showChangeOwnerSheet(txn.id, txn.user?.id ?? 0),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
