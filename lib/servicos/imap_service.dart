import 'package:enough_mail/enough_mail.dart';

class ImapService {
  static const _servidores = <String, (String, int, bool)>{
    'outlook.com':  ('imap.outlook.com',    993, true),
    'hotmail.com':  ('imap.outlook.com',    993, true),
    'live.com':     ('imap.outlook.com',    993, true),
    'msn.com':      ('imap.outlook.com',    993, true),
    'yahoo.com':    ('imap.mail.yahoo.com', 993, true),
    'yahoo.com.br': ('imap.mail.yahoo.com', 993, true),
    'icloud.com':   ('imap.mail.me.com',    993, true),
    'me.com':       ('imap.mail.me.com',    993, true),
    'mac.com':      ('imap.mail.me.com',    993, true),
    'zoho.com':     ('imap.zoho.com',       993, true),
    'zoho.com.br':  ('imap.zoho.com',       993, true),
    'uol.com.br':   ('imap.uol.com.br',     993, true),
    'bol.com.br':   ('imap.bol.com.br',     993, true),
    'terra.com.br': ('imap.terra.com.br',   993, true),
    'ig.com.br':    ('imap.ig.com.br',      993, true),
    'globo.com':    ('imap.globo.com',      993, true),
    'r7.com':       ('imap.r7.com',         993, true),
  };

  static ({String host, int port, bool ssl}) inferirServidor(String email) {
    final domain = email.split('@').last.toLowerCase();
    final s = _servidores[domain];
    return s != null
        ? (host: s.$1, port: s.$2, ssl: s.$3)
        : (host: 'imap.$domain', port: 993, ssl: true);
  }

  static String? notaProvedor(String email) {
    final domain = email.split('@').last.toLowerCase();
    if (domain.contains('yahoo')) {
      return '⚠️ Yahoo requer Senha de App.\n'
          'Acesse: Conta Yahoo → Segurança → Gerar senha de app';
    }
    if (['icloud.com', 'me.com', 'mac.com'].contains(domain)) {
      return '⚠️ iCloud exige Senha específica de app.\n'
          'Acesse: appleid.apple.com → Segurança → Senhas de app';
    }
    if (['outlook.com', 'hotmail.com', 'live.com', 'msn.com'].contains(domain)) {
      return 'ℹ️ Outlook: confirme que IMAP está ativado em Configurações de email.\n'
          'Com 2FA ativado: crie uma Senha de App em account.microsoft.com.';
    }
    return null;
  }

  static Future<bool> testarConexao({
    required String email,
    required String password,
    required String host,
    required int port,
    required bool ssl,
  }) async {
    final client = ImapClient(isLogEnabled: false);
    try {
      await client
          .connectToServer(host, port, isSecure: ssl)
          .timeout(const Duration(seconds: 10));
      await client.login(email, password).timeout(const Duration(seconds: 10));
      return true;
    } catch (_) {
      return false;
    } finally {
      try { await client.logout(); } catch (_) {}
    }
  }

  static Future<List<Map<String, dynamic>>> buscarEmails({
    required String email,
    required String password,
    required String host,
    required int port,
    required bool ssl,
    int quantidade = 30,
  }) async {
    final client = ImapClient(isLogEnabled: false);
    final result = <Map<String, dynamic>>[];

    try {
      await client
          .connectToServer(host, port, isSecure: ssl)
          .timeout(const Duration(seconds: 15));
      await client.login(email, password).timeout(const Duration(seconds: 10));

      final mailbox = await client.selectInbox();
      final total = mailbox.messagesExists;
      if (total == 0) return result;

      final start = (total - quantidade + 1).clamp(1, total);
      final seq = MessageSequence.fromRange(start, total);

      final fetched = await client
          .fetchMessages(
            seq,
            'ENVELOPE '
            'BODY.PEEK[HEADER.FIELDS (LIST-UNSUBSCRIBE DKIM-SIGNATURE AUTHENTICATION-RESULTS)] '
            'BODY.PEEK[TEXT]<0.4096>',
          )
          .timeout(const Duration(seconds: 30));

      for (final msg in fetched.messages.reversed) {
        try {
          final assunto = msg.decodeSubject() ?? '';
          final fromList = msg.from;
          final fromAddr =
              (fromList != null && fromList.isNotEmpty) ? fromList.first : null;
          final nome = fromAddr?.personalName ?? '';
          final addr = fromAddr?.email ?? msg.fromEmail ?? '';
          final remetente = nome.isNotEmpty ? '"$nome" <$addr>' : addr;
          final data = msg.envelope?.date?.toIso8601String() ?? '';

          final headers = <Map<String, dynamic>>[
            {'name': 'From', 'value': remetente},
            {'name': 'Subject', 'value': assunto},
            if (data.isNotEmpty) {'name': 'Date', 'value': data},
          ];

          for (final hName in [
            'list-unsubscribe',
            'dkim-signature',
            'authentication-results',
          ]) {
            final v = msg.getHeaderValue(hName);
            if (v != null) headers.add({'name': hName, 'value': v});
          }

          final plain = msg.decodeTextPlainPart() ?? '';
          final html = msg.decodeTextHtmlPart() ?? '';
          final base = plain.isNotEmpty
              ? plain
              : html.replaceAll(RegExp(r'<[^>]+>'), '');
          final snippet = base.trim().replaceAll(RegExp(r'\s+'), ' ');
          final snippetCurto =
              snippet.length > 200 ? snippet.substring(0, 200) : snippet;

          result.add({
            'id': 'imap_${email}_${msg.uid ?? msg.sequenceId ?? result.length}',
            'assunto': assunto,
            'remetente': remetente,
            'data': data,
            'snippet': snippetCurto,
            'html': html,
            'headers': headers,
            'conta': email,
            'ehImap': true,
          });
        } catch (_) {
          continue;
        }
      }
    } catch (_) {
      // retorna o que tiver
    } finally {
      try { await client.logout(); } catch (_) {}
    }

    return result;
  }
}
