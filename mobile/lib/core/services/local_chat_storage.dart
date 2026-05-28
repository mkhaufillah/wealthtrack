import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class ChatMessage {
  final String role; // "user" | "assistant"
  final String content;
  final DateTime timestamp;

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: json['role'] as String,
        content: json['content'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}

class LocalChatStorage {
  static const _fileName = 'wealthtrack_chat_history.json';
  List<ChatMessage> _messages = [];
  bool _loaded = false;

  List<ChatMessage> get messages => _messages;

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<void> load() async {
    if (_loaded) return;
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final list = jsonDecode(content) as List<dynamic>;
        _messages = list.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {
      // Corrupted file? Start fresh
      _messages = [];
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    final file = await _getFile();
    await file.writeAsString(jsonEncode(_messages.map((m) => m.toJson()).toList()));
  }

  Future<void> addMessage(String role, String content) async {
    await load();
    _messages.add(ChatMessage(role: role, content: content));
    await _persist();
  }

  Future<void> clear() async {
    _messages = [];
    _loaded = true;
    final file = await _getFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Returns the last [count] exchanges as [{role, content}] for API context.
  /// Each exchange = 1 user + 1 assistant message.
  List<Map<String, String>> getLastExchanges(int count) {
    final window = <Map<String, String>>[];
    for (final msg in _messages.reversed.take(count * 2).toList().reversed) {
      window.add({'role': msg.role, 'content': msg.content});
    }
    return window;
  }
}
