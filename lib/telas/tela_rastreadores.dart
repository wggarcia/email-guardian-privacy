import 'package:flutter/material.dart';

class TelaRastreadores extends StatelessWidget {
  final List<Map<String, dynamic>> emails;
  final bool premium;
  final VoidCallback onAssinar;

  const TelaRastreadores({
    super.key,
    required this.emails,
    required this.premium,
    required this.onAssinar,
  });

  Map<String, int> get _empresas {
    final mapa = <String, int>{};
    for (final e in emails) {
      final r = e['analise']?['rastreadores'] as Set<String>? ?? {};
      for (final empresa in r) {
        mapa[empresa] = (mapa[empresa] ?? 0) + 1;
      }
    }
    final sorted = Map.fromEntries(
      mapa.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
    return sorted;
  }

  int get _totalEmails => emails.where((e) {
    final r = e['analise']?['rastreadores'] as Set<String>? ?? {};
    return r.isNotEmpty;
  }).length;

  @override
  Widget build(BuildContext context) {
    final empresas = _empresas;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _headerRadar(empresas.length),
                const SizedBox(height: 24),
                if (!premium) _bannerPremium(context),
                const SizedBox(height: 16),
                if (empresas.isNotEmpty) ...[
                  const Text(
                    'Empresas detectadas',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),

        if (empresas.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.verified_user, size: 64, color: Colors.green),
                  SizedBox(height: 16),
                  Text(
                    'Nenhum rastreador detectado\nnos emails analisados',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                ],
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final entrada = empresas.entries.toList()[i];
                final nome = entrada.key;
                final contagem = entrada.value;
                final porcentagem = emails.isNotEmpty ? contagem / emails.length : 0.0;

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _rastreadorIcon(nome),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    nome.toUpperCase(),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  Text(
                                    '$contagem email${contagem > 1 ? 's' : ''} com rastreamento',
                                    style: const TextStyle(fontSize: 12, color: Colors.white60),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _corRisco(porcentagem),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${(porcentagem * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: porcentagem,
                            backgroundColor: Colors.white12,
                            valueColor: AlwaysStoppedAnimation(_corRisco(porcentagem)),
                            minHeight: 4,
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

        SliverToBoxAdapter(child: const SizedBox(height: 80)),
      ],
    );
  }

  Widget _headerRadar(int totalEmpresas) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: totalEmpresas > 0
              ? [const Color(0xFF4A0000), const Color(0xFF7B1111)]
              : [const Color(0xFF003300), const Color(0xFF1B5E20)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            totalEmpresas > 0 ? Icons.visibility : Icons.verified_user,
            size: 48,
            color: totalEmpresas > 0 ? Colors.red.shade200 : Colors.green.shade200,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  totalEmpresas > 0
                      ? '$totalEmpresas empresa${totalEmpresas > 1 ? 's' : ''} rastreando você'
                      : 'Sem rastreadores detectados',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  '$_totalEmails emails continham pixels de rastreamento',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bannerPremium(BuildContext context) {
    return GestureDetector(
      onTap: onAssinar,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A237E).withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: const [
            Icon(Icons.block, color: Colors.blue),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                '💎 Premium: bloqueie pixels de rastreamento automaticamente',
                style: TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  Widget _rastreadorIcon(String nome) {
    const icones = {
      'mailchimp': '🐒',
      'sendgrid': '📨',
      'klaviyo': '📊',
      'hubspot': '🟠',
      'salesforce': '☁️',
      'amazonaws': '☁️',
      'mailgun': '🔫',
      'brevo': '📩',
      'sendinblue': '📩',
      'mailerlite': '📬',
    };
    final emoji = icones[nome.toLowerCase()] ?? '🕵️';
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(emoji, style: const TextStyle(fontSize: 20)),
    );
  }

  Color _corRisco(double porcentagem) {
    if (porcentagem >= 0.5) return Colors.red;
    if (porcentagem >= 0.2) return Colors.orange;
    return Colors.amber;
  }
}
