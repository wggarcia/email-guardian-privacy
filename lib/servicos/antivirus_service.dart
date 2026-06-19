// Motor antivírus local — sem dependências externas
// Safe Browsing (Google API) é integrado via SafeBrowsingService quando a chave estiver configurada

class AntivirusService {
  // ── Marcas mais falsificadas no Brasil ──────────────────────────────────────
  static const _marcasConhecidas = {
    'paypal': ['paypal.com'],
    'itaú': ['itau.com.br', 'itau.com'],
    'bradesco': ['bradesco.com.br'],
    'nubank': ['nubank.com.br'],
    'inter': ['bancointer.com.br', 'inter.co'],
    'mercadopago': ['mercadopago.com', 'mercadopago.com.br'],
    'mercadolivre': ['mercadolivre.com.br', 'mercadolivre.com'],
    'amazon': ['amazon.com.br', 'amazon.com'],
    'microsoft': ['microsoft.com', 'outlook.com', 'hotmail.com'],
    'apple': ['apple.com', 'icloud.com'],
    'google': ['google.com', 'gmail.com', 'googlemail.com'],
    'netflix': ['netflix.com'],
    'santander': ['santander.com.br'],
    'caixa': ['caixa.gov.br'],
    'bancodobrasil': ['bb.com.br'],
    'correios': ['correios.com.br'],
    'receita': ['fazenda.gov.br', 'receita.fazenda.gov.br'],
    'detran': ['detran.gov.br'],
    'serasa': ['serasa.com.br'],
    'claro': ['claro.com.br'],
    'vivo': ['vivo.com.br'],
    'tim': ['tim.com.br'],
    'oi': ['oi.com.br'],
    'shopee': ['shopee.com.br'],
    'ifood': ['ifood.com.br'],
    'submarino': ['submarino.com.br'],
    'americanas': ['americanas.com.br'],
    'magalu': ['magazineluiza.com.br', 'magalu.com.br'],
  };

  // ── Extensões de anexo perigosas ────────────────────────────────────────────
  static const _extensoesPerigosas = {
    '.exe': 'executável Windows',
    '.msi': 'instalador Windows',
    '.bat': 'script batch',
    '.cmd': 'script de comandos',
    '.vbs': 'script Visual Basic',
    '.ps1': 'script PowerShell',
    '.js':  'script JavaScript',
    '.jar': 'aplicativo Java',
    '.apk': 'app Android externo',
    '.dmg': 'imagem de disco',
    '.iso': 'imagem de disco',
    '.docm': 'Word com macros',
    '.xlsm': 'Excel com macros',
    '.pptm': 'PowerPoint com macros',
    '.xlsb': 'Excel binário',
  };

  // ── Substituições homógrafas comuns ─────────────────────────────────────────
  static const _homografos = {
    'а': 'a', 'о': 'o', 'е': 'e', 'р': 'p', 'с': 'c',
    'х': 'x', 'і': 'i', 'ї': 'i', 'ó': 'o', 'ò': 'o',
  };

  // Padrões numérico-letra
  static String _normalizarDominio(String dominio) {
    var d = dominio.toLowerCase();
    _homografos.forEach((k, v) => d = d.replaceAll(k, v));
    d = d.replaceAll('0', 'o').replaceAll('1', 'i').replaceAll('3', 'e')
         .replaceAll('4', 'a').replaceAll('5', 's').replaceAll('vv', 'w')
         .replaceAll('rn', 'm');
    return d;
  }

  // ── 1. Detector de Spoofing ─────────────────────────────────────────────────
  static Map<String, dynamic> verificarSpoofing(String remetente) {
    // Extrai: "Nome Display <email@dominio.com>"
    final matchEmail = RegExp(r'<([^@]+@([^>]+))>').firstMatch(remetente);
    if (matchEmail == null) return {'spoofing': false};

    final emailCompleto = matchEmail.group(1)!.toLowerCase();
    final dominio = matchEmail.group(2)!.toLowerCase();
    final nomeDisplay = remetente.replaceAll(RegExp(r'<[^>]+>'), '').trim().toLowerCase();

    // Verifica se o nome display menciona uma marca mas o domínio não confere
    for (final entry in _marcasConhecidas.entries) {
      final marca = entry.key;
      final dominiosOficiais = entry.value;

      final nomeTemMarca = nomeDisplay.contains(marca) ||
          nomeDisplay.contains(marca.replaceAll(' ', '')) ||
          emailCompleto.split('@').first.contains(marca);

      if (nomeTemMarca) {
        final dominioEhOficial = dominiosOficiais.any((d) =>
            dominio == d || dominio.endsWith('.$d'));

        if (!dominioEhOficial) {
          return {
            'spoofing': true,
            'marcaAlvo': marca,
            'dominioReal': dominio,
            'dominiosOficiais': dominiosOficiais,
            'gravidade': 'CRÍTICO',
          };
        }
      }
    }

    return {'spoofing': false, 'dominio': dominio};
  }

