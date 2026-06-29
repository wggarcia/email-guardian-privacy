import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import '../servicos/imap_service.dart';

// Guia por provedor: título, passos, URL, ícone
class _GuiaProvedor {
  final String titulo;
  final String subtitulo;
  final List<String> passos;
  final String url;
  final String labelBotao;
  final IconData icone;
  final Color cor;

  const _GuiaProvedor({
    required this.titulo,
    required this.subtitulo,
    required this.passos,
    required this.url,
    required this.labelBotao,
    required this.icone,
    required this.cor,
  });
}

const _guias = <String, _GuiaProvedor>{
  'outlook': _GuiaProvedor(
    titulo: 'Outlook / Hotmail',
    subtitulo: 'Requer Senha de Aplicativo',
    passos: [
      'Acesse account.microsoft.com/security',
      'Em "Segurança avançada", clique em "Senhas de aplicativo"',
      'Crie uma senha, copie os 16 caracteres gerados',
      'Cole aqui no campo Senha abaixo',
    ],
    url: 'https://account.microsoft.com/security',
    labelBotao: 'Abrir conta Microsoft',
    icone: Icons.open_in_new,
    cor: Color(0xFF0078D4),
  ),
  'yahoo': _GuiaProvedor(
    titulo: 'Yahoo Mail',
    subtitulo: 'Requer Senha de Aplicativo',
    passos: [
      'Acesse a segurança da sua conta Yahoo',
      'Role até "Gerar senha de aplicativo"',
      'Selecione "Email", gere e copie a senha',
      'Cole aqui no campo Senha abaixo',
    ],
    url: 'https://login.yahoo.com/account/security',
    labelBotao: 'Abrir segurança do Yahoo',
    icone: Icons.open_in_new,
    cor: Color(0xFF6001D2),
  ),
  'icloud': _GuiaProvedor(
    titulo: 'iCloud Mail',
    subtitulo: 'Requer Senha Específica de App',
    passos: [
      'Acesse appleid.apple.com e faça login',
      'Em "Segurança", clique em "Gerar Senha"',
      'Dê um nome (ex: Email Guardian) e confirme',
      'Copie a senha gerada e cole abaixo',
    ],
    url: 'https://appleid.apple.com',
    labelBotao: 'Abrir Apple ID',
    icone: Icons.open_in_new,
    cor: Color(0xFF555555),
  ),
  'zoho': _GuiaProvedor(
    titulo: 'Zoho Mail',
    subtitulo: 'IMAP precisa estar ativado',
    passos: [
      'Acesse mail.zoho.com → Configurações',
      'Vá em "Contas de email" → "Acesso IMAP"',
      'Ative o IMAP e salve',
      'Volte aqui e use sua senha normal do Zoho',
    ],
    url: 'https://mail.zoho.com/zm/#mail/settings',
    labelBotao: 'Abrir configurações Zoho',
    icone: Icons.open_in_new,
    cor: Color(0xFFE42527),
  ),
};

_GuiaProvedor? _guiaParaDomain(String? domain) {
  if (domain == null) return null;
  if (domain == 'outlook.com' || domain == 'hotmail.com') return _guias['outlook'];
  if (domain.contains('yahoo')) return _guias['yahoo'];
  if (domain == 'icloud.com') return _guias['icloud'];
  if (domain.contains('zoho')) return _guias['zoho'];
  return null;
}

class TelaAdicionarConta extends StatefulWidget {
  const TelaAdicionarConta({super.key});

  @override
  State<TelaAdicionarConta> createState() => _TelaAdicionarContaState();
}

