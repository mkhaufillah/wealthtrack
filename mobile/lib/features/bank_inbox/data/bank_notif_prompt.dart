import 'package:flutter/foundation.dart';

/// First-run Android listener prompt. iOS has no NotificationListener.
bool bankNotifPromptDue({
  required bool android,
  required bool seen,
  required bool enabled,
}) =>
    android && !seen && !enabled;

/// Ask for POST_NOTIFICATIONS only after the listener is on.
bool pushNotifAskDue({required bool requested, required bool enabled}) =>
    !requested && enabled;

bool get isAndroidBankListener {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android;
}

const kBankNotifPromptSeenKey = 'bank_notif_prompt_seen';
const kBankPushRequestedKey = 'bank_push_requested';
