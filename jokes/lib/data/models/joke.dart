class Joke {
  const Joke({required this.id, required this.content});

  final String id;
  final String content;

  factory Joke.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? json['_id'] ?? '').toString();
    final content = _extractContent(json);

    return Joke(
      id: id.isEmpty ? content.hashCode.toString() : id,
      content: content,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
    };
  }

  static String _extractContent(Map<String, dynamic> json) {
    final candidates = [
      json['joke'],
      json['content'],
      json['text'],
      json['title'],
      json['setup'],
    ];

    for (final value in candidates) {
      if (value != null && value.toString().trim().isNotEmpty) {
        if (json['punchline'] != null && value == json['setup']) {
          return '${value.toString().trim()}\n${json['punchline'].toString().trim()}';
        }
        return value.toString().trim();
      }
    }

    return json.toString();
  }
}
