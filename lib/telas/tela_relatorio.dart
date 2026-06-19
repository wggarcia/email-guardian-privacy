import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TelaRelatorio extends StatelessWidget {
  final List<Map<String, dynamic>> emails;
  final bool premium;
  final VoidCallback onAssinar;

  const TelaRelatorio({
    super.key,
    required this.emails,
    required this.premium,
    required this.onAssinar,
  });

  // ── Computed stats ──────────────────────────────────────────────────────────

  Map<String, int> get _porTipo {
    final mapa = <String, int>{};
    for (final e in emails) {
      final t = (e['analise']?['tipo'] ?? '🧾 SEGURO') as String;
      mapa[t] = (mapa[t] ?? 0) + 1;
    }
    return mapa;
  }

  Map<String, int> get _rastreadores {
    final mapa = <String, int>{};
    for (final e in emails) {
      final r = e['analise']?['rastreadores'] as Set<String>? ?? {};
      for (final tr in r) mapa[tr] = (mapa[tr] ?? 0) + 1;
    }
    return Map.fromEntries(
      mapa.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
  }

  int get _criticos => emails.where((e) {
        final n = e['antivirus']?['ameaca']?['nivel'] as String?;
        return n == 'CRÍTICO' || n == 'ALTO';
      }).length;

  int get _manipulacao =>
      (_porTipo['🎭 MANIPULAÇÃO'] ?? 0);

  int get _marketing =>
      (_porTipo['🚀 MARKETING'] ?? 0) + (_porTipo['📨 NEWSLETTER'] ?? 0);

  int get _scoreGeral {
    if (emails.isEmpty) return 100;
    final criticos = _criticos;
    final manip = _manipulacao;
    final penalidade = (criticos * 15 + manip * 3).clamp(0, 85);
    return (100 - penalidade).clamp(15, 100);
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: AppBar(
        title: const Text('Relatório de Segurança'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copiar relatório',
            onPressed: () => _copiarRelatorio(context),
          ),
        ],
      ),
      body: emails.isEmpty
          ? const Center(
              child: Text('Carregue os emails primeiro',
                  style: TextStyle(color: Colors.white54)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildScoreGeral(),
                const SizedBox(height: 20),
                _buildResumoCards(),
                const SizedBox(height: 20),
                _buildBreakdownTipo(),
                const SizedBox(height: 20),
                if (_rastreadores.isNotEmpty) ...[
                  _buildTopRastreadores(),
                  const SizedBox(height: 20),
                ],
                _buildRemetentesPerigosos(),
                const SizedBox(height: 20),
                if (!premium) _buildCtaPremium(context),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _buildScoreGeral() {
    final score = _scoreGeral;
    final cor = score >= 80
        ? Colors.green
        : score >= 50
            ? Colors.orange
            : Colors.red;
    final label = score >= 80
        ? 'Sua caixa está protegida'
        : score >= 50
            ? 'Atenção necessária'
            : 'Sua caixa está em risco';

    return Center(
      child: Column(
        children: [
          const Text('Nota de Segurança',
              style: TextStyle(fontSize: 13, color: Colors.white54)),
          const SizedBox(height: 16),
          SizedBox(
            width: 140,
            height: 140,
            child: CustomPaint(
              painter: _GaugePainter(score / 100, cor),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('$score',
                        style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: cor)),
                    Text('/100',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.white38)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(label,
              style: TextStyle(fontSize: 16, color: cor, fontWeight: FontWeight.bold)),
          Text('${emails.length} emails analisados',
              style: const TextStyle(fontSize: 12, color: Colors.white38)),
        ],
      ),
    );
  }

  Widget _buildResumoCards() {
    return Row(
      children: [
        Expanded(child: _miniCard('🚨', '${_criticos}', 'Ameaças', Colors.red)),
        const SizedBox(width: 8),
        Expanded(
            child: _miniCard('🎭', '${_manipulacao}', 'Manipulação', Colors.deepPurple)),
        const SizedBox(width: 8),
        Expanded(
            child: _miniCard('🕵️', '${_rastreadores.length}', 'Rastreadores', Colors.orange)),
        const SizedBox(width: 8),
        Expanded(child: _miniCard('📧', '${_marketing}', 'Marketing', Colors.blue)),
      ],
    );
  }

  Widget _miniCard(String emoji, String valor, String label, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 4),
          Text(valor,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cor)),
          Text(label,
              style: const TextStyle(fontSize: 10, color: Colors.white54),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildBreakdownTipo() {
    final total = emails.length;
    final categorias = [
      ('🚨 GOLPE', Colors.red),
      ('⚠️ PHISHING', Colors.orange),
      ('📢 SUSPEITO', Colors.amber),
      ('🎭 MANIPULAÇÃO', Colors.deepPurple),
      ('🧾 SEGURO', Colors.green),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Distribuição por categoria',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 14),
            ...categorias.map((c) {
              final count = _porTipo[c.$1] ?? 0;
              final pct = total > 0 ? count / total : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(c.$1,
                            style: const TextStyle(fontSize: 12, color: Colors.white70)),
                        Text('$count',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: c.$2)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 6,
                        backgroundColor: Colors.white10,
                        valueColor: AlwaysStoppedAnimation(c.$2),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTopRastreadores() {
    final top = _rastreadores.entries.take(5).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Empresas que mais te rastreiam',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 12),
            ...top.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(e.key,
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis),
                      ),
                      Expanded(
                        flex: 5,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: emails.isNotEmpty ? e.value / emails.length : 0,
                            minHeight: 6,
                            backgroundColor: Colors.white10,
                            valueColor:
                                const AlwaysStoppedAnimation(Colors.orange),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${e.value}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.orange)),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildRemetentesPerigosos() {
    final perigosos = emails
        .where((e) {
          final n = e['antivirus']?['ameaca']?['nivel'] as String?;
          return n == 'CRÍTICO' || n == 'ALTO';
        })
        .take(5)
        .toList();

    if (perigosos.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: const [
              Icon(Icons.verified_user, color: Colors.green),
              SizedBox(width: 12),
              Text('Nenhum remetente perigoso encontrado',
                  style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Remetentes suspeitos',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 12),
            ...perigosos.map((e) {
              final nivel = e['antivirus']?['ameaca']?['nivel'] as String? ?? '';
              final cor = nivel == 'CRÍTICO' ? Colors.red : Colors.orange;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e['remetente'] as String? ?? '',
                            style: const TextStyle(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            e['assunto'] as String? ?? '',
                            style: const TextStyle(
                                fontSize: 10, color: Colors.white38),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Text(nivel,
                        style: TextStyle(
                            fontSize: 10, fontWeight: FontWeight.bold, color: cor)),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildCtaPremium(BuildContext context) {
    return GestureDetector(
      onTap: onAssinar,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF1A237E), Color(0xFF283593)]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: const [
            Text('💎 Premium — proteção completa',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            SizedBox(height: 6),
            Text(
              'Quarentena automática · Limpeza em massa · Alertas 24h',
              style: TextStyle(fontSize: 12, color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _copiarRelatorio(BuildContext context) {
    final score = _scoreGeral;
    final label = score >= 80 ? 'PROTEGIDA' : score >= 50 ? 'COM ATENÇÃO' : 'EM RISCO';
    final buffer = StringBuffer()
      ..writeln('📊 RELATÓRIO EMAIL GUARDIAN')
      ..writeln('=' * 30)
      ..writeln('Nota de Segurança: $score/100 ($label)')
      ..writeln('Emails analisados: ${emails.length}')
      ..writeln()
      ..writeln('🚨 Ameaças críticas: $_criticos')
      ..writeln('🎭 Emails manipulativos: $_manipulacao')
      ..writeln('🕵️ Empresas rastreando: ${_rastreadores.length}')
      ..writeln('📧 Marketing/Newsletter: $_marketing')
      ..writeln();

    if (_rastreadores.isNotEmpty) {
      buffer.writeln('Top rastreadores:');
      _rastreadores.entries.take(3).forEach((e) {
        buffer.writeln('  · ${e.key}: ${e.value} emails');
      });
      buffer.writeln();
    }

    buffer.writeln('Gerado pelo Email Guardian — proteja seu email');

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Relatório copiado — cole onde quiser!'),
        backgroundColor: Color(0xFF4A90D9),
      ),
    );
  }
}

// ── Gauge circular ─────────────────────────────────────────────────────────────
class _GaugePainter extends CustomPainter {
  final double progresso;
  final Color cor;

  _GaugePainter(this.progresso, this.cor);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    paint.color = Colors.white10;
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
