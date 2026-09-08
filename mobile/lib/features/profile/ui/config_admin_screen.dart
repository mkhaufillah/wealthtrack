import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/ui/copy_fallback.dart';
import '../../../../core/ui/ui_config.dart';
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

  // Theme swatch presets — preview colors only; backend owns full tokens.
  static const _presetPreviews = {
    'peach': {'light': '#FFF3EE', 'dark': '#2A2430', 'accent': '#F3A6B8'},
    'ocean': {'light': '#EFF6FB', 'dark': '#1C2532', 'accent': '#6FA8DC'},
    'forest': {'light': '#F2F7F1', 'dark': '#1E2A22', 'accent': '#7FBF9F'},
    'rose': {'light': '#FBF3F4', 'dark': '#2B2126', 'accent': '#D9A0B0'},
  };
  String _selectedPreset = 'peach';

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
      Map<String, dynamic>? themeLight;
      Map<String, dynamic>? themeDark;
      for (final item in items) {
        if (item['key'] == 'format') fmt = (item['value'] as Map).cast<String, dynamic>();
        if (item['key'] == 'flags') flags = (item['value'] as Map).cast<String, dynamic>();
        if (item['key'] == 'theme.light') themeLight = (item['value'] as Map).cast<String, dynamic>();
        if (item['key'] == 'theme.dark') themeDark = (item['value'] as Map).cast<String, dynamic>();
      }
      // Match the ACTIVE theme preset so the swatch reflects reality
      // (background tokens are unique per preset).
      final activePreset = _matchPreset(
        themeLight?['background']?.toString(),
        themeDark?['background']?.toString(),
      );
      setState(() {
        _format = fmt;
        _flags = flags;
        _selectedPreset = activePreset;
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
        SnackBar(content: Text(t('common.check_input'))),
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
      // Live-apply format/theme: re-fetch /ui/bootstrap so MoneyFormat and
      // AppColors pick up the new values and root watch rebuilds the app.
      unawaited(ref.read(uiConfigProvider.notifier).load());
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
      // Live-apply format/theme: re-fetch /ui/bootstrap so MoneyFormat and
      // AppColors pick up the new values and root watch rebuilds the app.
      unawaited(ref.read(uiConfigProvider.notifier).load());
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.read(apiClientProvider).handleError(e).toString())),
      );
    }
  }

  Future<void> _saveTheme() async {
    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.put('/ui/config/theme.light', data: {'preset': _selectedPreset});
      await api.put('/ui/config/theme.dark', data: {'preset': _selectedPreset});
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('common.saved_live'))),
      );
      _load();
      // Live-apply format/theme: re-fetch /ui/bootstrap so MoneyFormat and
      // AppColors pick up the new values and root watch rebuilds the app.
      unawaited(ref.read(uiConfigProvider.notifier).load());
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.read(apiClientProvider).handleError(e).toString())),
      );
    }
  }

  /// Maps active light+dark background hex back to the matching preset id.
  /// Defaults to 'peach' when the stored theme is custom / unknown.
  String _matchPreset(String? lightBg, String? darkBg) {
    String normalize(String? h) =>
        (h ?? '').replaceAll('#', '').toUpperCase();
    final l = normalize(lightBg);
    final d = normalize(darkBg);
    for (final entry in _presetPreviews.entries) {
      final preview = entry.value;
      final pl = normalize(preview['light']);
      final pd = normalize(preview['dark']);
      // Match if either active background aligns with a preset's palette.
      if ((l.isNotEmpty && l == pl) || (d.isNotEmpty && d == pd)) {
        return entry.key;
      }
    }
    return 'peach';
  }

  Widget _themeSwatch(String preset) {
    final preview = _presetPreviews[preset]!;
    Color parse(String hex) => Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);
    final selected = _selectedPreset == preset;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _selectedPreset = preset),
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.divider,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(preset,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 18, height: 18,
                  decoration: BoxDecoration(
                    color: parse(preview['light']!),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.divider),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  width: 18, height: 18,
                  decoration: BoxDecoration(
                    color: parse(preview['dark']!),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.divider),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              width: 26, height: 5,
              decoration: BoxDecoration(
                color: parse(preview['accent']!),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ],
        ),
      ),
    );
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
                    _card(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t('profile.config_theme'),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(
                            t('profile.config_theme_hint'),
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _presetPreviews.keys
                                .map((p) => _themeSwatch(p))
                                .toList(),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _saving ? null : _saveTheme,
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
                  ],
                ),
    );
  }
}