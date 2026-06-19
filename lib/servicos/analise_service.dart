import 'package:flutter/material.dart';

class AnaliseService {
  static const _dominiosRastreamento = [
    'mailchimp.com', 'list-manage.com', 'sendgrid.net', 'sendgrid.com',
    'constantcontact.com', 'klaviyo.com', 'hubspot.com', 'hs-email.net',
    'salesforce.com', 'exacttarget.com', 'mailgun.org', 'mailgun.net',
    'amazonaws.com', 'mandrillapp.com', 'marketo.com', 'pardot.com',
    'eloqua.com', 'createsend.com', 'campaignmonitor.com', 'mailerlite.com',
    'activehosted.com', 'aweber.com', 'getresponse.com', 'convertkit.com',
    'drip.com', 'intercom-mail.com', 'customer.io', 'braze.com',
    'iterable.com', 'sendpulse.com', 'brevo.com', 'sendinblue.com',
  ];

  static Map<String, dynamic> analisar(
    String texto,
    String html,
    List<dynamic> headers,
    String remetente,
    String assunto,
  ) {
    final phishing = _detectarPhishing(texto, assunto);
    final manipulacao = _detectarManipulacao(texto, assunto);
    final rastreadores = _detectarRastreadores(html);
    final unsubscribeLink = _detectarUnsubscribe(headers);
    final categoria = _categorizar(texto, assunto, headers, unsubscribeLink);

    // Dark pattern sobrescreve apenas quando não há phishing/suspeito real
    final tipoFinal = phishing['score'] as int >= 25
        ? phishing['tipo']
        : manipulacao['score'] as int >= 40
            ? '🎭 MANIPULAÇÃO'
            : phishing['tipo'];
    final corFinal = phishing['score'] as int >= 25
        ? phishing['cor']
        : manipulacao['score'] as int >= 40
            ? Colors.deepPurple
            : phishing['cor'];

    return {
      ...phishing,
      'tipo': tipoFinal,
      'cor': corFinal,
      'manipulacao': manipulacao,
      'rastreadores': rastreadores,
      'quantidadeRastreadores': rastreadores.length,
      'linkDesinscrever': unsubscribeLink,
      'categoria': categoria,
      'remetente': remetente,
      'assunto': assunto,
    };
  }

  static Set<String> _detectarRastreadores(String html) {
    final encontrados = <String>{};
    final lower = html.toLowerCase();
    for (final dominio in _dominiosRastreamento) {
      if (lower.contains(dominio)) {
        encontrados.add(dominio.split('.').first);
      }
    }
    return encontrados;
  }

  static String? _detectarUnsubscribe(List<dynamic> headers) {
    for (final h in headers) {
      final name = (h['name'] ?? '').toString().toLowerCase();
      if (name == 'list-unsubscribe') {
        final val = h['value'].toString();
        final urlMatch = RegExp(r'<(https?://[^>]+)>').firstMatch(val);
        if (urlMatch != null) return urlMatch.group(1);
        final mailMatch = RegExp(r'<(mailto:[^>]+)>').firstMatch(val);
        if (mailMatch != null) return mailMatch.group(1);
      }
    }
    return null;
  }

  static String _categorizar(
    String texto,
    String assunto,
    List<dynamic> headers,
    String? unsubscribeLink,
  ) {
    if (unsubscribeLink != null) return 'marketing';

    final t = '${texto.toLowerCase()} ${assunto.toLowerCase()}';

    if (RegExp(r'promoç|oferta|desconto|sale|%\s*off|cupom|grátis|frete').hasMatch(t)) return 'marketing';
    if (RegExp(r'newsletter|informativo|notícia|update|novidade').hasMatch(t)) return 'newsletter';
    if (RegExp(r'fatura|boleto|pagamento|invoice|cobrança|vencimento').hasMatch(t)) return 'financeiro';
    if (RegExp(r'senha|código|verificação|confirmar|autenticar|2fa|otp').hasMatch(t)) return 'autenticacao';
    if (RegExp(r'segui|comentou|curtiu|mencionou|linkedin|instagram|facebook|twitter').hasMatch(t)) return 'social';

    return 'outros';
  }

