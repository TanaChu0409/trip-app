import 'dart:convert';

/// Fail-closed: arbitrary strings and unknown fields never enter the log.
class DiagnosticSanitizer {
  final Map<String, String> _aliases = {};
  static const redacted = '[redacted]';
  static bool isJson(String? type) => {
        'application/json',
        'application/vnd.pgrst.object+json',
        'application/vnd.pgrst.array+json',
        'application/problem+json',
      }.contains(type?.split(';').first.trim().toLowerCase());
  static const _fields = {
    'id',
    'trip_id',
    'day_id',
    'stop_id',
    'user_id',
    'owner_id',
    'photo_id',
    'permission',
    'role',
    'status',
    'code',
    'is_archived',
    'is_highlight',
    'sort_order',
    'count',
    'type',
    'data',
    'error',
    'errors',
    'details',
    'message',
    'hint',
    'title',
    'name',
    'email',
    'note',
    'badge',
    'color',
    'storage_path',
    'signedURL',
    'signedUrl',
    'url',
    'map_url',
    'time_label',
    'created_at',
    'updated_at',
    'start_date',
    'end_date',
    'user',
    'session',
    'access_token',
    'p_stop',
    'p_stop_id',
    'p_day_id',
    'p_trip_id',
    'p_permission',
    'p_email',
    'refresh_token',
    'password',
    'token',
    'expires_in',
  };
  static const _enums = {
    'owner',
    'editor',
    'viewer',
    'guest',
    'success',
    'error',
    'ok',
    'already_member',
    'user_not_found',
    'self_invite',
    'invalid_permission',
  };
  static const _segments = {
    'auth',
    'v1',
    'rest',
    'storage',
    'object',
    'sign',
    'public',
    'upload',
    'token',
    'logout',
    'authorize',
    'user',
    'recover',
    'signup',
    'verify',
    'rpc',
    'trips',
    'trip_days',
    'days',
    'stops',
    'parking_spots',
    'shared_access',
    'profiles',
    'profiles_public',
    'stop_photos',
    'stop-photos',
    'invite_member_by_email',
    'join_trip_by_code',
    'update_trip_color',
    'remove_custom_stop_color',
    'remove_trip_custom_stop_color',
    'create_stop_with_palette',
    'update_stop_with_palette',
    'set_trip_archived',
    'set_owned_trip_archived',
    'diagnostics',
    'archived',
    'new',
    'edit',
    'navigation',
    'members',
  };

  String alias(String value) =>
      _aliases[value] ??
      (_aliases.length >= 4096 || value.length > 256
          ? '[id omitted]'
          : _aliases.putIfAbsent(value, () => 'ref-${_aliases.length + 1}'));

  void clear() => _aliases.clear();

  Object? body(Object? value, {String key = '', int depth = 0}) {
    if (depth > 8) return '[depth omitted]';
    if (key == 'id' || key.endsWith('_id')) {
      return value == null ? null : alias(value.toString());
    }
    // Only structural/numeric diagnostic values are retained. User content,
    // tokens, dates, coordinates, filenames and arbitrary server text are not.
    if (value is Map) {
      final result = <String, Object?>{};
      var unknown = 0;
      for (final entry in value.entries.take(100)) {
        final name = entry.key.toString();
        if (_fields.contains(name)) {
          result[name] = body(entry.value, key: name, depth: depth + 1);
        } else {
          result['omitted-field-${++unknown}'] = redacted;
        }
      }
      if (value.length > 100) result['truncated'] = true;
      return result;
    }
    if (value is List) {
      return {
        'count': value.length,
        'items': value.take(30).map((v) => body(v, depth: depth + 1)).toList(),
        'truncated': value.length > 30,
      };
    }
    if (value == null) return null;
    if (value is bool && {'is_archived', 'is_highlight'}.contains(key)) {
      return value;
    }
    if (value is num &&
        {'count', 'sort_order', 'expires_in', 'status'}.contains(key)) {
      return value;
    }
    if (value is String) {
      if ({'permission', 'p_permission', 'role', 'status', 'type'}
              .contains(key) &&
          _enums.contains(value)) {
        return value;
      }
      if (key == 'code' &&
          RegExp(r'^(?:[0-9]{5}|PGRST[0-9]{3})$').hasMatch(value)) {
        return value;
      }
    }
    return redacted;
  }

  String path(Uri uri) {
    try {
      return _path(uri);
    } catch (_) {
      return '/[path omitted]';
    }
  }

