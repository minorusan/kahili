import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class ClientLogger {
  static String get _baseUrl {
    if (kIsWeb) return '';
    return 'http://192.168.0.11:3401';
  }

  static Future<void> log(String level, String message, [String? stackTrace]) async {
    try {
      await http.post(
        Uri.parse('$_baseUrl/api/client-log'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'level': level,
          'message': message,
          'stackTrace': stackTrace,
        }),
      );
    } catch (_) {
      // silently fail — can't log the logger failing
    }
  }

  static Future<void> error(String message, [String? stackTrace]) =>
      log('error', message, stackTrace);

  static Future<void> info(String message) => log('info', message);
}
