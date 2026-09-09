import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_icons.dart';
import '../../../../core/ui/copy_fallback.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/utils/currency_formatter.dart';

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
    final type = (item['type'] ?? 'expense').toString();
    final cats = await api.get('/categories', queryParams: {'type': type});
    final list = (cats.data as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    if (!context.mounted) return;
    final suggested = item['suggested_category_id'];
    list.sort((a, b) {
      final sa = a['id'] == suggested;
      final sb = b['id'] == suggested;
      if (sa == sb) return 0;
      return sa ? -1 : 1;
    });
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(t('bank.pick_category')),
        content: SizedBox(
          width: 320,
          height: 280,
          child: ListView(
            children: list.map((c) {
              final id = c['id'] as int;
              final rec = suggested == id;
              return ListTile(
                title: Text('${c['name']}'),
                subtitle: rec ? Text(t('bank.pick_suggested')) : null,
                selected: rec,
                trailing: rec ? AppIcon(AppIcons.check, color: AppColors.accent) : null,
                onTap: () => Navigator.pop(ctx, id),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('common.cancel'))),
        ],
      ),
    );
    if (picked == null) return;
    await api.post('/bank-inbox/${item['id']}/confirm', data: {'category_id': picked});
    onDone();
  }
}
