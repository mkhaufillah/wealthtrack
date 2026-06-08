import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../models/credit_card_model.dart';

class CreditCardState {
  final bool isLoading;
  final String? error;
  final List<CreditCardModel> cards;
  final CreditCardModel? selectedCard;
  final NextMonthProjection? projection;

  const CreditCardState({
    this.isLoading = false,
    this.error,
    this.cards = const [],
    this.selectedCard,
    this.projection,
  });

  CreditCardState copyWith({
    bool? isLoading,
    String? error,
    List<CreditCardModel>? cards,
    CreditCardModel? selectedCard,
    NextMonthProjection? projection,
    bool clearError = false,
  }) =>
      CreditCardState(
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
        cards: cards ?? this.cards,
        selectedCard: selectedCard ?? this.selectedCard,
        projection: projection ?? this.projection,
      );
}

class CreditCardNotifier extends StateNotifier<CreditCardState> {
  final ApiClient _api;

  CreditCardNotifier(this._api) : super(const CreditCardState());

  Future<void> loadCards() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await _api.get('/credit-cards');
      final list = (res.data as List)
          .map((e) => CreditCardModel.fromJson(e as Map<String, dynamic>))
          .toList();
      state = state.copyWith(isLoading: false, cards: list);
    } catch (e) {
      state = state.copyWith(
          isLoading: false, error: _api.handleError(e).toString());
    }
  }

  Future<void> loadCardDetail(int id) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await _api.get('/credit-cards/$id');
      final card =
          CreditCardModel.fromJson(res.data as Map<String, dynamic>);
      state = state.copyWith(isLoading: false, selectedCard: card);
    } catch (e) {
      state = state.copyWith(
          isLoading: false, error: _api.handleError(e).toString());
    }
  }

  Future<bool> createCard(Map<String, dynamic> data) async {
    try {
      final res = await _api.post('/credit-cards', data: data);
      final card =
          CreditCardModel.fromJson(res.data as Map<String, dynamic>);
      state = state.copyWith(
        cards: [...state.cards, card],
        selectedCard: card,
      );
      return true;
    } catch (e) {
      state = state.copyWith(error: _api.handleError(e).toString());
      return false;
    }
  }

  Future<bool> deleteCard(int id) async {
    try {
      await _api.delete('/credit-cards/$id');
      state = state.copyWith(
        cards: state.cards.where((c) => c.id != id).toList(),
        selectedCard:
            state.selectedCard?.id == id ? null : state.selectedCard,
      );
      return true;
    } catch (e) {
      state = state.copyWith(error: _api.handleError(e).toString());
      return false;
    }
  }

  Future<bool> addTransaction(int cardId, Map<String, dynamic> data) async {
    try {
      await _api.post('/credit-cards/$cardId/transactions', data: data);
      // Refresh detail to get updated transactions/installments
      await loadCardDetail(cardId);
      return true;
    } catch (e) {
      state = state.copyWith(error: _api.handleError(e).toString());
      return false;
    }
  }

  Future<bool> addInstallment(int cardId, Map<String, dynamic> data) async {
    try {
      await _api.post('/credit-cards/$cardId/installments', data: data);
      await loadCardDetail(cardId);
      await loadProjection();
      return true;
    } catch (e) {
      state = state.copyWith(error: _api.handleError(e).toString());
      return false;
    }
  }


  Future<bool> deleteInstallment(int cardId, int instId) async {
    try {
      await _api.delete('/credit-cards/$cardId/installments/$instId');
      await loadCardDetail(cardId);
      return true;
    } catch (e) {
      state = state.copyWith(error: _api.handleError(e).toString());
      return false;
    }
  }

  Future<void> loadProjection() async {
    try {
      final res = await _api.get('/credit-cards/next-month-projection');
      final projection =
          NextMonthProjection.fromJson(res.data as Map<String, dynamic>);
      state = state.copyWith(projection: projection);
    } catch (e) {
      state = state.copyWith(error: _api.handleError(e).toString());
    }
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  void clearSelection() {
    state = state.copyWith(selectedCard: null);
  }
}

final creditCardProvider =
    StateNotifierProvider<CreditCardNotifier, CreditCardState>((ref) {
  final api = ref.watch(apiClientProvider);
  return CreditCardNotifier(api);
});