  // ── 2. Verificador SPF / DKIM / DMARC ──────────────────────────────────────
  static Map<String, dynamic> verificarAutenticacao(List<dynamic> headers) {
    String spf = 'desconhecido', dkim = 'desconhecido', dmarc = 'desconhecido';
    bool falhou = false;

    for (final h in headers) {
      final nome = (h['name'] ?? '').toString().toLowerCase();
      final valor = (h['value'] ?? '').toString().toLowerCase();

      if (nome == 'authentication-results' || nome == 'arc-authentication-results') {
        // SPF
        final spfMatch = RegExp(r'spf=(\w+)').firstMatch(valor);
        if (spfMatch != null) {
          spf = spfMatch.group(1)!;
          if (spf == 'fail' || spf == 'softfail') falhou = true;
        }
        // DKIM
        final dkimMatch = RegExp(r'dkim=(\w+)').firstMatch(valor);
        if (dkimMatch != null) {
          dkim = dkimMatch.group(1)!;
          if (dkim == 'fail') falhou = true;
        }
        // DMARC
        final dmarcMatch = RegExp(r'dmarc=(\w+)').firstMatch(valor);
        if (dmarcMatch != null) {
          dmarc = dmarcMatch.group(1)!;
          if (dmarc == 'fail') falhou = true;
        }
      }

      // Received-SPF header alternativo
      if (nome == 'received-spf') {
        if (valor.startsWith('fail') || valor.startsWith('softfail')) {
          spf = 'fail';
          falhou = true;
        } else if (valor.startsWith('pass')) {
          spf = 'pass';
        }
      }
    }

    return {
      'spf': spf,
      'dkim': dkim,
      'dmarc': dmarc,
      'autenticacaoFalhou': falhou,
      'resumo': falhou
          ? 'Falha na verificação — email pode ser falsificado'
          : (spf == 'pass' && dkim == 'pass' ? 'Autenticação verificada' : 'Autenticação parcial'),
    };
  }

  // ── 3. Analisador de Anexos ─────────────────────────────────────────────────
  static Map<String, dynamic> analisarAnexos(Map<String, dynamic> payload) {
    final anexosPerigosos = <Map<String, dynamic>>[];
    final partes = <dynamic>[];

    void coletarPartes(dynamic parte) {
      if (parte == null) return;
      if (parte is Map) {
        partes.add(parte);
        final subParts = parte['parts'];
        if (subParts is List) {
          for (final p in subParts) coletarPartes(p);
        }
      }
    }

    coletarPartes(payload);

    for (final parte in partes) {
      final filename = (parte['filename'] ?? '').toString().toLowerCase();
      final mimeType = (parte['mimeType'] ?? '').toString().toLowerCase();

      if (filename.isEmpty) continue;

      // Verifica extensão perigosa
      for (final ext in _extensoesPerigosas.entries) {
        if (filename.endsWith(ext.key)) {
          anexosPerigosos.add({
            'nome': parte['filename'],
            'extensao': ext.key,
            'tipo': ext.value,
            'mimeType': mimeType,
          });
          break;
        }
      }

      // Detecta PDF ou imagem que pode esconder executável
      if ((mimeType.contains('octet-stream') || mimeType.contains('application/x-')) &&
          !filename.endsWith('.pdf') &&
          !filename.endsWith('.jpg') &&
          !filename.endsWith('.png')) {
        if (anexosPerigosos.every((a) => a['nome'] != parte['filename'])) {
          anexosPerigosos.add({
            'nome': parte['filename'],
            'extensao': '',
            'tipo': 'arquivo binário suspeito',
            'mimeType': mimeType,
          });
        }
      }
    }

    return {
      'temAnexosPerigosos': anexosPerigosos.isNotEmpty,
      'anexosPerigosos': anexosPerigosos,
      'quantidadePerigosa': anexosPerigosos.length,
    };
  }

