import 'dart:convert';
import 'package:http/http.dart' as http;

// Google Safe Browsing API v4
// Chave gratuita em: https://console.cloud.google.com → APIs → Safe Browsing
// Cota gratuita: 10.000 consultas/dia

class SafeBrowsingService {
  // Configure sua chave aqui ou via variável de ambiente
  static const _apiKey = String.fromEnvironment('SAFE_BROWSING_KEY', defaultValue: '');

  static bool get configurado => _apiKey.isNotEmpty;

  static const _endpoint =
      'https://safebrowsing.googleapis.com/v4/threatMatches:find';

  static const _threatTypes = [
    'MALWARE',
    'SOCIAL_ENGINEERING',
    'UNWANTED_SOFTWARE',
    'POTENTIALLY_HARMFUL_APPLICATION',
  ];

  /// Verifica uma lista de URLs contra o banco do Google.
  /// Retorna mapa de url → bool (true = perigosa).
  static Future<Map<String, bool>> verificarUrls(List<String> urls) async {
    if (!configurado || urls.isEmpty) {
      return {for (final u in urls) u: false};
    }

    try {
      final body = {
        'client': {'clientId': 'email-guardian', 'clientVersion': '1.0.1'},
        'threatInfo': {
          'threatTypes': _threatTypes,
          'platformTypes': ['ANY_PLATFORM'],
          'threatEntryTypes': ['URL'],
          'threatEntries': urls.map((u) => {'url': u}).toList(),
        },
      };

      final response = await http
          .post(
            Uri.parse('$_endpoint?key=$_apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        return {for (final u in urls) u: false};
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final matches = (data['matches'] ?? []) as List;
      final urlsPerigosas = matches
          .map((m) => (m['threat']?['url'] ?? '').toString())
          .toSet();

      return {for (final u in urls) u: urlsPerigosas.contains(u)};
    } catch (_) {
      return {for (final u in urls) u: false};
    }
  }

  /// Verifica uma única URL (conveniência).
  static Future<bool> urlEhPerigosa(String url) async {
    final resultado = await verificarUrls([url]);
    return resultado[url] ?? false;
  }
}
