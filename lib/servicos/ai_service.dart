import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/secrets.dart';

class AiService {
  static const _workerUrl = 'https://email-guardian-ai.wggarcia33.workers.dev/';
  static const _appKey = kAiWorkerKey;

  static Future<Map<String, dynamic>?> analisar({
    required String remetente,
    required String assunto,
    required String snippet,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse(_workerUrl),
            headers: {
              'Content-Type': 'application/json',
              'X-App-Key': _appKey,
            },
            body: jsonEncode({
              'remetente': remetente,
              'assunto': assunto,
              'snippet': snippet,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }
}