  // ── 4. Detector de Homógrafos no domínio ───────────────────────────────────
  static Map<String, dynamic> detectarHomografo(String remetente) {
    final matchDominio = RegExp(r'@([^\s>]+)').firstMatch(remetente);
    if (matchDominio == null) return {'homografo': false};

    final dominioOriginal = matchDominio.group(1)!.toLowerCase();
    final dominioNormalizado = _normalizarDominio(dominioOriginal);

    // Verifica se normalizado corresponde a marca conhecida mas original não
    for (final entry in _marcasConhecidas.entries) {
      for (final dominioOficial in entry.value) {
        final dominioOficialNorm = _normalizarDominio(dominioOficial);
        if (dominioNormalizado == dominioOficialNorm && dominioOriginal != dominioOficial) {
          return {
            'homografo': true,
            'dominioFalso': dominioOriginal,
            'dominioReal': dominioOficial,
            'marca': entry.key,
          };
        }
      }
    }

    return {'homografo': false};
  }

  // ── 5. Extrator de Links ────────────────────────────────────────────────────
  static List<String> extrairLinks(String texto) {
    final regex = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);
    return regex.allMatches(texto).map((m) => m.group(0)!).toSet().toList();
  }

  static bool linkEncurtado(String url) {
    const encurtadores = [
      'bit.ly', 'tinyurl.com', 'goo.gl', 't.co', 'ow.ly',
      'short.link', 'cutt.ly', 'rb.gy', 'is.gd', 'buff.ly',
    ];
    return encurtadores.any((e) => url.contains(e));
  }

  // ── 6. Score total de ameaça ────────────────────────────────────────────────
  static Map<String, dynamic> calcularScoreAmeaca({
    required Map<String, dynamic> phishing,
    required Map<String, dynamic> spoofing,
    required Map<String, dynamic> autenticacao,
    required Map<String, dynamic> anexos,
    required Map<String, dynamic> homografo,
    required List<String> links,
  }) {
    int score = 0;
    final alertas = <String>[];

    // Phishing keywords
    final scorePhishing = (phishing['score'] ?? 0) as int;
    score += (scorePhishing * 0.4).round();

    // Spoofing (peso alto)
    if (spoofing['spoofing'] == true) {
      score += 60;
      alertas.add('⚠️ Spoofing: fingindo ser ${spoofing['marcaAlvo']}');
    }

    // Autenticação falhou
    if (autenticacao['autenticacaoFalhou'] == true) {
      score += 35;
      alertas.add('🔓 SPF/DKIM/DMARC falhou — remetente não verificado');
    }

    // Anexos perigosos
    if (anexos['temAnexosPerigosos'] == true) {
      score += 50;
      final count = anexos['quantidadePerigosa'];
      alertas.add('📎 $count anexo${count > 1 ? 's' : ''} perigoso${count > 1 ? 's' : ''} detectado${count > 1 ? 's' : ''}');
    }

    // Homógrafo
    if (homografo['homografo'] == true) {
      score += 70;
      alertas.add('🔤 Domínio falso: ${homografo['dominioFalso']} imita ${homografo['dominioReal']}');
    }

    // Links encurtados
    final linksEncurtados = links.where(linkEncurtado).length;
    if (linksEncurtados > 0) {
      score += 20;
      alertas.add('🔗 $linksEncurtados link${linksEncurtados > 1 ? 's' : ''} encurtado${linksEncurtados > 1 ? 's' : ''}');
    }

    score = score.clamp(0, 100);

    String nivel;
    if (score >= 75)      nivel = 'CRÍTICO';
    else if (score >= 50) nivel = 'ALTO';
    else if (score >= 25) nivel = 'MÉDIO';
    else                  nivel = 'SEGURO';

    return {
      'score': score,
      'nivel': nivel,
      'alertas': alertas,
      'links': links,
      'linksCount': links.length,
      'linksEncurtados': linksEncurtados,
    };
  }

  // ── Análise completa de um email ────────────────────────────────────────────
  static Map<String, dynamic> analisarCompleto({
    required String remetente,
    required String assunto,
    required String snippet,
    required String html,
    required List<dynamic> headers,
    required Map<String, dynamic> payload,
    required Map<String, dynamic> phishingExistente,
  }) {
    final spoofing = verificarSpoofing(remetente);
    final autenticacao = verificarAutenticacao(headers);
    final anexos = analisarAnexos(payload);
    final homografo = detectarHomografo(remetente);
    final links = extrairLinks(html.isNotEmpty ? html : snippet);
    final ameaca = calcularScoreAmeaca(
      phishing: phishingExistente,
      spoofing: spoofing,
      autenticacao: autenticacao,
      anexos: anexos,
      homografo: homografo,
      links: links,
    );

    return {
      'spoofing': spoofing,
      'autenticacao': autenticacao,
      'anexos': anexos,
      'homografo': homografo,
      'ameaca': ameaca,
      'precisaQuarentena': ameaca['score'] >= 75,
    };
  }
}