  // ── Dark patterns / manipulação ────────────────────────────────────────────
  static Map<String, dynamic> _detectarManipulacao(String texto, String assunto) {
    final t = '${texto.toLowerCase()} ${assunto.toLowerCase()}';
    int score = 0;
    final categorias = <String>[];

    // Urgência falsa
    if (RegExp(r'expira hoje|últimas horas|só hoje|acaba em|última chance|restam poucas|por tempo limitado|encerra|agindo agora|aja agora').hasMatch(t)) {
      score += 25;
      categorias.add('urgência');
    }

    // FOMO — fear of missing out
    if (RegExp(r'você está perdendo|não perca|oportunidade única|apenas para você|selecionado especialmente|convite exclusivo|seus amigos já|missing out').hasMatch(t)) {
      score += 25;
      categorias.add('fomo');
    }

    // Escassez falsa
    if (RegExp(r'estoque limitado|últimas unidades|quase esgotado|apenas \d+ disponíveis|reservar agora|garantir meu|limited stock|selling fast').hasMatch(t)) {
      score += 25;
      categorias.add('escassez');
    }

    // Clickbait
    if (RegExp(r'você não vai acreditar|impressionante|inacreditável|esse truque|segredo que|descubra como|revelado|chocante|shocking').hasMatch(t)) {
      score += 20;
      categorias.add('clickbait');
    }

    // Pressão emocional
    if (RegExp(r'você merece|foi escolhido|parabéns você ganhou|não se arrependa|não deixe para amanhã|você foi selecionado').hasMatch(t)) {
      score += 20;
      categorias.add('emocional');
    }

    // Pressão social falsa
    if (RegExp(r'\d+ pessoas (já|viram|compraram)|todo mundo está|mais vendido|tendência|viral|best seller|trending').hasMatch(t)) {
      score += 15;
      categorias.add('social');
    }

    score = score.clamp(0, 100);
    return {'score': score, 'categorias': categorias, 'ehManipulacao': score >= 40};
  }

  static Map<String, dynamic> _detectarPhishing(String texto, String assunto) {
    final t = '${texto.toLowerCase()} ${assunto.toLowerCase()}';
    int score = 0;
    final sinais = <String>[];

    if (RegExp(r'pix').hasMatch(t) && RegExp(r'urgente|agora|imediato').hasMatch(t)) {
      score += 90;
      sinais.add('PIX urgente');
    }
    if (RegExp(r'senha|password').hasMatch(t) && RegExp(r'verificar|confirmar|atualizar').hasMatch(t)) {
      score += 85;
      sinais.add('Roubo de credencial');
    }
    if (RegExp(r'conta suspensa|account suspended|bloqueada|bloqueado').hasMatch(t)) {
      score += 80;
      sinais.add('Ameaça de bloqueio');
    }
    if (RegExp(r'bit\.ly|tinyurl|goo\.gl|t\.co/[a-z0-9]{5,}').hasMatch(t)) {
      score += 75;
      sinais.add('Link encurtado');
    }
    if (RegExp(r'verify your account|confirme seus dados|update your information').hasMatch(t)) {
      score += 70;
      sinais.add('Solicitação suspeita de dados');
    }
    if (RegExp(r'ganhe dinheiro|trabalhe em casa|renda extra').hasMatch(t)) {
      score += 60;
      sinais.add('Promessa suspeita');
    }
    if (RegExp(r'urgente|imediato|expira em').hasMatch(t)) {
      score += 25;
      sinais.add('Urgência');
    }
    if (RegExp(r'http://').hasMatch(t)) {
      score += 20;
      sinais.add('Link sem HTTPS');
    }

    score = score.clamp(0, 100);

    if (score >= 80) return {'tipo': '🚨 GOLPE', 'cor': Colors.red, 'score': score, 'sinais': sinais};
    if (score >= 50) return {'tipo': '⚠️ PHISHING', 'cor': Colors.orange, 'score': score, 'sinais': sinais};
    if (score >= 25) return {'tipo': '📢 SUSPEITO', 'cor': Colors.amber, 'score': score, 'sinais': sinais};
    return {'tipo': '🧾 SEGURO', 'cor': Colors.green, 'score': score, 'sinais': sinais};
  }

  // Gera estatísticas do scan completo
  static Map<String, dynamic> calcularEstatisticas(List<Map<String, dynamic>> emails) {
    int marketing = 0, golpes = 0, rastreadores = 0, desinscrever = 0, manipulacao = 0;
    final empresasRastreando = <String>{};
    final remetentesMarketing = <String>{};

    for (final e in emails) {
      final cat = e['analise']?['categoria'] ?? '';
      final tipo = e['analise']?['tipo'] ?? '';
      final r = e['analise']?['rastreadores'] as Set<String>? ?? {};
      final link = e['analise']?['linkDesinscrever'];

      if (cat == 'marketing' || cat == 'newsletter') {
        marketing++;
        final rem = e['remetente'] ?? '';
        if (rem.isNotEmpty) remetentesMarketing.add(rem);
      }
      if (tipo == '🚨 GOLPE' || tipo == '⚠️ PHISHING') golpes++;
      if (tipo == '🎭 MANIPULAÇÃO') manipulacao++;
      if (r.isNotEmpty) {
        rastreadores++;
        empresasRastreando.addAll(r);
      }
      if (link != null) desinscrever++;
    }

    return {
      'total': emails.length,
      'marketing': marketing,
      'golpes': golpes,
      'manipulacao': manipulacao,
      'comRastreadores': rastreadores,
      'empresasRastreando': empresasRastreando.length,
      'desinscrever': desinscrever,
      'remetentesMarketing': remetentesMarketing.length,
    };
  }
}
