import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class TelaSeguranca extends StatefulWidget {
  final List<Map<String, dynamic>> emails;
  final bool premium;
  final VoidCallback onAssinar;
  final Future<void> Function(String id) onQuarentenar;

  const TelaSeguranca({
    super.key,
    required this.emails,
    required this.premium,
    required this.onAssinar,
    required this.onQuarentenar,
  });

  @override
  State<TelaSeguranca> createState() => _TelaSegurancaState();
}

class _TelaSegurancaState extends State<TelaSeguranca> {
  int _secaoAtiva = 0; // 0 = ameaças, 1 = rastreadores, 2 = quarentena

  List<Map<String, dynamic>> get _emailsCriticos => widget.emails.where((e) {
    final nivel = e['antivirus']?['ameaca']?['nivel'] ?? '';
    return nivel == 'CRÍTICO' || nivel == 'ALTO';
  }).toList();

  List<Map<String, dynamic>> get _emailsMedio => widget.emails.where((e) {
    final nivel = e['antivirus']?['ameaca']?['nivel'] ?? '';
    return nivel == 'MÉDIO';
  }).toList();

  int get _scoreGeral {
    if (widget.emails.isEmpty) return 100;
    final criticos = _emailsCriticos.length;
    final medios = _emailsMedio.length;
    final penalidade = (criticos * 15 + medios * 5).clamp(0, 85);
    return (100 - penalidade).clamp(15, 100);
  }

