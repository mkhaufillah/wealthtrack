import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/copy_fallback.dart';
import '../data/bank_capture.dart';

class BankListenAppsScreen extends ConsumerStatefulWidget {
  const BankListenAppsScreen({super.key});

  @override
  ConsumerState<BankListenAppsScreen> createState() => _BankListenAppsScreenState();
}

class _BankListenAppsScreenState extends ConsumerState<BankListenAppsScreen> {
  List<Map<String, dynamic>> _apps = [];
  final Set<String> _selected = {};
  String _q = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apps = await BankCapture.listApps();
    final listen = await BankCapture.getListenPackages();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _selected
        ..clear()
        ..addAll(listen);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _q.isEmpty
        ? _apps
        : _apps.where((a) {
            final blob = '${a['label']} ${a['package']}'.toLowerCase();
            return blob.contains(_q.toLowerCase());
          }).toList();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(t('bank.listen_apps')),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: () async {
              await BankCapture.setListenPackages(_selected.toList());
              if (mounted) Navigator.pop(context);
            },
            child: Text(t('bank.listen_save')),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    children: [
                      Text(t('bank.listen_hint'), style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      const SizedBox(height: 8),
                      TextField(
                        decoration: InputDecoration(hintText: t('bank.listen_search')),
                        onChanged: (v) => setState(() => _q = v),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final app = filtered[i];
                      final pkg = app['package'].toString();
                      final on = _selected.contains(pkg);
                      return CheckboxListTile(
                        value: on,
                        activeColor: AppColors.accent,
                        checkColor: AppColors.onAccent,
                        side: BorderSide(color: AppColors.textPrimary, width: 1.6),
                        fillColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) return AppColors.accent;
                          return AppColors.background;
                        }),
                        title: Text(app['label'].toString()),
                        subtitle: Text(pkg, style: const TextStyle(fontSize: 11)),
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selected.add(pkg);
                            } else {
                              _selected.remove(pkg);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
