import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificacaoService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _inicializado = false;

  static const _idAlerta = 1;
  static const _idLembrete = 2;

  static const _detalhesAlerta = NotificationDetails(
    android: AndroidNotificationDetails(
      'eg_ameacas',
      'Alertas de Ameaças',
      channelDescription: 'Notificações de emails perigosos detectados',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(badgeNumber: 1),
  );

  static const _detalhesLembrete = NotificationDetails(
    android: AndroidNotificationDetails(
      'eg_lembretes',
      'Lembretes Diários',
      channelDescription: 'Lembrete para verificar emails',
      importance: Importance.defaultImportance,
    ),
    iOS: DarwinNotificationDetails(),
  );

  static Future<void> inicializar() async {
    if (_inicializado) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    _inicializado = true;
  }

  static Future<void> solicitarPermissao() async {
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  static Future<void> mostrarAlertaAmeaca(int qtd) async {
    if (!_inicializado) return;
    await _plugin.show(
      _idAlerta,
      '🚨 Email Guardian detectou ameaças',
      '$qtd email${qtd > 1 ? 's' : ''} perigoso${qtd > 1 ? 's' : ''} detectado${qtd > 1 ? 's' : ''} na sua caixa',
      _detalhesAlerta,
    );
  }

  static Future<void> agendarLembreteDiario() async {
    if (!_inicializado) return;
    await _plugin.periodicallyShow(
      _idLembrete,
      '📬 Email Guardian',
      'Verifique sua caixa — pode haver ameaças novas',
      RepeatInterval.daily,
      _detalhesLembrete,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  static Future<void> cancelarTodos() async {
    await _plugin.cancelAll();
  }
}
