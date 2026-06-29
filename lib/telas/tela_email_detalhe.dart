import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../servicos/ai_service.dart';

class TelaEmailDetalhe extends StatefulWidget {
  final Map<String, dynamic> email;
  final bool premium;
  final VoidCallback onAssinar;
  final Future<void> Function(String id) onQuarentenar;
  final Future<void> Function(String id) onDeletar;

  const TelaEmailDetalhe({
    super.key,
    required this.email,
    required this.premium,
    required this.onAssinar,
    required this.onQuarentenar,
    required this.onDeletar,
  });

  @override
  State<TelaEmailDetalhe> createState() => _TelaEmailDetalheState();
}

class _TelaEmailDetalheState extends State<TelaEmailDetalhe> {
  Map<String, dynamic>? _aiResult;
  bool _aiLoading = true;

  @override
  void initState() {
    super.initState();
    _analisarComIA();
  }

  Future<void> _analisarComIA() async {
    final result = await AiService.analisar(
      remetente: widget.email['remetente'] as String? ?? '',
      assunto: widget.email['assunto'] as String? ?? '',
      snippet: widget.email['snippet'] as String? ?? '',
    );
    if (mounted) setState(() { _aiResult = result; _aiLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final av = widget.email['antivirus'] as Map<String, dynamic>? ?? {};
    final analise = widget.email['analise'] as Map<String, dynamic>? ?? {};
    final ameaca = av['ameaca'] as Map<String, dynamic>? ?? {};
    final spoofing = av['spoofing'] as Map<String, dynamic>? ?? {};
    final autenticacao = av['autenticacao'] as Map<String, dynamic>? ?? {};
    final anexos = av['anexos'] as Map<String, dynamic>? ?? {};
    final homografo = av['homografo'] as Map<String, dynamic>? ?? {};
    final links = (ameaca['links'] ?? []) as List;
    final alertas = (ameaca['alertas'] ?? []) as List;
    final score = (ameaca['score'] ?? 0) as int;
    final nivel = ameaca['nivel'] as String? ?? 'SEGURO';
    final rastreadores = (analise['rastreadores'] as Set<String>?) ?? {};

    final corNivel = nivel == 'CRÍTICO'
        ? Colors.red
        : nivel == 'ALTO'
            ? Colors.orange
            : nivel == 'MÉDIO'
                ? Colors.amber
                : Colors.green;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: AppBar(
        title: const Text('Análise do Email'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: () async {
              await widget.onDeletar(widget.email['id'] as String);
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildScoreCard(score, nivel, corNivel),
          const SizedBox(height: 16),
          _buildAiCard(),
          const SizedBox(height: 16),
          _buildEmailInfo(),
          const SizedBox(height: 16),
          if (alertas.isNotEmpty) ...[
            _buildAlertasCard(alertas),
            const SizedBox(height: 16),
          ],
          _buildAutenticacao(autenticacao),
          const SizedBox(height: 16),
          if (spoofing['spoofing'] == true) ...[
            _buildSpoofingCard(spoofing),
            const SizedBox(height: 16),
          ],
          if (homografo['homografo'] == true) ...[
            _buildHomografoCard(homografo),
            const SizedBox(height: 16),
          ],
          if (anexos['temAnexosPerigosos'] == true) ...[
            _buildAnexosCard(anexos),
            const SizedBox(height: 16),
          ],
          if (rastreadores.isNotEmpty) ...[
            _buildRastreadoresCard(rastreadores),
            const SizedBox(height: 16),
          ],
          if (links.isNotEmpty) ...[
            _buildLinksCard(links),
            const SizedBox(height: 16),
          ],
          _buildAcoes(context, nivel, analise['linkDesinscrever'] as String?),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildAiCard() {
    if (_aiLoading) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.purple.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
        ),
        child: const Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.purple)),
            SizedBox(width: 12),
            Text('Analisando com IA...', style: TextStyle(fontSize: 13, color: Colors.purple)),
          ],
        ),
      );
    }
    if (_aiResult == null) return const SizedBox.shrink();

