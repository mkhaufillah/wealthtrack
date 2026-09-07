import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/ui/copy_fallback.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_icons.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../core/network/api_client.dart';

/// Admin panel: edit ui_config (format + flags) via /ui/config.
/// Theme tokens are deliberately read-only — editing them needs contrast
/// validation, so a raw JSON editor is not exposed.
class ConfigAdminScreen extends ConsumerStatefulWidget {
  const ConfigAdminScreen({super.key});

  @override
  ConsumerState<ConfigAdminScreen> createState() => _ConfigAdminScreenState();
}

class _ConfigAdminScreenState extends ConsumerState<ConfigAdminScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  Map<String, dynamic>? _format;
  Map<String, dynamic>? _flags;

  final _prefixCtrl = TextEditingController();
  final _groupSepCtrl = TextEditingController();
  final _decimalSepCtrl = TextEditingController();
  final _flagHomeAllTimeCtrl = TextEditingController(text: 'true');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _prefixCtrl.dispose();
    _groupSepCtrl.dispose();
    _decimalSepCtrl.dispose();
    _flagHomeAllTimeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get('/ui/config');
      if (!mounted) return;
      final data = res.data as Map<String, dynamic>;
      final items = (data['items'] as List)
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      Map<String, dynamic>? fmt;
      Map<String, dynamic>? flags;
      for (final item in items) {
        if (item['key'] == 'format') fmt = (item['value'] as Map).cast<String, dynamic>();
        if (item['key'] == 'flags') flags = (item['value'] as Map).cast<String, dynamic>();
      }
      setState(() {
        _format = fmt;
        _flags = flags;
        _prefixCtrl.text = fmt?['currency_prefix']?.toString() ?? 'Rp';
        _groupSepCtrl.text = fmt?['group_sep']?.toString() ?? '.';
        _decimalSepCtrl.text = fmt?['decimal_sep']?.toString() ?? ',';
        _flagHomeAllTimeCtrl.text = (flags?['home_all_time'] ?? true).toString();
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

  Future<void> _saveFormat() async {
    final prefix = _prefixCtrl.text.trim();
    final group = _groupSepCtrl.text.trim();
    final decimal = _decimalSepCtrl.text.trim();
    if (prefix.isEmpty || group.isEmpty || decimal.isEmpty || group == decimal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cek lagi isiannya ya.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      final currency = _format?['currency']?.toString() ?? 'IDR';
      await api.put('/ui/config/format', data: {
        'value': {
          'currency': currency,
          'currency_prefix': prefix,
          'group_sep': group,
          'decimal_sep': decimal,
        },
      });
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('common.saved_live'))),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.read(apiClientProvider).handleError(e).toString())),
      );
    }
  }

  Future<void> _saveFlags() async {
    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.put('/ui/config/flags', data: {
        'value': {
          'home_all_time': _flagHomeAllTimeCtrl.text.trim().toLowerCase() == 'true',
        },
      });
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('common.saved_live'))),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.read(apiClientProvider).handleError(e).toString())),
      );
    }
  }

  Widget _card(Widget child) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: AppColors.surface,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  Widget _fieldLabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 12),
        child: Text(label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t('profile.config_admin')),
        backgroundColor: AppColors.surface,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, style: TextStyle(color: AppColors.highlight)),
                  ),
                )
              : ListView(
                  children: [
                    _card(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t('profile.config_format'),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          _fieldLabel(t('profile.config_prefix')),
                          TextField(controller: _prefixCtrl, decoration: const InputDecoration(hintText: 'Rp')),
                          _fieldLabel(t('profile.config_group')),
                          TextField(controller: _groupSepCtrl, decoration: const InputDecoration(hintText: '.')),
                          _fieldLabel(t('profile.config_decimal')),
                          TextField(controller: _decimalSepCtrl, decoration: const InputDecoration(hintText: ',')),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _saving ? null : _saveFormat,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.accent,
                                foregroundColor: AppColors.onAccent,
                              ),
                              child: _saving
                                  ? const SizedBox(
                                      width: 20, height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : Text(t('common.save')),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _card(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t('profile.config_flags'),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          _fieldLabel(t('profile.config_home_flag')),
                          TextField(controller: _flagHomeAllTimeCtrl,
                              decoration: const InputDecoration(hintText: 'true / false')),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _saving ? null : _saveFlags,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.accent,
                                foregroundColor: AppColors.onAccent,
                              ),
                              child: _saving
                                  ? const SizedBox(
                                      width: 20, height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : Text(t('common.save')),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        t('profile.config_theme_locked'),
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
    );
  }
}