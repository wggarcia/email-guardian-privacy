import 'package:flutter/material.dart';

class TelaScan extends StatefulWidget {
  final Stream<String> progressoStream;
  final Future<Map<String, dynamic>> Function() executarScan;

  const TelaScan({
    super.key,
    required this.progressoStream,
    required this.executarScan,
  });

  @override
  State<TelaScan> createState() => _TelaScanState();
}

class _TelaScanState extends State<TelaScan> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  String _mensagem = 'Conectando ao Gmail...';
  bool _concluido = false;
  Map<String, dynamic>? _stats;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _iniciarScan();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _iniciarScan() async {
    widget.progressoStream.listen((msg) {
      if (mounted) setState(() => _mensagem = msg);
    });

    final stats = await widget.executarScan();

    if (mounted) {
      setState(() {
        _stats = stats;
        _concluido = true;
        _controller.stop();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      body: SafeArea(
        child: _concluido ? _buildResultado() : _buildScanning(),
      ),
    );
  }

  Widget _buildScanning() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            RotationTransition(
              turns: _controller,
              child: const Icon(Icons.radar, size: 80, color: Color(0xFF4A90D9)),
            ),
            const SizedBox(height: 32),
            const Text(
              'Analisando sua caixa de entrada',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              _mensagem,
              style: const TextStyle(fontSize: 14, color: Colors.white60),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultado() {
    final stats = _stats!;
    final total = stats['total'] ?? 0;
    final marketing = stats['marketing'] ?? 0;
    final golpes = stats['golpes'] ?? 0;
    final empresas = stats['empresasRastreando'] ?? 0;
    final desinscrever = stats['desinscrever'] ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          const Text(
            '🔍 Análise Concluída',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '$total emails analisados',
            style: const TextStyle(fontSize: 14, color: Colors.white60),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          _statCard(
            icon: '📧',
            titulo: 'Marketing / Newsletters',
            valor: '$marketing emails',
            detalhe: '$desinscrever remetentes com opção de desinscrição',
            cor: Colors.blue,
          ),
          const SizedBox(height: 12),

          _statCard(
            icon: '🕵️',
            titulo: 'Empresas Rastreando Você',
            valor: '$empresas empresas',
            detalhe: 'Coletando dados quando você abre os emails',
            cor: Colors.orange,
          ),
          const SizedBox(height: 12),

          _statCard(
            icon: '🚨',
            titulo: 'Golpes e Phishing',
            valor: '$golpes emails',
            detalhe: golpes > 0 ? 'Atenção — não clique em links suspeitos' : 'Nenhum detectado — ótimo!',
            cor: golpes > 0 ? Colors.red : Colors.green,
          ),
          const SizedBox(height: 32),

          if (marketing > 0 || empresas > 0)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF1A237E), Color(0xFF283593)]),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Text(
                    '💎 Premium desbloqueia:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  _beneficioItem('Desinscrever $desinscrever remetentes com 1 toque'),
                  _beneficioItem('Bloquear $empresas empresas rastreando você'),
                  _beneficioItem('Limpeza automática de marketing'),
                  _beneficioItem('Monitoramento contínuo 24h'),
                ],
              ),
            ),

          const SizedBox(height: 24),

          ElevatedButton(
            onPressed: () => Navigator.pop(context, _stats),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A90D9),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Ver meus emails', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required String icon,
    required String titulo,
    required String valor,
    required String detalhe,
    required Color cor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: const TextStyle(fontSize: 12, color: Colors.white60)),
                Text(valor, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cor)),
                Text(detalhe, style: const TextStyle(fontSize: 11, color: Colors.white54)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _beneficioItem(String texto) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.greenAccent, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(texto, style: const TextStyle(fontSize: 13, color: Colors.white70))),
        ],
      ),
    );
  }
}
