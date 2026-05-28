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

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    await _chatStorage.load();
    if (!mounted) return;
    setState(() {
      _messages.addAll(
        _chatStorage.messages.map((m) => _ChatMessage(text: m.content, isUser: m.role == 'user')),
      );
      _loaded = true;
    });
    _scrollToBottom();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _isLoading) return;

    _msgCtrl.clear();
    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _isLoading = true;
      // Placeholder AI message — will be updated as tokens arrive
      _messages.add(_ChatMessage(text: 'typing...', isUser: false));
    });
    _scrollToBottom();

    // Save user message locally
    await _chatStorage.addMessage('user', text);

    try {
      final api = ref.read(apiClientProvider);
      final history = _chatStorage.getLastExchanges(10);

      final tokenStream = api.streamPost('/ai/advise/stream', data: {
        'question': text,
        'model': _useAdvancedModel ? 'opus' : 'flash',
        'history': history,
      });

      final buffer = StringBuffer();
      await for (final token in tokenStream) {
        buffer.write(token);
        setState(() {
          _messages.last.text = buffer.toString();
        });
        _scrollToBottom();
      }

      final fullAnswer = buffer.toString();
      final displayText = fullAnswer.isNotEmpty ? fullAnswer : 'No response';
      setState(() {
        _messages.last.text = displayText;
        _isLoading = false;
      });
      await _chatStorage.addMessage('assistant', displayText);
    } catch (e) {
      setState(() {
        _messages.removeLast(); // remove placeholder
        _messages.add(_ChatMessage(
          text: '⚠️ Error: ${e.toString().replaceAll('Exception: ', '')}',
          isUser: false,
        ));
        _isLoading = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
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
          // Advanced model toggle — only for Filla (user id = 1)
          if (ref.watch(authProvider).user?.id == 1)
            Padding(
              padding: const EdgeInsets.only(right: 4),
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
          // Disclaimer
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.warning.withOpacity(0.1),
            child: const Text(
              'AI-generated advice, not certified financial planning',
              style: TextStyle(fontSize: 11, color: AppColors.warning),
            ),
          ),
          // Messages
          Expanded(
            child: _messages.isEmpty && !_loaded
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) {
                          return _buildMessage(_messages[i]);
                        },
                      ),
          ),
          // Input
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
                      onPressed: _isLoading ? null : _send,
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
  String text;
  final bool isUser;
  _ChatMessage({required this.text, required this.isUser});
}