  String _path(Uri uri) {
    final parts = uri.pathSegments.map((s) {
      if (_segments.contains(s)) return s;
      // Route patterns contain placeholders, never concrete user IDs.
      if ({':tripId', ':dayId', ':stopId'}.contains(s)) return s;
      return alias(s);
    });
    // No hostname, userinfo, fragment or raw query value is retained.
    final query = <String, Object?>{};
    for (final entry in uri.queryParameters.entries) {
      if (_fields.contains(entry.key)) {
        final value = entry.value;
        if (entry.key.endsWith('_id') || entry.key == 'id') {
          query[entry.key] = value.startsWith('eq.')
              ? 'eq.${alias(value.substring(3))}'
              : '[filter omitted]';
        } else {
          query[entry.key] = body(value, key: entry.key);
        }
      } else {
        query['omitted-query-${query.length + 1}'] = redacted;
      }
    }
    return '/${parts.join('/')}${query.isEmpty ? '' : '?${jsonEncode(query)}'}';
  }

  Map<String, String> headers(Map<String, String> headers) {
    final result = <String, String>{};
    for (final entry in headers.entries) {
      final key = entry.key.toLowerCase();
      if (key == 'content-type') {
        final mime = entry.value.split(';').first.trim().toLowerCase();
        result[key] = {
          'application/json',
          'application/vnd.pgrst.object+json',
          'application/vnd.pgrst.array+json',
          'application/problem+json',
          'text/plain',
          'application/octet-stream',
          'multipart/form-data',
          'application/x-www-form-urlencoded',
          'image/jpeg',
          'image/png',
          'image/webp',
        }.contains(mime)
            ? mime
            : '[type omitted]';
      } else if (key == 'content-length' &&
          RegExp(r'^\d{1,12}$').hasMatch(entry.value)) {
        result[key] = entry.value;
      }
    }
    return result;
  }

  Map<String, Object?> error(Object error, StackTrace? stack) {
    var raw = '';
    try {
      raw = error.toString();
    } catch (_) {
      // A broken toString() must never replace the original application error.
    }
    final code = RegExp(r'\b(?:PGRST\d{3}|42501|23503|23505|40001|28000)\b')
        .firstMatch(raw)
        ?.group(0);
    // Source snippets, arguments and arbitrary error messages may contain PII.
    // Keep only validated package/file locations, without absolute paths.
    final frames = <String>[];
    if (stack != null) {
      for (final line in stack.toString().split('\n').take(40)) {
        final location = RegExp(
          r'(?:package:|dart:)([a-zA-Z0-9_/.-]+\.dart:\d+:\d+)',
        ).firstMatch(line);
        if (location != null) frames.add(location.group(0)!);
      }
    }
    final type = error.runtimeType.toString();
    return {
      'type': RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,79}$').hasMatch(type)
          ? type
          : 'Error',
      if (code != null) 'code': code,
      'category': _errorCategory(raw.toLowerCase()),
      'message': '[unstructured text omitted]',
      'stack': frames,
      'stackOmitted': stack != null && frames.isEmpty,
    };
  }

  String _errorCategory(String message) {
    const patterns = {
      'missing required environment variable': 'missing_configuration',
      'bucket not found': 'photo_service_missing',
      'object not found': 'photo_missing',
      'row-level security': 'permission_denied',
      'permission': 'permission_denied',
      'jwt': 'session_expired',
      'refresh token': 'session_expired',
      'socketexception': 'network_unavailable',
      'network': 'network_unavailable',
      'failed host lookup': 'network_unavailable',
      'timed out': 'timeout',
      'unsupported image': 'unsupported_image_format',
      'invalid image': 'invalid_image_data',
      'decode': 'invalid_image_data',
      'compression': 'image_conversion_failed',
    };
    for (final entry in patterns.entries) {
      if (message.contains(entry.key)) return entry.value;
    }
    return 'unclassified';
  }
}

/// Bounded transient capture. Only snapshot() results may enter the log.
class DiagnosticBody {
  static const limit = 8192;
  final List<int> _prefix = [];
  int _size = 0;
  bool complete = false;

  void add(List<int> bytes, {required bool capture}) {
    _size += bytes.length;
    if (capture) _prefix.addAll(bytes.take(limit - _prefix.length));
  }

  void discard() => _prefix.clear();

  Map<String, Object?> snapshot(DiagnosticSanitizer sanitizer, String? mime) {
    final result = <String, Object?>{
      'observedBytes': _size,
      'complete': complete,
      'truncated': _size > limit,
    };
    if (!complete ||
        _prefix.length != _size ||
        _size > limit ||
        !DiagnosticSanitizer.isJson(mime)) {
      result['omitted'] = true;
    } else if (_prefix.isNotEmpty) {
      try {
        final safe = sanitizer.body(jsonDecode(utf8.decode(_prefix)));
        if (utf8.encode(jsonEncode(safe)).length <= limit) {
          result['content'] = safe;
        } else {
          result['truncated'] = true;
          result['omitted'] = true;
        }
      } catch (_) {
        result['omitted'] = true;
      }
    }
    discard();
    return result;
  }
}
