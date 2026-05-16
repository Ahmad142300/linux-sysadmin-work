import 'package:flutter/material.dart';
import 'package:chatbot_app/api/api_service.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatMessage {
  final String text;
  final bool isUser; // true for user, false for bot
  const _ChatMessage({required this.text, required this.isUser});
}

class _ChatPageState extends State<ChatPage> {
  final _messages = <_ChatMessage>[];
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _sidebarExpanded = false; // false -> 5%, true -> 20%
  List<ChatSessionDto> _sessions = [];
  int? _selectedSessionId;
  bool _loadingSessions = true;

  // Model Selection State
  String selectedModel = 'gpt-4.1';
  final List<String> availableModels = ['gpt-4.1', 'gemini-3-flash'];

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  // Sidebar text helper to handle overflow during collapse
  Widget _sidebarText(String text, {bool header = false}) {
    final collapsed = !_sidebarExpanded;
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: header ? const TextStyle(fontWeight: FontWeight.w600) : null,
    );
  }

  Future<void> _loadSessions() async {
    setState(() => _loadingSessions = true);
    try {
      final sessions = await ResponseApi.fetchSessions();
      setState(() {
        _sessions = sessions;
        _loadingSessions = false;
      });
    } catch (e) {
      setState(() => _loadingSessions = false);
    }
  }

  Future<void> _loadMessagesForSession(int sessionId) async {
    setState(() => _messages.clear());
    try {
      final msgs = await ResponseApi.fetchSessionMessages(sessionId);
      setState(() {
        for (final m in msgs) {
          _messages.add(
            _ChatMessage(text: m.content, isUser: m.role == 'user'),
          );
        }
      });
      _scrollToBottom();
    } catch (e) {}
  }

  void _selectSession(int sessionId) {
    setState(() => _selectedSessionId = sessionId);
    ResponseApi.selectSession(sessionId);
    _loadMessagesForSession(sessionId);
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _messages.add(_ChatMessage(text: text, isUser: true)));
    _controller.clear();
    _scrollToBottom();
    _fetchResponse(text);
  }

  void _fetchResponse(String message) async {
    try {
      // Passes the selectedModel variable to your API service
      final reply = await ResponseApi.fetchResponse(message, selectedModel);
      setState(() => _messages.add(_ChatMessage(text: reply, isUser: false)));

      final sid = ResponseApi.currentSessionId;
      if (sid != null && _selectedSessionId != sid) {
        _selectedSessionId = sid;
        final exists = _sessions.any((s) => s.id == sid);
        if (!exists) {
          setState(() {
            _sessions = [
              ChatSessionDto(
                id: sid,
                title: message.substring(
                  0,
                  message.length > 50 ? 50 : message.length,
                ),
                createdAt: DateTime.now(),
                lastVisitedAt: DateTime.now(),
              ),
              ..._sessions,
            ];
          });
        }
      }
      _loadSessions();
      _scrollToBottom();
    } catch (e) {
      setState(
        () => _messages.add(_ChatMessage(text: 'Error: $e', isUser: false)),
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _newChat() {
    ResponseApi.resetSession();
    _controller.clear();
    setState(() {
      _messages.clear();
      _selectedSessionId = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat', style: TextStyle(color: Colors.white)),
        backgroundColor: Theme.of(context).primaryColor,
        actions: [
          // Model Selector Dropdown
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedModel,
                icon: const Icon(Icons.bolt, color: Colors.white),
                dropdownColor: Colors.grey[900],
                items: availableModels.map((String model) {
                  return DropdownMenuItem<String>(
                    value: model,
                    child: Text(
                      model,
                      style: const TextStyle(color: Colors.white),
                    ),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null)
                    setState(() => selectedModel = newValue);
                },
              ),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final sidebarWidth =
              constraints.maxWidth * (_sidebarExpanded ? 0.20 : 0.05);
          final contentWidth = (constraints.maxWidth - sidebarWidth).clamp(
            0.0,
            double.infinity,
          );
          final hPad = (contentWidth * 0.06).clamp(12.0, 32.0);
          final maxBubbleWidth = contentWidth * 0.72;

          return Row(
            children: [
              // Sidebar
              Container(
                width: sidebarWidth,
                color: Colors.grey.shade100,
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      IconButton(
                        alignment: Alignment.centerLeft,
                        icon: Icon(
                          _sidebarExpanded
                              ? Icons.chevron_left
                              : Icons.chevron_right,
                        ),
                        onPressed: () => setState(
                          () => _sidebarExpanded = !_sidebarExpanded,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _loadingSessions
                            ? const Center(child: CircularProgressIndicator())
                            : ListView.builder(
                                padding: const EdgeInsets.all(8),
                                itemCount: _sessions.length + 1,
                                itemBuilder: (context, index) {
                                  if (index == 0)
                                    return _sidebarExpanded
                                        ? _sidebarText(
                                            'Chat sessions',
                                            header: true,
                                          )
                                        : const Divider();
                                  final session = _sessions[index - 1];
                                  final selected =
                                      session.id == _selectedSessionId;
                                  return TextButton(
                                    style: TextButton.styleFrom(
                                      alignment: Alignment.centerLeft,
                                      backgroundColor: selected
                                          ? Theme.of(
                                              context,
                                            ).primaryColor.withOpacity(0.1)
                                          : null,
                                    ),
                                    onPressed: () => _selectSession(session.id),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.chat_bubble_outline,
                                          size: 18,
                                          color: Colors.black54,
                                        ),
                                        if (_sidebarExpanded) ...[
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: _sidebarText(
                                              session.displayTitle,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              // Main Chat Area
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        controller: _scroll,
                        padding: EdgeInsets.symmetric(
                          horizontal: hPad,
                          vertical: 12,
                        ),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) {
                          final msg = _messages[i];
                          return Align(
                            alignment: msg.isUser
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              constraints: BoxConstraints(
                                maxWidth: maxBubbleWidth,
                              ),
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: msg.isUser
                                    ? Theme.of(context).primaryColor
                                    : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                msg.text,
                                style: TextStyle(
                                  color: msg.isUser
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    // Input Bar
                    Padding(
                      padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 12),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: _newChat,
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              onSubmitted: (_) => _send(),
                              decoration: InputDecoration(
                                hintText: 'Message $selectedModel...',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(22),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: Colors.grey.shade100,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _send,
                            icon: const Icon(Icons.send),
                            color: Theme.of(context).primaryColor,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
