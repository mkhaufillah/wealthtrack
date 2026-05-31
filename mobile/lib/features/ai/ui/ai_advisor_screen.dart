import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/local_chat_storage.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../features/auth/providers/auth_provider.dart';

class AiAdvisorScreen extends ConsumerStatefulWidget {
  const AiAdvisorScreen({super.key});

  @override
  ConsumerState<AiAdvisorScreen> createState() => _AiAdvisorScreenState();
}

class _AiAdvisorScreenState extends ConsumerState<AiAdvisorScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_ChatMessage> _messages = [];
  final LocalChatStorage _chatStorage = LocalChatStorage();
  bool _isLoading = false;
  bool _useAdvancedModel = false;
  bool _loaded = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get('/ai/chat/messages');
      final messages = (res.data as List<dynamic>).map((m) => _ChatMessage(
        id: m['id'] as int,
        text: m['content'] as String? ?? '',
        isUser: m['role'] == 'user',
        status: m['status'] as String? ?? 'complete',
      )).toList();
      if (!mounted) return;
      setState(() {
        _messages.addAll(messages);
        _loaded = true;
      });
      _scrollToBottom();
      if (_messages.any((m) => m.status == 'processing')) {
        _startPolling();
      }
    } catch (e) {
      // Fallback to local storage
      await _chatStorage.load();
      if (!mounted) return;
      setState(() {
        _messages.addAll(
          _chatStorage.messages.map((m) => _ChatMessage(
            id: DateTime.now().millisecondsSinceEpoch + _chatStorage.messages.indexOf(m),
            text: m.content, isUser: m.role == 'user', status: 'complete')),
        );
        _loaded = true;
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollMessages());
  }

  Future<void> _pollMessages() async {
    if (!mounted) return;
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get('/ai/chat/messages');
      final serverMessages = (res.data as List<dynamic>).map((m) => ({
        'id': m['id'] as int,
        'content': m['content'] as String? ?? '',
        'role': m['role'] as String? ?? '',
        'status': m['status'] as String? ?? '',
      })).toList();

      setState(() {
        for (final sm in serverMessages) {
          final idx = _messages.indexWhere((m) => m.id == sm['id']);
          if (idx != -1) {
            _messages[idx].text = sm['content'] as String;
            _messages[idx].status = sm['status'] as String;
          }
        }
      });
      _scrollToBottom();

      if (!_messages.any((m) => m.status == 'processing')) {
        _pollTimer?.cancel();
        _pollTimer = null;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send({int? retryParentId}) async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _isLoading) return;

    _msgCtrl.clear();
    final tempId = DateTime.now().millisecondsSinceEpoch;

    setState(() {
      _messages.add(_ChatMessage(id: tempId, text: text, isUser: true, status: 'complete'));
      _isLoading = true;
      _messages.add(_ChatMessage(id: tempId + 1, text: '', isUser: false, status: 'processing'));
    });
    _scrollToBottom();

    try {
      final api = ref.read(apiClientProvider);
      final history = _chatStorage.getLastExchanges(10);

      final res = await api.post('/ai/chat', data: {
        'question': text,
        'model': _useAdvancedModel ? 'opus' : 'flash',
        'history': history,
        if (retryParentId != null) 'retry_parent_id': retryParentId,
      });

      final data = res.data as Map<String, dynamic>;
      final userMsgId = data['user_message_id'] as int;
      final aiMsgId = data['ai_message_id'] as int;

      setState(() {
        _messages[_messages.length - 2] = _ChatMessage(id: userMsgId, text: text, isUser: true, status: 'complete');
        _messages.last = _ChatMessage(id: aiMsgId, text: '', isUser: false, status: 'processing');
        _isLoading = false;
      });

      await _chatStorage.addMessage('user', text);
      _startPolling();
    } catch (e) {
      setState(() {
        _messages.removeLast();
        _messages.add(_ChatMessage(
          id: tempId + 2,
          text: '',
          isUser: false,
          status: 'error',
        ));
        _isLoading = false;
      });
    }
    _scrollToBottom();
  }

  Future<void> _retry(_ChatMessage failedMsg) async {
    final userIdx = _messages.lastIndexWhere((m) => m.isUser && m.id < failedMsg.id);
    if (userIdx == -1) return;
    final userMsg = _messages[userIdx];
    final originalId = userMsg.id;
    setState(() => _messages.removeWhere((m) => m.id == failedMsg.id));
    _msgCtrl.text = userMsg.text;
    await _send(retryParentId: originalId);
    _msgCtrl.clear();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
    // Backup scroll after list fully lays out (MarkdownBody may need extra frame)
    Future.delayed(const Duration(milliseconds: 200), () {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollCtrl.hasClients || !mounted) return;
        final target = _scrollCtrl.position.maxScrollExtent;
        if (_scrollCtrl.position.pixels < target) {
          _scrollCtrl.animateTo(target,
              duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        }
      });
    });
  }

  Future<void> _clearChat() async {
    await _chatStorage.clear();
    setState(() => _messages.clear());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('AI Financial Advisor'),
        actions: [
          if (ref.watch(authProvider).user?.role == 'admin')
            Padding(
              padding: EdgeInsets.only(right: _messages.isNotEmpty ? 0 : 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => setState(() => _useAdvancedModel = !_useAdvancedModel),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _useAdvancedModel ? AppColors.accent : AppColors.textSecondary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _useAdvancedModel ? Icons.auto_awesome : Icons.flash_on,
                        size: 14,
                        color: _useAdvancedModel ? Colors.white : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _useAdvancedModel ? 'Advanced' : 'Flash',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _useAdvancedModel ? Colors.white : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: _clearChat,
              tooltip: 'Clear chat',
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.warning.withOpacity(0.1),
            child: const Text(
              'AI-generated advice, not certified financial planning',
              style: TextStyle(fontSize: 11, color: AppColors.warning),
            ),
          ),
          Expanded(
            child: _messages.isEmpty && !_loaded
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) => _buildMessage(_messages[i]),
                      ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            color: AppColors.surface,
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      decoration: InputDecoration(
                        hintText: 'Ask about your finances...',
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      maxLines: 3,
                      minLines: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: _isLoading ? AppColors.textSecondary : AppColors.accent,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 18),
                      onPressed: _isLoading ? null : () => _send(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.psychology_outlined, size: 64, color: AppColors.textSecondary.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text('Ask me anything about your finances',
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text('"How much did I spend on food this month?"',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text('"Give me saving tips"',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildMessage(_ChatMessage msg) {
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: msg.isUser ? AppColors.accent : AppColors.surface,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: msg.isUser ? const Radius.circular(4) : null,
            bottomLeft: msg.isUser ? null : const Radius.circular(4),
          ),
        ),
        child: msg.isUser
            ? Text(msg.text, style: const TextStyle(color: Colors.white, fontSize: 14))
            : msg.status == 'processing' && msg.text.isEmpty
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textSecondary),
                      ),
                      const SizedBox(width: 8),
                      Text('Thinking...', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                    ],
                  )
                : msg.status == 'error'
                    ? GestureDetector(
                        onTap: () => _retry(msg),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline, size: 16, color: AppColors.highlight),
                            const SizedBox(width: 6),
                            Text('Failed — tap to retry',
                                style: TextStyle(fontSize: 13, color: AppColors.highlight)),
                          ],
                        ),
                      )
                    : MarkdownBody(
                        data: msg.text,
                        styleSheet: MarkdownStyleSheet(
                          p: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                          strong: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
      ),
    );
  }
}

class _ChatMessage {
  final int id;
  String text;
  final bool isUser;
  String status;

  _ChatMessage({required this.id, required this.text, required this.isUser, this.status = 'complete'});
}
