import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../order_alerts.dart';

class SessionStore {
  SessionStore(this._storage);
  final FlutterSecureStorage _storage;
  String? accessToken;
  String? refreshToken;

  Future<void> load() async {
    accessToken = await _storage.read(key: 'access');
    refreshToken = await _storage.read(key: 'refresh');
  }

  Future<void> save(String access, String refresh) async {
    accessToken = access;
    refreshToken = refresh;
    await _storage.write(key: 'access', value: access);
    await _storage.write(key: 'refresh', value: refresh);
    await OrderAlerts.sync(access);
  }

  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    await _storage.deleteAll();
    await OrderAlerts.sync(null);
  }
}