class _TelaAdicionarContaState extends State<TelaAdicionarConta> {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final _emailCtrl = TextEditingController();
  final _senhaCtrl = TextEditingController();
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '993');

  bool _ssl = true;
  bool _mostrarSenha = false;
  bool _avancado = false;
  bool _testando = false;
  bool? _testeOk;
  String? _erroTeste;
  String? _provedorDomain;

  static const _provedores = [
    ('Outlook', 'outlook.com'),
    ('Hotmail', 'hotmail.com'),
    ('Yahoo', 'yahoo.com.br'),
    ('iCloud', 'icloud.com'),
    ('Zoho', 'zoho.com'),
    ('UOL', 'uol.com.br'),
    ('Terra', 'terra.com.br'),
    ('IG', 'ig.com.br'),
    ('Globo', 'globo.com'),
    ('Outro', null),
  ];

  void _selecionarProvedor(String? domain) {
    setState(() {
      _provedorDomain = domain;
      _testeOk = null;
      _erroTeste = null;
      if (domain != null) {
        final s = ImapService.inferirServidor('user@$domain');
        _hostCtrl.text = s.host;
        _portCtrl.text = s.port.toString();
        _ssl = s.ssl;
        _avancado = false;
      } else {
        _hostCtrl.clear();
        _portCtrl.text = '993';
        _ssl = true;
        _avancado = true;
      }
    });
  }

  Future<void> _inferirServidorSeVazio() async {
    final email = _emailCtrl.text.trim();
    if (email.contains('@') && _hostCtrl.text.isEmpty) {
      final s = ImapService.inferirServidor(email);
      setState(() {
        _hostCtrl.text = s.host;
        _portCtrl.text = s.port.toString();
        _ssl = s.ssl;
      });
    }
  }

  Future<void> _testar() async {
    final email = _emailCtrl.text.trim();
    final senha = _senhaCtrl.text;
    if (email.isEmpty || senha.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha email e senha primeiro')),
      );
      return;
    }
    await _inferirServidorSeVazio();
    setState(() { _testando = true; _testeOk = null; _erroTeste = null; });

    final ok = await ImapService.testarConexao(
      email: email,
      password: senha,
      host: _hostCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text) ?? 993,
      ssl: _ssl,
    );

    setState(() {
      _testando = false;
      _testeOk = ok;
      if (!ok) _erroTeste = 'Conexão falhou. Verifique email, senha e configurações do servidor.';
    });
  }

  Future<void> _salvar() async {
    final email = _emailCtrl.text.trim();
    final senha = _senhaCtrl.text;
    if (email.isEmpty || senha.isEmpty) return;
    await _inferirServidorSeVazio();
    await _storage.write(key: 'imap_$email', value: senha);
    if (mounted) {
      Navigator.pop(context, {
        'email': email,
        'host': _hostCtrl.text.trim(),
        'port': int.tryParse(_portCtrl.text) ?? 993,
        'ssl': _ssl,
      });
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _senhaCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final podeSalvar = _emailCtrl.text.isNotEmpty && _senhaCtrl.text.isNotEmpty;
    final guia = _guiaParaDomain(_provedorDomain);

    return Scaffold(
      appBar: AppBar(title: const Text('Adicionar conta de email')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Chips de provedor ──────────────────────────────────────────────
          const Text(
            'PROVEDOR',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white38, letterSpacing: 1.2),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _provedores.map((p) {
              final (nome, domain) = p;
              final selected = _provedorDomain == domain && domain != null ||
                  (_provedorDomain == null && domain == null && _avancado);
              return ChoiceChip(
                label: Text(nome),
                selected: selected,
                onSelected: (_) => _selecionarProvedor(domain),
              );
            }).toList(),
          ),

          // ── Guia passo a passo (Outlook / Yahoo / iCloud / Zoho) ──────────
          if (guia != null) ...[
            const SizedBox(height: 20),
            _GuiaCard(guia: guia),
          ],

          // ── Campos de credenciais ──────────────────────────────────────────
          const SizedBox(height: 24),
          const Text(
            'CREDENCIAIS',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white38, letterSpacing: 1.2),
          ),
          const SizedBox(height: 8),

          TextField(
            controller: _emailCtrl,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _senhaCtrl,
            obscureText: !_mostrarSenha,
            decoration: InputDecoration(
              labelText: guia != null ? 'Senha de aplicativo' : 'Senha',
              prefixIcon: const Icon(Icons.lock_outline),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_mostrarSenha ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _mostrarSenha = !_mostrarSenha),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),

          // ── Configurações avançadas ────────────────────────────────────────
          const SizedBox(height: 8),
          ExpansionTile(
            title: const Text(
              'Configurações avançadas (servidor IMAP)',
              style: TextStyle(fontSize: 13),
            ),
            initiallyExpanded: _avancado,
            onExpansionChanged: (v) => setState(() => _avancado = v),
            children: [
              const SizedBox(height: 8),
              TextField(
                controller: _hostCtrl,
                decoration: const InputDecoration(
                  labelText: 'Servidor IMAP',
                  hintText: 'ex: imap.exemplo.com',
                  prefixIcon: Icon(Icons.dns_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _portCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Porta',
                        prefixIcon: Icon(Icons.settings_ethernet),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    children: [
                      const Text('SSL/TLS', style: TextStyle(fontSize: 12, color: Colors.white60)),
                      Switch(value: _ssl, onChanged: (v) => setState(() => _ssl = v)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),

          const SizedBox(height: 16),

          // ── Resultado do teste ─────────────────────────────────────────────
          if (_testeOk != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_testeOk! ? Colors.green : Colors.red).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: (_testeOk! ? Colors.green : Colors.red).withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                _testeOk! ? '✅ Conexão bem-sucedida!' : '❌ $_erroTeste',
                style: TextStyle(fontSize: 12, color: _testeOk! ? Colors.green : Colors.red),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Botões ─────────────────────────────────────────────────────────
          OutlinedButton.icon(
            onPressed: _testando ? null : _testar,
            icon: _testando
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.wifi_protected_setup),
            label: Text(_testando ? 'Testando...' : 'Testar conexão'),
          ),
          const SizedBox(height: 8),

          ElevatedButton.icon(
            onPressed: podeSalvar ? _salvar : null,
            icon: const Icon(Icons.check),
            label: const Text('Salvar conta'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A90D9),
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white38,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 12),

          const Text(
            '🔒 A senha é armazenada com segurança no Keychain do dispositivo e nunca sai dele.',
            style: TextStyle(fontSize: 11, color: Colors.white38),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Widget do guia passo a passo ─────────────────────────────────────────────

class _GuiaCard extends StatelessWidget {
  final _GuiaProvedor guia;
  const _GuiaCard({required this.guia});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: guia.cor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: guia.cor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: guia.cor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(guia.titulo,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: guia.cor)),
                    Text(guia.subtitulo,
                        style: const TextStyle(fontSize: 11, color: Colors.white54)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...guia.passos.asMap().entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  margin: const EdgeInsets.only(right: 10, top: 1),
                  decoration: BoxDecoration(
                    color: guia.cor.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${e.key + 1}',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: guia.cor),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(e.value, style: const TextStyle(fontSize: 13, color: Colors.white70, height: 1.4)),
                ),
              ],
            ),
          )),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => launchUrl(Uri.parse(guia.url), mode: LaunchMode.externalApplication),
              icon: Icon(guia.icone, size: 16),
              label: Text(guia.labelBotao),
              style: ElevatedButton.styleFrom(
                backgroundColor: guia.cor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
