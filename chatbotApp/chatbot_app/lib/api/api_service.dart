import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ChatSessionDto {
  final int id;
  final String? title;
  final DateTime createdAt;
  final DateTime lastVisitedAt;

  ChatSessionDto({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.lastVisitedAt,
  });

  factory ChatSessionDto.fromJson(Map<String, dynamic> json) {
    return ChatSessionDto(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      lastVisitedAt: DateTime.parse(json['last_visited_at'] as String),
    );
  }

  String get displayTitle =>
      (title == null || title!.trim().isEmpty) ? 'Session $id' : title!;
}

class ChatMessageDto {
  final int id;
  final int sessionId;
  final String role; // 'user' | 'assistant'
  final String content;
  final DateTime createdAt;

  ChatMessageDto({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  factory ChatMessageDto.fromJson(Map<String, dynamic> json) {
    return ChatMessageDto(
      id: (json['id'] as num).toInt(),
      sessionId: (json['session_id'] as num).toInt(),
      role: json['role'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class ResponseApi {
  static String get baseUrl =>
      dotenv.env['BASE_URL'] ?? 'http://localhost:30008';
  // static const String baseUrl = 'http://localhost:5000';
  static int? _sessionId; // current chat session id

  static Future<String> fetchResponse(String message, String model) async {
    final payload = <String, dynamic>{'message': message};
    if (_sessionId != null) payload['session_id'] = _sessionId;

    final response = await http.post(
      Uri.parse('$baseUrl/$model'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      // capture session id for subsequent requests
      final sid = data['session_id'];
      if (sid is int) {
        _sessionId = sid;
      } else if (sid is String) {
        _sessionId = int.tryParse(sid);
      }
      final reply = data['response'] as String;
      return reply;
    } else {
      throw Exception('Failed to load response: ${response.statusCode}');
    }
  }

  // Start a new conversation
  static void resetSession() {
    _sessionId = null;
  }

  static int? get currentSessionId => _sessionId;

  // Fetch all sessions
  static Future<List<ChatSessionDto>> fetchSessions() async {
    final resp = await http.get(Uri.parse('$baseUrl/sessions'));
    if (resp.statusCode != 200) {
      throw Exception('Failed to load sessions: ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as List<dynamic>;
    return data
        .map((e) => ChatSessionDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // Fetch messages for a session
  static Future<List<ChatMessageDto>> fetchSessionMessages(
    int sessionId,
  ) async {
    final resp = await http.get(
      Uri.parse('$baseUrl/sessions/$sessionId/messages'),
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to load messages: ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as List<dynamic>;
    return data
        .map((e) => ChatMessageDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // Explicitly set current session
  static void selectSession(int sessionId) {
    _sessionId = sessionId;
  }
}
