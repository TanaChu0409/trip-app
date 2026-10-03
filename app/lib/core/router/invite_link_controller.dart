import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final inviteLinkControllerProvider = Provider<InviteLinkController>(
    (ref) => throw StateError('Invitation links have not been initialized'));

/// Only an invitation token is persisted; arbitrary redirect URLs are rejected.
class InviteLinkController extends ChangeNotifier {
  InviteLinkController(this._preferences);
  static const _key = 'pending_trip_invite';
  static const baseUrl = String.fromEnvironment('INVITE_BASE_URL');
  static final tokenPattern = RegExp(r'^[0-9a-f]{64}$');
  final SharedPreferences _preferences;
  StreamSubscription<Uri>? _subscription;
  String? _pendingToken;
  String? _lastLocation;
  String? get pendingRoute =>
      _pendingToken == null ? null : '/invite/$_pendingToken';

  String? redirect(String location, {required bool authenticated}) {
    final token = location.startsWith('/invite/')
        ? location.substring('/invite/'.length)
        : null;
    if (token != null &&
        tokenPattern.hasMatch(token) &&
        pendingRoute == null &&
        _lastLocation != location) {
      unawaited(remember(token));
    }
    _lastLocation = location;
    if (!authenticated) return location == '/auth' ? null : '/auth';
    if (location == '/auth') return pendingRoute ?? '/trips';
    if (pendingRoute != null && location != pendingRoute) return pendingRoute;
    return null;
  }

  static Uri parseBaseUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme != 'https' &&
            !(uri.scheme == 'http' && uri.host == 'localhost'))) {
      throw const FormatException('請設定有效的 INVITE_BASE_URL HTTPS 網址');
    }
    return uri.replace(
        path: uri.path.endsWith('/') ? uri.path : '${uri.path}/');
  }

  static String buildUrl(String token, {String base = baseUrl}) {
    if (!tokenPattern.hasMatch(token)) {
      throw const FormatException('Invalid invitation token');
    }
    return parseBaseUrl(base)
        .replace(queryParameters: {'invite': token}).toString();
  }

  static String? tokenFromUri(Uri uri, {String base = baseUrl}) {
    final expected = Uri.tryParse(base);
    if (expected == null ||
        expected.host.isEmpty ||
        uri.scheme != expected.scheme ||
        uri.host != expected.host ||
        uri.port != expected.port ||
        uri.path != parseBaseUrl(base).path) {
      return null;
    }
    final tokens = uri.queryParametersAll['invite'];
    if (tokens == null ||
        tokens.length != 1 ||
        !tokenPattern.hasMatch(tokens.single)) {
      return null;
    }
    return tokens.single;
  }

  Future<void> initialize() async {
    final saved = _preferences.getString(_key);
    if (saved != null && tokenPattern.hasMatch(saved)) _pendingToken = saved;
    if (kIsWeb) {
      final hashRoute = Uri.base.fragment;
      final hashToken = hashRoute.startsWith('/invite/')
          ? hashRoute.substring('/invite/'.length)
          : null;
      final token = hashToken != null && tokenPattern.hasMatch(hashToken)
          ? hashToken
          : tokenFromUri(Uri.base);
      if (token != null) await remember(token);
    } else {
      final links = AppLinks();
      _subscription = links.uriLinkStream.listen((uri) {
        final token = tokenFromUri(uri);
        if (token != null) unawaited(remember(token));
      });
      final initial = await links.getInitialLink();
      final token = initial == null ? null : tokenFromUri(initial);
      if (token != null) await remember(token);
    }
  }

  Future<void> remember(String token) async {
    if (!tokenPattern.hasMatch(token)) return;
    if (_pendingToken == token) return;
    _pendingToken = token;
    await _preferences.setString(_key, token);
    notifyListeners();
  }

  Future<void> clear() async {
    _pendingToken = null;
    await _preferences.remove(_key);
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
