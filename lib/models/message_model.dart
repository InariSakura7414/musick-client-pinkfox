class Message {
  final String content;
  final bool isFromUser;
  final DateTime timestamp;

  Message({
    required this.content,
    required this.isFromUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory Message.fromUser(String content) {
    return Message(
      content: content,
      isFromUser: true,
    );
  }

  factory Message.fromServer(String content) {
    return Message(
      content: content,
      isFromUser: false,
    );
  }
}
