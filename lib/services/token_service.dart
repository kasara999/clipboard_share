import 'dart:math';

// 【TokenService】
// アプリ起動時に1回だけランダムなトークン（合言葉）を生成し、
// iPhoneが接続してきたときにそのトークンが一致するか確認する。
// これにより、同じWi-Fi内の知らない端末が勝手に接続できないようにしている。
class TokenService {
  // static: インスタンスを作らなくてもクラス名.tokenで直接呼べる
  // _token: アンダースコアで始まる変数はこのファイル内からしかアクセスできない（プライベート）
  static String? _token; // ?はnull（値なし）を許可する型

  // getterプロパティ: _tokenにアクセスするための窓口
  // ??=は「もし_tokenがnullなら右辺を代入する」演算子
  // → 2回目以降は生成せず、最初に作ったトークンをそのまま返す（シングルトンパターン）
  static String get token {
    _token ??= _generateToken();
    return _token!; // !はnullでないことを保証する（nullなら実行時エラー）
  }

  // 32文字のランダム文字列を生成する
  static String _generateToken() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    // Random.secure(): 暗号学的に安全な乱数生成器（予測されにくい）
    final random = Random.secure();
    // List.generate(32, ...) で32個の要素を持つリストを作り、joinで1つの文字列に結合
    return List.generate(32, (_) => chars[random.nextInt(chars.length)]).join();
  }

  // 受け取ったトークンが正しいかチェックする
  static bool validate(String token) => token == _token;
}
