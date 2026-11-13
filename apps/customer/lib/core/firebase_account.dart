import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';

class FirebaseAccountException implements Exception {
  FirebaseAccountException(this.message);
  final String message;
}

Future<void> ensureFirebaseApp() async {
  if (Firebase.apps.isNotEmpty) return;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.android);
  } on FirebaseException catch (error) {
    if (error.code == 'duplicate-app' && Firebase.apps.isNotEmpty) return;
    throw FirebaseAccountException(error.message ?? 'تعذر تشغيل Firebase على هذا الجهاز.');
  }
}

Future<String> syncFirebaseAccount({
  required String email,
  required String password,
  required bool registering,
  String? name,
}) async {
  await ensureFirebaseApp();
  final auth = FirebaseAuth.instance;
  try {
    if (registering) {
      try {
        final created = await auth.createUserWithEmailAndPassword(email: email, password: password);
        if (name != null && name.trim().isNotEmpty) {
          await created.user?.updateDisplayName(name.trim());
        }
        final uid = created.user?.uid;
        if (uid == null) throw FirebaseAccountException('Firebase لم يرجّع حسابًا.');
        return uid;
      } on FirebaseAuthException catch (error) {
        if (error.code != 'email-already-in-use') throw _asAccountError(error);
        final signed = await auth.signInWithEmailAndPassword(email: email, password: password);
        final uid = signed.user?.uid;
        if (uid == null) throw FirebaseAccountException('Firebase لم يرجّع حسابًا.');
        return uid;
      }
    }
    final signed = await auth.signInWithEmailAndPassword(email: email, password: password);
    final uid = signed.user?.uid;
    if (uid == null) throw FirebaseAccountException('Firebase لم يرجّع حسابًا.');
    return uid;
  } on FirebaseAuthException catch (error) {
    throw _asAccountError(error);
  }
}

FirebaseAccountException _asAccountError(FirebaseAuthException error) {
  switch (error.code) {
    case 'operation-not-allowed':
      return FirebaseAccountException('تسجيل البريد غير مفعّل في Firebase. من لوحة Firebase افتح Authentication ثم Sign-in method وفعّل Email/Password.');
    case 'invalid-email':
      return FirebaseAccountException('البريد الإلكتروني غير صالح.');
    case 'weak-password':
      return FirebaseAccountException('كلمة المرور ضعيفة. استخدم 8 أحرف على الأقل.');
    case 'email-already-in-use':
      return FirebaseAccountException('هذا البريد مسجّل في Firebase. سجّل الدخول.');
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return FirebaseAccountException('البريد أو كلمة المرور غير صحيحة في Firebase.');
    case 'network-request-failed':
      return FirebaseAccountException('تعذر الاتصال بـ Firebase. تأكد من الإنترنت.');
    default:
      return FirebaseAccountException(error.message ?? 'تعذر إكمال حساب Firebase.');
  }
}
