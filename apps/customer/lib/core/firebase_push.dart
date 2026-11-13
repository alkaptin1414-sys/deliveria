import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';

Future<void> startFirebase() async {
  try {
    if (Firebase.apps.isNotEmpty) return;
    await Firebase.initializeApp(options: DefaultFirebaseOptions.android);
  } catch (_) {}
}