  Map<String, int> get _empresasRastreando {
    final mapa = <String, int>{};
    for (final e in widget.emails) {
      final r = e['analise']?['rastreadores'] as Set<String>? ?? {};
      for (final empresa in r) mapa[empresa] = (mapa[empresa] ?? 0) + 1;
    }
    return Map.fromEntries(mapa.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildScoreCard()),
        SliverToBoxAdapter(child: _buildAbas()),
        if (_secaoAtiva == 0) ..._buildAmeacas(),
        if (_secaoAtiva == 1) ..._buildRastreadores(),
        if (_secaoAtiva == 2) ..._buildQuarentena(),
        SliverToBoxAdapter(child: const SizedBox(height: 80)),
      ],
    );
  }

  Widget _buildScoreCard() {
    final score = _scoreGeral;
    final cor = score >= 80 ? Colors.green : score >= 50 ? Colors.orange : Colors.red;
    final label = score >= 80 ? 'Protegido' : score >= 50 ? 'Atenção' : 'Em risco';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: score >= 80
                ? [const Color(0xFF1B5E20), const Color(0xFF2E7D32)]
                : score >= 50
                    ? [const Color(0xFFE65100), const Color(0xFFF57C00)]
                    : [const Color(0xFFB71C1C), const Color(0xFFC62828)],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            // Gauge circular
            SizedBox(
              width: 80,
              height: 80,
              child: CustomPaint(
                painter: _GaugePainter(score / 100, cor),
                child: Center(
                  child: Text(
                    '$score',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(
                    '${_emailsCriticos.length} ameaça${_emailsCriticos.length != 1 ? 's' : ''} crítica${_emailsCriticos.length != 1 ? 's' : ''} • '
                    '${_empresasRastreando.length} rastreador${_empresasRastreando.length != 1 ? 'es' : ''}',
                    style: const TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.emails.length} emails analisados',
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAbas() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _abaBtn(0, '🚨 Ameaças', _emailsCriticos.length),
          const SizedBox(width: 8),
          _abaBtn(1, '🕵️ Rastreadores', _empresasRastreando.length),
          const SizedBox(width: 8),
          _abaBtn(2, '🔒 Quarentena', null),
        ],
      ),
    );
  }

  Widget _abaBtn(int index, String label, int? badge) {
    final ativo = _secaoAtiva == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _secaoAtiva = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: ativo ? const Color(0xFF4A90D9) : const Color(0xFF1E1E2E),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: ativo ? FontWeight.bold : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
              ),
              if (badge != null && badge > 0)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$badge', style: const TextStyle(fontSize: 10, color: Colors.white)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildAmeacas() {
    if (_emailsCriticos.isEmpty && _emailsMedio.isEmpty) {
      return [
        SliverFillRemaining(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.verified_user, size: 64, color: Colors.green),
                SizedBox(height: 16),
                Text('Nenhuma ameaça detectada',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text('Sua caixa está protegida',
                    style: TextStyle(color: Colors.white54)),
              ],
            ),
          ),
        ),
      ];
    }

    final todos = [..._emailsCriticos, ..._emailsMedio];
    return [
      SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => _cardAmeaca(todos[i]),
            childCount: todos.length,
          ),
        ),
      ),
    ];
  }

  Widget _cardAmeaca(Map<String, dynamic> email) {
    final av = email['antivirus'] as Map<String, dynamic>? ?? {};
    final ameaca = av['ameaca'] as Map<String, dynamic>? ?? {};
    final nivel = ameaca['nivel'] ?? 'MÉDIO';
    final score = ameaca['score'] ?? 0;
    final alertas = (ameaca['alertas'] ?? []) as List;
    final assunto = email['assunto'] ?? 'Sem assunto';
    final remetente = email['remetente'] ?? '';
    final links = (ameaca['links'] ?? []) as List;

    final corNivel = nivel == 'CRÍTICO' ? Colors.red
        : nivel == 'ALTO' ? Colors.orange
        : Colors.amber;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: corNivel.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: corNivel.withValues(alpha: 0.5)),
                  ),
                  child: Text('$nivel  $score/100',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: corNivel)),
                ),
                const Spacer(),
                if (widget.premium)
                  TextButton.icon(
                    onPressed: () => widget.onQuarentenar(email['id']),
                    icon: const Icon(Icons.security, size: 14),
                    label: const Text('Quarentenar', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(foregroundColor: Colors.orange),
                  )
                else
                  TextButton.icon(
                    onPressed: widget.onAssinar,
                    icon: const Icon(Icons.lock, size: 14),
                    label: const Text('Premium', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(foregroundColor: Colors.white38),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(assunto,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text(remetente,
                style: const TextStyle(fontSize: 11, color: Colors.white54),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 10),
            ...alertas.map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber, size: 14, color: Colors.orange),
                      const SizedBox(width: 6),
                      Expanded(child: Text(a.toString(), style: const TextStyle(fontSize: 12))),
                    ],
                  ),
                )),
            if (links.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Text('${links.length} link${links.length > 1 ? 's' : ''} encontrado${links.length > 1 ? 's' : ''}',
                  style: const TextStyle(fontSize: 11, color: Colors.white38)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                children: links.take(3).map((l) => GestureDetector(
                  onTap: widget.premium
                      ? () => launchUrl(Uri.parse(l.toString()), mode: LaunchMode.externalApplication)
                      : widget.onAssinar,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _encurtarUrl(l.toString()),
                      style: const TextStyle(fontSize: 10, color: Colors.blue),
                    ),
                  ),
                )).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildRastreadores() {
    final empresas = _empresasRastreando;
    if (empresas.isEmpty) {
      return [
        SliverFillRemaining(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.verified_user, size: 64, color: Colors.green),
                SizedBox(height: 16),
                Text('Nenhum rastreador detectado',
                    style: TextStyle(fontSize: 16, color: Colors.white70)),
              ],
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final entrada = empresas.entries.toList()[i];
              final nome = entrada.key;
              final count = entrada.value;
              final pct = widget.emails.isNotEmpty ? count / widget.emails.length : 0.0;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(nome.toUpperCase(),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          const Spacer(),
                          Text('$count email${count > 1 ? 's' : ''}',
                              style: const TextStyle(fontSize: 12, color: Colors.white60)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 5,
                          backgroundColor: Colors.white12,
                          valueColor: AlwaysStoppedAnimation(
                            pct >= 0.5 ? Colors.red : pct >= 0.2 ? Colors.orange : Colors.amber,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            childCount: empresas.length,
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildQuarentena() {
    if (!widget.premium) {
      return [
        SliverFillRemaining(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock, size: 64, color: Colors.white38),
                  const SizedBox(height: 16),
                  const Text('Quarentena Premium',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                    'Emails perigosos são isolados automaticamente — você decide o que fazer com cada um.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: widget.onAssinar,
                    child: const Text('Ativar Premium'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    final emailsNaQuarentena = widget.emails
        .where((e) => e['emQuarentena'] == true)
        .toList();

    if (emailsNaQuarentena.isEmpty) {
      return [
        SliverFillRemaining(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.security, size: 64, color: Colors.green),
                SizedBox(height: 16),
                Text('Quarentena vazia',
                    style: TextStyle(fontSize: 16, color: Colors.white70)),
                SizedBox(height: 8),
                Text('Emails críticos serão isolados aqui automaticamente',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.white38)),
              ],
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final e = emailsNaQuarentena[i];
              return Card(
                color: Colors.red.withValues(alpha: 0.1),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.dangerous, color: Colors.red),
                  title: Text(e['assunto'] ?? 'Sem assunto', maxLines: 1),
                  subtitle: Text(e['remetente'] ?? '', maxLines: 1),
                  trailing: TextButton(
                    onPressed: () {},
                    child: const Text('Liberar', style: TextStyle(color: Colors.orange)),
                  ),
                ),
              );
            },
            childCount: emailsNaQuarentena.length,
          ),
        ),
      ),
    ];
  }

  String _encurtarUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.length > 25 ? uri.host.substring(0, 25) : uri.host;
    } catch (_) {
      return url.length > 30 ? '${url.substring(0, 30)}…' : url;
    }
  }
}

// ── Gauge circular painter ─────────────────────────────────────────────────────
class _GaugePainter extends CustomPainter {
  final double progresso;
  final Color cor;

  _GaugePainter(this.progresso, this.cor);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    // Fundo
    paint.color = Colors.white12;
    canvas.drawCircle(center, radius, paint);

    // Progresso
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
