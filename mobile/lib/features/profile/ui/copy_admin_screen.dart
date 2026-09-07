import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/ui/copy_fallback.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/ui/app_icons.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../core/network/api_client.dart';

/// Admin panel: browse + edit ui_copy via /ui/copy (server-driven copy).
/// Visible only for role=admin; errors come straight from the backend (ID).
class CopyAdminScreen extends ConsumerStatefulWidget {
  const CopyAdminScreen({super.key});

  @override
  ConsumerState<CopyAdminScreen> createState() => _CopyAdminScreenState();
}

class _CopyAdminScreenState extends ConsumerState<CopyAdminScreen> {
  final _searchCtrl = TextEditingController();
  List<Map<String, String>> _items = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get('/ui/copy', queryParams: {
        if (_query.isNotEmpty) 'search': _query,
      });
      if (!mounted) return;
      final data = res.data as Map<String, dynamic>;
      setState(() {
        _items = (data['items'] as List)
            .map((e) => {
                  'key': (e as Map)['key'].toString(),
                  'value': e['value'].toString(),
                })
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

  Future<void> _edit(Map<String, String> item) async {
    final valueCtrl = TextEditingController(text: item['value']);
    final key = item['key']!;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(key, style: const TextStyle(fontSize: 16)),
        content: TextField(
          controller: valueCtrl,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: t('common.empty'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('common.save')),
          ),
        ],
      ),
    );
    if (saved != true) return;

    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.put('/ui/copy/$key', data: {'value': valueCtrl.text});
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t('profile.copy_admin')),
        backgroundColor: AppColors.surface,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: (v) {
                _query = v.trim();
                _load();
              },
              decoration: InputDecoration(
                hintText: t('profile.copy_search'),
                prefixIcon: const AppIcon(AppIcons.search, size: 18),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const AppIcon(AppIcons.close, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _query = '';
                          _load();
                        },
                      ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
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
          t('common.empty'),
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return ListView.builder(
      itemCount: _items.length,
      itemBuilder: (ctx, i) {
        final item = _items[i];
        return Card(
          elevation: 0,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          color: AppColors.surface,
          child: ListTile(
            title: Text(
              item['key']!,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              item['value']!,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            trailing: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const AppIcon(AppIcons.edit, size: 18),
            onTap: _saving ? null : () => _edit(item),
          ),
        );
      },
    );
  }
}