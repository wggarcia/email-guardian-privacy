import 'package:flutter/material.dart';

class TelaPrivacidade extends StatelessWidget {
  final VoidCallback onExcluirDados;
  const TelaPrivacidade({super.key, required this.onExcluirDados});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacidade e LGPD')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _secaoHeader(
            '🔒 Seus dados são seus',
            'O Email Guardian processa seus emails inteiramente no seu dispositivo. '
            'Nenhum conteúdo de email é enviado a servidores externos.',
          ),

          const SizedBox(height: 20),
          _titulo('O QUE É ARMAZENADO LOCALMENTE'),
          _itemDado(
            Icons.email_outlined,
            Colors.blue,
            'Endereço de email',
            'Para manter a sessão ativa entre aberturas do app.',
          ),
          _itemDado(
            Icons.lock_outline,
            Colors.orange,
            'Senhas IMAP (quando usadas)',
            'Criptografadas no Keychain (iOS) ou EncryptedSharedPreferences (Android). '
            'Nunca saem do dispositivo.',
          ),
          _itemDado(
            Icons.star_outline,
            Colors.purple,
            'Status de assinatura Premium',
            'Booleano local. Verificado pela App Store/Google Play.',
          ),
          _itemDado(
            Icons.access_time,
            Colors.teal,
            'Timestamp do último scan',
            'Para o lembrete de verificação diária. Não contém conteúdo de email.',
          ),
          _itemDado(
            Icons.check_circle_outline,
            Colors.green,
            'Consentimento LGPD',
            'Registro de que você aceitou a política de privacidade.',
          ),

          const SizedBox(height: 20),
          _titulo('O QUE NUNCA É ARMAZENADO'),
          _itemNao('Conteúdo dos seus emails — processado em memória RAM, descartado ao fechar o app'),
          _itemNao('Anexos ou arquivos dos emails'),
          _itemNao('Histórico de análises anteriores'),
          _itemNao('Qualquer dado enviado a servidores do Email Guardian'),
          _itemNao('Cookies, rastreamento de comportamento ou analytics'),

          const SizedBox(height: 20),
          _titulo('BASE LEGAL (LGPD Art. 7º, I)'),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
            ),
            child: const Text(
              'O tratamento de dados é baseado no seu consentimento expresso, '
              'coletado na primeira abertura do app. Você pode revogar este '
              'consentimento a qualquer momento excluindo todos os seus dados abaixo.',
              style: TextStyle(fontSize: 13, color: Colors.white70, height: 1.5),
            ),
          ),

          const SizedBox(height: 20),
          _titulo('SEUS DIREITOS (LGPD Art. 18)'),
          _direito('Acesso', 'Ver quais dados o app armazena sobre você.'),
          _direito('Correção', 'Atualizar suas informações de conta.'),
          _direito('Eliminação', 'Excluir todos os dados locais com o botão abaixo.'),
          _direito('Portabilidade', 'Os dados armazenados são seu email e preferências — exportáveis a qualquer momento.'),
          _direito('Revogação do consentimento', 'Use o botão "Excluir todos os dados" para revogar e apagar tudo.'),
          _direito('Informação sobre compartilhamento', 'Nenhum dado é compartilhado com terceiros.'),

          const SizedBox(height: 20),
          _titulo('CONTROLADOR DOS DADOS'),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Email Guardian', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text('Contato DPO: wggarcia33@gmail.com',
                    style: TextStyle(fontSize: 12, color: Colors.white60)),
                SizedBox(height: 4),
                Text('Os dados são controlados localmente no seu dispositivo.',
                    style: TextStyle(fontSize: 12, color: Colors.white60)),
              ],
            ),
          ),

          const SizedBox(height: 32),
          const Divider(color: Colors.white12),
          const SizedBox(height: 16),

          const Text(
            'EXCLUIR MEUS DADOS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.red,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Remove todos os dados armazenados pelo app neste dispositivo: '
            'contas, senhas, preferências e histórico. '
            'Equivale a revogar o consentimento (LGPD Art. 8º, §5º).',
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              onExcluirDados();
            },
            icon: const Icon(Icons.delete_forever),
            label: const Text('Excluir todos os meus dados'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade900,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _secaoHeader(String titulo, String descricao) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade900.withValues(alpha: 0.6), Colors.indigo.shade900.withValues(alpha: 0.6)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(descricao, style: const TextStyle(fontSize: 13, color: Colors.white70, height: 1.5)),
        ],
      ),
    );
  }

  Widget _titulo(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        texto,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white38, letterSpacing: 1.2),
      ),
    );
  }

  Widget _itemDado(IconData icon, Color cor, String titulo, String descricao) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: cor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 2),
                Text(descricao, style: const TextStyle(fontSize: 12, color: Colors.white54, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemNao(String texto) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.block, color: Colors.green, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texto, style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.4)),
          ),
        ],
      ),
    );
  }

  Widget _direito(String titulo, String descricao) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_outlined, color: Color(0xFF4A90D9), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$titulo: ',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.white),
                  ),
                  TextSpan(
                    text: descricao,
                    style: const TextStyle(fontSize: 12, color: Colors.white60, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
