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

  test('push asked only after listener enabled and never twice', () {
    expect(pushNotifAskDue(requested: false, enabled: false), isFalse);
    expect(pushNotifAskDue(requested: false, enabled: true), isTrue);
    expect(pushNotifAskDue(requested: true, enabled: true), isFalse);
    expect(pushNotifAskDue(requested: true, enabled: false), isFalse);
  });
}
