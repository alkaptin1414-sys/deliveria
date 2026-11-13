import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/order_alerts.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';

class SessionState {
  const SessionState({this.user, this.ready = false, this.online = true});
  final UserProfile? user;
  final bool ready;
  final bool online;

  SessionState copyWith({UserProfile? user, bool? ready, bool? online, bool clearUser = false}) {
    return SessionState(
      user: clearUser ? null : user ?? this.user,
      ready: ready ?? this.ready,
      online: online ?? this.online,
    );
  }
}

class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() => const SessionState();

  Future<void> bootstrap() async {
    final store = ref.read(sessionStoreProvider);
    await store.load();
    if (store.accessToken == null) {
      state = state.copyWith(ready: true, clearUser: true);
      return;
    }
    try {
      final user = await ref.read(apiProvider).me();
      state = SessionState(user: user, ready: true);
      OrderAlerts.sync(store.accessToken);
    } on ApiException catch (error) {
      if (error.code == 'OFFLINE') {
        state = state.copyWith(ready: true, online: false);
      } else {
        await store.clear();
        state = const SessionState(ready: true);
      }
    } catch (_) {
      state = state.copyWith(ready: true);
    }
  }

  void setUser(UserProfile user) {
    state = SessionState(user: user, ready: true);
    OrderAlerts.sync(ref.read(sessionStoreProvider).accessToken);
  }

  Future<void> logout() async {
    await ref.read(apiProvider).logout();
    state = const SessionState(ready: true);
  }
}

final sessionProvider = NotifierProvider<SessionController, SessionState>(SessionController.new);
