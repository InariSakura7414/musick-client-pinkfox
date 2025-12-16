import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

import '../models/message_model.dart';
import '../services/socket_service.dart';
import '../widgets/message_bubble.dart';

class RoomChatPage extends StatefulWidget {
  final SocketService socketService;
  final String roomId;
  final String roomName;
  final String userId;
  final String? userName;

  const RoomChatPage({
    super.key,
    required this.socketService,
    required this.roomId,
    required this.roomName,
    required this.userId,
    this.userName,
  });

  @override
  State<RoomChatPage> createState() => _RoomChatPageState();
}

class _RoomChatPageState extends State<RoomChatPage> {
  final Logger _logger = Logger();
  final List<Message> _messages = [];
  final TextEditingController _controller = TextEditingController();
  late final ScrollController _scrollController;
  late final String _selfName;
  StreamSubscription<String>? _sub;
  bool _sending = false;
  String _status = '';
  bool _isLoading = false;
  bool _hasMore = true;
  String _nextBeforeId = '';

  @override
  void initState() {
    super.initState();
    _selfName = (widget.userName != null && widget.userName!.isNotEmpty)
        ? widget.userName!
        : widget.userId;
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _sub = widget.socketService.messages.listen(_handleIncoming);
    _loadInitialMessages();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels <=
            _scrollController.position.minScrollExtent + 80 &&
        !_isLoading &&
        _hasMore) {
      _loadMoreMessages();
    }
  }

  void _handleIncoming(String raw) {
    // Ignore non-JSON messages that clearly aren't about this room.
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final roomId = decoded['room_id'];
      if (roomId is String && roomId == widget.roomId) {
        final body = decoded['body'];
        final senderId = decoded['sender_id'];
        final success = decoded['success'];
        final id = decoded['id'];
        final sentAt = decoded['sent_at'] ?? decoded['created_at'];

        // Mark our own message as delivered when success comes back.
        if (senderId is String && senderId == widget.userId && success is bool && success) {
          setState(() {
            for (var i = _messages.length - 1; i >= 0; i--) {
              final msg = _messages[i];
              if (msg.isFromUser && !msg.delivered &&
                  (id is int && msg.id == id.toString() || id is String && id.isNotEmpty && msg.id == id || msg.content == (body ?? ''))) {
                _messages[i] = Message(
                  content: msg.content,
                  isFromUser: true,
                  senderName: msg.senderName,
                  senderId: msg.senderId,
                  delivered: true,
                  id: id is int ? id.toString() : (id is String ? id : msg.id),
                  timestamp: _parseTime(sentAt) ?? msg.timestamp,
                );
                break;
              }
            }
            _status = '';
          });
          return;
        }

        // Messages from others (or from server broadcast).
        if (body is String && body.isNotEmpty) {
          final senderName = senderId is String && senderId.isNotEmpty ? senderId : 'Server';
          setState(() {
            final already = _messages.any((m) => m.id.isNotEmpty && m.id == (id is int ? id.toString() : (id is String ? id : '')));
            if (!already) {
              final isSelf = senderId is String && senderId == widget.userId;
              _messages.add(
                Message(
                  content: body,
                  isFromUser: isSelf,
                  senderName: isSelf ? _selfName : senderName,
                  senderId: senderId is String ? senderId : '',
                  delivered: true,
                  id: id is int ? id.toString() : (id is String ? id : ''),
                  timestamp: _parseTime(sentAt),
                ),
              );
            }
            _status = '';
          });
        }
        return;
      }
    } catch (_) {
      // Non-JSON payload; ignore.
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _status = '';
      _messages.add(
        Message(
          content: text,
          isFromUser: true,
                  senderName: _selfName,
          senderId: widget.userId,
          delivered: false,
          id: '',
        ),
      );
    });

    final payload = jsonEncode({
      'user_id': widget.userId,
      'room_id': widget.roomId,
      'body': text,
    });

    _logger.i('Sending room message (route 301): $payload');
    widget.socketService.sendToRoute(301, payload);

    _controller.clear();

    // Optionally wait briefly for a response to surface errors; not required.
    Future.delayed(const Duration(milliseconds: 200)).then((_) {
      if (mounted) {
        setState(() => _sending = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Room: ${widget.roomName}'),
      ),
      body: Column(
        children: [
          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_status, textAlign: TextAlign.center),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              controller: _scrollController,
              itemCount: _messages.length,
              itemBuilder: (context, index) => MessageBubble(message: _messages[index]),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_sending,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton(
                    onPressed: _sending ? null : _sendMessage,
                    mini: true,
                    child: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadInitialMessages() async {
    if (_isLoading) return;
    _isLoading = true;
    setState(() => _status = 'Loading messages...');
    await _fetchMessages(limit: 30, beforeId: '');
    if (mounted) setState(() => _status = '');
    _isLoading = false;
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoading || !_hasMore) return;
    _isLoading = true;
    await _fetchMessages(limit: 30, beforeId: _nextBeforeId);
    _isLoading = false;
  }

  Future<void> _fetchMessages({required int limit, required String beforeId}) async {
    final payload = jsonEncode({
      'room_id': widget.roomId,
      'user_id': widget.userId,
      'limit': limit,
      'before_id': beforeId,
      'include_system': false,
    });

    _logger.i('Fetching messages (route 310): $payload');
    widget.socketService.sendToRoute(310, payload);

    final raw = await _waitForFetchMessagesResponse(timeout: const Duration(seconds: 8));
    if (!mounted || raw == null) return;

    final parsed = _tryParseFetchMessagesResponse(raw);
    if (parsed == null) return;

    setState(() {
      _hasMore = parsed.hasMore;
      _nextBeforeId = parsed.nextBeforeId;
      if (parsed.messages.isNotEmpty) {
        // Prepend older messages
        _messages.insertAll(0, parsed.messages);
      }
    });
  }

  Future<String?> _waitForFetchMessagesResponse({required Duration timeout}) async {
    try {
      return await widget.socketService.messages
          .where((m) => m.isNotEmpty)
          .where((m) => !m.startsWith('Error:'))
          .where((m) => m != 'Disconnected')
          .where(_looksLikeFetchMessagesJson)
          .first
          .timeout(timeout);
    } catch (e) {
      _logger.w('Timed out waiting for fetch messages response: $e');
      return null;
    }
  }

  bool _looksLikeFetchMessagesJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      return decoded.containsKey('success') &&
          (decoded.containsKey('messages') || decoded.containsKey('has_more'));
    } catch (_) {
      return false;
    }
  }

  _FetchMessagesResponse? _tryParseFetchMessagesResponse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final success = decoded['success'];
      if (success is! bool || !success) return null;

      final messagesRaw = decoded['messages'];
      final hasMore = decoded['has_more'];
      final nextBeforeId = decoded['next_before_id'];

      final parsed = <Message>[];
      if (messagesRaw is List) {
        for (final entry in messagesRaw) {
          if (entry is! Map) continue;
          final body = entry['body'];
          final senderId = entry['sender_id'];
          final senderName = entry['sender_name'];
          final id = entry['id'];
          final createdAt = entry['created_at'];

          if (body is! String) continue;

          final senderIdStr = senderId is String ? senderId : '';
          final isSelf = senderIdStr == widget.userId;
          parsed.add(
            Message(
              content: body,
              isFromUser: isSelf,
              senderName: isSelf
                  ? _selfName
                  : (senderName is String && senderName.isNotEmpty
                      ? senderName
                      : (senderIdStr.isNotEmpty ? senderIdStr : 'Server')),
              senderId: senderIdStr,
              delivered: true,
              id: id is int ? id.toString() : (id is String ? id : ''),
              timestamp: _parseTime(createdAt),
            ),
          );
        }
      }

      // Oldest first expected; ensure list is chronological.
      parsed.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      return _FetchMessagesResponse(
        messages: parsed,
        hasMore: hasMore is bool ? hasMore : false,
        nextBeforeId: nextBeforeId is String ? nextBeforeId : '',
      );
    } catch (_) {
      return null;
    }
  }

  DateTime? _parseTime(dynamic value) {
    if (value is String && value.isNotEmpty) {
      try {
        return DateTime.parse(value).toLocal();
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

class _FetchMessagesResponse {
  final List<Message> messages;
  final bool hasMore;
  final String nextBeforeId;

  _FetchMessagesResponse({
    required this.messages,
    required this.hasMore,
    required this.nextBeforeId,
  });
}
