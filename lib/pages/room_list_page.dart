import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

import '../services/socket_service.dart';

class RoomListPage extends StatefulWidget {
  final SocketService socketService;
  final String userId;

  const RoomListPage({
    super.key,
    required this.socketService,
    required this.userId,
  });

  @override
  State<RoomListPage> createState() => _RoomListPageState();
}

class _RoomListPageState extends State<RoomListPage> {
  final Logger _logger = Logger();
  final List<_RoomSummary> _rooms = [];
  String _status = '';

  Future<void> _createRoomDialog() async {
    _CreateRoomResult? result;
    try {
      result = await showDialog<_CreateRoomResult>(
        context: context,
        builder: (dialogContext) => const _CreateRoomDialog(),
      );
    } catch (e) {
      _logger.e('Dialog error: $e');
      return;
    }

    if (!mounted || result == null) return;

    final payload = jsonEncode({
      'user_id': widget.userId,
      'room_name': result.name,
      'is_private': result.isPrivate,
    });

    _logger.i('Creating room (route 201): $payload');

    setState(() {
      _status = 'Creating room...';
    });

    widget.socketService.sendToRoute(201, payload);

    final raw = await _waitForCreateRoomResponse(timeout: const Duration(seconds: 8));
    if (!mounted) return;

    if (raw == null) {
      setState(() => _status = 'No create-room response received.');
      return;
    }

    final resp = _tryParseCreateRoomResponse(raw);
    if (resp == null) {
      setState(() => _status = 'Invalid create-room response: $raw');
      return;
    }

    if (!resp.success) {
      setState(() => _status = resp.message.isEmpty ? 'Create room failed.' : resp.message);
      return;
    }

    setState(() {
      _rooms.add(
        _RoomSummary(
          name: resp.roomName.isNotEmpty ? resp.roomName : result!.name,
          isPrivate: resp.isPrivate ?? result!.isPrivate,
          roomId: resp.roomId,
          roomCode: resp.roomCode,
        ),
      );
      _status = resp.message.isNotEmpty ? resp.message : 'Room created.';
    });
  }

  Future<String?> _waitForCreateRoomResponse({required Duration timeout}) async {
    try {
      return await widget.socketService.messages
          .where((m) => m.isNotEmpty)
          .where((m) => !m.startsWith('Error:'))
          .where((m) => m != 'Disconnected')
          .where(_looksLikeCreateRoomJson)
          .first
          .timeout(timeout);
    } catch (e) {
      _logger.w('Timed out waiting for create-room response: $e');
      return null;
    }
  }

  bool _looksLikeCreateRoomJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      return decoded.containsKey('success') &&
          (decoded.containsKey('room_id') ||
              decoded.containsKey('room_name') ||
              decoded.containsKey('room_code') ||
              decoded.containsKey('is_private') ||
              decoded.containsKey('message'));
    } catch (_) {
      return false;
    }
  }

  _CreateRoomResponse? _tryParseCreateRoomResponse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final success = decoded['success'];
      if (success is! bool) return null;

      final message = decoded['message'];
      final roomId = decoded['room_id'];
      final roomCode = decoded['room_code'];
      final roomName = decoded['room_name'];
      final isPrivate = decoded['is_private'];

      return _CreateRoomResponse(
        success: success,
        message: message is String ? message : '',
        roomId: roomId is String ? roomId : '',
        roomCode: roomCode is String ? roomCode : '',
        roomName: roomName is String ? roomName : '',
        isPrivate: isPrivate is bool ? isPrivate : null,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rooms'),
        actions: [
          TextButton(
            onPressed: _createRoomDialog,
            child: const Text('New room'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _status,
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: _rooms.isEmpty
                ? const Center(child: Text('No rooms yet'))
                : ListView.separated(
                    itemCount: _rooms.length,
                    separatorBuilder: (_, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final room = _rooms[index];
                      final privacyText = room.isPrivate ? 'Private' : 'Public';
                        final codePrefix = room.roomCode.isNotEmpty ? 'Code: ${room.roomCode} • ' : '';
                      return ListTile(
                        leading: Icon(room.isPrivate ? Icons.lock : Icons.group),
                        title: Text(room.name),
                        subtitle: Text('$codePrefix$privacyText'),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _RoomSummary {
  final String name;
  final bool isPrivate;
  final String roomId;
  final String roomCode;

  const _RoomSummary({
    required this.name,
    required this.isPrivate,
    this.roomId = '',
    this.roomCode = '',
  });
}

class _CreateRoomResult {
  final String name;
  final bool isPrivate;

  const _CreateRoomResult({required this.name, required this.isPrivate});
}

class _CreateRoomResponse {
  final bool success;
  final String message;
  final String roomId;
  final String roomCode;
  final String roomName;
  final bool? isPrivate;

  const _CreateRoomResponse({
    required this.success,
    required this.message,
    required this.roomId,
    required this.roomCode,
    required this.roomName,
    required this.isPrivate,
  });
}

class _CreateRoomDialog extends StatefulWidget {
  const _CreateRoomDialog();

  @override
  State<_CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends State<_CreateRoomDialog> {
  final _nameController = TextEditingController();
  bool _isPrivate = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(
      _CreateRoomResult(name: name, isPrivate: _isPrivate),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New room'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Room name',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Private room'),
            value: _isPrivate,
            onChanged: (value) {
              setState(() => _isPrivate = value ?? false);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }
}
