import 'package:flutter_riverpod/flutter_riverpod.dart';

class BudgetScreenNavigationState {
  final DateTime currentMonth;
  final String cycleLabel;
  final int userCycleDay;
  final String? cycleDateFrom;
  final String? cycleDateTo;

  const BudgetScreenNavigationState({
    required this.currentMonth,
    this.cycleLabel = '',
    this.userCycleDay = 1,
    this.cycleDateFrom,
    this.cycleDateTo,
  });

  BudgetScreenNavigationState copyWith({
    DateTime? currentMonth,
    String? cycleLabel,
    int? userCycleDay,
    String? cycleDateFrom,
    String? cycleDateTo,
  }) =>
      BudgetScreenNavigationState(
        currentMonth: currentMonth ?? this.currentMonth,
        cycleLabel: cycleLabel ?? this.cycleLabel,
        userCycleDay: userCycleDay ?? this.userCycleDay,
        cycleDateFrom: cycleDateFrom ?? this.cycleDateFrom,
        cycleDateTo: cycleDateTo ?? this.cycleDateTo,
      );
}

final budgetNavigationProvider =
    StateProvider<BudgetScreenNavigationState>((ref) {
  return BudgetScreenNavigationState(
    currentMonth: DateTime(DateTime.now().year, DateTime.now().month),
  );
});
