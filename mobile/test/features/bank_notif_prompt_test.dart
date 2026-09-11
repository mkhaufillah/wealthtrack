import 'package:flutter_test/flutter_test.dart';
import 'package:wealthtrack/features/bank_inbox/data/bank_notif_prompt.dart';

void main() {
  test('asks once on Android when listener is off', () {
    expect(
      bankNotifPromptDue(android: true, seen: false, enabled: false),
      isTrue,
    );
  });

  test('skips after Nanti or Izinkan', () {
    expect(
      bankNotifPromptDue(android: true, seen: true, enabled: false),
      isFalse,
    );
  });

  test('skips when already allowed', () {
    expect(
      bankNotifPromptDue(android: true, seen: false, enabled: true),
      isFalse,
    );
  });

  test('skips iOS', () {
    expect(
      bankNotifPromptDue(android: false, seen: false, enabled: false),
      isFalse,
    );
  });
}
