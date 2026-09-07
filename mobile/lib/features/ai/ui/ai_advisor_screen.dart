import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/ui/copy_fallback.dart';
import '../../../core/ui/app_icons.dart';
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
  int? _lastSavedAssistantId;
  Timer? _pollTimer;
  Timer? _scrollBackupTimer;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.get('/ai/chat/messages');
      final raw = res.data;
      final list = raw is List
          ? raw
          : (raw is Map && raw['messages'] is List)
              ? raw['messages'] as List
              : const [];
      final messages = list.map((m) => _ChatMessage(
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
        _isLoading = true;
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
      final raw = res.data;
      final list = raw is List
          ? raw
          : (raw is Map && raw['messages'] is List)
              ? raw['messages'] as List
              : const [];
      final serverMessages = list.map((m) => ({
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
        _isLoading = false;
        _ChatMessage? lastAi;
        for (final m in _messages.reversed) {
          if (!m.isUser && m.status == 'complete' && m.text.trim().isNotEmpty) {
            lastAi = m;
            break;
          }
        }
        if (lastAi != null && lastAi.id != _lastSavedAssistantId) {
          _lastSavedAssistantId = lastAi.id;
          await _chatStorage.addMessage('assistant', lastAi.text);
        }
      }
    } catch (e) {
      debugPrint('ERROR: $e');
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scrollBackupTimer?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// Last ~10 complete turns (user+asisten), tanpa pertanyaan yang baru diketik.
  List<Map<String, String>> _historyPayload() {
    final complete = _messages
        .where((m) => m.status == 'complete' && m.text.trim().isNotEmpty)
        .toList();
    if (complete.isNotEmpty && complete.last.isUser) {
      complete.removeLast();
    }
    const maxMsgs = 20;
    final slice = complete.length > maxMsgs
        ? complete.sublist(complete.length - maxMsgs)
        : complete;
    return [
      for (final m in slice)
        {'role': m.isUser ? 'user' : 'assistant', 'content': m.text},
    ];
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
      final history = _historyPayload();

      final res = await api.post('/ai/chat', data: {
        'question': text,
        'model': _useAdvancedModel ? 'advanced' : 'flash',
        'history': history,
        if (retryParentId != null) 'retry_parent_id': retryParentId,
      });

      final data = res.data as Map<String, dynamic>;
      final userMsgId = data['user_message_id'] as int;
      final aiMsgId = data['ai_message_id'] as int;

      setState(() {
        _messages[_messages.length - 2] = _ChatMessage(id: userMsgId, text: text, isUser: true, status: 'complete');
        _messages.last = _ChatMessage(id: aiMsgId, text: '', isUser: false, status: 'processing');
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
      if (!mounted || !_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
    _scrollBackupTimer?.cancel();
    _scrollBackupTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted || !_scrollCtrl.hasClients) return;
      final target = _scrollCtrl.position.maxScrollExtent;
      if (_scrollCtrl.position.pixels < target) {
        _scrollCtrl.animateTo(target,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _clearChat() async {
    final api = ref.read(apiClientProvider);
    try {
      await api.delete('/ai/chat/messages');
    } catch (e) {
      debugPrint('ERROR: $e');
      // ignore — local clear still happens
    }
    await _chatStorage.clear();
    setState(() => _messages.clear());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(t('ai.title')),
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
                      AppIcon(
                        _useAdvancedModel ? AppIcons.spark : AppIcons.ai,
                        size: 14,
                        color: _useAdvancedModel ? AppColors.surface : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _useAdvancedModel ? 'Advanced' : 'Flash',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _useAdvancedModel ? AppColors.surface : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_messages.isNotEmpty)
            IconButton(
              icon: AppIcon(AppIcons.trash, size: 20),
              onPressed: _clearChat,
              tooltip: 'Bersihin chat',
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.butter,
            child: Text(
              t('ai.disclaimer'),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.onAccent),
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
                      enabled: !_isLoading,
                      decoration: InputDecoration(
                        hintText: t('ai.hint'),
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
                      icon: AppIcon(AppIcons.send, color: AppColors.onAccent, size: 18),
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
          AppIcon(AppIcons.ai, size: 64, color: AppColors.textSecondary.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(t('home.ai_sub'),
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text(t('ai.sample1'),
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(t('ai.sample2'),
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
            ? Text(msg.text, style: TextStyle(color: AppColors.onAccent, fontSize: 14))
            : msg.status == 'processing' && msg.text.isEmpty
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textSecondary),
                      ),
                      const SizedBox(width: 8),
                      Text(t('common.thinking'), style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                    ],
                  )
                : msg.status == 'error'
                    ? GestureDetector(
                        onTap: () => _retry(msg),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppIcon(AppIcons.alert, size: 16, color: AppColors.highlight),
                            const SizedBox(width: 6),
                            Text(t('common.try_again'),
                                style: TextStyle(fontSize: 13, color: AppColors.highlight)),
                          ],
                        ),
                      )
                    : MarkdownBody(
                        data: msg.text,
                        styleSheet: MarkdownStyleSheet(
                          p: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                          strong: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          code: TextStyle(
                            fontSize: 13,
                            color: AppColors.textPrimary,
                            backgroundColor: AppColors.divider,
                          ),
                          codeblockDecoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          blockquoteDecoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: AppColors.accent.withOpacity(0.5),
                                width: 3,
                              ),
                            ),
                          ),
                          h1: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          h2: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          h3: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          a: TextStyle(color: AppColors.accent, decoration: TextDecoration.underline),
                          listBullet: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                          tableBorder: TableBorder.all(
                            color: AppColors.divider,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          tableCellPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          tableCells: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
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
