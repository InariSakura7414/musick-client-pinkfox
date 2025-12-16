class Message {
  final String content;
  final bool isFromUser;
  final DateTime timestamp;
  final String senderName;
  final String senderId;
  final bool delivered;
  final String id;

  Message({
    required this.content,
    required this.isFromUser,
    required this.senderName,
    required this.senderId,
    this.delivered = false,
    this.id = '',
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory Message.fromUser(String content) {
    return Message(
      content: content,
      isFromUser: true,
      senderName: 'You',
      senderId: '',
      delivered: false,
      id: '',
    );
  }

  factory Message.fromServer(
    String content, {
    String senderName = 'Server',
    String senderId = '',
    String id = '',
    DateTime? timestamp,
  }) {
    return Message(
      content: content,
      isFromUser: false,
      senderName: senderName,
      senderId: senderId,
      delivered: true,
      id: id,
      timestamp: timestamp,
    );
  }
}
