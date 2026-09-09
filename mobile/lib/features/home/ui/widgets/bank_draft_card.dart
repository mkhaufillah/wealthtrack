import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/copy_fallback.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/utils/currency_formatter.dart';

class BankDraftCard extends ConsumerWidget {
  const BankDraftCard({super.key, required this.item, required this.onDone});

  final Map<String, dynamic> item;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(apiClientProvider);
    final amount = (item['amount'] as num?)?.toInt();
    final merchant = (item['merchant'] ?? item['title'] ?? '').toString();
    final bank = (item['bank'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('home.bank_draft'), style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 6),
          Text(
            [bank, merchant].where((e) => e.isNotEmpty).join(' · '),
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
          ),
          if (amount != null)
            Text(formatCurrency(amount), style: TextStyle(color: AppColors.textPrimary, fontSize: 18)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _confirm(context, api),
                  child: Text(t('bank.confirm')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await api.post('/bank-inbox/${item['id']}/reject', data: {});
                    onDone();
                  },
                  child: Text(t('bank.reject')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await api.delete('/bank-inbox/${item['id']}');
                    onDone();
                  },
                  child: Text(t('common.delete')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirm(BuildContext context, ApiClient api) async {
    final cats = await api.get('/categories');
    final list = (cats.data as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    if (!context.mounted) return;
    int? catId = item['suggested_category_id'] as int?;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('bank.pick_category')),
        content: SizedBox(
          width: 320,
          height: 280,
          child: ListView(
            children: list
                .map((c) => ListTile(
                      title: Text('${c['name']}'),
                      onTap: () => Navigator.pop(ctx, c['id'] as int),
                    ))
                .toList(),
          ),
        ),
      ),
    );
    if (picked != null) catId = picked;
    if (catId == null) return;
    await api.post('/bank-inbox/${item['id']}/confirm', data: {'category_id': catId});
    onDone();
  }
}
