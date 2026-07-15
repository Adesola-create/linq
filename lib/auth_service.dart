import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _baseUrl = 'https://api.linq.ng/api/v1';
  static const String _tokenExpiryKey = 'token_expiry';
  static const String _currentAccountEmailKey = 'current_account_email';
  static const String _pendingInterruptedRouteKey = 'pending_interrupted_route';

  // Registered with Google as the OAuth client's authorized redirect URI.
  // The Google auth WebView watches for navigation to this prefix and
  // intercepts it instead of letting it load, pulling `code`/`state` off
  // the URL itself rather than hitting this (GET, browser-facing) route.
  static const String googleCallbackUrlPrefix =
      'https://api.linq.ng/api/v1/auth/google/callback';

  static String? _cachedToken;
  static int? _cachedTokenExpiryMs;

  // Incremented every time a provider is successfully saved or unsaved.
  // Any widget that shows a bookmark icon listens to this and re-checks
  // its saved state so all cards stay in sync without a full page reload.
  static final ValueNotifier<int> savedProvidersVersion = ValueNotifier(0);

  // Total unread message count across all threads. Listened to by the
  // dashboard app bar badge. Call refreshUnreadMessageCount() to update.
  static final ValueNotifier<int> unreadMessageCount = ValueNotifier(0);

  // Total unread notification count. Listened to by the dashboard bell badge.
  static final ValueNotifier<int> unreadNotificationCount = ValueNotifier(0);

  static Future<void> refreshUnreadNotificationCount() async {
    try {
      final result = await getNotifications(limit: 50, offset: 0);
      if (result['success'] == true) {
        final raw = result['data'];
        final list = raw is List
            ? raw
            : raw is Map
                ? (raw['data'] is List
                    ? raw['data']
                    : raw['notifications'] is List
                        ? raw['notifications']
                        : <dynamic>[])
                : <dynamic>[];
        int count = 0;
        for (final item in list) {
          if (item is Map) {
            final readAt = item['read_at'] ?? item['readAt'];
            final isRead = item['is_read'] ?? item['read'];
            bool unread;
            if (readAt != null && readAt.toString().trim().isNotEmpty) {
              unread = false;
            } else if (isRead is bool) {
              unread = !isRead;
            } else if (isRead is num) {
              unread = isRead == 0;
            } else {
              unread = true;
            }
            if (unread) count++;
          }
        }
        unreadNotificationCount.value = count;
      }
    } catch (_) {}
  }

  static Future<void> markNotificationRead(String ulid) async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) return;
      await _sendWithAuthRetry(
        (headers) => http
            .post(
              Uri.parse('$_baseUrl/notifications/$ulid/read'),
              headers: headers,
            )
            .timeout(const Duration(seconds: 10)),
      );
    } catch (_) {}
  }

  static Future<void> markAllNotificationsRead() async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) return;
      await _sendWithAuthRetry(
        (headers) => http
            .post(
              Uri.parse('$_baseUrl/notifications/read-all'),
              headers: headers,
            )
            .timeout(const Duration(seconds: 10)),
      );
      unreadNotificationCount.value = 0;
    } catch (_) {}
  }

  static Future<void> refreshUnreadMessageCount() async {
    try {
      final result = await getThreads();
      if (result['success'] != true) return;
      final threads = result['data'] as List<dynamic>? ?? [];
      int total = 0;
      for (final t in threads) {
        if (t is Map) {
          final v = t['unread_count'] ?? t['unread_messages_count'] ?? 0;
          total += v is int ? v : int.tryParse(v.toString()) ?? 0;
        }
      }
      unreadMessageCount.value = total;
    } catch (_) {}
  }

  // Guards concurrent 401 handlers from racing to clear the session.
  static bool _sessionBeingCleared = false;

  // Set when the session has been invalidated and a redirect to /login is
  // already in flight. Cleared on the next successful login. Callers check
  // this before navigating so only the first handler ever navigates.
  static bool _redirectingToLogin = false;

  /// Returns true if a redirect to login is already in progress.
  /// Widgets should check this before calling Navigator.pushNamedAndRemoveUntil('/login').
  static bool get redirectingToLogin => _redirectingToLogin;

  /// Call immediately before navigating to login after an auth failure.
  /// Returns false if another handler already claimed the redirect — caller
  /// should skip navigation in that case.
  static bool claimLoginRedirect() {
    if (_redirectingToLogin) return false;
    _redirectingToLogin = true;
    return true;
  }

  /// Called by the login screen once the user has successfully authenticated,
  /// to allow future auth failures to redirect again.
  static void resetLoginRedirect() {
    _redirectingToLogin = false;
  }

  /// Step 1 of the Google OAuth flow: ask the backend for a Google
  /// authorisation URL (and a CSRF `state` cached server-side for 10 min).
  /// [role] pre-selects the persona to create/use; omit to let the
  /// callback step determine it.
  static Future<Map<String, dynamic>> getGoogleAuthUrl({String? role}) async {
    try {
      final uri = Uri.parse('$_baseUrl/auth/google').replace(
        queryParameters: (role != null && role.isNotEmpty)
            ? {'role': role}
            : null,
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final payload = _asStringKeyedMap(data['data']) ?? data;
        final redirectUrl =
            _toString(payload['redirect_url']) ??
            _toString(payload['url']) ??
            _toString(data['redirect_url']);
        if (redirectUrl == null || redirectUrl.isEmpty) {
          return {
            'success': false,
            'message': 'Unable to start Google sign-in. Please try again.',
          };
        }
        return {'success': true, 'redirect_url': redirectUrl};
      }

      final data = jsonDecode(res.body);
      return {
        'success': false,
        'message': _extractMessage(data) ?? 'Unable to start Google sign-in.',
      };
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to start Google sign-in. Please try again.',
      };
    }
  }

  /// Step 2 of the Google OAuth flow: exchange the authorisation `code`
  /// (and matching `state`) captured from Google's redirect for a LINQ
  /// session. Three outcomes are possible per the API: `authenticated`
  /// (session issued), `needs_phone` (new Google identity — phone number
  /// required to finish registration), `needs_role` (email matches
  /// multiple personas — role selection required).
  static Future<Map<String, dynamic>> completeGoogleAuth({
    required String code,
    required String state,
    String? role,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/auth/google/callback'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'code': code,
              'state': state,
              if (role != null && role.isNotEmpty) 'role': role,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode == 200 || res.statusCode == 201) {
        final status = _extractGoogleAuthStatus(data, res.body);
        if (status == 'needs_phone' || status == 'needs_role') {
          return {
            'success': false,
            'status': status,
            'message': status == 'needs_phone'
                ? 'A phone number is required to finish creating your account.'
                : 'This Google account is linked to more than one role. Please choose how to continue.',
          };
        }
        await _saveSession(data);
        return {
          'success': true,
          'status': 'authenticated',
          'role': _extractRole(data),
          'email': _extractEmail(data),
        };
      }

      return {
        'success': false,
        'message': _extractMessage(data) ?? 'Google sign-in failed. Please try again.',
      };
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Google sign-in failed. Please try again.',
      };
    }
  }

  /// The callback response's outcome field isn't documented by name, so
  /// check the common shapes first and fall back to scanning the raw body
  /// for the literal outcome strings the API docs specify.
  static String _extractGoogleAuthStatus(
    Map<String, dynamic> data,
    String rawBody,
  ) {
    final payload = _asStringKeyedMap(data['data']);
    for (final key in ['status', 'outcome', 'result', 'next_step', 'next']) {
      final value = _toString(data[key]) ?? _toString(payload?[key]);
      if (value != null && value.isNotEmpty) return value;
    }
    if (rawBody.contains('needs_phone')) return 'needs_phone';
    if (rawBody.contains('needs_role')) return 'needs_role';
    return 'authenticated';
  }

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final requestBody = jsonEncode({'email': email, 'password': password});

      final res = await http
          .post(
            Uri.parse('$_baseUrl/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: requestBody,
          )
          .timeout(const Duration(seconds: 15));


      final data = jsonDecode(res.body);

      if (res.statusCode == 200) {
        await _saveSession(data);
        return {'success': true, 'role': _extractRole(data), 'email': email};
      }

      final rawMessage = _extractMessage(data) ?? '';
      return {
        'success': false,
        'message': rawMessage.isNotEmpty
            ? rawMessage
            : _friendlyLoginError(res.statusCode),
      };
    } on SocketException catch (e) {
      return {
        'success': false,
        'message':
            'No internet connection. Please check your network and try again.',
      };
    } on HttpException catch (e) {
      return {
        'success': false,
        'message': 'Unable to reach the server. Please try again later.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Something went wrong. Please try again.',
      };
    }
  }

  static Future<Map<String, dynamic>> register({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String password,
    required String role,
  }) async {
    try {
      final requestBody = jsonEncode({
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'phone': phone,
        'password': password,
        'role': role == 'user' ? 'customer' : 'provider',
      });

      final res = await http
          .post(
            Uri.parse('$_baseUrl/auth/register'),
            headers: {'Content-Type': 'application/json'},
            body: requestBody,
          )
          .timeout(const Duration(seconds: 15));


      final data = jsonDecode(res.body);

      if (res.statusCode == 200 || res.statusCode == 201) {
        await _saveSession(data);
        return {'success': true, 'role': _extractRole(data) ?? role};
      }

      final rawMessage = _extractMessage(data) ?? '';
      return {
        'success': false,
        'message': _friendlyRegisterError(res.statusCode, data),
      };
    } on SocketException catch (e) {
      return {
        'success': false,
        'message':
            'No internet connection. Please check your network and try again.',
      };
    } on HttpException catch (e) {
      return {
        'success': false,
        'message': 'Unable to reach the server. Please try again later.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Something went wrong. Please try again.',
      };
    }
  }

  // POST /api/v1/auth/password/reset — initiate a password reset by email.
  static Future<Map<String, dynamic>> requestPasswordReset({
    required String email,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/auth/password/reset'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email}),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200 || res.statusCode == 201) {
        return {'success': true};
      }

      final data = jsonDecode(res.body);
      final rawMessage = _extractMessage(data) ?? '';
      return {
        'success': false,
        'message': rawMessage.isNotEmpty
            ? rawMessage
            : 'Failed to send reset instructions. Please try again.',
      };
    } on SocketException {
      return {
        'success': false,
        'message':
            'No internet connection. Please check your network and try again.',
      };
    } on HttpException {
      return {
        'success': false,
        'message': 'Unable to reach the server. Please try again later.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Something went wrong. Please try again.',
      };
    }
  }

  // POST /api/v1/auth/password/reset/confirm — confirm a password reset
  // using the token sent to the user's email, and set a new password.
  static Future<Map<String, dynamic>> confirmPasswordReset({
    required String token,
    required String password,
    required String passwordConfirmation,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/auth/password/reset/confirm'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'token': token,
              'password': password,
              'password_confirmation': passwordConfirmation,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200 || res.statusCode == 201) {
        return {'success': true};
      }

      final data = jsonDecode(res.body);
      final rawMessage = _extractMessage(data) ?? '';
      return {
        'success': false,
        'message': rawMessage.isNotEmpty
            ? rawMessage
            : 'Failed to reset password. The code may be invalid or expired.',
      };
    } on SocketException {
      return {
        'success': false,
        'message':
            'No internet connection. Please check your network and try again.',
      };
    } on HttpException {
      return {
        'success': false,
        'message': 'Unable to reach the server. Please try again later.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Something went wrong. Please try again.',
      };
    }
  }

  static String _friendlyLoginError(int statusCode) {
    switch (statusCode) {
      case 401:
        return 'Incorrect email or password. Please try again.';
      case 403:
        return 'Your account has been suspended. Please contact support.';
      case 404:
        return 'No account found with this email. Please sign up.';
      case 429:
        return 'Too many attempts. Please wait a moment and try again.';
      case 500:
      case 502:
      case 503:
        return 'server is currently unavailable. Please try again later.';
      default:
        return 'Login failed. Please check your details and try again.';
    }
  }

  static String _friendlyRegisterError(
    int statusCode,
    Map<String, dynamic> data,
  ) {
    if (statusCode == 422) {
      // Extract validation details and convert to friendly messages
      final error =
          (data['error'] is Map ? data['error'] : null)
              as Map<String, dynamic>?;
      final details =
          (error?['details'] is Map ? error!['details'] : null)
              as Map<String, dynamic>?;
      if (details != null) {
        final messages = <String>[];
        details.forEach((field, errors) {
          if (errors is List && errors.isNotEmpty) {
            final raw = errors.first.toString();
            // If backend indicates email already exists, surface that clearly
            if (field == 'email' &&
                (raw.toLowerCase().contains('exist') ||
                    raw.toLowerCase().contains('already') ||
                    raw.toLowerCase().contains('taken') ||
                    raw.toLowerCase().contains('in use'))) {
              messages.add('That email address is already in use.');
            } else {
              messages.add(_friendlyFieldError(field, raw));
            }
          }
        });
        if (messages.isNotEmpty) return messages.join('\n');
      }
      final extracted = _extractMessage(data);
      return extracted ?? 'Please check your details and try again.';
    }
    switch (statusCode) {
      case 409:
        return 'An account with this email already exists. Please log in instead.';
      case 429:
        return 'Too many attempts. Please wait a moment and try again.';
      case 500:
      case 502:
      case 503:
        return 'Our servers are currently unavailable. Please try again later.';
      default:
        return 'Registration failed. Please check your details and try again.';
    }
  }

  static String _friendlyFieldError(String field, String rawError) {
    final raw = rawError.toLowerCase();
    switch (field) {
      case 'email':
        if (raw.contains('exist') ||
            raw.contains('already') ||
            raw.contains('taken') ||
            raw.contains('in use')) {
          return 'An account with this email already exists. Please log in.';
        }
        if (raw.contains('valid') ||
            raw.contains('format') ||
            raw.contains('invalid')) {
          return 'Please enter a valid email address.';
        }
        return 'Please enter a valid email address.';
      case 'password':
        return 'Password must be at least 10 characters with uppercase and lowercase letters.';
      case 'phone':
        return 'Please enter a valid phone number.';
      case 'first_name':
        return 'Please enter your first name.';
      case 'last_name':
        return 'Please enter your last name.';
      case 'role':
        return 'Please select a valid role (User or Service Provider).';
      default:
        return 'Please check your $field and try again.';
    }
  }

  static Future<void> _saveSession(Map<String, dynamic> data) async {
    // Clear any pending login-redirect claim so auth failures after a fresh
    // login can redirect again if needed.
    _redirectingToLogin = false;
    final prefs = await SharedPreferences.getInstance();

    if (data['data'] is Map) {
    }

    final payload = _asStringKeyedMap(data['data']);
    final user =
        _asStringKeyedMap(payload?['user']) ?? _asStringKeyedMap(data['user']);

    final token = _extractToken(data);
    final refreshToken = _extractRefreshToken(data);

    final role =
        _toString(user?['role']) ??
        _toString(payload?['role']) ??
        _toString(data['role']);
    final email =
        _extractEmail(data) ?? _extractEmail(payload) ?? _extractEmail(user);


    if (token != null && token.isNotEmpty) {
      final trimmedToken = _normalizeToken(token);
      if (trimmedToken.isNotEmpty) {
        await prefs.setString('token', trimmedToken);
        _cachedToken = trimmedToken;

        final expiresAt = _extractTokenExpiry(trimmedToken);
        if (expiresAt != null) {
          await prefs.setInt(_tokenExpiryKey, expiresAt.millisecondsSinceEpoch);
          _cachedTokenExpiryMs = expiresAt.millisecondsSinceEpoch;
        } else {
          await prefs.remove(_tokenExpiryKey);
          _cachedTokenExpiryMs = null;
        }
      } else {
        await prefs.remove('token');
        _cachedToken = null;
        _cachedTokenExpiryMs = null;
      }
    } else {
      await prefs.remove('token');
      _cachedToken = null;
      _cachedTokenExpiryMs = null;
    }

    if (refreshToken != null && refreshToken.isNotEmpty) {
      final trimmedRefreshToken = _normalizeToken(refreshToken);
      if (trimmedRefreshToken.isNotEmpty) {
        await prefs.setString('refresh_token', trimmedRefreshToken);
      }
    } else {
      final existingRefresh = prefs.getString('refresh_token');
      if (existingRefresh != null && existingRefresh.trim().isNotEmpty) {
      } else {
      }
    }

    if (role != null && role.isNotEmpty) {
      final normalizedRole = role.trim();
      await prefs.setString('role', normalizedRole);
      final normalizedEmail = _normalizeEmail(email);
      if (normalizedEmail != null) {
        await prefs.setString(_currentAccountEmailKey, normalizedEmail);
        final lastModeKey = _lastAccountModeKeyForEmail(normalizedEmail);
        await prefs.setString(lastModeKey, normalizedRole);
      } else {
        final existingLastMode = prefs.getString(_lastAccountModeKey);
        if (existingLastMode == null || existingLastMode.trim().isEmpty) {
          await prefs.setString(_lastAccountModeKey, normalizedRole);
        }
      }
    } else {
      await prefs.remove('role');
    }

    final profileSource =
        payload ??
        user ??
        ((data['user'] is Map)
            ? (data['user'] as Map<String, dynamic>)
            : null) ??
        ((data['profile'] is Map)
            ? (data['profile'] as Map<String, dynamic>)
            : null);

    if (profileSource != null) {
      try {
        await prefs.setString('profile', jsonEncode(profileSource));
      } catch (e) {
      }
    }
  }

  static String? _toString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    return null;
  }

  static Map<String, dynamic>? _asStringKeyedMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  static String _normalizeToken(String token) {
    var normalized = token.trim();
    while ((normalized.startsWith('"') && normalized.endsWith('"')) ||
        (normalized.startsWith("'") && normalized.endsWith("'"))) {
      normalized = normalized.substring(1, normalized.length - 1).trim();
    }
    while (normalized.toLowerCase().startsWith('bearer ')) {
      normalized = normalized.substring(7).trim();
    }
    return normalized;
  }

  static String? _extractToken(Map<String, dynamic> data) {
    const tokenKeys = {
      'token',
      'accessToken',
      'access_token',
      'authToken',
      'auth_token',
      'jwt',
    };

    String? search(dynamic value) {
      final map = _asStringKeyedMap(value);
      if (map != null) {
        for (final key in tokenKeys) {
          final text = _toString(map[key]);
          if (text != null && text.trim().isNotEmpty) {
            return text;
          }
        }

        for (final entry in map.entries) {
          if (entry.value is Map || entry.value is List) {
            final found = search(entry.value);
            if (found != null) return found;
          }
        }
      }

      if (value is List) {
        for (final item in value) {
          final found = search(item);
          if (found != null) return found;
        }
      }

      return null;
    }

    final token = search(data);
    return token == null ? null : _normalizeToken(token);
  }

  static String? _extractRefreshToken(Map<String, dynamic> data) {
    const refreshTokenKeys = {
      'refreshToken',
      'refresh_token',
      'refresh',
      'refreshJwt',
      'refresh_jwt',
    };

    String? search(dynamic value) {
      final map = _asStringKeyedMap(value);
      if (map != null) {
        for (final key in refreshTokenKeys) {
          final text = _toString(map[key]);
          if (text != null && text.trim().isNotEmpty) {
            return text;
          }
        }
        for (final entry in map.entries) {
          if (entry.value is Map || entry.value is List) {
            final found = search(entry.value);
            if (found != null) return found;
          }
        }
      }

      if (value is List) {
        for (final item in value) {
          final found = search(item);
          if (found != null) return found;
        }
      }

      return null;
    }

    final token = search(data);
    return token == null ? null : _normalizeToken(token);
  }

  static String? _extractRole(Map<String, dynamic> data) {
    final payload =
        (data['data'] is Map ? data['data'] : null) as Map<String, dynamic>?;
    final user =
        (payload?['user'] is Map ? payload!['user'] : null)
            as Map<String, dynamic>?;
    return _toString(user?['role']) ??
        _toString(payload?['role']) ??
        _toString(data['role']) ??
        _toString(data['userRole']) ??
        _toString(data['user_role']) ??
        _toString(data['type']);
  }

  static String? _extractMessage(Map<String, dynamic> data) {
    final payload =
        (data['data'] is Map ? data['data'] : null) as Map<String, dynamic>?;
    final error =
        (data['error'] is Map ? data['error'] : null) as Map<String, dynamic>?;

    Map<String, dynamic>? details;
    if (error?['details'] is Map) {
      details = error!['details'] as Map<String, dynamic>?;
    } else if (payload?['details'] is Map) {
      details = payload!['details'] as Map<String, dynamic>?;
    } else if (data['details'] is Map) {
      details = data['details'] as Map<String, dynamic>?;
    }

    if (details != null && details.isNotEmpty) {
      final detailMessages = <String>[];
      for (final entry in details.entries) {
        final values = <String>[];
        final value = entry.value;
        if (value is String) {
          values.add(value);
        } else if (value is List) {
          values.addAll(
            value
                .map((item) => _toString(item))
                .where((text) => text != null && text.isNotEmpty)
                .cast<String>(),
          );
        } else if (value != null) {
          final text = _toString(value);
          if (text != null && text.isNotEmpty) values.add(text);
        }
        if (values.isNotEmpty) {
          final fieldName = entry.key.toString().replaceAll('_', ' ');
          detailMessages.add('$fieldName: ${values.join(', ')}.');
        }
      }
      if (detailMessages.isNotEmpty) {
        return detailMessages.join(' ');
      }
    }

    return _toString(error?['message']) ??
        _toString(data['message']) ??
        _toString(payload?['message']) ??
        _toString(data['msg']);
  }

  static Future<void> clearJobsCache() => _clearCache('customer_jobs');

  static Future<Map<String, dynamic>> getJobDetails(String ulid) async {
    try {
      final res = await _sendWithAuthRetry(
        (headers) => http
            .get(Uri.parse('$_baseUrl/jobs/$ulid'), headers: headers)
            .timeout(const Duration(seconds: 15)),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final job =
            (data['data'] is Map ? data['data'] : null) ??
            (data['job'] is Map ? data['job'] : null) ??
            data;
        return {'success': true, 'data': job};
      }
      return {'success': false, 'message': 'Failed to load job details.'};
    } catch (e) {
      return {'success': false, 'message': 'Unable to load job details.'};
    }
  }

  static Future<void> logout() async {
    await _clearStoredSession();
  }

  // ── ROLE SWITCHING ─────────────────────────────────────────

  /// Switch to a different role for the authenticated user
  /// Calls backend endpoint to authorize the role switch
  /// Updates local active role on success
  static Future<Map<String, dynamic>> switchRole(String newRole) async {
    try {
      // Ensure we have a valid access token, attempt refresh if possible
      final token = await getToken();
      final refreshToken = await _getRefreshToken();

      if (token == null || token.isEmpty) {
        // Try to refresh using refresh token if available
        if (refreshToken != null && refreshToken.isNotEmpty) {
          final refreshed = await _refreshAccessToken();
          if (!refreshed) {
            return {
              'success': false,
              'message': 'Authentication required. Please log in again.',
            };
          }
        } else {
          return {
            'success': false,
            'message': 'Authentication required. Please log in again.',
          };
        }
      }

      final headers = await _getAuthHeaders();
      final requestBody = jsonEncode({'role': newRole});


      final res = await _sendWithAuthRetry(
        (headers) => http
            .post(
              Uri.parse('$_baseUrl/auth/switch-role'),
              headers: headers,
              body: requestBody,
            )
            .timeout(const Duration(seconds: 15)),
      );


      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);

        // Update local active role
        await setActiveRole(newRole);

        // Update profile cache if returned in response
        if (data['data'] is Map || data['user'] is Map) {
          await _saveSession(data);
        }

        return {
          'success': true,
          'statusCode': res.statusCode,
          'message': 'Role switched successfully',
          'role': newRole,
          'data': data,
        };
      }

      if (res.statusCode == 401) {
        await _clearStoredSession();
        return {
          'success': false,
          'statusCode': res.statusCode,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final data = jsonDecode(res.body);
      final msg = _extractMessage(data) ?? 'Failed to switch role.';
      return {
        'success': false,
        'statusCode': res.statusCode,
        'message': msg,
        'data': data,
      };
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Unable to switch role.'};
    }
  }

  /// Get the currently active role (user's current operating role)
  /// Returns the role the user is currently operating as
  static const String _activeRoleKey = 'active_role';
  static const String _lastAccountModeKey = 'last_account_mode';

  static String _lastAccountModeKeyForEmail(String email) =>
      '${_lastAccountModeKey}_${email.trim().toLowerCase()}';

  static String? _normalizeEmail(String? email) {
    final value = email?.trim().toLowerCase();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  static String? _extractEmail(Map<String, dynamic>? data) {
    if (data == null) return null;
    final payload =
        (data['data'] is Map ? data['data'] : null) as Map<String, dynamic>?;
    final user =
        (payload?['user'] is Map ? payload!['user'] : null)
            as Map<String, dynamic>?;
    return _toString(user?['email']) ??
        _toString(payload?['email']) ??
        _toString(data['email']) ??
        _toString(data['user_email']);
  }

  static Future<String?> getCurrentAccountEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return _normalizeEmail(prefs.getString(_currentAccountEmailKey));
  }

  static Future<String?> getActiveRole() async {
    final prefs = await SharedPreferences.getInstance();
    final activeRole = prefs.getString(_activeRoleKey);
    if (activeRole == null || activeRole.trim().isEmpty) {
      // Fallback to stored role if active_role not set
      return await getRole();
    }
    return activeRole.trim();
  }

  static Future<String?> getLastAccountMode({String? email}) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedEmail = _normalizeEmail(email);
    if (normalizedEmail != null) {
      final scoped = prefs.getString(
        _lastAccountModeKeyForEmail(normalizedEmail),
      );
      if (scoped != null && scoped.trim().isNotEmpty) {
        return scoped.trim();
      }
    }

    final lastMode = prefs.getString(_lastAccountModeKey);
    if (lastMode == null || lastMode.trim().isEmpty) {
      return null;
    }
    return lastMode.trim();
  }

  /// Ensures the stored token is scoped to [role]. Calls switchRole if needed.
  static Future<bool> ensureRole(String role) async {
    final current = await getActiveRole();
    if (current?.toLowerCase() == role.toLowerCase()) return true;
    final result = await switchRole(role);
    return result['success'] == true;
  }

  /// Set the active role (used after successful role switch)
  static Future<void> setActiveRole(String role, {String? email}) async {
    final prefs = await SharedPreferences.getInstance();
    if (role.isNotEmpty) {
      final normalized = role.trim();
      await prefs.setString(_activeRoleKey, normalized);
      final normalizedEmail =
          _normalizeEmail(email) ?? await getCurrentAccountEmail();
      if (normalizedEmail != null) {
        await prefs.setString(_currentAccountEmailKey, normalizedEmail);
        await prefs.setString(
          _lastAccountModeKeyForEmail(normalizedEmail),
          normalized,
        );
      } else {
        await prefs.setString(_lastAccountModeKey, normalized);
      }
    } else {
      await prefs.remove(_activeRoleKey);
    }
  }

  /// Get all available roles for the user
  /// (Currently returns stored role, but can be enhanced with backend data)
  static Future<List<String>> getAvailableRoles() async {
    final role = await getRole();
    if (role != null && role.isNotEmpty) {
      // For now, return single role, but can be enhanced when backend provides multiple roles
      return [role];
    }
    return [];
  }

  static const String _profileSetupCompleteKey = 'profile_setup_complete';

  static Future<void> markProfileSetupComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_profileSetupCompleteKey, true);
  }

  static Future<bool> hasCompletedProfileSetup() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_profileSetupCompleteKey) == true;
  }

  static Future<void> _clearStoredSession() async {
    // Prevent concurrent 401 handlers from each clearing and redirecting.
    if (_sessionBeingCleared) return;
    _sessionBeingCleared = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
      await prefs.remove('refresh_token');
      await prefs.remove(_tokenExpiryKey);
      await prefs.remove('role');
      await prefs.remove('active_role');
      await prefs.remove('profile');
      await prefs.remove(_currentAccountEmailKey);
      await prefs.remove('user_lat');
      await prefs.remove(_pendingInterruptedRouteKey);
      await prefs.remove('user_lng');
      await prefs.remove('pending_customer_job_draft');
      await prefs.remove('pending_provider_setup');
      _cachedToken = null;
      _cachedTokenExpiryMs = null;
    } finally {
      _sessionBeingCleared = false;
    }
  }

  // Expose whether a logout is in progress so callers can skip redundant
  // navigation to the login screen.
  static bool get isSessionBeingCleared => _sessionBeingCleared;

  static Future<void> savePendingInterruptedRoute(
    String route, {
    String? reason,
    Map<String, dynamic>? payload,
    String? email,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final normalizedEmail =
          _normalizeEmail(email) ?? await getCurrentAccountEmail();
      final data = <String, dynamic>{
        'route': route,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
        if (payload != null && payload.isNotEmpty) 'payload': payload,
        if (normalizedEmail != null) 'account_email': normalizedEmail,
        'saved_at': DateTime.now().toIso8601String(),
      };
      await prefs.setString(_pendingInterruptedRouteKey, jsonEncode(data));
    } catch (e) {
    }
  }

  static Future<Map<String, dynamic>?> getPendingInterruptedRoute({
    String? email,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_pendingInterruptedRouteKey);
      if (cached == null || cached.isEmpty) return null;

      final data = jsonDecode(cached);
      if (data is! Map<String, dynamic>) return null;

      final storedEmail = _normalizeEmail(data['account_email']?.toString());
      final normalizedEmail = _normalizeEmail(email);
      if (storedEmail != null &&
          normalizedEmail != null &&
          storedEmail != normalizedEmail) {
        return null;
      }

      return data;
    } catch (e) {
      return null;
    }
  }

  static Future<void> clearPendingInterruptedRoute() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingInterruptedRouteKey);
    } catch (e) {
    }
  }
  // ── PENDING FORM STATE MANAGEMENT ──────────────────────────────────────

  /// Cache provider setup form data to restore after re-login on auth failure
  static Future<void> savePendingProviderSetup(
    Map<String, dynamic> formData,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final normalizedEmail = await getCurrentAccountEmail();
      final payload = <String, dynamic>{
        'account_email': normalizedEmail,
        'payload': formData,
      };
      await prefs.setString('pending_provider_setup', jsonEncode(payload));
      await savePendingInterruptedRoute(
        '/provider-setup',
        reason: 'provider_setup',
        payload: formData,
        email: normalizedEmail,
      );
    } catch (e) {
    }
  }

  /// Retrieve cached provider setup form data (e.g., after re-login)
  static Future<Map<String, dynamic>?> getPendingProviderSetup({
    String? email,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('pending_provider_setup');
      if (cached != null) {
        final data = jsonDecode(cached);
        if (data is Map<String, dynamic>) {
          final storedEmail = _normalizeEmail(
            data['account_email']?.toString(),
          );
          final normalizedEmail = _normalizeEmail(email);
          if (storedEmail != null &&
              normalizedEmail != null &&
              storedEmail != normalizedEmail) {
            return null;
          }

          final payload = data['payload'];
          if (payload is Map<String, dynamic>) {
            return payload;
          }
          return data;
        }
      }
    } catch (e) {
    }
    return null;
  }

  /// Clear cached provider setup form data (after successful submission)
  static Future<void> clearPendingProviderSetup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pending_provider_setup');
      await clearPendingInterruptedRoute();
    } catch (e) {
    }
  }

  static const String _pendingCustomerJobDraftKey =
      'pending_customer_job_draft';

  static Future<void> savePendingCustomerJobDraft(
    Map<String, dynamic> draft,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final normalizedEmail = await getCurrentAccountEmail();
      final payload = <String, dynamic>{
        'account_email': normalizedEmail,
        'draft': draft,
      };
      await prefs.setString(_pendingCustomerJobDraftKey, jsonEncode(payload));
      await savePendingInterruptedRoute(
        '/customer-dashboard',
        reason: 'customer_job_draft',
        payload: draft,
        email: normalizedEmail,
      );
    } catch (e) {
    }
  }

  static Future<Map<String, dynamic>?> getPendingCustomerJobDraft({
    String? email,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_pendingCustomerJobDraftKey);
      if (cached != null && cached.isNotEmpty) {
        final data = jsonDecode(cached);
        if (data is Map<String, dynamic>) {
          final storedEmail = _normalizeEmail(
            data['account_email']?.toString(),
          );
          final normalizedEmail = _normalizeEmail(email);
          if (storedEmail != null &&
              normalizedEmail != null &&
              storedEmail != normalizedEmail) {
            return null;
          }

          final draft = data['draft'];
          if (draft is Map<String, dynamic>) {
            return draft;
          }
          return data;
        }
      }
    } catch (e) {
    }
    return null;
  }

  static Future<void> clearPendingCustomerJobDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingCustomerJobDraftKey);
      await clearPendingInterruptedRoute();
    } catch (e) {
    }
  }

  static Future<Map<String, dynamic>?> getCachedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('profile');
    if (cached == null) return null;
    try {
      return jsonDecode(cached) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> getProfile({
    bool forceRefresh = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = await getToken();

      if (!forceRefresh) {
        final cached = prefs.getString('profile');
        if (cached != null) {
          return {
            'success': true,
            'data': jsonDecode(cached),
            'fromCache': true,
          };
        }
      }

      if (token == null || token.isEmpty) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final res = await _sendWithAuthRetry(
        (headers) => http
            .get(Uri.parse('$_baseUrl/me'), headers: headers)
            .timeout(const Duration(seconds: 15)),
      );
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        Map<String, dynamic> savedProfile = decoded;
        if (prefs.getString('profile') != null) {
          try {
            final cached =
                jsonDecode(prefs.getString('profile')!) as Map<String, dynamic>;
            savedProfile = _mergeProfileCache(cached, decoded, {});
          } catch (_) {
            savedProfile = decoded;
          }
        }
        // Apply reverse mapping to API response for consistent UI field names
        final source = _extractProfileSource(savedProfile);
        if (source.isNotEmpty) {
          final mapped = _mapApiResponseToUi(source);
          final extractedUser = savedProfile['user'] is Map<String, dynamic>
              ? (savedProfile['user'] as Map<String, dynamic>)
              : savedProfile;
          extractedUser.addAll(mapped);
        }
        await prefs.setString('profile', jsonEncode(savedProfile));
        return {'success': true, 'data': savedProfile};
      }
      if (res.statusCode == 401) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }
      final data = jsonDecode(res.body);
      return {
        'success': false,
        'message': _extractMessage(data) ?? 'Failed to load profile.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Unable to load profile.'};
    }
  }

  static Future<Map<String, dynamic>> getProviderAccountProfile({
    bool forceRefresh = false,
  }) async {
    const cacheKey = 'provider_account_profile';
    try {
      if (!forceRefresh) {
        final cached = await _readCache(cacheKey);
        if (cached is Map<String, dynamic>) {
          final normalized = Map<String, dynamic>.from(cached);
          normalized.addAll(_mapApiResponseToUi(_extractProfileSource(cached)));
          return {'success': true, 'data': normalized, 'fromCache': true};
        }
      }

      final token = await getToken();
      if (token == null || token.isEmpty) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final res = await _sendWithAuthRetry(
        (headers) => http
            .get(Uri.parse('$_baseUrl/provider/profile'), headers: headers)
            .timeout(const Duration(seconds: 15)),
      );


      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final Map<String, dynamic> raw =
            (data['data'] is Map<String, dynamic>
                ? data['data'] as Map<String, dynamic>
                : null) ??
            (data['provider'] is Map<String, dynamic>
                ? data['provider'] as Map<String, dynamic>
                : null) ??
            (data is Map<String, dynamic> ? data : {});

        final normalized = Map<String, dynamic>.from(raw);
        normalized.addAll(_mapApiResponseToUi(raw));
        await _saveCache(cacheKey, normalized);
        return {'success': true, 'data': normalized};
      }

      if (res.statusCode == 401) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      if (res.statusCode == 404) {
        return {
          'success': false,
          'statusCode': 404,
          'message': 'Provider profile not found.',
        };
      }

      final data = jsonDecode(res.body);
      return {
        'success': false,
        'message':
            _extractMessage(data) ?? 'Failed to load provider account profile.',
      };
    } on SocketException {
      final cached = await _readCache(cacheKey);
      if (cached is Map<String, dynamic>) {
        return {'success': true, 'data': cached, 'fromCache': true};
      }
      return {'success': false, 'message': 'No internet connection.'};
    } catch (e) {
      final cached = await _readCache(cacheKey);
      if (cached is Map<String, dynamic>) {
        final normalized = Map<String, dynamic>.from(cached);
        normalized.addAll(_mapApiResponseToUi(_extractProfileSource(cached)));
        return {'success': true, 'data': normalized, 'fromCache': true};
      }
      return {
        'success': false,
        'message': 'Unable to load provider account profile.',
      };
    }
  }

  static String _cacheKey(String name) => 'linq_cache_$name';

  static Future<void> saveProviderImages(
    String ulid,
    Map<String, dynamic> providerData,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'provider_images_$ulid';
      final cacheTs = 'provider_images_ts_$ulid';
      await prefs.setString(
        cacheKey,
        jsonEncode({
          'image': providerData['image'] ?? '',
          'gallery': providerData['gallery_photos'] ?? [],
          'cached_at': DateTime.now().millisecondsSinceEpoch,
        }),
      );
      await prefs.setInt(cacheTs, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
    }
  }

  static Future<Map<String, dynamic>?> getProviderImages(String ulid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'provider_images_$ulid';
      final cached = prefs.getString(cacheKey);
      if (cached != null) {
        return jsonDecode(cached) as Map<String, dynamic>;
      }
    } catch (e) {
    }
    return null;
  }

  static bool hasProviderAccountProfileData(Map<String, dynamic>? profile) {
    if (profile == null || profile.isEmpty) return false;

    final source = _extractProfileSource(profile);
    final candidateFields = [
      'business_name',
      'provider_name',
      'company_name',
      'name',
      'display_name',
      'full_name',
      'profile_name',
      'profile_display_name',
    ];

    for (final field in candidateFields) {
      final value = source[field] ?? profile[field];
      if (value != null && value.toString().trim().isNotEmpty) {
        return true;
      }
    }

    final bio = (source['bio'] ?? source['description'] ?? source['about'])
        ?.toString()
        .trim();
    if (bio?.isNotEmpty == true) return true;

    final services =
        source['services'] ??
        source['service_categories'] ??
        source['category_slugs'] ??
        source['categories'];
    if (services is List && services.isNotEmpty) return true;

    final location =
        (source['location'] ??
                source['address'] ??
                source['workshop_address'] ??
                source['workshop_location'])
            ?.toString()
            .trim();
    if (location?.isNotEmpty == true) return true;

    return false;
  }

  static Future<void> saveProvidersList(
    List<Map<String, dynamic>> providers,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'cached_providers_full',
        jsonEncode({
          'data': providers,
          'cached_at': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    } catch (e) {
    }
  }

  static Future<List<Map<String, dynamic>>?> getProvidersList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_providers_full');
      if (cached != null) {
        final data = jsonDecode(cached) as Map<String, dynamic>;
        final providers = data['data'] as List<dynamic>?;
        if (providers != null) {
          return providers.cast<Map<String, dynamic>>();
        }
      }
    } catch (e) {
    }
    return null;
  }

  static Future<void> _saveCache(String key, dynamic data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey(key), jsonEncode(data));
  }

  static Future<void> _clearCache(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey(key));
  }

  static Future<dynamic> _readCache(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey(key));
    if (cached == null) return null;
    try {
      return jsonDecode(cached);
    } catch (_) {
      return null;
    }
  }

  static List<dynamic> _filterProvidersByCategory(
    List<dynamic> providers,
    String subcategoryId,
  ) {
    if (subcategoryId.trim().isEmpty) return providers;
    final match = subcategoryId.trim().toLowerCase();
    return providers.where((provider) {
      final rawCategories = provider['categories'];
      if (rawCategories is List) {
        for (final category in rawCategories) {
          if (category is Map<String, dynamic>) {
            final values = [
              category['ulid'],
              category['id'],
              category['_id'],
              category['slug'],
              category['category_id'],
              category['name'],
              category['title'],
              category['label'],
            ];
            for (final value in values) {
              if (value != null && value.toString().toLowerCase() == match) {
                return true;
              }
            }
          } else if (category is String && category.toLowerCase() == match) {
            return true;
          }
        }
      }
      return false;
    }).toList();
  }

  static Future<Map<String, dynamic>> getCustomerJobs({
    bool forceRefresh = false,
  }) async {
    const cacheKey = 'customer_jobs';
    try {
      if (!forceRefresh) {
        final cached = await _readCache(cacheKey);
        if (cached is List) {
          return {'success': true, 'data': cached, 'fromCache': true};
        }
      }

      Future<http.Response> makeRequest() => _sendWithAuthRetry(
        (headers) => http
            .get(
              Uri.parse('$_baseUrl/customer/jobs').replace(
                queryParameters: {'per_page': '50'},
              ),
              headers: headers,
            )
            .timeout(const Duration(seconds: 15)),
      );

      var res = await makeRequest();

      // Token may be provider-scoped — switch to customer and retry once on 403
      if (res.statusCode == 403) {
        final switched = await switchRole('customer');
        if (switched['success'] == true) {
          res = await makeRequest();
        }
      }


      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic> raw =
            (data is List ? data : null) ??
            (data['data'] is List ? data['data'] : null) ??
            (data['jobs'] is List ? data['jobs'] : null) ??
            [];
        await _saveCache(cacheKey, raw);
        return {'success': true, 'data': raw};
      }

      if (res.statusCode == 401) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final data = jsonDecode(res.body);
      return {
        'success': false,
        'message': _extractMessage(data) ?? 'Failed to load jobs.',
      };
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Unable to load jobs.'};
    }
  }

  static Future<Map<String, dynamic>> getCustomerSavedProviders({
    bool forceRefresh = false,
  }) async {
    const cacheKey = 'customer_saved_providers';
    try {
      if (!forceRefresh) {
        final cached = await _readCache(cacheKey);
        if (cached is List) {
          return {'success': true, 'data': cached, 'fromCache': true};
        }
      }

      Future<http.Response> makeRequest() => _sendWithAuthRetry(
        (headers) => http
            .get(
              Uri.parse('$_baseUrl/customer/saved-providers'),
              headers: headers,
            )
            .timeout(const Duration(seconds: 15)),
      );

      var res = await makeRequest();

      if (res.statusCode == 403) {
        final switched = await switchRole('customer');
        if (switched['success'] == true) {
          res = await makeRequest();
        }
      }


      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic> raw =
            (data is List ? data : null) ??
            (data['data'] is List ? data['data'] : null) ??
            (data['providers'] is List ? data['providers'] : null) ??
            [];
        await _saveCache(cacheKey, raw);
        return {'success': true, 'data': raw};
      }

      if (res.statusCode == 401) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final data = jsonDecode(res.body);
      return {
        'success': false,
        'message': _extractMessage(data) ?? 'Failed to load saved providers.',
      };
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Unable to load saved providers.'};
    }
  }

  /// Save a provider. POST /customer/saved-providers/{ulid}
  static Future<Map<String, dynamic>> saveProvider(String ulid) async {
    try {
      await switchRole('customer');
      final res = await _sendWithAuthRetry(
        (headers) => http
            .post(
              Uri.parse('$_baseUrl/customer/saved-providers/$ulid'),
              headers: headers,
            )
            .timeout(const Duration(seconds: 20)),
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        await _clearCache('customer_saved_providers');
        savedProvidersVersion.value++;
        return {'success': true, 'saved': true};
      }
      if (res.statusCode == 401) return {'success': false, 'auth_required': true};
      final data = jsonDecode(res.body);
      return {'success': false, 'message': _extractMessage(data) ?? 'Failed to save provider.'};
    } on SocketException {
      return {'success': false, 'message': 'No internet connection.'};
    } catch (e) {
      return {'success': false, 'message': 'Request timed out. Please try again.'};
    }
  }

  /// Unsave / delete a provider. DELETE /customer/saved-providers/{ulid}
  static Future<Map<String, dynamic>> unsaveProvider(String ulid) async {
    try {
      await switchRole('customer');
      final res = await _sendWithAuthRetry(
        (headers) => http
            .delete(
              Uri.parse('$_baseUrl/customer/saved-providers/$ulid'),
              headers: headers,
            )
            .timeout(const Duration(seconds: 20)),
      );

      if (res.statusCode == 200 || res.statusCode == 204) {
        await _clearCache('customer_saved_providers');
        savedProvidersVersion.value++;
        return {'success': true, 'saved': false};
      }
      if (res.statusCode == 401) return {'success': false, 'auth_required': true};
      if (res.statusCode == 404) return {'success': false, 'message': 'Provider was not in your saved list.'};
      final data = jsonDecode(res.body);
      return {'success': false, 'message': _extractMessage(data) ?? 'Failed to unsave provider.'};
    } on SocketException {
      return {'success': false, 'message': 'No internet connection.'};
    } catch (e) {
      return {'success': false, 'message': 'Request timed out. Please try again.'};
    }
  }

  // Legacy alias — callers that don't know the current state should migrate
  // to explicit saveProvider / unsaveProvider calls.
  static Future<Map<String, dynamic>> toggleSaveProvider(String ulid) =>
      saveProvider(ulid);

  static Future<bool> isProviderSaved(String ulid) async {
    if (ulid.isEmpty) return false;
    final cached = await _readCache('customer_saved_providers');
    if (cached is! List) return false;
    return cached.any((item) {
      if (item is! Map) return false;
      final p = item['provider'] is Map ? item['provider'] as Map : item;
      return (p['ulid'] ?? p['id'] ?? '').toString() == ulid;
    });
  }

  static Future<void> saveCustomerJob(Map<String, dynamic> jobData) async {
    const cacheKey = 'customer_jobs';
    final cached = await _readCache(cacheKey);
    final jobId = _jobIdFromData(jobData);
    if (jobId.isEmpty) {
      if (cached is! List) {
        await _saveCache(cacheKey, [jobData]);
      }
      return;
    }

    if (cached is List) {
      final updated = <dynamic>[];
      var replaced = false;
      for (final item in cached) {
        if (item is Map<String, dynamic>) {
          final itemId = _jobIdFromData(item);
          if (itemId.isNotEmpty && itemId == jobId) {
            updated.add(jobData);
            replaced = true;
            continue;
          }
        }
        updated.add(item);
      }
      if (!replaced) {
        updated.add(jobData);
      }
      await _saveCache(cacheKey, updated);
      return;
    }

    await _saveCache(cacheKey, [jobData]);
  }

  /// Get public jobs available on the platform (for providers to browse)
  static Future<Map<String, dynamic>> getJobs({
    bool forceRefresh = false,
  }) async {
    const cacheKey = 'jobs_list';
    try {
      if (!forceRefresh) {
        final cached = await _readCache(cacheKey);
        if (cached is List) {
          return {'success': true, 'data': cached, 'fromCache': true};
        }
      }

      final res = await _sendWithAuthRetry(
        (headers) => http
            .get(Uri.parse('$_baseUrl/jobs'), headers: headers)
            .timeout(const Duration(seconds: 15)),
      );


      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic> raw =
            (data is List ? data : null) ??
            (data['data'] is List ? data['data'] : null) ??
            (data['jobs'] is List ? data['jobs'] : null) ??
            [];
        await _saveCache(cacheKey, raw);
        return {'success': true, 'data': raw};
      }

      if (res.statusCode == 401) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final data = jsonDecode(res.body);
      return {
        'success': false,
        'message': _extractMessage(data) ?? 'Failed to load jobs.',
      };
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Unable to load jobs.'};
    }
  }

  /// Get jobs specific to the authenticated provider (jobs the provider has accepted or posted)
  static Future<Map<String, dynamic>> getProviderJobs({
    bool forceRefresh = false,
  }) async {
    const cacheKey = 'provider_jobs';
    try {
      if (!forceRefresh) {
        final cached = await _readCache(cacheKey);
        if (cached is List) {
          return {'success': true, 'data': cached, 'fromCache': true};
        }
      }

      final res = await _sendWithAuthRetry(
        (headers) => http
            .get(Uri.parse('$_baseUrl/provider/jobs'), headers: headers)
            .timeout(const Duration(seconds: 15)),
      );


      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic> raw =
            (data is List ? data : null) ??
            (data['data'] is List ? data['data'] : null) ??
            (data['jobs'] is List ? data['jobs'] : null) ??
            [];
        await _saveCache(cacheKey, raw);
        return {'success': true, 'data': raw};
      }

      if (res.statusCode == 401) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final data = jsonDecode(res.body);
      return {
        'success': false,
        'message': _extractMessage(data) ?? 'Failed to load provider jobs.',
      };
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Unable to load provider jobs.'};
    }
  }

  static String _jobIdFromData(Map<String, dynamic>? data) {
    if (data == null) return '';
    for (final key in ['id', 'ulid', 'job_id', 'jobId']) {
      final raw = data[key];
      final value = raw is String
          ? raw.trim()
          : raw is num
          ? raw.toString()
          : raw?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> fields,
  ) async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        return {
          'success': false,
          'message': 'Authentication required. Please log in again.',
        };
      }

      // Map UI fields to API structure
      final apiFields = _mapProfileFieldsToApi(fields);

      final bool useMultipart = _containsLocalImages(fields);
      Future<http.Response> sendRequest(String method) => useMultipart
          ? _sendMultipartProfileUpdate(apiFields, method: method)
          : _sendProviderProfileRequest(apiFields, method: method);

      var res = await sendRequest('PATCH');
      if (res.statusCode == 404) {
        res = await sendRequest('POST');
      }

      if (res.statusCode == 200 || res.statusCode == 201) {
        final prefs = await SharedPreferences.getInstance();
        final cached = prefs.getString('profile');
        final Map<String, dynamic> localCache = cached != null
            ? jsonDecode(cached) as Map<String, dynamic>
            : {};

        Map<String, dynamic> updatedCache;
        try {
          final responseData = jsonDecode(res.body);
          if (responseData is Map<String, dynamic>) {
            updatedCache = _mergeProfileCache(localCache, responseData, fields);
          } else {
            updatedCache = localCache;
          }
        } catch (_) {
          updatedCache = localCache;
        }

        if (updatedCache.isEmpty) {
          updatedCache = Map<String, dynamic>.from(fields);
        }

        await prefs.setString('profile', jsonEncode(updatedCache));
        return {'success': true};
      }

      if (res.statusCode == 401) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final data = jsonDecode(res.body);
      return {
        'success': false,
        'message': _extractMessage(data) ?? 'Failed to update profile.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Unable to update profile.'};
    }
  }

  static Future<String?> getToken() async {
    if (_cachedToken != null && _cachedToken!.trim().isNotEmpty) {
      return _cachedToken;
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null && token.trim().isNotEmpty) {
      final normalized = _normalizeToken(token);
      if (normalized != token) {
        await prefs.setString('token', normalized);
      }
      _cachedToken = normalized;
      return normalized;
    } else if (token != null) {
      // Remove empty token
      await prefs.remove('token');
    }

    final cachedProfile = prefs.getString('profile');
    if (cachedProfile != null) {
      try {
        final profile = jsonDecode(cachedProfile) as Map<String, dynamic>;
        final candidate = _extractToken(profile);
        if (candidate != null && candidate.trim().isNotEmpty) {
          final normalized = _normalizeToken(candidate);
          await prefs.setString('token', normalized);
          _cachedToken = normalized;
          return normalized;
        }
      } catch (_) {
        // ignore malformed cached profile
      }
    }

    return null;
  }

  static Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('role');
    if (role == null || role.trim().isEmpty) {
      return null;
    }
    return role.trim();
  }

  // ── HELPER METHODS ──────────────────────────────────────────
  /// Creates proper authorization headers with token validation and logging
  static Future<bool> _isAccessTokenExpired({
    Duration buffer = const Duration(seconds: 30),
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final expiryMs = _cachedTokenExpiryMs ?? prefs.getInt(_tokenExpiryKey);
    if (expiryMs == null) {
      final token = await getToken();
      if (token == null) return false;
      final expiresAt = _extractTokenExpiry(token);
      if (expiresAt == null) return false;
      _cachedTokenExpiryMs = expiresAt.millisecondsSinceEpoch;
      await prefs.setInt(_tokenExpiryKey, _cachedTokenExpiryMs!);
      return DateTime.now().isAfter(expiresAt.subtract(buffer));
    }
    return DateTime.now().isAfter(
      DateTime.fromMillisecondsSinceEpoch(expiryMs).subtract(buffer),
    );
  }

  static DateTime? _extractTokenExpiry(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;

      String normalizePayload(String payload) {
        var normalized = payload.replaceAll('-', '+').replaceAll('_', '/');
        while (normalized.length % 4 != 0) {
          normalized += '=';
        }
        return normalized;
      }

      final payload = normalizePayload(parts[1]);
      final decoded = utf8.decode(base64Url.decode(payload));
      final data = jsonDecode(decoded);
      if (data is Map<String, dynamic>) {
        final expValue = data['exp'];
        if (expValue == null) return null;
        final epochSeconds = expValue is String
            ? int.tryParse(expValue)
            : (expValue is num ? expValue.toInt() : null);
        if (epochSeconds == null) return null;
        return DateTime.fromMillisecondsSinceEpoch(
          epochSeconds * 1000,
          isUtc: true,
        );
      }
    } catch (_) {
      // ignore invalid token format
    }
    return null;
  }

  static Future<Map<String, String>> _getAuthHeaders() async {
    final token = await getToken();

    if (token == null || token.isEmpty) {
      return {'Content-Type': 'application/json'};
    }

    final trimmedToken = _normalizeToken(token);
    if (trimmedToken.isEmpty) {
      return {'Content-Type': 'application/json'};
    }

    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-Requested-With': 'XMLHttpRequest',
      'Authorization': 'Bearer $trimmedToken',
    };

    // Log token info for debugging (length only, not actual token)

    return headers;
  }

  static Future<bool> _refreshAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = await _getRefreshToken();
    final accessToken = await getToken();

    if (refreshToken == null || refreshToken.trim().isEmpty) {
      final stored = prefs.getString('refresh_token');
      return false;
    }

    try {
      final refresh = _normalizeToken(refreshToken);
      final access = accessToken == null ? null : _normalizeToken(accessToken);
      final attempts = <Map<String, dynamic>>[
        {
          'label': 'refresh_token body + refresh bearer',
          'body': {'refresh_token': refresh},
          'bearer': refresh,
        },
        {
          'label': 'refreshToken body + refresh bearer',
          'body': {'refreshToken': refresh},
          'bearer': refresh,
        },
        if (refresh.isNotEmpty)
          {
            'label': 'refresh_token body only',
            'body': {'refresh_token': refresh},
            'bearer': null,
          },
        if (refresh.isNotEmpty)
          {
            'label': 'refreshToken body only',
            'body': {'refreshToken': refresh},
            'bearer': null,
          },
      ];

      for (final attempt in attempts) {
        final bearer = attempt['bearer'] as String?;
        final body = attempt['body'] as Map<String, dynamic>;
        final headers = <String, String>{
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest',
          if (bearer != null && bearer.isNotEmpty)
            'Authorization': 'Bearer $bearer',
        };

        final res = await http
            .post(
              Uri.parse('$_baseUrl/auth/refresh'),
              headers: headers,
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 15));


        if (res.statusCode == 200 || res.statusCode == 201) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final newToken = _extractToken(data);
          if (newToken == null || newToken.isEmpty) {
            continue;
          }

          final normalizedToken = _normalizeToken(newToken);
          await prefs.setString('token', normalizedToken);
          _cachedToken = normalizedToken;

          final expiresAt = _extractTokenExpiry(normalizedToken);
          if (expiresAt != null) {
            await prefs.setInt(
              _tokenExpiryKey,
              expiresAt.millisecondsSinceEpoch,
            );
            _cachedTokenExpiryMs = expiresAt.millisecondsSinceEpoch;
          } else {
            await prefs.remove(_tokenExpiryKey);
            _cachedTokenExpiryMs = null;
          }

          final newRefreshToken = _extractRefreshToken(data);
          if (newRefreshToken != null && newRefreshToken.isNotEmpty) {
            await prefs.setString(
              'refresh_token',
              _normalizeToken(newRefreshToken),
            );
          }
          return true;
        }
      }
    } catch (e) {
    }

    return false;
  }

  static Future<String?> _getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('refresh_token');
    if (stored != null && stored.trim().isNotEmpty) {
      final normalized = _normalizeToken(stored);
      if (normalized != stored) {
        await prefs.setString('refresh_token', normalized);
      }
      return normalized;
    }

    final cachedProfile = prefs.getString('profile');
    if (cachedProfile != null) {
      try {
        final profile = jsonDecode(cachedProfile) as Map<String, dynamic>;
        final candidate = _extractRefreshToken(profile);
        if (candidate != null && candidate.trim().isNotEmpty) {
          final normalized = _normalizeToken(candidate);
          await prefs.setString('refresh_token', normalized);
          return normalized;
        }
      } catch (_) {
        // ignore malformed cached profile
      }
    }

    return null;
  }

  static Future<http.Response> _sendWithAuthRetry(
    Future<http.Response> Function(Map<String, String> headers) send,
  ) async {
    // Check if token is near expiry and attempt refresh IF we have a refresh token
    if (await _isAccessTokenExpired()) {
      final refreshToken = await _getRefreshToken();
      if (refreshToken != null && refreshToken.trim().isNotEmpty) {
        await _refreshAccessToken();
      }
    }

    var headers = await _getAuthHeaders();
    var res = await send(headers);

    if (res.statusCode != 401) return res;

    // On 401, attempt a token refresh if we have a refresh token.
    // Do NOT call _clearStoredSession() here — a transient 401 from a silent
    // background refresh must not destroy the session. Callers that handle
    // auth_required: true are responsible for clearing and redirecting.
    final refreshToken = await _getRefreshToken();
    if (refreshToken == null || refreshToken.trim().isEmpty) {
      return res;
    }

    final refreshed = await _refreshAccessToken();
    if (!refreshed) {
      return res;
    }

    headers = await _getAuthHeaders();
    return send(headers);
  }

  static Future<http.Response> _sendStreamedWithAuthRetry(
    Future<http.StreamedResponse> Function(Map<String, String> headers) send,
  ) async {
    // Check if token is near expiry and attempt refresh IF we have a refresh token
    if (await _isAccessTokenExpired()) {
      final refreshToken = await _getRefreshToken();
      if (refreshToken != null && refreshToken.trim().isNotEmpty) {
        await _refreshAccessToken();
      }
    }

    var headers = await _getAuthHeaders();
    var streamed = await send(headers);
    var res = await http.Response.fromStream(streamed);

    if (res.statusCode != 401) return res;

    // On 401, attempt refresh. Do NOT clear the session here — same reason
    // as in _sendWithAuthRetry; callers own the clear + redirect decision.
    final refreshToken = await _getRefreshToken();
    if (refreshToken == null || refreshToken.trim().isEmpty) {
      return res;
    }

    final refreshed = await _refreshAccessToken();
    if (!refreshed) {
      return res;
    }

    headers = await _getAuthHeaders();
    streamed = await send(headers);
    return await http.Response.fromStream(streamed);
  }

  static Map<String, dynamic> _extractProfileSource(Map<String, dynamic> data) {
    Map<String, dynamic>? source = data;
    if (source['data'] is Map<String, dynamic>) {
      source = source['data'] as Map<String, dynamic>;
    }
    if (source['user'] is Map<String, dynamic>) {
      source = source['user'] as Map<String, dynamic>;
    }
    if (source['provider'] is Map<String, dynamic>) {
      source = source['provider'] as Map<String, dynamic>;
    }
    return Map<String, dynamic>.from(source);
  }

  static Map<String, dynamic> _mapApiResponseToUi(
    Map<String, dynamic> apiData,
  ) {
    final ui = <String, dynamic>{};

    // Preserve name-like fields from API so UI can extract display name
    final nameKeys = [
      'name',
      'display_name',
      'full_name',
      'username',
      'provider_name',
      'profile_name',
      'first_name',
      'last_name',
    ];
    for (final k in nameKeys) {
      if (apiData[k] != null) ui[k] = apiData[k];
    }

    // Map profile_photo_url back to avatar
    if (apiData['profile_photo_url'] != null) {
      ui['avatar'] = apiData['profile_photo_url'];
    }

    // Map category_slugs back to services
    if (apiData['category_slugs'] is List) {
      ui['services'] = apiData['category_slugs'];
    }

    // Map workshop_address back to location
    if (apiData['workshop_address'] != null) {
      ui['location'] = apiData['workshop_address'];
    }

    // Map hourly_rate_kobo back to hourly_rate (kobo to ₦)
    if (apiData['hourly_rate_kobo'] != null) {
      try {
        final kobo = apiData['hourly_rate_kobo'] as int?;
        if (kobo != null) {
          ui['hourly_rate'] = (kobo / 100).toString();
        }
      } catch (_) {}
    }

    // Map gallery_photos back to photos
    if (apiData['gallery_photos'] is List) {
      ui['photos'] = apiData['gallery_photos'];
    }

    // Map availability_json back to availability (day names to day indices)
    if (apiData['availability_json'] is Map) {
      final availJson = apiData['availability_json'] as Map;
      final dayNames = {
        'monday': 1,
        'tuesday': 2,
        'wednesday': 3,
        'thursday': 4,
        'friday': 5,
        'saturday': 6,
        'sunday': 7,
      };
      final availMap = <int, List<String>>{};

      availJson.forEach((dayName, ranges) {
        if (dayNames.containsKey(dayName) && ranges is List) {
          final dayIdx = dayNames[dayName]!;
          availMap[dayIdx] = ranges.map((r) => r.toString()).toList();
        }
      });
      if (availMap.isNotEmpty) {
        ui['availability'] = availMap;
      }
    }

    // Copy bio, photo_url directly
    if (apiData['bio'] != null) {
      ui['bio'] = apiData['bio'];
    }
    if (apiData['photo_url'] != null) {
      ui['photo_url'] = apiData['photo_url'];
    }

    return ui;
  }

  static Map<String, dynamic> _mapProfileFieldsToApi(
    Map<String, dynamic> uiFields,
  ) {
    final api = <String, dynamic>{};

    if (uiFields['bio'] != null) {
      api['bio'] = uiFields['bio'];
    }
    if (uiFields['description'] != null) {
      api['bio'] = uiFields['description'];
    }

    // Map avatar to profile_photo_url
    if (uiFields['avatar'] != null) {
      api['profile_photo_url'] = uiFields['avatar'];
    }

    // Map services to category_slugs
    if (uiFields['services'] is List) {
      api['category_slugs'] = uiFields['services'];
    }
    if (uiFields['service_categories'] is List) {
      api['category_slugs'] = uiFields['service_categories'];
    }

    // Map location to workshop_address
    if (uiFields['location'] != null) {
      api['workshop_address'] = uiFields['location'];
    }

    // Map user-facing name fields
    if (uiFields['name'] != null) {
      api['name'] = uiFields['name'];
    }
    if (uiFields['first_name'] != null) {
      api['first_name'] = uiFields['first_name'];
    }
    if (uiFields['last_name'] != null) {
      api['last_name'] = uiFields['last_name'];
    }
    if (uiFields['landmark'] != null) {
      api['landmark'] = uiFields['landmark'];
    }
    if (uiFields['workshop_location'] != null) {
      api['workshop_location'] = uiFields['workshop_location'];
    }

    // Map hourly_rate to hourly_rate_kobo (convert to kobo if needed)
    if (uiFields['hourly_rate'] != null) {
      final rateStr = uiFields['hourly_rate'].toString().trim();
      if (rateStr.isNotEmpty) {
        try {
          final rate = double.parse(rateStr);
          api['hourly_rate_kobo'] = (rate * 100).toInt(); // ₦ to kobo
        } catch (_) {
          api['hourly_rate_kobo'] = 0;
        }
      }
    }

    // Map photos to gallery_photos
    if (uiFields['photos'] is List) {
      api['gallery_photos'] = uiFields['photos'];
    }

    // Map availability to availability_json
    if (uiFields['availability'] is Map) {
      final availMap = uiFields['availability'] as Map;
      final availJson = <String, List<String>>{};
      final dayNames = [
        'monday',
        'tuesday',
        'wednesday',
        'thursday',
        'friday',
        'saturday',
        'sunday',
      ];

      for (final entry in availMap.entries) {
        final dayIdx = entry.key as int?;
        final ranges = entry.value as List?;
        if (dayIdx != null &&
            dayIdx >= 1 &&
            dayIdx <= 7 &&
            ranges != null &&
            ranges.isNotEmpty) {
          final dayName = dayNames[dayIdx - 1];
          availJson[dayName] = ranges.map((r) => r.toString()).toList();
        }
      }
      if (availJson.isNotEmpty) {
        api['availability_json'] = availJson;
      }
    }

    // Workshop location (if available)
    // For now, this is typically managed separately or via map selection

    return api;
  }

  static bool _isLocalImagePath(String? path) {
    if (path == null || path.trim().isEmpty) return false;
    final trimmed = path.trim();
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('http')) return false;
    if (lower.startsWith('file://') || lower.startsWith('content://'))
      return true;
    if (trimmed.startsWith('/') ||
        RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(trimmed)) {
      return true;
    }
    return File(trimmed).existsSync();
  }

  static bool _containsLocalImages(Map<String, dynamic> fields) {
    if (_isLocalImagePath(fields['avatar']?.toString())) {
      return true;
    }
    final photos = fields['photos'];
    if (photos is List) {
      for (final photo in photos) {
        if (_isLocalImagePath(photo?.toString())) return true;
      }
    }
    return false;
  }

  static Future<http.Response> _sendMultipartProfileUpdate(
    Map<String, dynamic> fields, {
    String method = 'PATCH',
  }) async {
    return _sendStreamedWithAuthRetry((headers) async {
      final request = http.MultipartRequest(
        method,
        Uri.parse('$_baseUrl/provider/profile'),
      );
      request.headers.addAll(headers);

      final missingPaths = <String>[];

      for (final entry in fields.entries) {
        final key = entry.key;
        final value = entry.value;

        if (key == 'profile_photo_url' &&
            value is String &&
            _isLocalImagePath(value)) {
          try {
            final path = value.toString();
            if (File(path).existsSync()) {
              request.files.add(
                await http.MultipartFile.fromPath('profile_photo_url', path),
              );
            } else {
              missingPaths.add(path);
            }
          } catch (e) {
            missingPaths.add(value.toString());
          }
          continue;
        }

        if (key == 'gallery_photos' && value is List) {
          final remotePhotos = <String>[];
          for (final photo in value) {
            final path = photo?.toString() ?? '';
            if (_isLocalImagePath(path)) {
              try {
                if (File(path).existsSync()) {
                  request.files.add(
                    await http.MultipartFile.fromPath('gallery_photos[]', path),
                  );
                } else {
                  missingPaths.add(path);
                }
              } catch (e) {
                missingPaths.add(path);
              }
            } else if (path.isNotEmpty) {
              remotePhotos.add(path);
            }
          }
          if (remotePhotos.isNotEmpty) {
            request.fields['gallery_photos'] = jsonEncode(remotePhotos);
          }
          continue;
        }

        if (value is Map || value is List) {
          request.fields[key] = jsonEncode(value);
        } else if (value != null) {
          request.fields[key] = value.toString();
        }
      }

      if (missingPaths.isNotEmpty && request.files.isEmpty) {
        // If none of the local files could be attached, fall back to JSON request.
        final fallback = await _sendProviderProfileRequest(
          fields,
          method: method,
        );
        // Convert http.Response to http.StreamedResponse for the caller
        final bytes = fallback.bodyBytes;
        final streamed = http.StreamedResponse(
          Stream.fromIterable([bytes]),
          fallback.statusCode,
          headers: fallback.headers,
          contentLength: bytes.length,
        );
        return streamed;
      }

      if (missingPaths.isNotEmpty) {
      }

      return await request.send();
    });
  }

  static Future<http.Response> _sendProviderProfileRequest(
    Map<String, dynamic> fields, {
    String method = 'PATCH',
  }) async {
    return _sendWithAuthRetry(
      (headers) =>
          (method == 'POST'
                  ? http.post(
                      Uri.parse('$_baseUrl/provider/profile'),
                      headers: headers,
                      body: jsonEncode(fields),
                    )
                  : http.patch(
                      Uri.parse('$_baseUrl/provider/profile'),
                      headers: headers,
                      body: jsonEncode(fields),
                    ))
              .timeout(const Duration(seconds: 15)),
    );
  }

  static Map<String, dynamic> _mergeProfileCache(
    Map<String, dynamic> cached,
    Map<String, dynamic> responseData,
    Map<String, dynamic> fields,
  ) {
    final merged = Map<String, dynamic>.from(cached);
    final Map<String, dynamic> target = merged['user'] is Map<String, dynamic>
        ? (merged['user'] as Map<String, dynamic>)
        : merged;

    final responseSource = _extractProfileSource(responseData);
    if (responseSource.isNotEmpty) {
      // Apply reverse mapping to convert API field names to UI field names
      final mappedSource = _mapApiResponseToUi(responseSource);
      target.addAll(mappedSource);
    }

    for (final entry in fields.entries) {
      if (entry.value != null) {
        // Don't overwrite avatar/photos with local file paths; keep server URLs
        if (entry.key == 'avatar' &&
            _isLocalImagePath(entry.value?.toString())) {
          continue;
        }
        if (entry.key == 'photos' && entry.value is List) {
          final photos = entry.value as List;
          final hasLocalPaths = photos.any(
            (p) => _isLocalImagePath(p?.toString()),
          );
          if (hasLocalPaths) {
            continue; // Keep server response photos
          }
        }
        target[entry.key] = entry.value;
      }
    }

    if (merged['user'] is Map<String, dynamic>) {
      merged['user'] = target;
    }
    return merged;
  }

  static Future<Map<String, dynamic>> getProviders({
    double? lat,
    double? lng,
    bool forceRefresh = false,
  }) async {
    const cacheKey = 'providers_all';
    try {
      // Try cache first if not forced refresh
      if (!forceRefresh) {
        final cached = await _readCache(cacheKey);
        if (cached is List) {
          return {'success': true, 'data': cached, 'fromCache': true};
        }
      }

      final uri = Uri.parse('$_baseUrl/providers').replace(
        queryParameters: {
          if (lat != null) 'lat': lat.toString(),
          if (lng != null) 'lng': lng.toString(),
        },
      );
      final res = await _sendWithAuthRetry(
        (headers) => http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 15)),
      );
      if (res.statusCode == 401) {
      }
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic> raw =
            (data is List ? data : null) ??
            (data['data'] is List ? data['data'] : null) ??
            (data['providers'] is List ? data['providers'] : null) ??
            [];

        // Cache both provider list and individual provider images
        await _saveCache(cacheKey, raw);
        final providers = raw.cast<Map<String, dynamic>>();
        await saveProvidersList(providers);

        // Cache individual provider images
        for (final provider in providers) {
          final ulid = provider['ulid']?.toString();
          if (ulid != null && ulid.isNotEmpty) {
            await saveProviderImages(ulid, provider);
          }
        }

        if (raw.isNotEmpty) {
        }
        return {'success': true, 'data': raw};
      }
      return {'success': false, 'message': 'Failed to load providers.'};
    } on SocketException {
      return {'success': false, 'message': 'No internet connection.'};
    } catch (e) {
      return {'success': false, 'message': 'Unable to load providers.'};
    }
  }

  static Future<Map<String, dynamic>> getCategories({
    bool forceRefresh = false,
  }) async {
    const cacheKey = 'categories';
    try {
      if (!forceRefresh) {
        final cached = await _readCache(cacheKey);
        if (cached is List) {
          return {'success': true, 'data': cached, 'fromCache': true};
        }
      }

      final res = await _sendWithAuthRetry(
        (headers) => http
            .get(Uri.parse('$_baseUrl/public/categories'), headers: headers)
            .timeout(const Duration(seconds: 15)),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic> raw =
            (data is List ? data : null) ??
            (data['data'] is List ? data['data'] : null) ??
            (data['categories'] is List ? data['categories'] : null) ??
            [];
        await _saveCache(cacheKey, raw);
        if (raw.isNotEmpty) {
        }
        return {'success': true, 'data': raw};
      }
      return {'success': false, 'message': 'Failed to load categories.'};
    } on SocketException {
      final cached = await _readCache(cacheKey);
      if (cached is List) {
        return {'success': true, 'data': cached, 'fromCache': true};
      }
      return {'success': false, 'message': 'No internet connection.'};
    } catch (e) {
      return {'success': false, 'message': 'Unable to load categories.'};
    }
  }

  static Future<Map<String, dynamic>> getProviderProfile(
    String ulid, {
    bool forceRefresh = false,
  }) async {
    final cacheKey = 'provider_profile_$ulid';
    try {
      if (!forceRefresh) {
        final cached = await _readCache(cacheKey);
        if (cached is Map<String, dynamic>) {
          return {'success': true, 'data': cached, 'fromCache': true};
        }
      }

      final res = await _sendWithAuthRetry(
        (headers) => http
            .get(Uri.parse('$_baseUrl/providers/$ulid'), headers: headers)
            .timeout(const Duration(seconds: 15)),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final Map<String, dynamic> raw =
            (data['data'] is Map ? data['data'] : null) ??
            (data['provider'] is Map ? data['provider'] : null) ??
            (data is Map<String, dynamic> ? data : {});

        // Cache the full profile
        await _saveCache(cacheKey, raw);

        // Also cache provider images separately for faster dashboard loading
        await saveProviderImages(ulid, raw);

        return {'success': true, 'data': raw};
      }
      final cached = await _readCache(cacheKey);
      if (cached is Map<String, dynamic>) {
        return {'success': true, 'data': cached, 'fromCache': true};
      }
      return {'success': false, 'message': 'Failed to load provider profile.'};
    } on SocketException {
      final cached = await _readCache(cacheKey);
      if (cached is Map<String, dynamic>) {
        return {'success': true, 'data': cached, 'fromCache': true};
      }
      return {'success': false, 'message': 'No internet connection.'};
    } catch (e) {
      final cached = await _readCache(cacheKey);
      if (cached is Map<String, dynamic>) {
        return {'success': true, 'data': cached, 'fromCache': true};
      }
      return {'success': false, 'message': 'Unable to load provider profile.'};
    }
  }

  static Future<Map<String, dynamic>> getProvidersBySubcategory({
    required String subcategoryId,
    double? lat,
    double? lng,
    bool forceRefresh = false,
  }) async {
    final cacheKey = subcategoryId.trim().isEmpty
        ? 'providers_all'
        : 'providers_cat_${subcategoryId.trim()}';

    try {
      if (!forceRefresh) {
        final cached = await _readCache(cacheKey);
        if (cached is List) {
          return {'success': true, 'data': cached, 'fromCache': true};
        }
        if (subcategoryId.trim().isNotEmpty) {
          final allCached = await _readCache('providers_all');
          if (allCached is List) {
            final filtered = _filterProvidersByCategory(
              allCached,
              subcategoryId,
            );
            if (filtered.isNotEmpty) {
              return {'success': true, 'data': filtered, 'fromCache': true};
            }
          }
        }
      }

      final token = await getToken();
      final uri = Uri.parse('$_baseUrl/providers').replace(
        queryParameters: {
          if (subcategoryId.isNotEmpty) 'category': subcategoryId,
          if (subcategoryId.isNotEmpty) 'category_id': subcategoryId,
          if (lat != null) 'lat': lat.toString(),
          if (lng != null) 'lng': lng.toString(),
        },
      );
      final res = await _sendWithAuthRetry(
        (headers) => http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 15)),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic> raw =
            (data is List ? data : null) ??
            (data['data'] is List ? data['data'] : null) ??
            (data['providers'] is List ? data['providers'] : null) ??
            [];
        await _saveCache(cacheKey, raw);
        if (subcategoryId.trim().isEmpty) {
          await _saveCache('providers_all', raw);
        }
        return {'success': true, 'data': raw};
      }

      if (!forceRefresh) {
        final cached = await _readCache(cacheKey);
        if (cached is List) {
          return {'success': true, 'data': cached, 'fromCache': true};
        }
      }
      return {'success': false, 'message': 'Failed to load providers.'};
    } on SocketException {
      final cached = await _readCache(cacheKey);
      if (cached is List) {
        return {'success': true, 'data': cached, 'fromCache': true};
      }
      return {'success': false, 'message': 'No internet connection.'};
    } catch (e) {
      return {'success': false, 'message': 'Unable to load providers.'};
    }
  }

  static Future<Map<String, dynamic>> createJobDraft({
    required String title,
    required String description,
    List<String>? categories,
    required String categorySlug,
    DateTime? preferredDate,
    double? budget,
    String? budgetMode,
    int? budgetMinKobo,
    double? locationLat,
    double? locationLng,
    String? locationAddressText,
    String? targetProviderUlid,
    bool? openToCategoryProviders,
  }) async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        return {
          'success': false,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final roleReady = await _ensureCustomerRoleForJobs();
      if (roleReady['success'] != true) {
        return roleReady;
      }

      final requestBody = jsonEncode({
        'title': title,
        'description': description,
        'status': 'draft',
        'category_slug': categorySlug,
        if (categories != null && categories.isNotEmpty)
          'categories': categories,
        if (preferredDate != null)
          'preferred_date': preferredDate.toIso8601String(),
        if (budget != null) 'budget': budget,
        if (budget != null && budgetMode != null) 'budget_mode': budgetMode,
        if (budgetMinKobo != null) 'budget_min_kobo': budgetMinKobo,
        if (budgetMode == 'fixed' && budgetMinKobo != null)
          'budget_max_kobo': budgetMinKobo,
        if (locationLat != null ||
            locationLng != null ||
            locationAddressText != null)
          'location': {
            if (locationLat != null) 'lat': locationLat,
            if (locationLng != null) 'lng': locationLng,
            if (locationAddressText != null)
              'address_text': locationAddressText,
          },
        if (targetProviderUlid != null && targetProviderUlid.isNotEmpty)
          'target_provider_ulid': targetProviderUlid,
        if (openToCategoryProviders != null)
          'open_to_category_providers': openToCategoryProviders,
      });


      final res = await _sendWithAuthRetry(
        (headers) => http
            .post(
              Uri.parse('$_baseUrl/jobs'),
              headers: headers,
              body: requestBody,
            )
            .timeout(const Duration(seconds: 15)),
      );


      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        await _clearCache('customer_jobs');
        return {'success': true, 'data': data};
      }

      if (res.statusCode == 401) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final data = jsonDecode(res.body);
      if (res.statusCode == 403) {
        return {
          'success': false,
          'statusCode': res.statusCode,
          'message': 'Please switch to customer mode before creating a job.',
          'data': data,
        };
      }

      return {
        'success': false,
        'statusCode': res.statusCode,
        'message': _extractMessage(data) ?? 'Failed to create job draft.',
      };
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Unable to create job draft.'};
    }
  }

  static Future<Map<String, dynamic>> _ensureCustomerRoleForJobs() async {
    final activeRole = await getActiveRole();
    final sessionRole = await getRole();
    final normalizedActiveRole = activeRole?.trim();
    final normalizedSessionRole = sessionRole?.trim();
    if ((normalizedActiveRole == null ||
            normalizedActiveRole.isEmpty ||
            normalizedActiveRole == 'customer') &&
        (normalizedSessionRole == null ||
            normalizedSessionRole.isEmpty ||
            normalizedSessionRole == 'customer')) {
      return {'success': true};
    }

    final switchResult = await switchRole('customer');
    if (switchResult['success'] == true) {
      return {'success': true};
    }

    return {
      'success': false,
      'statusCode': switchResult['statusCode'],
      'message':
          switchResult['message']?.toString() ??
          'Please switch to customer mode before creating a job.',
      'data': switchResult['data'],
    };
  }

  static Future<Map<String, dynamic>> publishJob(String jobUlid) async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        return {
          'success': false,
          'message': 'Authentication required. Please log in again.',
        };
      }


      final res = await _sendWithAuthRetry(
        (headers) => http
            .post(
              Uri.parse('$_baseUrl/jobs/$jobUlid/publish'),
              headers: headers,
              body: jsonEncode({}),
            )
            .timeout(const Duration(seconds: 15)),
      );


      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        await _clearCache('customer_jobs');
        return {'success': true, 'data': data};
      }

      if (res.statusCode == 401) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      if (res.statusCode == 409) {
        await _clearCache('customer_jobs');
        return {
          'success': false,
          'already_published': true,
          'message': 'This job is already published and open to providers.',
        };
      }

      if (res.statusCode == 402) {
        final data = jsonDecode(res.body);
        final error = data['error'] as Map<String, dynamic>?;
        if (error != null && error['code'] == 'ERR_INSUFFICIENT_FUNDS') {
          final details = error['details'] as Map<String, dynamic>?;
          final required = details?['required_kobo'] ?? 0;
          final available = details?['available_kobo'] ?? 0;
          final requiredNaira = (required / 100).toStringAsFixed(2);
          final availableNaira = (available / 100).toStringAsFixed(2);
          return {
            'success': false,
            'message':
                'Insufficient wallet balance. You need ₦$requiredNaira but only have ₦$availableNaira. Please top up your wallet to publish this job.',
            'error_code': 'INSUFFICIENT_FUNDS',
            'required_kobo': required,
            'available_kobo': available,
          };
        }
        return {
          'success': false,
          'message':
              _extractMessage(data) ?? 'Payment required to publish job.',
        };
      }

      final data = jsonDecode(res.body);
      final error = (data['error'] is Map<String, dynamic>)
          ? data['error'] as Map<String, dynamic>
          : null;
      final errorCode = _toString(error?['code']);
      final requestId =
          _toString(error?['request_id']) ?? _toString(error?['requestId']);
      final serverMessage = _extractMessage(data);

      String friendlyMessage() {
        final lower = serverMessage?.toLowerCase() ?? '';
        if (lower.contains('invalid') ||
            lower.contains('data given') ||
            lower.contains('validation')) {
          return 'Some job details are invalid or missing. Please review the job and try again.';
        }
        if (res.statusCode == 500) {
          return 'The server encountered an unexpected error while publishing the job. Please try again later.';
        }
        return serverMessage ?? 'Failed to publish job.';
      }

      return {
        'success': false,
        'message': friendlyMessage(),
        if (errorCode != null) 'error_code': errorCode,
        if (requestId != null) 'request_id': requestId,
      };
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Unable to publish job.'};
    }
  }

  static Future<Map<String, dynamic>> hireProvider(
    String jobUlid,
    String applicationUlid,
  ) async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        return {
          'success': false,
          'message': 'Authentication required. Please log in again.',
        };
      }


      final res = await _sendWithAuthRetry(
        (headers) => http
            .post(
              Uri.parse('$_baseUrl/jobs/$jobUlid/hire/$applicationUlid'),
              headers: headers,
            )
            .timeout(const Duration(seconds: 15)),
      );


      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        return {'success': true, 'data': data};
      }

      if (res.statusCode == 401) {
        return {
          'success': false,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final data = jsonDecode(res.body);
      return {
        'success': false,
        'message': _extractMessage(data) ?? 'Failed to hire provider.',
      };
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Unable to hire provider.'};
    }
  }

  // ── WALLET OPERATIONS ────────────────────────────────────────────

  static Future<Map<String, dynamic>> getWalletBalance() async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final res = await _sendWithAuthRetry(
        (headers) => http
            .get(Uri.parse('$_baseUrl/wallet'), headers: headers)
            .timeout(const Duration(seconds: 15)),
      );


      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return {'success': true, 'data': data};
      }

      if (res.statusCode == 401) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final data = jsonDecode(res.body);
      return {
        'success': false,
        'message': _extractMessage(data) ?? 'Failed to load wallet balance.',
      };
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Unable to load wallet balance.'};
    }
  }

  static Future<Map<String, dynamic>> getTransactions({
    int perPage = 50,
    String? cursor,
  }) async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final res = await _sendWithAuthRetry(
        (headers) => http
            .get(
              Uri.parse('$_baseUrl/wallet/transactions').replace(
                queryParameters: {
                  'per_page': perPage.toString(),
                  if (cursor != null) 'cursor': cursor,
                },
              ),
              headers: headers,
            )
            .timeout(const Duration(seconds: 15)),
      );


      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return {'success': true, 'data': data};
      }

      if (res.statusCode == 401) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final data = jsonDecode(res.body);
      return {
        'success': false,
        'message': _extractMessage(data) ?? 'Failed to load transactions.',
      };
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Unable to load transactions.'};
    }
  }

  static Future<Map<String, dynamic>> getNotifications({
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final res = await _sendWithAuthRetry(
        (headers) => http
            .get(
              Uri.parse('$_baseUrl/notifications').replace(
                queryParameters: {
                  'limit': limit.toString(),
                  'offset': offset.toString(),
                },
              ),
              headers: headers,
            )
            .timeout(const Duration(seconds: 15)),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return {'success': true, 'data': data};
      }

      if (res.statusCode == 401) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final data = jsonDecode(res.body);
      return {
        'success': false,
        'message': _extractMessage(data) ?? 'Failed to load notifications.',
      };
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Unable to load notifications.'};
    }
  }

  static Future<Map<String, dynamic>> getKycStatus() async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final res = await _sendWithAuthRetry(
        (headers) => http
            .get(Uri.parse('$_baseUrl/trust/kyc/status'), headers: headers)
            .timeout(const Duration(seconds: 15)),
      );


      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return {'success': true, 'data': data};
      }

      if (res.statusCode == 401) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final data = jsonDecode(res.body);
      return {
        'success': false,
        'message': _extractMessage(data) ?? 'Failed to load verification status.',
      };
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Unable to load verification status.'};
    }
  }

  static Future<Map<String, dynamic>> sendPhoneOtp() async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final requestBody = jsonEncode({'purpose': 'verify'});

      final res = await _sendWithAuthRetry(
        (headers) => http
            .post(
              Uri.parse('$_baseUrl/auth/otp/send'),
              headers: headers,
              body: requestBody,
            )
            .timeout(const Duration(seconds: 15)),
      );


      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        return {'success': true, 'data': data};
      }

      if (res.statusCode == 401) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final data = jsonDecode(res.body);
      return {
        'success': false,
        'message': _extractMessage(data) ?? 'Failed to send verification code.',
      };
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Unable to send verification code.'};
    }
  }

  static Future<Map<String, dynamic>> verifyPhoneOtp(String otp) async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final requestBody = jsonEncode({'otp': otp, 'purpose': 'verify'});

      final res = await _sendWithAuthRetry(
        (headers) => http
            .post(
              Uri.parse('$_baseUrl/auth/otp/verify'),
              headers: headers,
              body: requestBody,
            )
            .timeout(const Duration(seconds: 15)),
      );


      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        return {'success': true, 'data': data};
      }

      if (res.statusCode == 401) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final data = jsonDecode(res.body);
      return {
        'success': false,
        'message': _extractMessage(data) ?? 'Invalid or expired code.',
      };
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Unable to verify code.'};
    }
  }

  static Future<Map<String, dynamic>> sendEmailVerificationLink() async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final res = await _sendWithAuthRetry(
        (headers) => http
            .post(
              Uri.parse('$_baseUrl/auth/email/verify/send'),
              headers: headers,
            )
            .timeout(const Duration(seconds: 15)),
      );


      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        return {'success': true, 'data': data};
      }

      if (res.statusCode == 401) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final data = jsonDecode(res.body);
      return {
        'success': false,
        'message':
            _extractMessage(data) ?? 'Failed to send verification link.',
      };
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Unable to send verification link.'};
    }
  }

  static Future<Map<String, dynamic>> confirmEmailVerification(String token) async {
    try {
      final authToken = await getToken();
      if (authToken == null || authToken.isEmpty) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final requestBody = jsonEncode({'token': token});

      final res = await _sendWithAuthRetry(
        (headers) => http
            .post(
              Uri.parse('$_baseUrl/auth/email/verify'),
              headers: headers,
              body: requestBody,
            )
            .timeout(const Duration(seconds: 15)),
      );


      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        return {'success': true, 'data': data};
      }

      if (res.statusCode == 401) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final data = jsonDecode(res.body);
      return {
        'success': false,
        'message': _extractMessage(data) ?? 'Invalid or expired verification token.',
      };
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Unable to verify email.'};
    }
  }

  static Future<Map<String, dynamic>> getR2PutUrl({
    required String purpose,
    required String mime,
    required int sizeBytes,
  }) async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final uri = Uri.parse('$_baseUrl/uploads/r2-put-url').replace(
        queryParameters: {
          'purpose': purpose,
          'mime': mime,
          'size_bytes': sizeBytes.toString(),
        },
      );

      final res = await _sendWithAuthRetry(
        (headers) => http.get(uri, headers: headers).timeout(const Duration(seconds: 15)),
      );


      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        return {'success': true, 'data': data};
      }

      if (res.statusCode == 401) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final data = jsonDecode(res.body);
      return {
        'success': false,
        'message': _extractMessage(data) ?? 'Failed to prepare file upload.',
      };
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Unable to prepare file upload.'};
    }
  }

  static Future<Map<String, dynamic>> uploadBytesToUrl({
    required String uploadUrl,
    required Map<String, dynamic> headers,
    required Uint8List bytes,
  }) async {
    try {
      final putHeaders = headers.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );

      final res = await http
          .put(Uri.parse(uploadUrl), headers: putHeaders, body: bytes)
          .timeout(const Duration(seconds: 60));


      if (res.statusCode == 200 || res.statusCode == 201 || res.statusCode == 204) {
        return {'success': true};
      }

      return {
        'success': false,
        'message': 'Upload failed (status ${res.statusCode}).',
      };
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Unable to upload file.'};
    }
  }

  static Future<Map<String, dynamic>> submitKycVerification({
    required String nin,
    required String bvn,
    required String dob,
    required String selfieUrl,
  }) async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final requestBody = jsonEncode({
        'level': 2,
        'nin': nin,
        'bvn': bvn,
        'dob': dob,
        'selfie_url': selfieUrl,
      });

      final res = await _sendWithAuthRetry(
        (headers) => http
            .post(
              Uri.parse('$_baseUrl/trust/kyc/submit'),
              headers: headers,
              body: requestBody,
            )
            .timeout(const Duration(seconds: 15)),
      );


      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        return {'success': true, 'data': data};
      }

      if (res.statusCode == 401) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final data = jsonDecode(res.body);
      return {
        'success': false,
        'message':
            _extractMessage(data) ?? 'Failed to submit identity verification.',
      };
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to submit identity verification.',
      };
    }
  }

  static Future<Map<String, dynamic>> initiateTopup({
    required double amount,
    required String paymentMethod,
  }) async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        return {
          'success': false,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final amountKobo = (amount * 100).round();
      final requestBody = jsonEncode({
        'amount_kobo': amountKobo,
        'payment_method': paymentMethod,
      });

      final res = await _sendWithAuthRetry(
        (headers) => http
            .post(
              Uri.parse('$_baseUrl/wallet/topup'),
              headers: headers,
              body: requestBody,
            )
            .timeout(const Duration(seconds: 15)),
      );


      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        return {'success': true, 'data': data};
      }

      if (res.statusCode == 401) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final data = jsonDecode(res.body);
      return {
        'success': false,
        'message': _extractMessage(data) ?? 'Failed to initiate top-up.',
      };
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Unable to initiate top-up.'};
    }
  }

  // GET /api/v1/threads — list chat threads for the authenticated user
  static Future<Map<String, dynamic>> getThreads({
    String? filter,
    int limit = 30,
  }) async {
    final filterKey = (filter == null || filter.isEmpty) ? 'all' : filter;
    try {
      final params = <String, String>{'limit': limit.toString()};
      if (filter != null && filter.isNotEmpty) params['filter'] = filter;
      final uri = Uri.parse('$_baseUrl/threads').replace(queryParameters: params);
      final res = await _sendWithAuthRetry(
        (headers) => http.get(uri, headers: headers).timeout(const Duration(seconds: 15)),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic> threads = (data is List ? data : null) ??
            (data['data'] is List ? data['data'] as List : null) ??
            (data['threads'] is List ? data['threads'] as List : null) ??
            [];
        await _saveThreadsCache(filterKey, threads);
        return {'success': true, 'data': threads};
      }
      if (res.statusCode == 401) return {'success': false, 'auth_required': true};
      return {'success': false, 'message': 'Failed to load messages.'};
    } on SocketException {
      return {'success': false, 'message': 'No internet connection.'};
    } catch (e) {
      return {'success': false, 'message': 'Unable to load messages.'};
    }
  }

  /// Returns the message threads cached for the current account/filter,
  /// or null if nothing has been cached yet. Used to render the messages
  /// screen instantly while a fresh copy loads in the background.
  static Future<List<dynamic>?> getCachedThreads(String? filter) async {
    final filterKey = (filter == null || filter.isEmpty) ? 'all' : filter;
    try {
      final key = await _accountScopedCacheKey('threads_$filterKey');
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(key);
      if (cached == null) return null;
      final data = jsonDecode(cached);
      if (data is List) return data;
    } catch (_) {}
    return null;
  }

  static Future<void> _saveThreadsCache(
    String filterKey,
    List<dynamic> threads,
  ) async {
    try {
      final key = await _accountScopedCacheKey('threads_$filterKey');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(threads));
    } catch (_) {}
  }

  /// Builds a cache key scoped to the currently signed-in account so that
  /// switching between accounts on the same device doesn't leak cached data
  /// (e.g. message threads) between users.
  static Future<String> _accountScopedCacheKey(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_currentAccountEmailKey) ?? 'guest';
    return _cacheKey('${email}_$name');
  }

  // GET /api/v1/threads/{ulid} — get thread metadata (participants, typing status, etc.)
  static Future<Map<String, dynamic>> getThread(String ulid) async {
    try {
      final res = await _sendWithAuthRetry(
        (headers) => http
            .get(Uri.parse('$_baseUrl/threads/$ulid'), headers: headers)
            .timeout(const Duration(seconds: 10)),
      );
      if (res.statusCode == 200) {
        final raw = jsonDecode(res.body);
        final Map<String, dynamic> thread = (raw is Map<String, dynamic> && raw['data'] is Map)
            ? (raw['data'] as Map).cast<String, dynamic>()
            : (raw is Map<String, dynamic> ? raw : <String, dynamic>{});
        return {'success': true, 'data': thread};
      }
      if (res.statusCode == 401) return {'success': false, 'auth_required': true};
      return {'success': false, 'message': 'Failed to load thread.'};
    } on SocketException {
      return {'success': false, 'message': 'No internet connection.'};
    } catch (e) {
      return {'success': false, 'message': 'Unable to load thread.'};
    }
  }

  // POST /api/v1/threads/{ulid}/typing — broadcast a typing indicator to the thread
  static Future<void> sendTypingIndicator(String ulid) async {
    try {
      await _sendWithAuthRetry(
        (headers) => http
            .post(Uri.parse('$_baseUrl/threads/$ulid/typing'), headers: headers)
            .timeout(const Duration(seconds: 5)),
      );
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> getMessages({
    String? threadUlid,
    String? jobUlid,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final params = <String, String>{'limit': limit.toString()};
      if (offset > 0) params['offset'] = offset.toString();
      if (threadUlid != null) params['thread_ulid'] = threadUlid;
      if (jobUlid != null) params['job_ulid'] = jobUlid;
      final uri = Uri.parse('$_baseUrl/messages').replace(queryParameters: params);
      final res = await _sendWithAuthRetry(
        (headers) => http.get(uri, headers: headers).timeout(const Duration(seconds: 15)),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic> messages = (data['data'] is List ? data['data'] as List : null) ??
            (data is List ? data : null) ??
            [];
        return {'success': true, 'data': messages};
      }
      if (res.statusCode == 401) return {'success': false, 'auth_required': true};
      return {'success': false, 'message': 'Failed to load messages.'};
    } on SocketException {
      return {'success': false, 'message': 'No internet connection.'};
    } catch (e) {
      return {'success': false, 'message': 'Unable to load messages.'};
    }
  }

  static Future<Map<String, dynamic>> sendVoiceMessage({
    required Uint8List bytes,
    required String mimeType,
    required int durationSeconds,
    String? threadUlid,
    String? jobUlid,
  }) async {
    // Step 1: get pre-signed upload URL
    print('[VoiceUpload] Step 1 — getR2PutUrl purpose=voice_note mime=$mimeType size=${bytes.length}');
    final signed = await getR2PutUrl(
      purpose: 'voice_note',
      mime: mimeType,
      sizeBytes: bytes.length,
    );
    print('[VoiceUpload] R2 response => $signed');
    if (signed['success'] != true) return signed;

    final uploadInfo = signed['data'] is Map
        ? Map<String, dynamic>.from(signed['data'] as Map)
        : <String, dynamic>{};
    final uploadUrl = (uploadInfo['upload_url'] ?? '').toString();
    final objectUrl =
        (uploadInfo['object_url'] ?? uploadInfo['object_key'] ?? '').toString();
    final uploadHeaders = uploadInfo['headers'] is Map
        ? Map<String, dynamic>.from(uploadInfo['headers'] as Map)
        : <String, dynamic>{'Content-Type': mimeType};

    print('[VoiceUpload] upload_url=$uploadUrl  object_url=$objectUrl');

    if (uploadUrl.isEmpty) {
      return {'success': false, 'message': 'Failed to get upload URL.'};
    }

    // Step 2: upload the bytes
    print('[VoiceUpload] Step 2 — uploading ${bytes.length} bytes');
    final uploaded = await uploadBytesToUrl(
      uploadUrl: uploadUrl,
      headers: uploadHeaders,
      bytes: bytes,
    );
    print('[VoiceUpload] Upload result => $uploaded');
    if (uploaded['success'] != true) return uploaded;

    // Step 3: post the message with the URL + duration
    print('[VoiceUpload] Step 3 — sendMessage kind=voice url=$objectUrl duration=${durationSeconds}s');
    try {
      final payload = <String, dynamic>{
        'kind': 'voice',
        'voice_note_url': objectUrl,
        'duration_seconds': durationSeconds,
      };
      if (threadUlid != null) payload['thread_ulid'] = threadUlid;
      if (jobUlid != null) payload['job_ulid'] = jobUlid;

      final res = await _sendWithAuthRetry(
        (headers) => http
            .post(
              Uri.parse('$_baseUrl/messages'),
              headers: {...headers, 'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 20)),
      );
      print('[VoiceUpload] sendMessage status=${res.statusCode} body=${res.body}');
      if (res.statusCode == 200 || res.statusCode == 201) {
        return {'success': true, 'data': jsonDecode(res.body)};
      }
      if (res.statusCode == 401) {
        return {'success': false, 'auth_required': true, 'message': 'Authentication required.'};
      }
      final data = jsonDecode(res.body);
      return {'success': false, 'message': _extractMessage(data) ?? 'Failed to send voice message.'};
    } on SocketException {
      return {'success': false, 'message': 'No internet connection.'};
    } catch (e) {
      print('[VoiceUpload] sendMessage ERROR: $e');
      return {'success': false, 'message': 'Failed to send voice message.'};
    }
  }

  static Future<Map<String, dynamic>> sendMessage({
    required String body,
    String? threadUlid,
    String? jobUlid,
    String kind = 'text',
  }) async {
    try {
      final payload = <String, dynamic>{'kind': kind, 'body': body};
      if (threadUlid != null) payload['thread_ulid'] = threadUlid;
      if (jobUlid != null) payload['job_ulid'] = jobUlid;
      final res = await _sendWithAuthRetry(
        (headers) => http
            .post(
              Uri.parse('$_baseUrl/messages'),
              headers: {...headers, 'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 20)),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        return {'success': true, 'data': data};
      }
      if (res.statusCode == 401) return {'success': false, 'auth_required': true};
      final data = jsonDecode(res.body);
      return {'success': false, 'message': _extractMessage(data) ?? 'Failed to send message.'};
    } on SocketException {
      return {'success': false, 'message': 'No internet connection.'};
    } catch (e) {
      return {'success': false, 'message': 'Request timed out. Please try again.'};
    }
  }

  static Future<void> markThreadRead(String threadUlid) async {
    try {
      await _sendWithAuthRetry(
        (headers) => http
            .post(Uri.parse('$_baseUrl/threads/$threadUlid/read'), headers: headers)
            .timeout(const Duration(seconds: 10)),
      );
    } catch (_) {}
  }

  static Future<void> markMessageRead(String messageUlid) async {
    try {
      await _sendWithAuthRetry(
        (headers) => http
            .post(Uri.parse('$_baseUrl/messages/$messageUlid/read'), headers: headers)
            .timeout(const Duration(seconds: 10)),
      );
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> getOrCreateDirectThread(String providerUlid) async {
    try {
      await switchRole('customer');
      final res = await _sendWithAuthRetry(
        (headers) => http
            .post(
              Uri.parse('$_baseUrl/threads'),
              headers: {...headers, 'Content-Type': 'application/json'},
              body: jsonEncode({'provider_ulid': providerUlid}),
            )
            .timeout(const Duration(seconds: 20)),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        final raw = jsonDecode(res.body);
        // Unwrap common response envelope: {data: {ulid:...}} → {ulid:...}
        final Map<String, dynamic> thread;
        if (raw is Map<String, dynamic> && raw['data'] is Map) {
          thread = (raw['data'] as Map).cast<String, dynamic>();
        } else if (raw is Map<String, dynamic>) {
          thread = raw;
        } else {
          thread = <String, dynamic>{};
        }
        return {'success': true, 'data': thread};
      }
      if (res.statusCode == 401) return {'success': false, 'auth_required': true};
      final data = jsonDecode(res.body);
      return {'success': false, 'message': _extractMessage(data) ?? 'Failed to start conversation.'};
    } on SocketException {
      return {'success': false, 'message': 'No internet connection.'};
    } catch (e) {
      return {'success': false, 'message': 'Request timed out. Please try again.'};
    }
  }

  static Future<Map<String, dynamic>> getTopupStatus(String reference) async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        return {
          'success': false,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final res = await _sendWithAuthRetry(
        (headers) => http
            .get(
              Uri.parse('$_baseUrl/wallet/topups/$reference'),
              headers: headers,
            )
            .timeout(const Duration(seconds: 15)),
      );


      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return {'success': true, 'data': data};
      }

      if (res.statusCode == 401) {
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final data = jsonDecode(res.body);
      return {
        'success': false,
        'message': _extractMessage(data) ?? 'Failed to load top-up status.',
      };
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Unable to load top-up status.'};
    }
  }

}
