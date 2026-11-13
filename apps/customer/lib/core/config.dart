import 'dart:io';

class AppConfig {
  /// Fixed Cloudflare hostname for Deliveria API (named tunnel, not quick tunnel).
  /// Override at build time with `--dart-define=API_BASE=https://...` if needed.
  static const hostedApiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'https://deliveria.tembmail.com',
  );

  static int _baseIndex = 0;

  static List<String> get _candidates {
    if (hostedApiBase.isNotEmpty) return [hostedApiBase];
    // Local developer fallbacks only.
    if (Platform.isAndroid) {
      return const [
        'http://192.168.1.5:3000',
        'http://10.0.2.2:3000',
      ];
    }
    return const ['http://127.0.0.1:3000'];
  }

  static String get apiBase => _candidates[_baseIndex];

  static bool tryNextBase() {
    if (_baseIndex + 1 >= _candidates.length) return false;
    _baseIndex += 1;
    return true;
  }

  static const devKey = String.fromEnvironment('DEV_TOOLS_KEY', defaultValue: 'deliveria-dev');
}
