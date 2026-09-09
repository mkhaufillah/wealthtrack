import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/copy_fallback.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/utils/currency_formatter.dart';
import '../data/bank_capture.dart';

class BankInboxScreen extends ConsumerStatefulWidget {
  const BankInboxScreen({super.key});

  @override
  ConsumerState<BankInboxScreen> createState() => _BankInboxScreenState();
}

class _BankInboxScreenState extends ConsumerState<BankInboxScreen> {
  bool _loading = true;
  bool _accessOn = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final api = ref.read(apiClientProvider);
    final enabled = await BankCapture.isEnabled();
    await BankCapture.flushToServer(api);
    if (!mounted) return;
    setState(() => _accessOn = enabled);
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref.read(apiClientProvider).get('/bank-inbox');
      if (!mounted) return;
      final data = res.data as Map<String, dynamic>;
      setState(() {
        _items = (data['items'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ref.read(apiClientProvider).handleError(e).toString();
      });
    }
  }

  Future<void> _act(int id, String action) async {
    try {
      await ref.read(apiClientProvider).post('/bank-inbox/$id/$action', data: {});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'confirm' ? t('bank.saved') : t('bank.rejected'),
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.read(apiClientProvider).handleError(e).toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(t('bank.inbox_title')),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: Column(
        children: [
          if (!_accessOn)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Card(
                color: AppColors.surface,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('bank.enable_hint'),
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () async {
                          await BankCapture.openSettings();
                          final on = await BankCapture.isEnabled();
                          if (mounted) setState(() => _accessOn = on);
                        },
                        child: Text(t('bank.enable')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: TextStyle(color: AppColors.highlight)),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          t('bank.inbox_empty'),
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _boot,
      child: ListView.builder(
        itemCount: _items.length,
        itemBuilder: (ctx, i) {
          final item = _items[i];
          final parsed = item['parsed'] == true || item['parsed'] == 1;
          final amount = item['amount'];
          final amountInt = amount is int ? amount : (amount is num ? amount.toInt() : null);
          final bank = (item['bank'] ?? '').toString();
          final merchant = (item['merchant'] ?? '').toString();
          final status = (item['status'] ?? '').toString();
          final pending = status == 'pending' || status.isEmpty;
          final raw = '${item['title'] ?? ''} ${item['text'] ?? ''}'.trim();
          return Card(
            elevation: 0,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bank.isEmpty ? t('bank.inbox_title') : bank.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (status == 'confirmed')
                    Text(t('bank.status_saved'), style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  if (status == 'rejected')
                    Text(t('bank.status_skipped'), style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Text(
                    parsed && amountInt != null
                        ? formatCurrency(amountInt)
                        : t('bank.unparsed'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    merchant.isNotEmpty ? merchant : raw,
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  if (pending) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        FilledButton(
                          onPressed: parsed ? () => _act(item['id'] as int, 'confirm') : null,
                          child: Text(t('bank.confirm')),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => _act(item['id'] as int, 'reject'),
                          child: Text(t('bank.reject')),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