    final _ = _aiResult!['seguro'] as bool? ?? true;
    final nivel = (_aiResult!['nivel'] as String? ?? 'seguro').toLowerCase();
    final resumo = _aiResult!['resumo'] as String? ?? '';
    final alertas = (_aiResult!['alertas'] as List?)?.cast<String>() ?? [];

    final cor = nivel == 'perigoso'
        ? Colors.red
        : nivel == 'suspeito'
            ? Colors.orange
            : Colors.green;
    final icone = nivel == 'perigoso' ? '🚨' : nivel == 'suspeito' ? '⚠️' : '✅';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(icone, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('IA: ${nivel.toUpperCase()}',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: cor)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('Claude AI', style: TextStyle(fontSize: 9, color: Colors.purple, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    if (resumo.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(resumo, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (alertas.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...alertas.map((a) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: TextStyle(color: cor, fontSize: 12)),
                  Expanded(child: Text(a, style: const TextStyle(fontSize: 11, color: Colors.white60))),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }

  Widget _buildScoreCard(int score, String nivel, Color cor) {
    final descricao = nivel == 'CRÍTICO'
        ? 'Não clique em links. Mova para quarentena.'
        : nivel == 'ALTO'
            ? 'Atenção — sinais suspeitos detectados.'
            : nivel == 'MÉDIO'
                ? 'Verifique o remetente antes de agir.'
                : 'Email parece legítimo.';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cor.withValues(alpha: 0.18), cor.withValues(alpha: 0.04)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cor.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            height: 76,
            child: CustomPaint(
              painter: _GaugePainter(score / 100, cor),
              child: Center(
                child: Text(
                  '$score',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cor),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nível: $nivel',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cor)),
                const SizedBox(height: 6),
                Text(descricao, style: const TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _campo('Assunto', widget.email['assunto'] as String? ?? 'Sem assunto',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _campo('Remetente', widget.email['remetente'] as String? ?? '',
                style: const TextStyle(fontSize: 13, color: Colors.white70)),
            if ((widget.email['snippet'] as String? ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              _campo(
                'Prévia',
                widget.email['snippet'] as String? ?? '',
                style: const TextStyle(fontSize: 12, color: Colors.white54),
                maxLines: 3,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _campo(String label, String valor,
      {TextStyle? style, int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white38)),
        const SizedBox(height: 2),
        Text(valor, style: style, maxLines: maxLines, overflow: TextOverflow.ellipsis),
      ],
    );
  }

  Widget _buildAlertasCard(List alertas) {
    return Card(
      color: Colors.red.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.warning, color: Colors.red, size: 16),
              SizedBox(width: 6),
              Text('Alertas', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 14)),
            ]),
            const SizedBox(height: 10),
            ...alertas.map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.circle, size: 6, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(child: Text(a.toString(), style: const TextStyle(fontSize: 12))),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildAutenticacao(Map<String, dynamic> auth) {
    final spf = auth['spf'] as String? ?? 'desconhecido';
    final dkim = auth['dkim'] as String? ?? 'desconhecido';
    final dmarc = auth['dmarc'] as String? ?? 'desconhecido';

    Color chipColor(String v) => v == 'pass'
        ? Colors.green
        : (v == 'fail' || v == 'softfail')
            ? Colors.red
            : Colors.white38;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Autenticação do Remetente',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 10),
            Row(
              children: [
                _authChip('SPF', spf, chipColor(spf)),
                const SizedBox(width: 8),
                _authChip('DKIM', dkim, chipColor(dkim)),
                const SizedBox(width: 8),
                _authChip('DMARC', dmarc, chipColor(dmarc)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              auth['resumo'] as String? ?? '',
              style: TextStyle(
                fontSize: 11,
                color: auth['autenticacaoFalhou'] == true ? Colors.red : Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _authChip(String label, String valor, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cor.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54)),
          const SizedBox(height: 2),
          Text(valor, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: cor)),
        ],
      ),
    );
  }

  Widget _buildSpoofingCard(Map<String, dynamic> spoofing) {
    return _ameacaContainer(
      Colors.red,
      Icons.warning,
      'SPOOFING DETECTADO',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Este email finge ser ${(spoofing['marcaAlvo'] as String? ?? '').toUpperCase()}, mas vem de:',
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text(spoofing['dominioReal'] as String? ?? '',
              style: const TextStyle(fontSize: 14, color: Colors.red, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Domínios oficiais: ${(spoofing['dominiosOficiais'] as List?)?.join(', ')}',
            style: const TextStyle(fontSize: 11, color: Colors.white38),
          ),
        ],
      ),
    );
  }

  Widget _buildHomografoCard(Map<String, dynamic> h) {
    return _ameacaContainer(
      Colors.purple,
      Icons.text_fields,
      'ATAQUE HOMÓGRAFO',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Domínio usa caracteres parecidos para enganar:',
              style: TextStyle(fontSize: 12, color: Colors.white70)),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(h['dominioFalso'] as String? ?? '',
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('→ imita →', style: TextStyle(color: Colors.white38, fontSize: 11)),
              ),
              Text(h['dominioReal'] as String? ?? '',
                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnexosCard(Map<String, dynamic> anexos) {
    final lista = (anexos['anexosPerigosos'] as List?) ?? [];
    return _ameacaContainer(
      Colors.orange,
      Icons.attach_file,
      'ANEXOS PERIGOSOS',
      Column(
        children: lista
            .map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber, size: 14, color: Colors.orange),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${a['nome']} — ${a['tipo']}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _ameacaContainer(Color cor, IconData icon, String titulo, Widget conteudo) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: cor, size: 16),
              const SizedBox(width: 8),
              Text(titulo, style: TextStyle(fontWeight: FontWeight.bold, color: cor, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 10),
          conteudo,
        ],
      ),
    );
  }

  Widget _buildRastreadoresCard(Set<String> rastreadores) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rastreadores (${rastreadores.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: rastreadores
                  .map((r) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.purple.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('🕵️ $r',
                            style: const TextStyle(fontSize: 11, color: Colors.purple)),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinksCard(List links) {
    const encurtadores = ['bit.ly', 'tinyurl.com', 'goo.gl', 't.co', 'ow.ly', 'short.link', 'cutt.ly'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Links encontrados (${links.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            ...links.take(6).map((l) {
              final url = l.toString();
              final encurtado = encurtadores.any((e) => url.contains(e));
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      encurtado ? Icons.warning_amber : Icons.link,
                      size: 14,
                      color: encurtado ? Colors.orange : Colors.white38,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        url.length > 52 ? '${url.substring(0, 52)}…' : url,
                        style: TextStyle(
                          fontSize: 11,
                          color: encurtado ? Colors.orange : Colors.white54,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (links.length > 6)
              Text('+ ${links.length - 6} links adicionais',
                  style: const TextStyle(fontSize: 11, color: Colors.white38)),
          ],
        ),
      ),
    );
  }

  Widget _buildAcoes(BuildContext context, String nivel, String? unsubscribeLink) {
    final ehCritico = nivel == 'CRÍTICO' || nivel == 'ALTO';
    return Column(
      children: [
        if (ehCritico) ...[
          if (widget.premium)
            ElevatedButton.icon(
              onPressed: () async {
                await widget.onQuarentenar(widget.email['id'] as String);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Email isolado na Quarentena'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  Navigator.pop(context);
                }
              },
              icon: const Icon(Icons.security),
              label: const Text('Mover para Quarentena'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: widget.onAssinar,
              icon: const Icon(Icons.lock),
              label: const Text('Premium: quarentena automática'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A90D9),
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          const SizedBox(height: 8),
        ],
        if (unsubscribeLink != null) ...[
          OutlinedButton.icon(
            onPressed: () => launchUrl(
              Uri.parse(unsubscribeLink),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.unsubscribe),
            label: const Text('Descadastrar deste remetente'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
            ),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          onPressed: () async {
            await widget.onDeletar(widget.email['id'] as String);
            if (context.mounted) Navigator.pop(context);
          },
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          label: const Text('Deletar email', style: TextStyle(color: Colors.red)),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 44),
            side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
          ),
        ),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double progresso;
  final Color cor;

  _GaugePainter(this.progresso, this.cor);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    paint.color = Colors.white12;
    canvas.drawCircle(center, radius, paint);

    paint.color = cor;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progresso,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.progresso != progresso;
}
