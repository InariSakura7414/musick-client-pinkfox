import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'package:logger/logger.dart';

class SocketService {
  final logger = Logger();
  Socket? _socket;
  final StreamController<String> _messageStream = StreamController<String>.broadcast();
  Uint8List _buffer = Uint8List(0); // Start empty, will grow
  
  Stream<String> get messages => _messageStream.stream;

  Future<bool> connect(String ip, int port) async {
    try {
      _socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
      _startListening();
      return true;
    } catch (e) {
      logger.e('Connection error: $e');
      return false;
    }
  }

  void _startListening() {
    _socket?.listen(
      (Uint8List data) {
        _handleIncomingData(data);
      },
      onError: (error) {
        logger.e('Socket error: $error');
        _messageStream.add('Error: $error');
        disconnect();
      },
      onDone: () {
        logger.i('Socket closed');
        _messageStream.add('Disconnected');
        disconnect();
      },
    );
  }

  void _handleIncomingData(Uint8List data) {
    // Append incoming data to buffer by creating a new buffer
    final newBuffer = Uint8List(_buffer.length + data.length);
    newBuffer.setRange(0, _buffer.length, _buffer);
    newBuffer.setRange(_buffer.length, newBuffer.length, data);
    _buffer = newBuffer; // Reassign buffer

    // Process complete messages from buffer
    int offset = 0;
    while (offset + 8 <= _buffer.length) {
      final byteData = ByteData.view(_buffer.buffer, _buffer.offsetInBytes + offset, _buffer.length - offset);
      final size = byteData.getInt32(0, Endian.little);
      
      // Check if we have a complete message
      if (offset + 8 + size > _buffer.length) {
        break; // Wait for more data
      }

      final id = byteData.getInt32(4, Endian.little);
      final messageData = _buffer.sublist(offset + 8, offset + 8 + size);
      final messageText = utf8.decode(messageData);

      logger.d('Received - ID: $id, Size: $size, Data: $messageText');
      _messageStream.add(messageText);

      offset += 8 + size;
    }

    // Remove processed data from buffer
    if (offset > 0) {
      if (offset < _buffer.length) {
        _buffer = _buffer.sublist(offset);
      } else {
        _buffer = Uint8List(0); // All processed, reset buffer
      }
    }
  }

  /// Sends a UTF-8 message to the default echo route (ID=1).
  void sendMessage(String message) => sendToRoute(1, message);

  /// Sends a UTF-8 message to an arbitrary EasyTCP route ID.
  /// Example: sendToRoute(10, 'abc')
  void sendToRoute(int routeId, String message) {
    sendBytes(routeId, Uint8List.fromList(utf8.encode(message)));
  }

  /// Sends raw bytes to an arbitrary EasyTCP route ID.
  /// Packet format: Size(4)|ID(4)|Data(n) in little-endian.
  void sendBytes(int routeId, Uint8List payload) {
    final socket = _socket;
    if (socket == null) {
      logger.w('Not connected');
      return;
    }

    if (routeId < 0 || routeId > 0x7fffffff) {
      logger.e('Invalid routeId (must fit int32): $routeId');
      return;
    }

    if (payload.length > 0x7fffffff) {
      logger.e('Payload too large: ${payload.length}');
      return;
    }

    try {
      final size = payload.length;

      final buffer = Uint8List(8 + size);
      final byteData = ByteData.view(buffer.buffer);
      byteData.setInt32(0, size, Endian.little);
      byteData.setInt32(4, routeId, Endian.little);
      buffer.setRange(8, 8 + size, payload);

      socket.add(buffer);
      socket.flush();
    } catch (e) {
      logger.e('Send error: $e');
    }
  }

  void disconnect() {
    _socket?.destroy();
    _socket = null;
    _buffer = Uint8List(0);
  }

  bool isConnected() {
    return _socket != null;
  }

  void dispose() {
    disconnect();
    _messageStream.close();
  }
}
