import 'dart:math';

class TokenService {
  static String? _token;

  static String get token {
    _token ??= _generateToken();
    return _token!;
  }

  static String _generateToken() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(32, (_) => chars[random.nextInt(chars.length)]).join();
  }

  static bool validate(String token) => token == _token;
}
