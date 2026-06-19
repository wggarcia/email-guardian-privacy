import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'servicos/analise_service.dart';
import 'servicos/antivirus_service.dart';
import 'servicos/quarentena_service.dart';
import 'servicos/notificacao_service.dart';
import 'telas/tela_scan.dart';
import 'telas/tela_limpeza.dart';
import 'telas/tela_seguranca.dart';
import 'telas/tela_email_detalhe.dart';
import 'telas/tela_relatorio.dart';

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
          secondary: const Color(0xFF4A90D9),
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
  // Auth
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'https://www.googleapis.com/auth/gmail.modify'],
  );
  String? _accessToken;
  String? _emailUsuario;

  // Data
  List<Map<String, dynamic>> _emails = [];
  Map<String, dynamic>? _stats;
  bool _carregando = false;
  String _status = 'Faça login para começar';

  // Premium / trial
  bool _premium = false;
  DateTime? _inicioTrial;
  ProductDetails? _produtoPremium;
  late StreamSubscription<List<PurchaseDetails>> _iapSub;
  final InAppPurchase _iap = InAppPurchase.instance;

  // UI
  int _tabAtual = 0;
  final StreamController<String> _progressoCtrl = StreamController<String>.broadcast();

  // Serviços
  QuarentenaService? _quarentena;
  bool _precisaVerificar = false;

  @override
  void initState() {
    super.initState();
    _inicializar();
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

    await _iniciarIAP();
    await _carregarProduto();

    final emailSalvo = prefs.getString('email');
    if (emailSalvo != null) {
      final user = await _googleSignIn.signInSilently();
      if (user != null) await _autenticar(user);
    }

    final consentimento = prefs.getBool('consentimento') ?? false;
    if (!consentimento && mounted) {
      Future.delayed(Duration.zero, _mostrarConsentimento);
    }

    setState(() {});
  }

  Future<void> _iniciarIAP() async {
    if (!await _iap.isAvailable()) return;
    _iapSub = _iap.purchaseStream.listen((purchases) async {
      for (final p in purchases) {
        if (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('premium', true);
          setState(() { _premium = true; _status = '💎 Premium ativado'; });
          if (p.pendingCompletePurchase) await _iap.completePurchase(p);
        }
      }
    });
  }

  Future<void> _carregarProduto() async {
    if (!await _iap.isAvailable()) return;
    final r = await _iap.queryProductDetails({'premium_mensal'});
    if (r.productDetails.isNotEmpty) setState(() => _produtoPremium = r.productDetails.first);
  }

  bool get _temAcesso {
    if (_premium) return true;
    if (_inicioTrial == null) return false;
    return DateTime.now().difference(_inicioTrial!).inDays < 7;
  }

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

      // Paywall inteligente com números reais
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
    final stats = AnaliseService.calcularEstatisticas(_emails);

    return stats;
  }

  Future<void> _carregarEmails({bool silencioso = false}) async {
    if (_accessToken == null) return;
    if (!silencioso) setState(() { _carregando = true; _status = '📥 Carregando emails...'; });

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
          return _carregarEmails(silencioso: silencioso);
        }
        return;
      }

      if (res.statusCode != 200) return;

      final data = json.decode(res.body);
      final lista = (data['messages'] ?? []) as List;
      final temp = <Map<String, dynamic>>[];

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
        };

        if (_premium && antivirus['precisaQuarentena'] == true) {
          final ok = await _quarentena?.moverParaQuarentena(msg['id'] as String);
          if (ok == true) emailMap['emQuarentena'] = true;
        }

        temp.add(emailMap);
      }

      final statsNovos = AnaliseService.calcularEstatisticas(temp);
      setState(() {
        _emails = temp;
        _stats = statsNovos;
        _status = '✅ ${temp.length} emails carregados';
      });

      // Salvar timestamp do último scan
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ultimo_scan', DateTime.now().toIso8601String());

      // Notificação imediata se encontrou ameaças
      final golpes = (statsNovos['golpes'] ?? 0) as int;
      if (golpes > 0 && !silencioso) {
        await NotificacaoService.mostrarAlertaAmeaca(golpes);
      }
    } catch (e) {
      setState(() => _status = '❌ Erro ao carregar');
    } finally {
      if (!silencioso) setState(() => _carregando = false);
    }
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

  Future<void> _moverLixeira(String id) async {
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
    final ok = await _quarentena?.moverParaQuarentena(id);
    if (ok == true && mounted) {
      setState(() {
        for (final e in _emails) {
          if (e['id'] == id) e['emQuarentena'] = true;
        }
      });
    }
  }

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
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('email');
    await prefs.remove('ultimo_scan');
    setState(() {
      _accessToken = null;
      _emailUsuario = null;
      _quarentena = null;
      _emails.clear();
      _stats = null;
      _status = 'Faça login para começar';
    });
  }

  Future<void> _mostrarConsentimento() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('🔒 Privacidade'),
        content: const Text(
          'O Email Guardian analisa seus emails para detectar golpes, rastreadores e marketing.\n\n'
          'Os dados são processados localmente no dispositivo. Nenhum conteúdo é enviado para servidores externos.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('consentimento', true);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Entendi e aceito'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_emailUsuario == null) return _buildLogin();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Email Guardian', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_carregando) const Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => _carregarEmails()),
          PopupMenuButton(
            itemBuilder: (_) => [
              PopupMenuItem(value: 'logout', child: const Text('Sair da conta')),
              PopupMenuItem(value: 'privacidade', child: const Text('Política de privacidade')),
            ],
            onSelected: (v) async {
              if (v == 'logout') await _logout();
              if (v == 'privacidade') await launchUrl(Uri.parse('https://wggarcia.github.io/email-guardian-privacy/'));
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
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            selectedIcon: const Icon(Icons.dashboard),
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
          NavigationDestination(
            icon: const Icon(Icons.cleaning_services_outlined),
            selectedIcon: const Icon(Icons.cleaning_services),
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
                label: const Text('Entrar com Google', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
        if (_precisaVerificar && _emailUsuario != null)
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
                  Row(
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 4, right: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: cor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(tipo, style: TextStyle(fontSize: 10, color: cor)),
                      ),
                      if (temRastreador)
                        Container(
                          margin: const EdgeInsets.only(top: 4, right: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('🕵️ rastreador', style: TextStyle(fontSize: 10, color: Colors.purple)),
                        ),
                      if (temUnsubscribe)
                        Container(
                          margin: const EdgeInsets.only(top: 4, right: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('📧 marketing', style: TextStyle(fontSize: 10, color: Colors.orange)),
                        ),
                      if (avAlerta)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('🛡️ $avNivel', style: const TextStyle(fontSize: 10, color: Colors.red)),
                        ),
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
              _produtoPremium != null
                  ? '${_produtoPremium!.price}/mês'
                  : 'R\$ 4,99/mês',
              style: const TextStyle(
                  fontSize: 18,
                  color: Color(0xFF4A90D9),
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            if (golpes > 0)
              _beneficio('Isolar $golpes email${golpes > 1 ? 's' : ''} perigoso${golpes > 1 ? 's' : ''} em Quarentena automática'),
            if (rastreadores > 0)
              _beneficio(
                  'Bloquear $rastreadores empresa${rastreadores > 1 ? 's' : ''} que te rastreiam'),
            if (desinscrever > 0)
              _beneficio(
                  'Cancelar $desinscrever newsletter${desinscrever > 1 ? 's' : ''} com 1 toque'),
            _beneficio('Monitoramento contínuo 24h e alertas'),
            _beneficio('Limpeza automática de marketing toda hora'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _comprar();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A90D9),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Ativar Premium agora',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Agora não',
                  style: TextStyle(color: Colors.white38)),
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
                TextButton(onPressed: () { Navigator.pop(context); _iap.restorePurchases(); }, child: const Text('Restaurar compra')),
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
        child: Row(
          children: const [
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
