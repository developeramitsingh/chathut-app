import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  static String get baseUrl {
    if (kIsWeb) {
      return 'http://localhost:3000';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000';
    }
    return 'http://localhost:3000';
  }

  static String? token;
  static Map<String, dynamic>? currentUser;

  static Map<String, String> get headers {
    final authHeaders = token != null ? {'Authorization': 'Bearer $token'} : {};
    return {'Content-Type': 'application/json', ...authHeaders};
  }

  static Map<String, dynamic> _decodeJson(String responseBody) {
    try {
      return jsonDecode(responseBody) as Map<String, dynamic>;
    } on FormatException catch (_) {
      throw Exception('Invalid JSON response from backend: $responseBody');
    }
  }

  static List<dynamic> _decodeJsonList(String responseBody) {
    try {
      return jsonDecode(responseBody) as List<dynamic>;
    } on FormatException catch (_) {
      throw Exception('Invalid JSON response from backend: $responseBody');
    }
  }

  static Future<Map<String, dynamic>> signup({
    required String name,
    required String phone,
    required String gender,
    String? email,
    String role = 'user',
  }) async {
    final uri = Uri.parse('$baseUrl/auth/signup');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'phone': phone,
        'email': email,
        'gender': gender,
        'role': role,
      }),
    );

    final body = _decodeJson(response.body);
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception(body['message'] ?? 'Signup failed (status ${response.statusCode})');
    }

    return body;
  }

  static Future<void> requestOtp(String phone) async {
    final uri = Uri.parse('$baseUrl/auth/request-otp');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phone}),
    );

    final body = _decodeJson(response.body);
    if (response.statusCode != 200) {
      throw Exception(body['message'] ?? 'Unable to request OTP (status ${response.statusCode})');
    }
  }

  static Future<void> login({
    required String phone,
    required String otp,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/login');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phone, 'otp': otp}),
    );
    final body = _decodeJson(response.body);
    if (response.statusCode != 200) {
      throw Exception(body['message'] ?? 'Login failed (status ${response.statusCode})');
    }

    token = body['accessToken'] as String?;
    currentUser = body['user'] as Map<String, dynamic>?;
  }

  static Future<List<dynamic>> getRooms() async {
    final uri = Uri.parse('$baseUrl/rooms');
    final response = await http.get(uri, headers: headers);
    final body = _decodeJsonList(response.body);
    if (response.statusCode != 200) {
      throw Exception('Unable to load rooms (status ${response.statusCode})');
    }
    return body;
  }

  static Future<List<dynamic>> getLiveUsers() async {
    final uri = Uri.parse('$baseUrl/users/live');
    final response = await http.get(uri, headers: headers);
    final body = _decodeJsonList(response.body);
    if (response.statusCode != 200) {
      throw Exception('Unable to load live users (status ${response.statusCode})');
    }
    return body;
  }

  static Future<Map<String, dynamic>> getRoom(String roomId) async {
    final uri = Uri.parse('$baseUrl/rooms/$roomId');
    final response = await http.get(uri, headers: headers);
    final body = _decodeJson(response.body);
    if (response.statusCode != 200) {
      throw Exception(body['message'] ?? 'Unable to load room (status ${response.statusCode})');
    }
    return body;
  }

  static Future<Map<String, dynamic>> createRoom({required String name}) async {
    final uri = Uri.parse('$baseUrl/rooms');
    final response = await http.post(uri, headers: headers, body: jsonEncode({'name': name}));
    final body = _decodeJson(response.body);
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception(body['message'] ?? 'Unable to create room (status ${response.statusCode})');
    }
    return body;
  }

  static Future<Map<String, dynamic>> joinRoom({required String roomId, required String role}) async {
    final uri = Uri.parse('$baseUrl/rooms/$roomId/join');
    final response = await http.post(uri, headers: headers, body: jsonEncode({'role': role}));
    final body = _decodeJson(response.body);
    if (response.statusCode != 200) {
      throw Exception(body['message'] ?? 'Unable to join room (status ${response.statusCode})');
    }
    return body;
  }

  static Future<Map<String, dynamic>> leaveRoom({required String roomId}) async {
    final uri = Uri.parse('$baseUrl/rooms/$roomId/leave');
    final response = await http.post(uri, headers: headers);
    final body = _decodeJson(response.body);
    if (response.statusCode != 200) {
      throw Exception(body['message'] ?? 'Unable to leave room (status ${response.statusCode})');
    }
    return body;
  }

  static void logout() {
    token = null;
    currentUser = null;
  }
}
