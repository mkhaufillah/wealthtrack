import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_icons.dart';
import '../../../core/ui/copy_fallback.dart';
import '../../../shared/providers/app_providers.dart';
import '../data/bank_capture.dart';

class BankRulesScreen extends ConsumerStatefulWidget {
  const BankRulesScreen({super.key});

  @override
  ConsumerState<BankRulesScreen> createState() => _BankRulesScreenState();
}

class _BankRulesScreenState extends ConsumerState<BankRulesScreen> {
  List<Map<String, dynamic>> _rules = [];
  List<Map<String, dynamic>> _cats = [];
  Map<String, String> _banks = const {'': ''};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(apiClientProvider);
      final rules = await api.get('/bank-inbox/rules');
      final cats = await api.get('/categories');
      final listen = await BankCapture.getListenPackages();
      final apps = await BankCapture.listApps();
      final labels = <String, String>{};
      for (final a in apps) {
        labels[a['package'].toString()] = a['label'].toString();
      }
      final banks = <String, String>{'': ''};
      for (final pkg in listen) {
        final slug = BankCapture.slugForPackage(pkg);
        banks[slug] = labels[pkg] ?? slug;
      }
      if (!mounted) return;
      setState(() {
        _rules = (rules.data as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _cats = (cats.data as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _banks = banks;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _catName(int id) {
    for (final c in _cats) {
      if (c['id'] == id) return '${c['name']}';
    }
    return '#$id';
  }

  Future<void> _add() async {
    final kw = TextEditingController();
    String bank = '';
    int? catId = _cats.isEmpty ? null : _cats.first['id'] as int?;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(t('bank.rules_add')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: bank,
                  items: _banks.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value.isEmpty ? t('bank.rules_bank_any') : e.value)))
                      .toList(),
                  onChanged: (v) => setLocal(() => bank = v ?? ''),
                ),
                const SizedBox(height: 16),
                TextField(controller: kw, decoration: InputDecoration(labelText: t('bank.rules_keyword'))),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: catId,
                  items: _cats
                      .map((c) => DropdownMenuItem(value: c['id'] as int, child: Text('${c['name']}')))
                      .toList(),
                  onChanged: (v) => setLocal(() => catId = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('common.cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('bank.rules_add'))),
          ],
        ),
      ),
    );
    if (saved != true || catId == null) {
      kw.dispose();
      return;
    }
    try {
      await ref.read(apiClientProvider).post('/bank-inbox/rules', data: {
        'bank': bank.isEmpty ? null : bank,
        'keyword': kw.text.trim(),
        'category_id': catId,
      });
      await _load();
    } finally {
      kw.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(t('bank.rules_title')),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _cats.isEmpty ? null : _add,
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        child: AppIcon(AppIcons.add, size: 22, color: AppColors.onAccent),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rules.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(t('bank.rules_empty'))))
              : ListView(
                  children: _rules
                      .map(
                        (r) => ListTile(
                          title: Text(r['keyword'].toString()),
                          subtitle: Text('${r['bank'] ?? t('bank.rules_bank_any')} → ${_catName(r['category_id'] as int)}'),
                          trailing: IconButton(
                            icon: const AppIcon(AppIcons.trash),
                            onPressed: () async {
                              await ref.read(apiClientProvider).delete('/bank-inbox/rules/${r['id']}');
                              await _load();
                            },
                          ),
                        ),
                      )
                      .toList(),
                ),
    );
  }
}
