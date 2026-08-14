import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'servicos/analise_service.dart';
import 'servicos/antivirus_service.dart';
import 'servicos/imap_service.dart';
import 'servicos/quarentena_service.dart';
import 'servicos/notificacao_service.dart';
import 'telas/tela_scan.dart';
import 'telas/tela_limpeza.dart';
import 'telas/tela_seguranca.dart';
import 'telas/tela_email_detalhe.dart';
import 'telas/tela_relatorio.dart';
import 'telas/tela_adicionar_conta.dart';
import 'telas/tela_privacidade.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));
  await NotificacaoService.inicializar();
  runApp(const EmailGuardianApp());
}

class EmailGuardianApp extends StatelessWidget {
  const EmailGuardianApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Email Guardian',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF4A90D9),
          onPrimary: Colors.white,
          secondary: const Color(0xFF4A90D9),
          onSecondary: Colors.white,
          surface: const Color(0xFF1E1E2E),
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A1A),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E1E2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A0A1A),
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
          ),
        ),
      ),
      home: const TelaHome(),
    );
  }
}

class TelaHome extends StatefulWidget {
  const TelaHome({super.key});

  @override
  State<TelaHome> createState() => _TelaHomeState();
}

class _TelaHomeState extends State<TelaHome> {
  // ── Auth ───────────────────────────────────────────────────────────────────
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'https://www.googleapis.com/auth/gmail.modify'],
  );
  String? _accessToken;
  String? _emailUsuario;

  // ── IMAP accounts ──────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _contasImap = [];
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ── Data ───────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _emails = [];
  Map<String, dynamic>? _stats;
  bool _carregando = false;
  String _status = 'Faça login para começar';

  // ── Premium / trial ────────────────────────────────────────────────────────
  bool _premium = false;
  DateTime? _inicioTrial;
  ProductDetails? _produtoPremium;
  late StreamSubscription<List<PurchaseDetails>> _iapSub;
  final InAppPurchase _iap = InAppPurchase.instance;

  // ── UI ─────────────────────────────────────────────────────────────────────
  int _tabAtual = 0;
  final StreamController<String> _progressoCtrl = StreamController<String>.broadcast();

  // ── Serviços ───────────────────────────────────────────────────────────────
  QuarentenaService? _quarentena;
  bool _precisaVerificar = false;

  bool get _temConta => _emailUsuario != null || _contasImap.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Rede de segurança final: NENHUMA falha de inicialização (Google
    // Sign-In, IAP/Billing, SharedPreferences corrompido, etc.) pode derrubar
    // o app. É exatamente isto que o revisor automático do Google verifica.
    _inicializar().catchError((_) {
      if (mounted) setState(() => _status = 'Erro ao iniciar — tente novamente');
    });
  }

  @override
  void dispose() {
    _iapSub.cancel();
    _progressoCtrl.close();
    super.dispose();
  }

  Future<void> _inicializar() async {
    final prefs = await SharedPreferences.getInstance();

    final salvo = prefs.getString('inicioTrial');
    _inicioTrial = salvo != null ? DateTime.parse(salvo) : DateTime.now();
    if (salvo == null) await prefs.setString('inicioTrial', _inicioTrial!.toIso8601String());

    _premium = prefs.getBool('premium') ?? false;

    final ultimoScanStr = prefs.getString('ultimo_scan');
    if (ultimoScanStr != null) {
      final ultimoScan = DateTime.parse(ultimoScanStr);
      _precisaVerificar = DateTime.now().difference(ultimoScan).inHours >= 23;
    }

    // Carregar contas IMAP salvas
    final contasJson = prefs.getString('imap_contas');
    if (contasJson != null) {
      try {
        _contasImap = (json.decode(contasJson) as List).cast<Map<String, dynamic>>();
      } catch (_) {
        _contasImap = [];
      }
    }

    // Faturamento (IAP): nunca deve derrubar o app na inicialização — se a
    // Play Store / Billing Library não responder (ex.: ambiente de revisão do
    // Google, dispositivo sem conta configurada), apenas seguimos sem premium.
    try {
      await _iniciarIAP();
      await _carregarProduto();
    } catch (_) {}

    // Login silencioso do Google: se o token salvo não puder ser renovado
    // (conta revogada, sem Play Services, ambiente de teste automatizado),
    // isso nunca deve travar o app — o usuário volta para a tela de login.
    try {
      final emailSalvo = prefs.getString('email');
      if (emailSalvo != null) {
        final user = await _googleSignIn.signInSilently();
        if (user != null) await _autenticar(user);
      }
    } catch (_) {
      _accessToken = null;
      _emailUsuario = null;
    }

    // Se tem IMAP mas não Gmail, carregar emails IMAP
    if (_emailUsuario == null && _contasImap.isNotEmpty) {
      try {
        await _carregarEmails();
      } catch (_) {}
    }

    final consentimento = prefs.getBool('consentimento') ?? false;
    if (!consentimento && mounted) {
      Future.delayed(Duration.zero, _mostrarConsentimento);
    }

    if (mounted) setState(() {});
  }

  Future<void> _iniciarIAP() async {
    if (!await _iap.isAvailable()) return;
    _iapSub = _iap.purchaseStream.listen((purchases) async {
      for (final p in purchases) {
        if (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('premium', true);
          if (mounted) setState(() { _premium = true; _status = '💎 Premium ativado'; });
          if (p.pendingCompletePurchase) await _iap.completePurchase(p);
        }
      }
    }, onError: (_) {});
  }

  Future<void> _carregarProduto() async {
    if (!await _iap.isAvailable()) return;
    final r = await _iap.queryProductDetails({'premium_mensal'});
    if (r.productDetails.isNotEmpty && mounted) {
      setState(() => _produtoPremium = r.productDetails.first);
    }
  }

  bool get _temAcesso {
    if (_premium) return true;
    if (_inicioTrial == null) return false;
    return DateTime.now().difference(_inicioTrial!).inDays < 7;
  }

  // ── Gmail OAuth ────────────────────────────────────────────────────────────

  Future<void> _login() async {
    try {
      final user = await _googleSignIn.signIn();
      if (user == null) return;
      await _autenticar(user);
    } catch (e) {
      setState(() => _status = 'Erro no login');
    }
  }

  Future<void> _autenticar(dynamic user) async {
    final auth = await user.authentication;
    _accessToken = auth.accessToken;
    _emailUsuario = user.email;
    _quarentena = QuarentenaService(_accessToken);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('email', user.email);

    setState(() => _status = '✅ ${user.email}');

    await NotificacaoService.solicitarPermissao();
    await NotificacaoService.agendarLembreteDiario();

    if (_emails.isEmpty) await _executarScanOnboarding();
  }

  Future<void> _executarScanOnboarding() async {
    if (!mounted) return;

    final stats = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => TelaScan(
          progressoStream: _progressoCtrl.stream,
          executarScan: _scanCompleto,
        ),
      ),
    );

    if (stats != null) {
      setState(() => _stats = stats);

      if (!_premium && mounted) {
        final golpes = (stats['golpes'] ?? 0) as int;
        final rastreadores = (stats['empresasRastreando'] ?? 0) as int;
        if (golpes > 0 || rastreadores >= 3) {
          await Future.delayed(const Duration(milliseconds: 700));
          if (mounted) _mostrarPaywallInteligente(stats);
        }
      }
    }
  }

  Future<Map<String, dynamic>> _scanCompleto() async {
    _progressoCtrl.add('Buscando emails recentes...');
    await _carregarEmails(silencioso: true);

    _progressoCtrl.add('Detectando rastreadores...');
    await Future.delayed(const Duration(milliseconds: 300));

    _progressoCtrl.add('Verificando ameaças e phishing...');
    await Future.delayed(const Duration(milliseconds: 300));

    _progressoCtrl.add('Analisando autenticidade dos remetentes...');
    await Future.delayed(const Duration(milliseconds: 300));

    _progressoCtrl.add('Calculando estatísticas...');
    return AnaliseService.calcularEstatisticas(_emails);
  }

  // ── Carregamento de emails ─────────────────────────────────────────────────

  Future<void> _carregarEmails({bool silencioso = false}) async {
    final temGmail = _accessToken != null;
    final temImap = _contasImap.isNotEmpty;
    if (!temGmail && !temImap) return;

    if (!silencioso) setState(() { _carregando = true; _status = '📥 Carregando emails...'; });

    try {
      final futures = <Future<List<Map<String, dynamic>>>>[];
      if (temGmail) futures.add(_buscarEmailsGmail());
      for (final c in _contasImap) futures.add(_buscarEmailsImap(c));

      final resultados = await Future.wait(futures);
      final todos = resultados.expand((r) => r).toList();

      todos.sort((a, b) {
        try {
          final da = DateTime.tryParse(a['data'] ?? '') ?? DateTime(2000);
          final db = DateTime.tryParse(b['data'] ?? '') ?? DateTime(2000);
          return db.compareTo(da);
        } catch (_) { return 0; }
      });

      final stats = AnaliseService.calcularEstatisticas(todos);
      setState(() {
        _emails = todos;
        _stats = stats;
        _status = '✅ ${todos.length} email${todos.length != 1 ? 's' : ''} carregado${todos.length != 1 ? 's' : ''}';
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ultimo_scan', DateTime.now().toIso8601String());

      final golpes = (stats['golpes'] ?? 0) as int;
      if (golpes > 0 && !silencioso) await NotificacaoService.mostrarAlertaAmeaca(golpes);
    } catch (e) {
      setState(() => _status = '❌ Erro ao carregar');
    } finally {
      if (!silencioso) setState(() => _carregando = false);
    }
  }

  Future<List<Map<String, dynamic>>> _buscarEmailsGmail() async {
    if (_accessToken == null) return [];
    final temp = <Map<String, dynamic>>[];

    try {
      final res = await http.get(
        Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=50'),
        headers: {'Authorization': 'Bearer $_accessToken'},
      );

      if (res.statusCode == 401) {
        final user = await _googleSignIn.signInSilently();
        if (user != null) {
          final auth = await user.authentication;
          _accessToken = auth.accessToken;
          return _buscarEmailsGmail();
        }
        return temp;
      }

      if (res.statusCode != 200) return temp;

      final data = json.decode(res.body);
      final lista = (data['messages'] ?? []) as List;

      for (final msg in lista.take(30)) {
        final detalhe = await http.get(
          Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/${msg['id']}?format=full'),
          headers: {'Authorization': 'Bearer $_accessToken'},
        );
        if (detalhe.statusCode != 200) continue;

        final json0 = json.decode(detalhe.body) as Map<String, dynamic>;
        final headers = (json0['payload']?['headers'] ?? []) as List;

        String assunto = '', remetente = '', data = '';
        for (final h in headers) {
          switch (h['name']) {
            case 'Subject': assunto = h['value'] ?? ''; break;
            case 'From': remetente = h['value'] ?? ''; break;
            case 'Date': data = h['value'] ?? ''; break;
          }
        }

        final snippet = json0['snippet'] ?? '';
        final html = _extrairHtml(json0) ?? snippet;
        final analise = AnaliseService.analisar(snippet, html, headers, remetente, assunto);
        final payload = json0['payload'] as Map<String, dynamic>? ?? {};
        final antivirus = AntivirusService.analisarCompleto(
          remetente: remetente,
          assunto: assunto,
          snippet: snippet,
          html: html,
          headers: headers,
          payload: payload,
          phishingExistente: analise,
        );

        final emailMap = <String, dynamic>{
          'id': msg['id'],
          'assunto': assunto,
          'remetente': remetente,
          'data': data,
          'snippet': snippet,
          'analise': analise,
          'antivirus': antivirus,
          'emQuarentena': false,
          'conta': _emailUsuario,
        };

        if (_premium && antivirus['precisaQuarentena'] == true) {
          final ok = await _quarentena?.moverParaQuarentena(msg['id'] as String);
          if (ok == true) emailMap['emQuarentena'] = true;
        }

        temp.add(emailMap);
      }
    } catch (_) {}

    return temp;
  }

  Future<List<Map<String, dynamic>>> _buscarEmailsImap(Map<String, dynamic> conta) async {
    final email = conta['email'] as String;
    final password = await _storage.read(key: 'imap_$email');
    if (password == null) return [];

    final brutos = await ImapService.buscarEmails(
      email: email,
      password: password,
      host: conta['host'] as String,
      port: conta['port'] as int,
      ssl: conta['ssl'] as bool,
    );

    return brutos.map((b) {
      final remetente = b['remetente'] as String;
      final assunto = b['assunto'] as String;
      final snippet = b['snippet'] as String;
      final html = (b['html'] as String?) ?? '';
      final headers = b['headers'] as List<dynamic>;

      final analise = AnaliseService.analisar(snippet, html, headers, remetente, assunto);
      final antivirus = AntivirusService.analisarCompleto(
        remetente: remetente,
        assunto: assunto,
        snippet: snippet,
        html: html,
        headers: headers,
        payload: const {},
        phishingExistente: analise,
      );

      return <String, dynamic>{
        ...b,
        'analise': analise,
        'antivirus': antivirus,
        'emQuarentena': false,
      };
    }).toList();
  }

  String? _extrairHtml(Map<String, dynamic> json0) {
    try {
      final parts = json0['payload']?['parts'] as List?;
      if (parts != null) {
        for (final p in parts) {
          if (p['mimeType'] == 'text/html') {
            final data = p['body']?['data'];
            if (data != null) return utf8.decode(base64Url.decode(data));
          }
        }
      }
      final body = json0['payload']?['body']?['data'];
      if (body != null) return utf8.decode(base64Url.decode(body));
    } catch (_) {}
    return null;
  }

  // ── Gestão de contas IMAP ─────────────────────────────────────────────────

  Future<void> _adicionarConta() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const TelaAdicionarConta()),
    );
    if (result == null || !mounted) return;

    setState(() => _contasImap.add(result));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('imap_contas', json.encode(_contasImap));

    final emailsAntes = _emails.length;
    await _carregarEmails();

    if (mounted && _emails.length == emailsAntes && _contasImap.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Não foi possível carregar emails. Verifique as credenciais e se o IMAP está ativado no provedor.'),
          duration: Duration(seconds: 6),
          backgroundColor: Color(0xFF5C3317),
        ),
      );
    }
  }

  Future<void> _removerContaImap(String email) async {
    await _storage.delete(key: 'imap_$email');
    setState(() {
      _contasImap.removeWhere((c) => c['email'] == email);
      _emails.removeWhere((e) => e['conta'] == email);
      _stats = AnaliseService.calcularEstatisticas(_emails);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('imap_contas', json.encode(_contasImap));
  }

  void _mostrarGerenciarContas() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(builder: (ctx, setS) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Contas conectadas',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              if (_emailUsuario != null)
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.account_circle)),
                  title: Text(_emailUsuario!),
                  subtitle: const Text('Gmail (Google)'),
                  trailing: TextButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _logout();
                    },
                    child: const Text('Sair', style: TextStyle(color: Colors.red)),
                  ),
                ),
              ..._contasImap.map((c) => ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.blue,
                      child: Icon(Icons.mail, color: Colors.white, size: 18),
                    ),
                    title: Text(c['email'] as String),
                    subtitle: Text(c['host'] as String),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _removerContaImap(c['email'] as String);
                      },
                    ),
                  )),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _adicionarConta();
                },
                icon: const Icon(Icons.add),
                label: const Text('Adicionar outra conta'),
              ),
            ],
          ),
        );
      }),
    );
  }

  // ── Ações sobre emails ─────────────────────────────────────────────────────

  Future<void> _moverLixeira(String id) async {
    if (id.startsWith('imap_')) {
      setState(() => _emails.removeWhere((e) => e['id'] == id));
      return;
    }
    if (_accessToken == null) return;
    await http.post(
      Uri.parse('https://gmail.googleapis.com/gmail/v1/users/me/messages/$id/trash'),
      headers: {'Authorization': 'Bearer $_accessToken'},
    );
    setState(() => _emails.removeWhere((e) => e['id'] == id));
  }

  Future<void> _removerLote(List<String> ids) async {
    for (final id in ids) await _moverLixeira(id);
    setState(() => _stats = AnaliseService.calcularEstatisticas(_emails));
  }

  Future<void> _quarentenarEmail(String id) async {
    if (id.startsWith('imap_')) return;
    final ok = await _quarentena?.moverParaQuarentena(id);
    if (ok == true && mounted) {
      setState(() {
        for (final e in _emails) {
          if (e['id'] == id) e['emQuarentena'] = true;
        }
      });
    }
  }

  // ── IAP ────────────────────────────────────────────────────────────────────

  Future<void> _comprar() async {
    if (!await _iap.isAvailable()) return;
    final r = await _iap.queryProductDetails({'premium_mensal'});
    if (r.productDetails.isEmpty) {
      setState(() => _status = '❌ Produto não encontrado');
      return;
    }
    _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: r.productDetails.first));
  }

  Future<void> _logout() async {
    await _googleSignIn.signOut();
    await NotificacaoService.cancelarTodos();
    for (final c in _contasImap) {
      await _storage.delete(key: 'imap_${c['email']}');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('email');
    await prefs.remove('ultimo_scan');
    await prefs.remove('imap_contas');
    setState(() {
      _accessToken = null;
      _emailUsuario = null;
      _quarentena = null;
      _contasImap.clear();
      _emails.clear();
      _stats = null;
      _status = 'Faça login para começar';
    });
  }

  // LGPD Art. 18 — exclusão completa de todos os dados locais
  Future<void> _excluirTodosDados() async {
    if (!mounted) return;
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('⚠️ Excluir todos os dados?'),
        content: const Text(
          'Isso irá:\n\n'
          '• Desconectar todas as contas\n'
          '• Apagar senhas salvas no Keychain\n'
          '• Limpar todas as preferências locais\n'
          '• Revogar seu consentimento LGPD\n\n'
          'Equivale ao direito de eliminação (LGPD Art. 18, IV).\n\n'
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir tudo'),
          ),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    await _googleSignIn.signOut();
    await NotificacaoService.cancelarTodos();
    await _storage.deleteAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    setState(() {
      _accessToken = null;
      _emailUsuario = null;
      _quarentena = null;
      _contasImap.clear();
      _emails.clear();
      _stats = null;
      _premium = false;
      _inicioTrial = null;
      _status = 'Faça login para começar';
    });
  }

  Future<void> _mostrarConsentimento() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('🔒 Consentimento — LGPD'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'O Email Guardian solicita seu consentimento (LGPD Art. 7º, I) para:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 10),
              _textoConsentimento('🔍 Analisar o conteúdo dos seus emails para detectar golpes, phishing, rastreadores e marketing.'),
              _textoConsentimento('📱 Armazenar localmente seu endereço de email e credenciais IMAP (no Keychain do dispositivo).'),
              _textoConsentimento('🔔 Enviar notificações locais de alerta de segurança.'),
              const SizedBox(height: 10),
              const Text(
                '✅ O que NUNCA fazemos:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green),
              ),
              const SizedBox(height: 6),
              _textoConsentimento('Nenhum conteúdo de email é enviado a servidores externos.'),
              _textoConsentimento('Não compartilhamos dados com terceiros.'),
              _textoConsentimento('Não usamos analytics ou rastreamento de comportamento.'),
              const SizedBox(height: 10),
              const Text(
                'Seus direitos (LGPD Art. 18): acesso, correção, eliminação e revogação do consentimento a qualquer momento em Menu → Privacidade.',
                style: TextStyle(fontSize: 11, color: Colors.white54, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('consentimento', true);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Li e consinto'),
          ),
        ],
      ),
    );
  }

  Widget _textoConsentimento(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: Colors.white54)),
          Expanded(child: Text(texto, style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.4))),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_temConta) return _buildLogin();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Email Guardian', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_carregando) const Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => _carregarEmails()),
          PopupMenuButton<String>(
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              const PopupMenuItem(value: 'contas', child: Text('Gerenciar contas')),
              const PopupMenuItem(value: 'adicionar', child: Text('Adicionar conta')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'privacidade_lgpd', child: Text('🔒 Privacidade e LGPD')),
              const PopupMenuItem(value: 'excluir_dados', child: Text('⚠️ Excluir meus dados', style: TextStyle(color: Colors.red))),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'logout', child: Text('Sair de todas as contas')),
            ],
            onSelected: (v) async {
              if (v == 'contas') _mostrarGerenciarContas();
              if (v == 'adicionar') await _adicionarConta();
              if (v == 'privacidade_lgpd') {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => TelaPrivacidade(onExcluirDados: _excluirTodosDados),
                ));
              }
              if (v == 'excluir_dados') await _excluirTodosDados();
              if (v == 'logout') await _logout();
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _tabAtual,
        children: [
          _buildPainel(),
          _buildEmailsList(),
          TelaSeguranca(
            emails: _emails,
            premium: _temAcesso,
            onAssinar: _mostrarPaywall,
            onQuarentenar: _quarentenarEmail,
          ),
          TeleLimpeza(emails: _emails, premium: _temAcesso, onAssinar: _mostrarPaywall, onRemover: _removerLote),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabAtual,
        onDestinationSelected: (i) => setState(() => _tabAtual = i),
        backgroundColor: const Color(0xFF1E1E2E),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Painel',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _emails.any((e) => ['🚨 GOLPE', '⚠️ PHISHING'].contains(e['analise']?['tipo'])),
              child: const Icon(Icons.mail_outlined),
            ),
            selectedIcon: const Icon(Icons.mail),
            label: 'Emails',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _emails.any((e) {
                final n = e['antivirus']?['ameaca']?['nivel'] as String?;
                return n == 'CRÍTICO' || n == 'ALTO';
              }),
              child: const Icon(Icons.security_outlined),
            ),
            selectedIcon: const Icon(Icons.security),
            label: 'Segurança',
          ),
          const NavigationDestination(
            icon: Icon(Icons.cleaning_services_outlined),
            selectedIcon: Icon(Icons.cleaning_services),
            label: 'Limpeza',
          ),
        ],
      ),
    );
  }

  Widget _buildLogin() {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.shield, size: 80, color: Color(0xFF4A90D9)),
              const SizedBox(height: 24),
              const Text(
                'Email Guardian',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Proteja seu email de golpes,\nrastreadores e marketing indesejado',
                style: TextStyle(fontSize: 16, color: Colors.white60),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              ElevatedButton.icon(
                onPressed: _login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.login),
                label: const Text('Entrar com Google (Gmail)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Expanded(child: Divider(color: Colors.white24)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('ou', style: TextStyle(color: Colors.white38)),
                  ),
                  Expanded(child: Divider(color: Colors.white24)),
                ],
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _adicionarConta,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: const BorderSide(color: Color(0xFF4A90D9)),
                ),
                icon: const Icon(Icons.mail_outline, color: Color(0xFF4A90D9)),
                label: const Text(
                  'Outlook, Yahoo, iCloud e outros',
                  style: TextStyle(fontSize: 15, color: Color(0xFF4A90D9), fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => launchUrl(Uri.parse('https://wggarcia.github.io/email-guardian-privacy/')),
                child: const Text('Política de Privacidade', style: TextStyle(color: Colors.white38)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPainel() {
    final stats = _stats;
    if (stats == null && _emails.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox, size: 64, color: Colors.white30),
            const SizedBox(height: 16),
            const Text('Nenhum email carregado ainda', style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _carregarEmails(),
              icon: const Icon(Icons.refresh),
              label: const Text('Carregar emails'),
            ),
          ],
        ),
      );
    }

    final s = stats ?? AnaliseService.calcularEstatisticas(_emails);
    final diasTrial = _inicioTrial != null ? 7 - DateTime.now().difference(_inicioTrial!).inDays : 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_precisaVerificar && _temConta)
          _bannerLembrete(),

        if (!_premium && !_temAcesso)
          _bannerPremiumCompleto()
        else if (!_premium)
          _bannerTrial(diasTrial),

        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(child: _statCard('${s['total']}', 'Emails', Icons.mail, Colors.blue)),
            const SizedBox(width: 12),
            Expanded(child: _statCard('${s['marketing']}', 'Marketing', Icons.campaign, Colors.orange)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _statCard('${s['golpes']}', 'Golpes', Icons.dangerous, Colors.red)),
            const SizedBox(width: 12),
            Expanded(child: _statCard('${s['empresasRastreando']}', 'Rastreadores', Icons.visibility, Colors.purple)),
          ],
        ),

        const SizedBox(height: 24),

        if ((s['golpes'] as int) > 0) ...[
          _alertaGolpes(s['golpes'] as int),
          const SizedBox(height: 12),
        ],

        Builder(builder: (ctx) {
          final criticos = _emails.where((e) {
            final n = e['antivirus']?['ameaca']?['nivel'] as String?;
            return n == 'CRÍTICO' || n == 'ALTO';
          }).length;
          if (criticos == 0) return const SizedBox.shrink();
          return Column(
            children: [
              GestureDetector(
                onTap: () => setState(() => _tabAtual = 2),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.security, color: Colors.red),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '🛡️ Antivírus: $criticos email${criticos > 1 ? 's' : ''} com ameaça${criticos > 1 ? 's' : ''} detectada${criticos > 1 ? 's' : ''}',
                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.red),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          );
        }),

        if ((s['desinscrever'] as int) > 0)
          _acaoRapida(
            icon: Icons.unsubscribe,
            titulo: 'Desinscrever em massa',
            descricao: '${s['desinscrever']} remetentes com opção de cancelamento',
            cor: Colors.orange,
            onTap: () => setState(() => _tabAtual = 3),
          ),

        const SizedBox(height: 8),

        if ((s['empresasRastreando'] as int) > 0)
          _acaoRapida(
            icon: Icons.visibility_off,
            titulo: 'Ver rastreadores',
            descricao: '${s['empresasRastreando']} empresa${(s['empresasRastreando'] as int) > 1 ? 's' : ''} monitorando você',
            cor: Colors.purple,
            onTap: () => setState(() => _tabAtual = 2),
          ),

        const SizedBox(height: 16),

        if (_emails.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TelaRelatorio(
                  emails: _emails,
                  premium: _temAcesso,
                  onAssinar: _mostrarPaywall,
                ),
              ),
            ),
            icon: const Icon(Icons.bar_chart),
            label: const Text('Ver relatório de segurança'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
            ),
          ),

        const SizedBox(height: 12),
        Text(_status, style: const TextStyle(fontSize: 12, color: Colors.white38), textAlign: TextAlign.center),
      ],
    );
  }

  Widget _buildEmailsList() {
    if (_emails.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inbox, size: 64, color: Colors.white30),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _carregarEmails(),
              icon: const Icon(Icons.refresh),
              label: const Text('Carregar emails'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _emails.length,
      itemBuilder: (context, i) {
        final e = _emails[i];
        final analise = e['analise'] as Map<String, dynamic>;
        final tipo = analise['tipo'] ?? '🧾 SEGURO';
        final cor = analise['cor'] as Color? ?? Colors.green;
        final temRastreador = (analise['rastreadores'] as Set?)?.isNotEmpty == true;
        final temUnsubscribe = analise['linkDesinscrever'] != null;
        final avNivel = e['antivirus']?['ameaca']?['nivel'] as String?;
        final avAlerta = avNivel == 'CRÍTICO' || avNivel == 'ALTO';
        final ehImap = e['ehImap'] == true;
        final conta = e['conta'] as String?;
        final contaLabel = conta != null && conta.contains('@')
            ? '@${conta.split('@').last}'
            : null;

        return Dismissible(
          key: Key(e['id']),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            color: Colors.red,
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) => _moverLixeira(e['id']),
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TelaEmailDetalhe(
                    email: e,
                    premium: _temAcesso,
                    onAssinar: _mostrarPaywall,
                    onQuarentenar: _quarentenarEmail,
                    onDeletar: (id) async => _moverLixeira(id),
                  ),
                ),
              ),
              leading: CircleAvatar(
                backgroundColor: cor.withValues(alpha: 0.2),
                child: Text(tipo.split(' ').first, style: const TextStyle(fontSize: 16)),
              ),
              title: Text(
                e['assunto'] ?? 'Sem assunto',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e['remetente'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.white60),
                  ),
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      _chip(tipo, cor),
                      if (ehImap && contaLabel != null)
                        _chip(contaLabel, Colors.blueGrey),
                      if (temRastreador)
                        _chip('🕵️ rastreador', Colors.purple),
                      if (temUnsubscribe)
                        _chip('📧 marketing', Colors.orange),
                      if (avAlerta)
                        _chip('🛡️ $avNivel', Colors.red),
                    ],
                  ),
                ],
              ),
              isThreeLine: true,
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                onPressed: () => _moverLixeira(e['id']),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _chip(String label, Color cor) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: cor)),
    );
  }

  // ── Paywall ────────────────────────────────────────────────────────────────

  void _mostrarPaywallInteligente(Map<String, dynamic> stats) {
    final golpes = (stats['golpes'] ?? 0) as int;
    final rastreadores = (stats['empresasRastreando'] ?? 0) as int;
    final desinscrever = (stats['desinscrever'] ?? 0) as int;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (golpes > 0)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '🚨 Encontrei $golpes email${golpes > 1 ? 's' : ''} com sinais de golpe na sua caixa',
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
            const Text('💎 Proteja-se com o Premium',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              _produtoPremium != null ? '${_produtoPremium!.price}/mês' : 'R\$ 4,99/mês',
              style: const TextStyle(fontSize: 18, color: Color(0xFF4A90D9), fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            if (golpes > 0)
              _beneficio('Isolar $golpes email${golpes > 1 ? 's' : ''} perigoso${golpes > 1 ? 's' : ''} em Quarentena automática'),
            if (rastreadores > 0)
              _beneficio('Bloquear $rastreadores empresa${rastreadores > 1 ? 's' : ''} que te rastreiam'),
            if (desinscrever > 0)
              _beneficio('Cancelar $desinscrever newsletter${desinscrever > 1 ? 's' : ''} com 1 toque'),
            _beneficio('Monitoramento contínuo 24h e alertas'),
            _beneficio('Limpeza automática de marketing toda hora'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () { Navigator.pop(context); _comprar(); },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A90D9),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Ativar Premium agora', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Agora não', style: TextStyle(color: Colors.white38)),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _mostrarPaywall() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('💎 Email Guardian Premium',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              _produtoPremium != null ? '${_produtoPremium!.price}/mês' : 'R\$ 4,99/mês',
              style: const TextStyle(fontSize: 18, color: Color(0xFF4A90D9), fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            _beneficio('Desinscrever remetentes em massa com 1 toque'),
            _beneficio('Bloquear rastreadores de pixels automaticamente'),
            _beneficio('Limpeza automática de marketing a cada hora'),
            _beneficio('Monitoramento contínuo e alertas de golpes'),
            _beneficio('Suporte sem anúncios'),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () { Navigator.pop(context); _comprar(); },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A90D9),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Ativar Premium', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () { Navigator.pop(context); _iap.restorePurchases(); },
                  child: const Text('Restaurar compra'),
                ),
                const Text('·', style: TextStyle(color: Colors.white38)),
                TextButton(
                  onPressed: () => launchUrl(Uri.parse('https://www.apple.com/legal/internet-services/itunes/dev/stdeula/')),
                  child: const Text('Termos'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Renovação automática mensal. Cancele a qualquer momento.',
                style: TextStyle(fontSize: 11, color: Colors.white38), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // ── Widgets auxiliares ─────────────────────────────────────────────────────

  Widget _statCard(String valor, String label, IconData icon, Color cor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cor, size: 24),
          const SizedBox(height: 8),
          Text(valor, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: cor)),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.white60)),
        ],
      ),
    );
  }

  Widget _acaoRapida({required IconData icon, required String titulo, required String descricao, required Color cor, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cor.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: cor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(descricao, style: const TextStyle(fontSize: 12, color: Colors.white60)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: cor),
          ],
        ),
      ),
    );
  }

  Widget _alertaGolpes(int count) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, color: Colors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '⚠️ $count email${count > 1 ? 's' : ''} com sinais de golpe detectado${count > 1 ? 's' : ''}',
              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _tabAtual = 1),
            child: const Text('Ver', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _bannerTrial(int dias) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer, color: Colors.green),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Teste gratuito: ${dias > 0 ? '$dias dia${dias > 1 ? 's' : ''} restante${dias > 1 ? 's' : ''}' : 'expira hoje'}',
              style: const TextStyle(color: Colors.green, fontSize: 13),
            ),
          ),
          TextButton(onPressed: _mostrarPaywall, child: const Text('Assinar')),
        ],
      ),
    );
  }

  Widget _bannerPremiumCompleto() {
    return GestureDetector(
      onTap: _mostrarPaywall,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF1A237E), Color(0xFF283593)]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            const Text('💎 Ative o Premium para desbloquear todos os recursos',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text('Desinscrever em massa · Bloquear rastreadores · Limpeza automática',
                style: TextStyle(fontSize: 12, color: Colors.white70), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF4A90D9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _produtoPremium != null ? 'Assinar por ${_produtoPremium!.price}/mês' : 'Assinar Premium',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bannerLembrete() {
    return GestureDetector(
      onTap: () async {
        setState(() => _precisaVerificar = false);
        await _carregarEmails();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
        ),
        child: const Row(
          children: [
            Icon(Icons.refresh, color: Colors.blue, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '📬 Sua caixa não foi verificada há mais de 23h — verificar agora',
                style: TextStyle(fontSize: 12, color: Colors.blue),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _beneficio(String texto) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.greenAccent, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(texto, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}
