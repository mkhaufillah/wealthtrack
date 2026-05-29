import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/core/services/local_chat_storage.dart';

void main() {
  group('LocalChatStorage', () {
    testWidgets('initial state has empty messages', (tester) async {
      final storage = LocalChatStorage();
      expect(storage.messages, isEmpty);
    });

    testWidgets('getLastExchanges returns empty for empty storage', (tester) async {
      final storage = LocalChatStorage();
      expect(storage.getLastExchanges(5), isEmpty);
    });
  });
}
