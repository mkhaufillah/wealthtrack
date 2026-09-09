import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
  final _pasteCtrl = TextEditingController();
  String _pastePkg = 'com.bca';

  @override
  void dispose() {
    _pasteCtrl.dispose();
    super.dispose();
  }

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

  Future<void> _pickAndConfirm(Map<String, dynamic> item) async {
    final type = (item['type'] ?? 'expense').toString();
    List<Map<String, dynamic>> cats = [];
    try {
      final res = await ref.read(apiClientProvider).get('/categories', queryParams: {'type': type});
      cats = (res.data as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.read(apiClientProvider).handleError(e).toString())),
      );
      return;
    }
    if (!mounted || cats.isEmpty) return;
    final suggested = item['suggested_category_id'];
    final chosen = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: 320,
          child: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(t('bank.pick_category'), style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              ...cats.map((c) {
                final id = c['id'] as int;
                final selected = suggested == id;
                return ListTile(
                  title: Text('${c['name']}'),
                  selected: selected,
                  onTap: () => Navigator.pop(ctx, id),
                );
              }),
            ],
          ),
        ),
      ),
    );
    if (chosen == null) return;
    await _act(item['id'] as int, 'confirm', data: {'category_id': chosen});
  }

  Future<void> _act(int id, String action, {Map<String, dynamic>? data}) async {
    try {
      await ref.read(apiClientProvider).post('/bank-inbox/$id/$action', data: data ?? {});
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

  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        content: Text(t('bank.delete_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('common.cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('common.delete'), style: TextStyle(color: AppColors.highlight)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(apiClientProvider).delete('/bank-inbox/$id');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('bank.deleted'))),
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
        actions: [
          TextButton(
            onPressed: () => context.push('/bank-inbox/rules'),
            child: Text(t('bank.rules_title')),
          ),
        ],
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ExpansionTile(
              title: Text(t('bank.paste_title')),
              subtitle: Text(t('bank.ios_hint'), style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              children: [
                TextField(
                  controller: _pasteCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(hintText: t('bank.paste_hint')),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () async {
                    await ref.read(apiClientProvider).post('/bank-inbox', data: {
                      'package': _pastePkg,
                      'title': '',
                      'text': _pasteCtrl.text,
                    });
                    _pasteCtrl.clear();
                    await _load();
                  },
                  child: Text(t('bank.paste_send')),
                ),
                const SizedBox(height: 8),
              ],
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
                    Wrap(
                      spacing: 8,
                      runSpacing: 0,
                      children: [
                        FilledButton(
                          onPressed: parsed ? () => _pickAndConfirm(item) : null,
                          child: Text(t('bank.confirm')),
                        ),
                        if (item['internal_suggested'] == true) ...[
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () => _act(
                              item['id'] as int,
                              'confirm',
                              data: {'internal': true, 'pair_id': item['pair_id']},
                            ),
                            child: Text(t('bank.internal')),
                          ),
                        ],
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => _act(item['id'] as int, 'reject'),
                          child: Text(t('bank.reject')),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => _delete(item['id'] as int),
                          child: Text(t('common.delete')),
                        ),
                      ],
                    ),
                  ] else
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => _delete(item['id'] as int),
                        child: Text(t('common.delete')),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
