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
                    ? const SingleChildScrollView(
                        physics: AlwaysScrollableScrollPhysics(),
                        child: EmptyState(message: 'No transactions yet. Add one now!'),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: state.transactions.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 1),
                        itemBuilder: (context, i) {
                          final txn = state.transactions[i];
                          return Card(
                            child: TransactionTile(data: {
                              'type': txn.type,
                              'category': {
                                'icon': txn.category.icon,
                                'name': txn.category.name,
                              },
                              'amount': txn.amount,
                              'description': txn.description,
                              'date': txn.date,
                            }),
                          );
                        },
                      ),
      ),
    );
  }
}