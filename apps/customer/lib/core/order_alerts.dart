import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

class OrderAlerts {
  static const _channel = MethodChannel('deliveria/alerts');

  static Future<void> sync(String? accessToken) async {
    final prefs = await SharedPreferences.getInstance();
    if (accessToken == null || accessToken.isEmpty) {
      await prefs.remove('alert_access');
      await prefs.remove('alert_base');
      try {
        await _channel.invokeMethod<void>('stop');
      } catch (_) {}
      return;
    }
    final android = FlutterLocalNotificationsPlugin().resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await prefs.setString('alert_access', accessToken);
    await prefs.setString('alert_base', AppConfig.apiBase);
    try {
      await _channel.invokeMethod<void>('start');
    } catch (_) {}
  }
}
