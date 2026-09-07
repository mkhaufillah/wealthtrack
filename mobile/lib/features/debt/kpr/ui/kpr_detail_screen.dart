import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../core/ui/copy_fallback.dart';
import '../../../../core/ui/app_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../providers/kpr_provider.dart';
import '../../models/kpr_model.dart';
import '../../../../shared/utils/currency_formatter.dart';
import '../../../../shared/widgets/loading_indicator.dart';
import '../../../../shared/widgets/error_display.dart';
import '../../../../core/theme/app_theme.dart';

class KPRDetailScreen extends ConsumerStatefulWidget {
  final int simulationId;
  const KPRDetailScreen({super.key, required this.simulationId});

  @override
  ConsumerState<KPRDetailScreen> createState() => _KPRDetailScreenState();
}

class _KPRDetailScreenState extends ConsumerState<KPRDetailScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(kprProvider.notifier).loadDetail(widget.simulationId);
      ref.read(kprProvider.notifier).loadExtraPayments(widget.simulationId);
    });
  }

  Future<void> _onRefresh() async {
    await ref.read(kprProvider.notifier).loadDetail(widget.simulationId);
  }

  Future<void> _confirmDelete(KPRSimulation sim) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(t('kpr.delete')),
        content: Text(
          'Hapus "${sim.name.isEmpty ? 'simulasi ini' : sim.name}"? Gak bisa dibalikin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Hapus', style: TextStyle(color: AppColors.highlight)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await ref.read(kprProvider.notifier).delete(sim.id);
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Simulasi kehapus')),
          );
          context.pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gagal hapus simulasi')),
          );
        }
      }
    }
  }

  Future<void> _confirmDeleteExtraPayment(ExtraPaymentRecord ep) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(t('kpr.extra')),
        content: Text(
          'Hapus pembayaran ekstra ${formatCurrency(ep.amount)} di bulan ke-${ep.applyMonth}? '
          'Jadwalnya dihitung ulang. Gak bisa dibalikin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Hapus', style: TextStyle(color: AppColors.highlight)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await ref
          .read(kprProvider.notifier)
          .deleteExtraPayment(ep.simulationId, ep.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Pembayaran ekstra kehapus'
                  : 'Gagal hapus pembayaran ekstra',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(kprProvider);
    final sim = state.selectedSimulation;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(sim?.name.isNotEmpty == true ? sim!.name : 'Detail KPR'),
        actions: [
          if (sim != null)
            IconButton(
              icon: AppIcon(AppIcons.money),
              tooltip: 'Pembayaran ekstra',
              onPressed: () => context.push(
                  '/debt/kpr/${sim.id}/extra-payment'),
            ),
          if (sim != null)
            IconButton(
              icon: AppIcon(AppIcons.trash),
              tooltip: 'Hapus',
              onPressed: () => _confirmDelete(sim),
            ),
        ],
      ),
      body: state.isLoading && sim == null
          ? const LoadingIndicator()
          : state.error != null && sim == null
              ? ErrorDisplay(
                  message: state.error!,
                  onRetry: _onRefresh,
                )
              : sim == null
                  ? const ErrorDisplay(message: 'Simulasi gak ketemu')
                  : RefreshIndicator(
                      onRefresh: _onRefresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                        children: [
                          _buildSummaryCards(sim),
                          const SizedBox(height: 16),
                          _buildExtraPaymentSection(sim, state),
                          const SizedBox(height: 16),
                          _buildScheduleSection(sim),
                        ],
                      ),
                    ),
    );
  }

  // ─── Summary Cards ──────────────────────────────────────

  Widget _buildSummaryCards(KPRSimulation sim) {
    final monthlyPayment = sim.summary?['monthly_payment'] as int? ??
        _estimateMonthlyPaymentFromSchedule(sim.schedule);
    final totalInterest = sim.summary?['total_interest'] as int? ??
        _totalInterestFromSchedule(sim.schedule, sim.totalLoan);
    final totalPayment = sim.summary?['total_payment'] as int? ??
        (sim.schedule != null
            ? sim.schedule!.fold<int>(0, (s, m) => s + m.payment)
            : 0);

    return Column(
      children: [
        // ── First row: Property Price ───────────────
        _buildSummaryCard(
          icon: Icons.home_outlined,
          label: 'Harga rumah',
          value: formatCurrency(sim.propertyPrice),
        ),
        const SizedBox(height: 10),

        // ── Second row: Loan Amount + Monthly Payment ──
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                icon: Icons.account_balance_outlined,
                label: 'Pinjaman',
                value: formatCurrency(sim.totalLoan),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildSummaryCard(
                icon: Icons.payments_outlined,
                label: 'Cicilan / bulan',
                value: formatCurrency(monthlyPayment),
                accent: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ── Third row: Total Interest + Total Payment ──
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                icon: Icons.trending_up,
                label: 'Total bunga',
                value: formatCurrency(totalInterest),
                valueColor: AppColors.highlight,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildSummaryCard(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Total bayar',
                value: formatCurrency(totalPayment),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ── Info row: Tenor + Interest Type ─────────
        _buildInfoRow(sim),
      ],
    );
  }

  Widget _buildSummaryCard({
    required IconData icon,
    required String label,
    required String value,
    bool accent = false,
    Color? valueColor,
    
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: accent
            ? Border.all(color: AppColors.accent.withOpacity(0.3), width: 1.5)
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (accent ? AppColors.accent : AppColors.textSecondary).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 18,
              color: accent ? AppColors.accent : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: valueColor ?? AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(KPRSimulation sim) {
    final years = sim.tenorMonths ~/ 12;
    final remMonths = sim.tenorMonths % 12;
    String tenorLabel;
    if (years > 0 && remMonths > 0) {
      tenorLabel = '$years years ${remMonths}mo';
    } else if (years > 0) {
      tenorLabel = '$years years';
    } else {
      tenorLabel = '${sim.tenorMonths} months';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          AppIcon(AppIcons.calendar, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Text(
            tenorLabel,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const Spacer(),
          _buildInterestBadge(sim.interestType),
        ],
      ),
    );
  }

  Widget _buildInterestBadge(String interestType) {
    final label = kprInterestLabel(interestType);
    Color bgColor;
    Color textColor;
    switch (interestType.toLowerCase()) {
      case 'fixed':
        bgColor = AppColors.success.withOpacity(0.12);
        textColor = AppColors.success;
        break;
      case 'floating':
        bgColor = AppColors.warning.withOpacity(0.12);
        textColor = AppColors.warning;
        break;
      case 'graduated':
        bgColor = AppColors.accent.withOpacity(0.12);
        textColor = AppColors.accent;
        break;
      case 'mix':
        bgColor = AppColors.highlight.withOpacity(0.12);
        textColor = AppColors.highlight;
        break;
      default:
        bgColor = AppColors.textSecondary.withOpacity(0.12);
        textColor = AppColors.textSecondary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor),
      ),
    );
  }

  // ─── Extra Payment Section ──────────────────────────────

  Widget _buildExtraPaymentSection(
      KPRSimulation sim, KPRState state) {
    final extras = state.extraPayments;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppIcon(AppIcons.money,
                size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Text(
              'Pembayaran ekstra',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            if (extras.isNotEmpty)
              Text(
                '${extras.length} catatan',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        if (extras.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.divider.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                AppIcon(AppIcons.info,
                    size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Belum ada pembayaran ekstra. Tap ikon uang di atas buat nambah.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          ...extras.map((ep) => _buildExtraPaymentCard(ep, sim)),
      ],
    );
  }

  Widget _buildExtraPaymentCard(ExtraPaymentRecord ep, KPRSimulation sim) {
    final isTenor = ep.reductionType == 'tenor';
    final monthsSaved = ep.oldRemainingMonths - ep.newRemainingMonths;
    final paymentDiff = ep.oldInstallment - ep.newInstallment;

    // Calculate the actual start date of the extra payment's apply month
    final startMonth = sim.startMonth;
    final startYear = sim.startYear;
    final totalMonths = startMonth + ep.applyMonth - 1;
    final applyYear = startYear + (totalMonths - 1) ~/ 12;
    final applyMonthDate = ((totalMonths - 1) % 12) + 1;
    final monthNames = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
    ];
    final startDateStr = '${monthNames[applyMonthDate]} $applyYear';
    // Convert "2040-12" → "Dec 2040"
    String _fmtEndDate(String yyyyMm) {
      if (yyyyMm.isEmpty) return '';
      final parts = yyyyMm.split('-');
      if (parts.length < 2) return yyyyMm;
      final m = int.tryParse(parts[1]);
      if (m == null || m < 1 || m > 12) return yyyyMm;
      return '${monthNames[m]} ${parts[0]}';
    }
    final endDateStr = _fmtEndDate(ep.newEndDate.isNotEmpty ? ep.newEndDate : ep.originalEndDate);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isTenor
              ? AppColors.accent.withOpacity(0.3)
              : AppColors.success.withOpacity(0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: (isTenor ? AppColors.accent : AppColors.success)
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isTenor
                        ? Icons.timer_outlined
                        : Icons.trending_down,
                    size: 16,
                    color:
                        isTenor ? AppColors.accent : AppColors.success,
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isTenor
                          ? 'Tenor lebih pendek'
                          : 'Cicilan lebih kecil',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Bulan ke-${ep.applyMonth} • ${formatCurrency(ep.amount)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  '${_fmtDate(ep.createdAt)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                PopupMenuButton<String>(
                  icon: AppIcon(AppIcons.more,
                      size: 18, color: AppColors.textSecondary),
                  padding: EdgeInsets.zero,
                  onSelected: (value) {
                    if (value == 'delete') {
                      _confirmDeleteExtraPayment(ep);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          AppIcon(AppIcons.trash, size: 18),
                          SizedBox(width: 8),
                          Text('Hapus'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Divider(height: 24, color: AppColors.divider),
            Row(
              children: [
                Expanded(
                  child: _statItem(
                      'Cicilan',
                      '${formatCurrency(ep.oldInstallment)} → ${formatCurrency(ep.newInstallment)}'),
                ),
                Expanded(
                  child: _statItem(
                    'Sisa tenor',
                    '${ep.oldRemainingMonths} → ${ep.newRemainingMonths} bln',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _statItem(
                    'Lunas',
                    '${ep.originalEndDate} → ${ep.newEndDate}',
                  ),
                ),
                Expanded(
                  child: _statItem(
                    'Bunga dihemat',
                    formatCurrency(ep.totalInterestSaving),
                    highlight: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.accent.withOpacity(0.15),
                ),
              ),
              child: Text(
                'Hitungan cicilan & tenor baru mulai $startDateStr — $endDateStr',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.accent,
                  height: 1.4,
                ),
              ),
            ),
            if (monthsSaved > 0 || paymentDiff > 0) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (isTenor
                          ? AppColors.accent
                          : AppColors.success)
                      .withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isTenor
                      ? 'Lunas $monthsSaved bulan lebih cepet 🎯'
                      : 'Cicilan turun ${formatCurrency(paymentDiff)}/bulan 💰',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isTenor
                        ? AppColors.accent
                        : AppColors.success,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statItem(String label, String value, {bool highlight = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: highlight ? AppColors.accent : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  String _fmtDate(String iso) {
    if (iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return iso.length > 10 ? iso.substring(0, 10) : iso;
    }
  }

  // ─── Schedule Section ──────────────────────────────────

  Widget _buildScheduleSection(KPRSimulation sim) {
    final schedule = sim.schedule;
    if (schedule == null || schedule.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Column(
            children: [
              AppIcon(AppIcons.chart, size: 40, color: AppColors.textSecondary.withOpacity(0.4)),
              const SizedBox(height: 12),
              Text(
                'No schedule data available',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Group by year (12-month chunks)
    final Map<int, List<KPRScheduleItem>> yearMap = {};
    for (final item in schedule) {
      final yearIndex = (item.monthNumber - 1) ~/ 12;
      yearMap.putIfAbsent(yearIndex, () => []);
      yearMap[yearIndex]!.add(item);
    }

    final yearKeys = yearMap.keys.toList()..sort();

    final now = DateTime.now();
    final startMonth = sim.startMonth;
    final startYear = sim.startYear;
    final startTotalMonths = startYear * 12 + (startMonth - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppIcon(AppIcons.calendar, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Text(
              'Jadwal cicilan',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...yearKeys.map((yearIdx) {
          final items = yearMap[yearIdx]!;
          return _buildYearTile(yearIdx, items, startTotalMonths, now);
        }),
      ],
    );
  }

  Widget _buildYearTile(
    int yearIndex,
    List<KPRScheduleItem> items,
    int startTotalMonths,
    DateTime now,
  ) {
    final yearNumber = yearIndex + 1;
    final totalYearPayment = items.fold<int>(0, (s, m) => s + m.payment);
    final totalYearInterest = items.fold<int>(0, (s, m) => s + m.interest);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.divider.withOpacity(0.3)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: AppColors.divider,
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: AppColors.accent,
          ),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          shape: const Border(),
          collapsedShape: const Border(),
          title: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '$yearNumber',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tahun $yearNumber',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${items.length} bulan',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatCurrency(totalYearPayment),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Bunga: ${formatCurrency(totalYearInterest)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.highlight,
                    ),
                  ),
                ],
              ),
            ],
          ),
          children: [
            // ── Table header ──
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: BoxDecoration(
                color: AppColors.background.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  _tableHeader('Bln', flex: 1),
                  _tableHeader('Cicilan', flex: 2),
                  _tableHeader('Pokok', flex: 2),
                  _tableHeader('Bunga', flex: 2),
                  _tableHeader('Sisa', flex: 2),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // ── Table rows ──
            ...items.map((item) {
              final itemTotalMonths = startTotalMonths + (item.monthNumber - 1);
              final itemYear = itemTotalMonths ~/ 12;
              final itemMonth = itemTotalMonths % 12 + 1;
              final isCurrentMonth = itemYear == now.year && itemMonth == now.month;

              return Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                decoration: BoxDecoration(
                  color: isCurrentMonth
                      ? AppColors.accent.withOpacity(0.08)
                      : null,
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.divider.withOpacity(0.2),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    _tableCell('${_shortMonthName(itemMonth)} $itemYear', flex: 1, bold: isCurrentMonth),
                    _tableCell(formatCurrency(item.payment), flex: 2),
                    _tableCell(formatCurrency(item.principal), flex: 2),
                    _tableCell(formatCurrency(item.interest), flex: 2,
                        color: AppColors.highlight),
                    _tableCell(formatCurrency(item.remainingBalance), flex: 2),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _tableHeader(String label, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _tableCell(String text, {int flex = 1, bool bold = false, Color? color}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: color ?? AppColors.textPrimary,
        ),
      ),
    );
  }

  // ─── Helper: estimate from schedule if summary not available ───

  int _estimateMonthlyPaymentFromSchedule(List<KPRScheduleItem>? schedule) {
    if (schedule == null || schedule.isEmpty) return 0;
    // Average first 12 months
    final count = schedule.length > 12 ? 12 : schedule.length;
    int sum = 0;
    for (int i = 0; i < count; i++) {
      sum += schedule[i].payment;
    }
    return (sum / count).round();
  }

  int _totalInterestFromSchedule(List<KPRScheduleItem>? schedule, int totalLoan) {
    if (schedule == null || schedule.isEmpty) return 0;
    final totalPaid = schedule.fold<int>(0, (s, m) => s + m.payment);
    return totalPaid - totalLoan;
  }

  String _shortMonthName(int m) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
                    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    return months[m - 1];
  }
}
