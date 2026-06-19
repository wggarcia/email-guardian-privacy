import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Gerencia a label "Quarentena" no Gmail
// Emails perigosos vão para quarentena ao invés da lixeira — recuperáveis

class QuarentenaService {
  static const _prefKeyLabelId = 'quarentena_label_id';
  static const _labelName = 'Quarentena EG';

  String? _accessToken;
  String? _labelId;

  QuarentenaService(this._accessToken);

  /// Garante que a label existe e retorna o ID
  Future<String?> _obterOuCriarLabel() async {
    if (_labelId != null) return _labelId;

    final prefs = await SharedPreferences.getInstance();
    final salvo = prefs.getString(_prefKeyLabelId);
    if (salvo != null) {
      _labelId = salvo;
      return _labelId;
    }

    // Busca labels existentes
    final listRes = await http.get(
      Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/labels'),
      headers: {'Authorization': 'Bearer $_accessToken'},
    );

    if (listRes.statusCode == 200) {
      final data = json.decode(listRes.body) as Map<String, dynamic>;
      final labels = (data['labels'] ?? []) as List;
      for (final l in labels) {
        if ((l['name'] ?? '').toString().toLowerCase() == _labelName.toLowerCase()) {
          _labelId = l['id'].toString();
          await prefs.setString(_prefKeyLabelId, _labelId!);
          return _labelId;
        }
      }
    }

    // Cria a label
    final createRes = await http.post(
      Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/labels'),
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'name': _labelName,
        'labelListVisibility': 'labelShow',
        'messageListVisibility': 'show',
        'color': {
          'backgroundColor': '#fb4c2f',
          'textColor': '#ffffff',
        },
      }),
    );

    if (createRes.statusCode == 200) {
      final label = json.decode(createRes.body) as Map<String, dynamic>;
      _labelId = label['id'].toString();
      await prefs.setString(_prefKeyLabelId, _labelId!);
      return _labelId;
    }

    return null;
  }

  /// Move um email para quarentena (label + remove do INBOX)
  Future<bool> moverParaQuarentena(String emailId) async {
    final labelId = await _obterOuCriarLabel();
    if (labelId == null) return false;

    final res = await http.post(
      Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/$emailId/modify'),
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'addLabelIds': [labelId],
        'removeLabelIds': ['INBOX'],
      }),
    );

    return res.statusCode == 200;
  }

  /// Libera um email da quarentena (volta para INBOX)
  Future<bool> liberarDaQuarentena(String emailId) async {
    final labelId = await _obterOuCriarLabel();
    if (labelId == null) return false;

    final res = await http.post(
      Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/$emailId/modify'),
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'addLabelIds': ['INBOX'],
        'removeLabelIds': [labelId],
      }),
    );

    return res.statusCode == 200;
  }

  /// Lista emails em quarentena
  Future<List<Map<String, dynamic>>> listarQuarentena() async {
    final labelId = await _obterOuCriarLabel();
    if (labelId == null) return [];

    final res = await http.get(
      Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages?labelIds=$labelId&maxResults=20'),
      headers: {'Authorization': 'Bearer $_accessToken'},
    );

    if (res.statusCode != 200) return [];

    final data = json.decode(res.body) as Map<String, dynamic>;
    return ((data['messages'] ?? []) as List).cast<Map<String, dynamic>>();
  }
}
