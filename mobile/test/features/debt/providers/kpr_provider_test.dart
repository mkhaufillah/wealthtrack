import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wealthtrack/features/debt/kpr/providers/kpr_provider.dart';
import 'package:wealthtrack/features/debt/models/kpr_model.dart';
import 'package:wealthtrack/shared/providers/app_providers.dart';
import '../../../helpers/mocks.dart';

void main() {
  group('KPRNotifier', () {
    late MockApiClient mockApi;
    late ProviderContainer container;
    late KPRNotifier notifier;

    setUp(() {
      mockApi = MockApiClient();
      container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(mockApi),
      ]);
      notifier = container.read(kprProvider.notifier);
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is correct', () {
      expect(notifier.state.isLoading, false);
      expect(notifier.state.error, isNull);
      expect(notifier.state.simulations, isEmpty);
      expect(notifier.state.selectedSimulation, isNull);
    });

    group('loadAll', () {
      test('loads simulations list successfully', () async {
        mockApi.onGet('/kpr/simulations', [
          {
            'id': 1,
            'user_id': 1,
            'name': 'Rumah Impian',
            'property_price': 1000000000,
            'down_payment': 200000000,
            'total_loan': 800000000,
            'tenor_months': 120,
            'interest_type': 'fixed',
            'created_at': '2026-06-09T10:00:00Z',
            'total_interest': 300000000,
            'monthly_payment': 6666667,
            'start_month': 6,
            'start_year': 2026,
            'current_month_number': 1,
            'current_month_payment': 6666667,
            'current_remaining_balance': 793333333,
          },
        ]);

        await notifier.loadAll();

        expect(notifier.state.isLoading, false);
        expect(notifier.state.error, isNull);
        expect(notifier.state.simulations.length, 1);
        expect(notifier.state.simulations[0].name, 'Rumah Impian');
        expect(notifier.state.simulations[0].id, 1);
      });

      test('sets loading state during fetch', () async {
        mockApi.onGet('/kpr/simulations', []);
        final future = notifier.loadAll();

        expect(notifier.state.isLoading, true);

        await future;
      });

      test('sets error on failure when response is not a list', () async {
        // No mock set up → empty Map response fails to cast as List
        await notifier.loadAll();

        expect(notifier.state.isLoading, false);
        expect(notifier.state.error, isNotNull);
        expect(notifier.state.simulations, isEmpty);
      });
    });

    group('loadDetail', () {
      test('loads simulation detail successfully', () async {
        mockApi.onGet('/kpr/simulations/1', {
          'id': 1,
          'user_id': 1,
          'name': 'Detail Sim',
          'property_price': 500000000,
          'down_payment': 100000000,
          'total_loan': 400000000,
          'tenor_months': 60,
          'interest_type': 'fixed',
          'created_at': '2026-06-09T10:00:00Z',
          'start_year': 2026,
        });

        await notifier.loadDetail(1);

        expect(notifier.state.isLoading, false);
        expect(notifier.state.error, isNull);
        expect(notifier.state.selectedSimulation, isNotNull);
        expect(notifier.state.selectedSimulation!.name, 'Detail Sim');
        expect(notifier.state.selectedSimulation!.id, 1);
      });

      test('sets error on detail fetch failure', () async {
        // No mock → empty Map response → fromJson fails on missing 'id' cast
        await notifier.loadDetail(1);

        expect(notifier.state.isLoading, false);
        expect(notifier.state.error, isNotNull);
        expect(notifier.state.selectedSimulation, isNull);
      });
    });

    group('create', () {
      KPRSimulation createdSimulation(KPRNotifier n) =>
          n.state.selectedSimulation!;

      test('creates simulation and adds to list', () async {
        mockApi.onPost('/kpr/simulations', {
          'id': 1,
          'user_id': 1,
          'name': 'New Sim',
          'property_price': 1000000000,
          'down_payment': 200000000,
          'total_loan': 800000000,
          'tenor_months': 120,
          'interest_type': 'fixed',
          'created_at': '2026-06-09T10:00:00Z',
        });

        final result = await notifier.create({
          'name': 'New Sim',
          'property_price': 1000000000,
          'down_payment': 200000000,
          'tenor_months': 120,
          'interest_type': 'fixed',
        });

        expect(result, true);
        expect(notifier.state.selectedSimulation, isNotNull);
        expect(notifier.state.selectedSimulation!.name, 'New Sim');
        expect(notifier.state.simulations.length, 1);
        expect(notifier.state.simulations[0].name, 'New Sim');
      });

      test('returns false on creation failure', () async {
        // No mock → empty Map response → fromJson fails
        final result = await notifier.create({
          'name': 'Fail Sim',
        });

        expect(result, false);
        expect(notifier.state.error, isNotNull);
      });

      test('appends multiple simulations to list', () async {
        mockApi.onPost('/kpr/simulations', {
          'id': 1,
          'user_id': 1,
          'name': 'First',
          'created_at': '2026-01-01T00:00:00Z',
        });
        await notifier.create({'name': 'First'});
        expect(notifier.state.simulations.length, 1);

        // Override mock response for second call
        mockApi.onPost('/kpr/simulations', {
          'id': 2,
          'user_id': 1,
          'name': 'Second',
          'created_at': '2026-02-01T00:00:00Z',
        });
        await notifier.create({'name': 'Second'});

        expect(notifier.state.simulations.length, 2);
        expect(notifier.state.simulations[0].name, 'First');
        expect(notifier.state.simulations[1].name, 'Second');
      });
    });

    group('delete', () {
      test('deletes simulation and removes from list', () async {
        // Seed a simulation
        mockApi.onPost('/kpr/simulations', {
          'id': 1,
          'user_id': 1,
          'name': 'To Delete',
          'created_at': '2026-06-09T10:00:00Z',
        });
        await notifier.create({'name': 'To Delete'});
        expect(notifier.state.simulations.length, 1);

        mockApi.onDelete('/kpr/simulations/1');
        final result = await notifier.delete(1);

        expect(result, true);
        expect(notifier.state.simulations, isEmpty);
      });

      test('clears selectedSimulation when deleting active selection', () async {
        mockApi.onPost('/kpr/simulations', {
          'id': 1,
          'user_id': 1,
          'name': 'Selected',
          'created_at': '2026-06-09T10:00:00Z',
        });
        await notifier.create({'name': 'Selected'});
        expect(notifier.state.selectedSimulation, isNotNull);

        mockApi.onDelete('/kpr/simulations/1');
        await notifier.delete(1);

        expect(notifier.state.selectedSimulation, isNull);
      });

      test('does not clear selectedSimulation when deleting different id', () async {
        mockApi.onPost('/kpr/simulations', {
          'id': 1,
          'user_id': 1,
          'name': 'Keep',
          'created_at': '2026-06-09T10:00:00Z',
        });
        await notifier.create({'name': 'Keep'});

        // Select a different one via loadDetail
        mockApi.onGet('/kpr/simulations/2', {
          'id': 2,
          'user_id': 1,
          'name': 'Other',
          'created_at': '2026-06-09T10:00:00Z',
        });
        await notifier.loadDetail(2);
        expect(notifier.state.selectedSimulation!.id, 2);

        // Delete id 1
        mockApi.onDelete('/kpr/simulations/1');
        await notifier.delete(1);

        // Selection should remain on id 2
        expect(notifier.state.selectedSimulation, isNotNull);
        expect(notifier.state.selectedSimulation!.id, 2);
        expect(notifier.state.simulations.length, 1);
      });
    });

    group('clearError', () {
      test('resets error to null', () async {
        // Trigger an error
        await notifier.loadAll();
        expect(notifier.state.error, isNotNull);

        notifier.clearError();

        expect(notifier.state.error, isNull);
      });

      test('does not affect other state', () async {
        mockApi.onGet('/kpr/simulations', [
          {
            'id': 1,
            'user_id': 1,
            'name': 'Test',
            'created_at': '2026-01-01T00:00:00Z',
          },
        ]);
        await notifier.loadAll();
        expect(notifier.state.simulations.length, 1);

        // Set an error
        await notifier.loadDetail(999);
        expect(notifier.state.error, isNotNull);

        notifier.clearError();

        expect(notifier.state.error, isNull);
        expect(notifier.state.simulations.length, 1);
        expect(notifier.state.simulations[0].name, 'Test');
      });
    });

    group('clearSelection', () {
      test('resets selectedSimulation to null', () async {
        mockApi.onGet('/kpr/simulations/1', {
          'id': 1,
          'user_id': 1,
          'name': 'Test',
          'created_at': '2026-06-09T10:00:00Z',
        });
        await notifier.loadDetail(1);
        expect(notifier.state.selectedSimulation, isNotNull);

        notifier.clearSelection();

        expect(notifier.state.selectedSimulation, isNull);
      });

      test('does not affect simulations list', () async {
        mockApi.onGet('/kpr/simulations', [
          {
            'id': 1,
            'user_id': 1,
            'name': 'Keep List',
            'created_at': '2026-01-01T00:00:00Z',
          },
        ]);
        await notifier.loadAll();
        expect(notifier.state.simulations.length, 1);

        notifier.clearSelection();

        expect(notifier.state.simulations.length, 1);
      });
    });
  });
}
