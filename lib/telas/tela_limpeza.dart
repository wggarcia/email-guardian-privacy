import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class TeleLimpeza extends StatefulWidget {
  final List<Map<String, dynamic>> emails;
  final bool premium;
  final VoidCallback onAssinar;
  final Future<void> Function(List<String> ids) onRemover;

  const TeleLimpeza({
    super.key,
    required this.emails,
    required this.premium,
    required this.onAssinar,
    required this.onRemover,
  });

  @override
  State<TeleLimpeza> createState() => _TeleLimpezaState();
}

class _TeleLimpezaState extends State<TeleLimpeza> {
  bool _removendo = false;
  final Set<String> _selecionados = {};

  List<Map<String, dynamic>> get _marketing => widget.emails.where((e) {
    final cat = e['analise']?['categoria'] ?? '';
    return cat == 'marketing' || cat == 'newsletter';
  }).toList();

  List<Map<String, dynamic>> get _comUnsubscribe => widget.emails.where((e) {
    return e['analise']?['linkDesinscrever'] != null;
  }).toList();

  // Agrupa por remetente dominante
  Map<String, List<Map<String, dynamic>>> get _porRemetente {
    final mapa = <String, List<Map<String, dynamic>>>{};
    for (final e in _marketing) {
      final rem = _normalizar(e['remetente'] ?? 'Desconhecido');
      mapa.putIfAbsent(rem, () => []).add(e);
    }
    final sorted = Map.fromEntries(
      mapa.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length)),
    );
    return sorted;
  }

  String _normalizar(String remetente) {
    final match = RegExp(r'<([^>]+)>').firstMatch(remetente);
    if (match != null) {
      final email = match.group(1)!;
      final domain = email.split('@').last;
      return domain.split('.').reversed.skip(1).first.toUpperCase();
    }
    if (remetente.contains('@')) {
      return remetente.split('@').last.split('.').first.toUpperCase();
    }
    return remetente.length > 20 ? remetente.substring(0, 20) : remetente;
  }

  Future<void> _desinscreverTodos() async {
    if (!widget.premium) {
      widget.onAssinar();
      return;
    }
    for (final e in _comUnsubscribe) {
      final link = e['analise']?['linkDesinscrever'] as String?;
      if (link != null && link.startsWith('http')) {
        try {
          await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (_) {}
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ Solicitações enviadas para ${_comUnsubscribe.length} remetentes')),
    );
  }

  Future<void> _removerSelecionados() async {
    if (!widget.premium && _selecionados.length > 5) {
      widget.onAssinar();
      return;
    }
    setState(() => _removendo = true);
    await widget.onRemover(_selecionados.toList());
    setState(() {
      _selecionados.clear();
      _removendo = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final porRemetente = _porRemetente;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _resumoLimpeza(),
                const SizedBox(height: 16),
                if (_comUnsubscribe.isNotEmpty) _botaoDesinscreverTodos(),
                const SizedBox(height: 24),
                const Text(
                  'Por remetente',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),

        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final entrada = porRemetente.entries.toList()[i];
              final nome = entrada.key;
              final lista = entrada.value;
              final temUnsubscribe = lista.any((e) => e['analise']?['linkDesinscrever'] != null);
              final ids = lista.map((e) => e['id'] as String).toList();
              final todosSelec = ids.every((id) => _selecionados.contains(id));

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.withValues(alpha: 0.2),
                    child: Text(nome[0], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  ),
                  title: Text(nome, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${lista.length} email${lista.length > 1 ? 's' : ''}${temUnsubscribe ? ' · pode desinscrever' : ''}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (temUnsubscribe)
                        IconButton(
                          icon: const Icon(Icons.unsubscribe, color: Colors.orange),
                          tooltip: 'Desinscrever',
                          onPressed: widget.premium
                              ? () async {
                                  final link = lista.firstWhere(
                                    (e) => e['analise']?['linkDesinscrever'] != null,
                                  )['analise']?['linkDesinscrever'] as String?;
                                  if (link != null) await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
                                }
                              : widget.onAssinar,
                        ),
                      Checkbox(
                        value: todosSelec,
                        onChanged: (_) {
                          setState(() {
                            if (todosSelec) {
                              _selecionados.removeAll(ids);
                            } else {
                              _selecionados.addAll(ids);
                            }
                          });
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
            childCount: porRemetente.length,
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (_selecionados.isNotEmpty)
                  ElevatedButton.icon(
                    onPressed: _removendo ? null : _removerSelecionados,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    icon: _removendo
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.delete),
                    label: Text('Remover ${_selecionados.length} selecionados'),
                  ),
                const SizedBox(height: 60),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _resumoLimpeza() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1A237E), Color(0xFF283593)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _miniStat('${_marketing.length}', 'Marketing'),
          _miniStat('${_comUnsubscribe.length}', 'Para desinscrever'),
          _miniStat('${_porRemetente.length}', 'Remetentes'),
        ],
      ),
    );
  }

  Widget _miniStat(String valor, String label) {
    return Column(
      children: [
        Text(valor, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
      ],
    );
  }

  Widget _botaoDesinscreverTodos() {
    return ElevatedButton.icon(
      onPressed: _desinscreverTodos,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFE65100),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(Icons.unsubscribe),
      label: Text(
        widget.premium
            ? 'Desinscrever ${_comUnsubscribe.length} remetentes de uma vez'
            : '💎 Desinscrever todos (Premium)',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      ),
    );
  }
}
