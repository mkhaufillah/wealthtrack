import 'package:flutter/foundation.dart';

/// First-run Android listener prompt. iOS has no NotificationListener.
bool bankNotifPromptDue({
  required bool android,
  required bool seen,
  required bool enabled,
}) =>
    android && !seen && !enabled;

bool get isAndroidBankListener {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android;
}

const kBankNotifPromptSeenKey = 'bank_notif_prompt_seen';
