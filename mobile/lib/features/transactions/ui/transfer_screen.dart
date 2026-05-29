import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/transfer_provider.dart';
import 'widgets/amount_field.dart';

class TransferBalanceScreen extends ConsumerStatefulWidget {
  const TransferBalanceScreen({super.key});
  @override
  ConsumerState<TransferBalanceScreen> createState() =>
      _TransferBalanceScreenState();
}

class _TransferRecipient {
  final int userId;
  final String displayName;
  final TextEditingController amountCtrl;
  _TransferRecipient({
    required this.userId,
    required this.displayName,
    TextEditingController? amountCtrl,
  }) : amountCtrl = amountCtrl ?? TextEditingController();
}

class _TransferBalanceScreenState
    extends ConsumerState<TransferBalanceScreen> {
  List<_TransferRecipient> _recipients = [];
  List<Map<String, dynamic>> _allMembers = [];
  bool _loadingMembers = true;
  late DateTime _selectedDate;
  bool _hasInitialized = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMembers());
  }

  @override
  void dispose() {
    for (final r in _recipients) {
      r.amountCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _loadMembers() async {
    final notifier = ref.read(transferBalanceProvider.notifier);
    final currentUser = ref.read(authProvider).user;
    final members = await notifier.getHouseholdMembers();

    if (!mounted) return;
    setState(() {
      _allMembers = members;
      _loadingMembers = false;
      // Pre-select first row if none yet and there are other members
      if (_recipients.isEmpty && _hasInitialized == false) {
        _hasInitialized = true;
        final others =
            members.where((m) => m['user_id'] != currentUser?.id).toList();
        if (others.isNotEmpty) {
          _addRecipient();
        }
      }
    });
  }

  List<Map<String, dynamic>> get _availableMembers {
    final currentUser = ref.read(authProvider).user;
    final selectedIds = _recipients.map((r) => r.userId).toSet();
    return _allMembers
        .where((m) =>
            m['user_id'] != currentUser?.id && !selectedIds.contains(m['user_id']))
        .toList();
  }

  void _addRecipient() {
    final available = _availableMembers;
    if (available.isEmpty) return;
    // Pick first available
    final member = available.first;
    setState(() {
      _recipients.add(_TransferRecipient(
        userId: member['user_id'] as int,
        displayName: member['display_name'] as String? ?? 'User',
      ));
    });
  }

  void _removeRecipient(int index) {
    setState(() {
      _recipients[index].amountCtrl.dispose();
      _recipients.removeAt(index);
    });
  }

  Future<void> _pickDate() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: isDark
              ? ColorScheme.dark(
                  primary: AppColors.darkPrimary,
                  onPrimary: Colors.white,
                  surface: AppColors.darkSurface,
                )
              : ColorScheme.light(
                  primary: AppColors.primary,
                  onPrimary: Colors.white,
                  surface: AppColors.surface,
                ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _submit() async {
    // Validate: at least one recipient with amount > 0
    final transfers = <Map<String, dynamic>>[];
    for (final r in _recipients) {
      final amount = int.tryParse(r.amountCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
      if (amount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Amount for ${r.displayName} must be > 0'),
          ),
        );
        return;
      }
      transfers.add({'user_id': r.userId, 'amount': amount});
    }

    if (transfers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one recipient')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Confirm Transfer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Date: ${_formatDate(_selectedDate)}'),
            const SizedBox(height: 8),
            for (final t in transfers)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const Icon(Icons.person_outline, size: 16),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${_recipients.firstWhere((r) => r.userId == t['user_id']).displayName}: Rp${_fmtAmount(t['amount'] as int)}',
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text('Rp${_fmtAmount(transfers.fold<int>(0, (s, t) => s + (t['amount'] as int)))}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send Transfer'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final success = await ref.read(transferBalanceProvider.notifier).submit(
      date: _formatDate(_selectedDate),
      transfers: transfers,
    );

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '✅ Transfer successful! ${transfers.length} transaction pair(s) created.'),
        ),
      );
      // Refresh transaction list when we go back
      context.pop(true);
    } else {
      final state = ref.read(transferBalanceProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.error ?? 'Transfer failed')),
      );
    }
  }

  String _fmtAmount(int n) {
    return n.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transferBalanceProvider);
    final currentUser = ref.watch(authProvider).user;
    final isSubmitting = state.isSubmitting;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Transfer Balance'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _loadingMembers
          ? const Center(child: CircularProgressIndicator())
          : _allMembers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.group_off, size: 64, color: AppColors.textSecondary),
                      SizedBox(height: 16),
                      Text('No household members available',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // ── Sender card ──
                    Card(
                      elevation: 0,
                      color: AppColors.surface,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(children: [
                          CircleAvatar(
                            backgroundColor: (currentUser?.displayName ?? '') == 'Nahda'
                                ? Colors.pink.shade100
                                : Colors.blue.shade100,
                            child: Text(
                              (currentUser?.displayName ?? '?')[0]
                                  .toUpperCase(),
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: (currentUser?.displayName ?? '') == 'Nahda'
                                      ? Colors.pink.shade700
                                      : Colors.blue.shade700),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('From',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary)),
                              Text(currentUser?.displayName ?? '-',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16)),
                            ],
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Date picker ──
                    Card(
                      elevation: 0,
                      color: AppColors.surface,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: Icon(Icons.calendar_today,
                            color: AppColors.textPrimary),
                        title: Text(_formatDate(_selectedDate)),
                        trailing: const Icon(Icons.edit_calendar, size: 18),
                        onTap: isSubmitting ? null : _pickDate,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Recipients section ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Recipients',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary)),
                        if (_availableMembers.isNotEmpty)
                          TextButton.icon(
                            onPressed: isSubmitting ? null : _addRecipient,
                            icon: const Icon(Icons.person_add, size: 18),
                            label: const Text('Add'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (_recipients.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(32),
                        alignment: Alignment.center,
                        child: Column(
                          children: [
                            Icon(Icons.person_add_alt_1,
                                size: 48, color: AppColors.textSecondary),
                            const SizedBox(height: 8),
                            Text('Tap "Add" to select a recipient',
                                style: TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),

                    // ── Recipient cards ──
                    ..._recipients.asMap().entries.map((entry) {
                      final i = entry.key;
                      final r = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Card(
                          elevation: 0,
                          color: AppColors.surface,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: r.displayName == 'Nahda'
                                          ? Colors.pink.shade100
                                          : Colors.blue.shade100,
                                      child: Text(
                                        r.displayName[0].toUpperCase(),
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: r.displayName == 'Nahda'
                                                ? Colors.pink.shade700
                                                : Colors.blue.shade700),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(r.displayName,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600)),
                                    ),
                                    if (_recipients.length > 1)
                                      IconButton(
                                        icon: Icon(Icons.close,
                                            size: 18, color: AppColors.textSecondary),
                                        onPressed: isSubmitting
                                            ? null
                                            : () => _removeRecipient(i),
                                        padding: EdgeInsets.zero,
                                        constraints:
                                            const BoxConstraints(minWidth: 32),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                AmountField(controller: r.amountCtrl),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        onPressed:
                            (_recipients.isEmpty || isSubmitting) ? null : _submit,
                        icon: isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.send_rounded),
                        label: Text(isSubmitting
                            ? 'Processing...'
                            : 'Send Transfer'),
                      ),
                    ),

                    if (state.error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                color: Colors.red, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(state.error!,
                                  style: const TextStyle(
                                      color: Colors.red, fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 32),
                  ],
                ),
    );
  }
}
