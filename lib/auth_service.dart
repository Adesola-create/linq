import 'dart:convert';
import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _baseUrl = 'https://api.linq.ng/api/v1';
  static const String _tokenExpiryKey = 'token_expiry';

  static final _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);
  static String? _cachedToken;
  static int? _cachedTokenExpiryMs;

  static Future<Map<String, dynamic>> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null)
        return {'success': false, 'message': 'Google sign-in was cancelled.'};

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;

      print('[AuthService] GOOGLE id_token: $idToken');

      // Send token to backend
      final res = await http
          .post(
            Uri.parse('$_baseUrl/auth/google'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'id_token': idToken}),
          )
          .timeout(const Duration(seconds: 15));

      print('[AuthService] GOOGLE status: ${res.statusCode}');
      print('[AuthService] GOOGLE response: ${res.body}');

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 || res.statusCode == 201) {
        await _saveSession(data);
        return {'success': true, 'role': _extractRole(data)};
      }
      final msg = _extractMessage(data) ?? '';
      print('[AuthService] GOOGLE failed: $msg');
      return {
        'success': false,
        'message': 'Google sign-in failed. Please try again.',
      };
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } catch (e) {
      print('[AuthService] GOOGLE error: $e');
      return {
        'success': false,
        'message': 'Google sign-in failed. Please try again.',
      };
    }
  }

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final requestBody = jsonEncode({'email': email, 'password': password});
      print('[AuthService] LOGIN → $_baseUrl/auth/login');
      print('[AuthService] LOGIN body: $requestBody');

      final res = await http
          .post(
            Uri.parse('$_baseUrl/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: requestBody,
          )
          .timeout(const Duration(seconds: 15));

      print('[AuthService] LOGIN status: ${res.statusCode}');
      print('[AuthService] LOGIN response: ${res.body}');

      final data = jsonDecode(res.body);

      if (res.statusCode == 200) {
        await _saveSession(data);
        return {'success': true, 'role': _extractRole(data)};
      }

      final rawMessage = _extractMessage(data) ?? '';
      print('[AuthService] LOGIN failed: $rawMessage');
      return {
        'success': false,
        'message': rawMessage.isNotEmpty
            ? rawMessage
            : _friendlyLoginError(res.statusCode),
      };
    } on SocketException catch (e) {
      print('[AuthService] LOGIN SocketException: $e');
      return {
        'success': false,
        'message':
            'No internet connection. Please check your network and try again.',
      };
    } on HttpException catch (e) {
      print('[AuthService] LOGIN HttpException: $e');
      return {
        'success': false,
        'message': 'Unable to reach the server. Please try again later.',
      };
    } catch (e) {
      print('[AuthService] LOGIN error: $e');
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
      print('[AuthService] REGISTER → $_baseUrl/auth/register');
      print('[AuthService] REGISTER body: $requestBody');

      final res = await http
          .post(
            Uri.parse('$_baseUrl/auth/register'),
            headers: {'Content-Type': 'application/json'},
            body: requestBody,
          )
          .timeout(const Duration(seconds: 15));

      print('[AuthService] REGISTER status: ${res.statusCode}');
      print('[AuthService] REGISTER response: ${res.body}');

      final data = jsonDecode(res.body);

      if (res.statusCode == 200 || res.statusCode == 201) {
        await _saveSession(data);
        return {'success': true, 'role': _extractRole(data) ?? role};
      }

      final rawMessage = _extractMessage(data) ?? '';
      print('[AuthService] REGISTER failed: $rawMessage');
      return {
        'success': false,
        'message': _friendlyRegisterError(res.statusCode, data),
      };
    } on SocketException catch (e) {
      print('[AuthService] REGISTER SocketException: $e');
      return {
        'success': false,
        'message':
            'No internet connection. Please check your network and try again.',
      };
    } on HttpException catch (e) {
      print('[AuthService] REGISTER HttpException: $e');
      return {
        'success': false,
        'message': 'Unable to reach the server. Please try again later.',
      };
    } catch (e) {
      print('[AuthService] REGISTER error: $e');
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
              messages.add('An account with this email already exists. Please log in.');
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
        if (raw.contains('exist') || raw.contains('already') || raw.contains('taken') || raw.contains('in use')) {
          return 'An account with this email already exists. Please log in.';
        }
        if (raw.contains('valid') || raw.contains('format') || raw.contains('invalid')) {
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
    final prefs = await SharedPreferences.getInstance();

    print('[AuthService] _saveSession: Response keys: ${data.keys.toList()}');
    if (data['data'] is Map) {
      print(
        '[AuthService] _saveSession: data.data keys: ${(data['data'] as Map).keys.toList()}',
      );
    }

    final payload = _asStringKeyedMap(data['data']);
    final user =
        _asStringKeyedMap(payload?['user']) ?? _asStringKeyedMap(data['user']);

    final token = _extractToken(data);
    final refreshToken = _extractRefreshToken(data);

    print('[AuthService] _saveSession: access token found: ${token != null && token.isNotEmpty}');
    print('[AuthService] _saveSession: refresh token found: ${refreshToken != null && refreshToken.isNotEmpty}');
    // Log all top-level keys and data keys to help diagnose missing refresh token
    print('[AuthService] _saveSession: full data keys: ${data.keys.toList()}');
    if (payload != null) print('[AuthService] _saveSession: payload keys: ${payload.keys.toList()}');
    if (user != null) print('[AuthService] _saveSession: user keys: ${user.keys.toList()}');

    final role =
        _toString(user?['role']) ??
        _toString(payload?['role']) ??
        _toString(data['role']);

    print(
      '[AuthService] _saveSession: Token length: ${token?.length ?? 0}, Role: ${role ?? 'null'}',
    );

    if (token != null && token.isNotEmpty) {
      final trimmedToken = _normalizeToken(token);
      if (trimmedToken.isNotEmpty) {
        await prefs.setString('token', trimmedToken);
        _cachedToken = trimmedToken;
        print('[AuthService] _saveSession: Token saved (${trimmedToken.length} chars)');

        final expiresAt = _extractTokenExpiry(trimmedToken);
        if (expiresAt != null) {
          await prefs.setInt(_tokenExpiryKey, expiresAt.millisecondsSinceEpoch);
          _cachedTokenExpiryMs = expiresAt.millisecondsSinceEpoch;
          print('[AuthService] _saveSession: Token expiry saved at $expiresAt');
        } else {
          await prefs.remove(_tokenExpiryKey);
          _cachedTokenExpiryMs = null;
          print('[AuthService] _saveSession: Token expiry not available');
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
      print('[AuthService] _saveSession: No token found in response');
    }

    if (refreshToken != null && refreshToken.isNotEmpty) {
      final trimmedRefreshToken = _normalizeToken(refreshToken);
      if (trimmedRefreshToken.isNotEmpty) {
        await prefs.setString('refresh_token', trimmedRefreshToken);
        print('[AuthService] _saveSession: Refresh token saved (${trimmedRefreshToken.length} chars)');
      }
    } else {
      print('[AuthService] _saveSession: No refresh token in response — server may not issue one');
    }

    if (role != null && role.isNotEmpty) {
      final normalizedRole = role.trim();
      await prefs.setString('role', normalizedRole);
      await prefs.setString(_activeRoleKey, normalizedRole);
      await prefs.setString(_lastAccountModeKey, normalizedRole);
      print('[AuthService] _saveSession: Active role set to: $normalizedRole');
      print('[AuthService] _saveSession: Role saved: $normalizedRole');
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
        print('[AuthService] Profile cache saved');
      } catch (e) {
        print('[AuthService] Failed to cache profile: $e');
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
          values.addAll(value
              .map((item) => _toString(item))
              .where((text) => text != null && text.isNotEmpty)
              .cast<String>());
        } else if (value != null) {
          final text = _toString(value);
          if (text != null && text.isNotEmpty) values.add(text);
        }
        if (values.isNotEmpty) {
          final fieldName = entry.key.toString().replaceAll('_', ' ');
          detailMessages.add(
            '${fieldName[0].toUpperCase()}${fieldName.substring(1)}: ${values.join(', ')}',
          );
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
      print('[AuthService] GET JOB DETAILS status: ${res.statusCode}');
      print('[AuthService] GET JOB DETAILS response: ${res.body}');
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
      print('[AuthService] GET JOB DETAILS error: $e');
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
      final token = await getToken();
      if (token == null || token.isEmpty) {
        print('[AuthService] switchRole: No token available');
        return {
          'success': false,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final headers = await _getAuthHeaders();
      final requestBody = jsonEncode({'role': newRole});

      print('[AuthService] SWITCH ROLE → $_baseUrl/auth/switch-role');
      print('[AuthService] SWITCH ROLE body: $requestBody');

      final res = await _sendWithAuthRetry(
        (headers) => http
            .post(
              Uri.parse('$_baseUrl/auth/switch-role'),
              headers: headers,
              body: requestBody,
            )
            .timeout(const Duration(seconds: 15)),
      );

      print('[AuthService] SWITCH ROLE status: ${res.statusCode}');
      print('[AuthService] SWITCH ROLE response: ${res.body}');

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        
        // Update local active role
        await setActiveRole(newRole);
        
        // Update profile cache if returned in response
        if (data['data'] is Map || data['user'] is Map) {
          await _saveSession(data);
        }

        print('[AuthService] SWITCH ROLE: Successfully switched to $newRole');
        return {
          'success': true,
          'message': 'Role switched successfully',
          'role': newRole,
          'data': data,
        };
      }

      if (res.statusCode == 401) {
        print('[AuthService] SWITCH ROLE: 401 Unauthorized - Clearing session');
        await _clearStoredSession();
        return {
          'success': false,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final data = jsonDecode(res.body);
      final msg = _extractMessage(data) ?? 'Failed to switch role.';
      return {
        'success': false,
        'message': msg,
      };
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } catch (e) {
      print('[AuthService] SWITCH ROLE error: $e');
      return {'success': false, 'message': 'Unable to switch role.'};
    }
  }

  /// Get the currently active role (user's current operating role)
  /// Returns the role the user is currently operating as
  static const String _activeRoleKey = 'active_role';
  static const String _lastAccountModeKey = 'last_account_mode';

  static Future<String?> getActiveRole() async {
    final prefs = await SharedPreferences.getInstance();
    final activeRole = prefs.getString(_activeRoleKey);
    if (activeRole == null || activeRole.trim().isEmpty) {
      // Fallback to stored role if active_role not set
      return await getRole();
    }
    return activeRole.trim();
  }

  static Future<String?> getLastAccountMode() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMode = prefs.getString(_lastAccountModeKey);
    if (lastMode == null || lastMode.trim().isEmpty) {
      return null;
    }
    return lastMode.trim();
  }

  /// Set the active role (used after successful role switch)
  static Future<void> setActiveRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    if (role.isNotEmpty) {
      final normalized = role.trim();
      await prefs.setString(_activeRoleKey, normalized);
      await prefs.setString(_lastAccountModeKey, normalized);
      print('[AuthService] setActiveRole: Active role set to $normalized');
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

  static Future<void> _clearStoredSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('refresh_token');
    await prefs.remove(_tokenExpiryKey);
    await prefs.remove('role');
    await prefs.remove('active_role');
    await prefs.remove('profile');
    await prefs.remove('user_lat');
    await prefs.remove('user_lng');
    _cachedToken = null;
    _cachedTokenExpiryMs = null;
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
        print('[AuthService] getProfile: No token available');
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
      print('[AuthService] GET PROFILE status: ${res.statusCode}');
      print('[AuthService] GET PROFILE response: ${res.body}');
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        Map<String, dynamic> savedProfile = decoded;
        if (prefs.getString('profile') != null) {
          try {
            final cached = jsonDecode(prefs.getString('profile')!) as Map<String, dynamic>;
            savedProfile = _mergeProfileCache(cached, decoded, {});
            print('[AuthService] Profile cache merged with /me response');
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
        print(
          '[AuthService] Profile cache updated with /me response: $savedProfile',
        );
        return {'success': true, 'data': savedProfile};
      }
      if (res.statusCode == 401) {
        await _clearStoredSession();
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
      print('[AuthService] GET PROFILE error: $e');
      return {'success': false, 'message': 'Unable to load profile.'};
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
      print('[AuthService] Cached provider images for $ulid');
    } catch (e) {
      print('[AuthService] Error caching provider images: $e');
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
      print('[AuthService] Error reading provider images: $e');
    }
    return null;
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
      print(
        '[AuthService] Cached ${providers.length} provider records with images',
      );
    } catch (e) {
      print('[AuthService] Error caching providers list: $e');
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
      print('[AuthService] Error reading providers list: $e');
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

      final token = await getToken();
      print(
        '[AuthService] GET CUSTOMER JOBS token: ${token != null ? 'present (${token.length} chars)' : 'null'}',
      );

      final res = await _sendWithAuthRetry(
        (headers) => http
            .get(Uri.parse('$_baseUrl/customer/jobs'), headers: headers)
            .timeout(const Duration(seconds: 15)),
      );

      print('[AuthService] GET CUSTOMER JOBS status: ${res.statusCode}');
      print('[AuthService] GET CUSTOMER JOBS response: ${res.body}');

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        print('[AuthService] GET CUSTOMER JOBS decoded keys: ${data is Map ? (data as Map).keys.toList() : "is List"}');
        final List<dynamic> raw =
            (data is List ? data : null) ??
            (data['data'] is List ? data['data'] : null) ??
            (data['jobs'] is List ? data['jobs'] : null) ??
            [];
        print('[AuthService] GET CUSTOMER JOBS extracted ${raw.length} items');
        if (raw.isNotEmpty) {
          print('[AuthService] GET CUSTOMER JOBS first item keys: ${(raw.first as Map).keys.toList()}');
          print('[AuthService] GET CUSTOMER JOBS first item status: ${(raw.first as Map)["status"]}');
        }
        await _saveCache(cacheKey, raw);
        return {'success': true, 'data': raw};
      }

      if (res.statusCode == 401) {
        print(
          '[AuthService] GET CUSTOMER JOBS: 401 Unauthorized - Token cleared',
        );
        await _clearStoredSession();
        return {
          'success': false,
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
      print('[AuthService] GET CUSTOMER JOBS error: $e');
      return {'success': false, 'message': 'Unable to load jobs.'};
    }
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

      print('[AuthService] GET JOBS status: ${res.statusCode}');
      print('[AuthService] GET JOBS response: ${res.body}');

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
        await _clearStoredSession();
        return {
          'success': false,
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
      print('[AuthService] GET JOBS error: $e');
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

      print('[AuthService] GET PROVIDER JOBS status: ${res.statusCode}');
      print('[AuthService] GET PROVIDER JOBS response: ${res.body}');

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
        await _clearStoredSession();
        return {
          'success': false,
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
      print('[AuthService] GET PROVIDER JOBS error: $e');
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
        print('[AuthService] updateProfile: No token available');
        return {
          'success': false,
          'message': 'Authentication required. Please log in again.',
        };
      }

      // Map UI fields to API structure
      final apiFields = _mapProfileFieldsToApi(fields);

      final bool useMultipart = _containsLocalImages(fields);
      final http.Response res = useMultipart
          ? await _sendMultipartProfileUpdate(apiFields)
          : await _sendWithAuthRetry(
              (headers) => http
                  .patch(
                    Uri.parse('$_baseUrl/provider/profile'),
                    headers: headers,
                    body: jsonEncode(apiFields),
                  )
                  .timeout(const Duration(seconds: 15)),
            );

      print('[AuthService] UPDATE PROFILE status: ${res.statusCode}');
      print('[AuthService] UPDATE PROFILE response: ${res.body}');
      if (res.statusCode == 200 || res.statusCode == 201) {
        final prefs = await SharedPreferences.getInstance();
        final cached = prefs.getString('profile');
        final Map<String, dynamic> localCache =
            cached != null ? jsonDecode(cached) as Map<String, dynamic> : {};

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
        print('[AuthService] Profile cache updated: ${jsonEncode(updatedCache)}');
        return {'success': true};
      }

      if (res.statusCode == 401) {
        print('[AuthService] UPDATE PROFILE: 401 Unauthorized - Token cleared');
        await _clearStoredSession();
        return {
          'success': false,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final data = jsonDecode(res.body);
      return {
        'success': false,
        'message': _extractMessage(data) ?? 'Failed to update profile.',
      };
    } catch (e) {
      print('[AuthService] UPDATE PROFILE error: $e');
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
      print('[AuthService] getToken: returning stored token');
      return normalized;
    } else if (token != null) {
      // Remove empty token
      await prefs.remove('token');
      print('[AuthService] getToken: removed empty token');
    }

    final cachedProfile = prefs.getString('profile');
    if (cachedProfile != null) {
      try {
        final profile = jsonDecode(cachedProfile) as Map<String, dynamic>;
        final candidate = _extractToken(profile);
        if (candidate != null && candidate.trim().isNotEmpty) {
          print('[AuthService] getToken: returning token from cached profile');
          final normalized = _normalizeToken(candidate);
          await prefs.setString('token', normalized);
          _cachedToken = normalized;
          return normalized;
        }
      } catch (_) {
        // ignore malformed cached profile
      }
    }

    print('[AuthService] getToken: no token found');
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
  static Future<bool> _isAccessTokenExpired({Duration buffer = const Duration(seconds: 30)}) async {
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
    return DateTime.now().isAfter(DateTime.fromMillisecondsSinceEpoch(expiryMs).subtract(buffer));
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
        return DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000, isUtc: true);
      }
    } catch (_) {
      // ignore invalid token format
    }
    return null;
  }

  static Future<Map<String, String>> _getAuthHeaders() async {
    final token = await getToken();

    if (token == null || token.isEmpty) {
      print('[AuthService] _getAuthHeaders: No token available!');
      return {'Content-Type': 'application/json'};
    }

    final trimmedToken = _normalizeToken(token);
    if (trimmedToken.isEmpty) {
      print('[AuthService] _getAuthHeaders: Token is empty after trim!');
      return {'Content-Type': 'application/json'};
    }

    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-Requested-With': 'XMLHttpRequest',
      'Authorization': 'Bearer $trimmedToken',
    };

    // Log token info for debugging (length only, not actual token)
    print(
      '[AuthService] _getAuthHeaders: Token present (${trimmedToken.length} chars) - Authorization header set',
    );

    return headers;
  }

  static Future<bool> _refreshAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = await _getRefreshToken();
    final accessToken = await getToken();

    if (refreshToken == null || refreshToken.trim().isEmpty) {
      print('[AuthService] REFRESH TOKEN: no refresh token available to refresh');
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

        print(
          '[AuthService] REFRESH TOKEN → $_baseUrl/auth/refresh (${attempt['label']})',
        );
        final res = await http
            .post(
              Uri.parse('$_baseUrl/auth/refresh'),
              headers: headers,
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 15));

        print('[AuthService] REFRESH TOKEN status: ${res.statusCode}');
        print('[AuthService] REFRESH TOKEN response: ${res.body}');

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
            await prefs.setInt(_tokenExpiryKey, expiresAt.millisecondsSinceEpoch);
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
      print('[AuthService] REFRESH TOKEN error: $e');
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
    if (await _isAccessTokenExpired()) {
      print('[AuthService] Access token expired or near expiry; refreshing before request');
      await _refreshAccessToken();
    }

    var headers = await _getAuthHeaders();
    var res = await send(headers);

    if (res.statusCode != 401) return res;

    print('[AuthService] Request returned 401; attempting token refresh');
    final refreshed = await _refreshAccessToken();
    if (!refreshed) {
      print('[AuthService] Token refresh failed — clearing session');
      await _clearStoredSession();
      return res;
    }

    print('[AuthService] Token refresh succeeded; retrying request');
    headers = await _getAuthHeaders();
    return send(headers);
  }

  static Future<http.Response> _sendStreamedWithAuthRetry(
    Future<http.StreamedResponse> Function(Map<String, String> headers) send,
  ) async {
    if (await _isAccessTokenExpired()) {
      print('[AuthService] Access token expired or near expiry; refreshing before streamed request');
      await _refreshAccessToken();
    }

    var headers = await _getAuthHeaders();
    var streamed = await send(headers);
    var res = await http.Response.fromStream(streamed);

    if (res.statusCode != 401) return res;

    print('[AuthService] Streamed request returned 401; attempting token refresh');
    final refreshed = await _refreshAccessToken();
    if (!refreshed) {
      print('[AuthService] Token refresh failed — clearing session');
      await _clearStoredSession();
      return res;
    }

    print('[AuthService] Token refresh succeeded; retrying streamed request');
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

    // Map avatar to profile_photo_url
    if (uiFields['avatar'] != null) {
      api['profile_photo_url'] = uiFields['avatar'];
    }

    // Map services to category_slugs
    if (uiFields['services'] is List) {
      api['category_slugs'] = uiFields['services'];
    }

    // Map location to workshop_address
    if (uiFields['location'] != null) {
      api['workshop_address'] = uiFields['location'];
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
      final dayNames = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
      
      for (final entry in availMap.entries) {
        final dayIdx = entry.key as int?;
        final ranges = entry.value as List?;
        if (dayIdx != null && dayIdx >= 1 && dayIdx <= 7 && ranges != null && ranges.isNotEmpty) {
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
    if (trimmed.toLowerCase().startsWith('http')) return false;
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
    Map<String, dynamic> fields,
  ) async {
    return _sendStreamedWithAuthRetry((headers) async {
      final request = http.MultipartRequest('PATCH', Uri.parse('$_baseUrl/provider/profile'));
      request.headers.addAll(headers);

      for (final entry in fields.entries) {
        final key = entry.key;
        final value = entry.value;

        if (key == 'profile_photo_url' && value is String && _isLocalImagePath(value)) {
          request.files.add(await http.MultipartFile.fromPath('profile_photo_url', value));
          continue;
        }

        if (key == 'gallery_photos' && value is List) {
          final remotePhotos = <String>[];
          for (final photo in value) {
            final path = photo?.toString() ?? '';
            if (_isLocalImagePath(path)) {
              request.files.add(await http.MultipartFile.fromPath('gallery_photos[]', path));
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
      return await request.send();
    });
  }

  static Map<String, dynamic> _mergeProfileCache(
    Map<String, dynamic> cached,
    Map<String, dynamic> responseData,
    Map<String, dynamic> fields,
  ) {
    final merged = Map<String, dynamic>.from(cached);
    final Map<String, dynamic> target =
        merged['user'] is Map<String, dynamic>
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
        if (entry.key == 'avatar' && _isLocalImagePath(entry.value?.toString())) {
          continue;
        }
        if (entry.key == 'photos' && entry.value is List) {
          final photos = entry.value as List;
          final hasLocalPaths = photos.any((p) => _isLocalImagePath(p?.toString()));
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
          print(
            '[AuthService] Returning cached providers (${cached.length} items)',
          );
          return {'success': true, 'data': cached, 'fromCache': true};
        }
      }

      final uri = Uri.parse('$_baseUrl/providers').replace(
        queryParameters: {
          if (lat != null) 'lat': lat.toString(),
          if (lng != null) 'lng': lng.toString(),
        },
      );
      print('[AuthService] GET PROVIDERS → $uri');
      final res = await _sendWithAuthRetry(
        (headers) => http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 15)),
      );
      if (res.statusCode == 401) {
        await _clearStoredSession();
        print('[AuthService] GET PROVIDERS: 401 Unauthorized - Token cleared');
      }
      print('[AuthService] GET PROVIDERS status: ${res.statusCode}');
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
          print('[AuthService] Cached ${raw.length} providers with images');
        }
        return {'success': true, 'data': raw};
      }
      return {'success': false, 'message': 'Failed to load providers.'};
    } on SocketException {
      return {'success': false, 'message': 'No internet connection.'};
    } catch (e) {
      print('[AuthService] GET PROVIDERS error: $e');
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
      print('[AuthService] GET CATEGORIES → ${res.statusCode}: ${res.body}');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic> raw =
            (data is List ? data : null) ??
            (data['data'] is List ? data['data'] : null) ??
            (data['categories'] is List ? data['categories'] : null) ??
            [];
        await _saveCache(cacheKey, raw);
        if (raw.isNotEmpty) {
          print(
            '[AuthService] GET CATEGORIES raw first item keys: ${(raw.first as Map).keys.toList()}',
          );
          print('[AuthService] GET CATEGORIES raw first item: ${raw.first}');
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
      print('[AuthService] GET CATEGORIES error: $e');
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
          print('[AuthService] Returning cached provider profile for $ulid');
          return {'success': true, 'data': cached, 'fromCache': true};
        }
      }

      final res = await _sendWithAuthRetry(
        (headers) => http
            .get(Uri.parse('$_baseUrl/providers/$ulid'), headers: headers)
            .timeout(const Duration(seconds: 15)),
      );
      print('[AuthService] GET PROVIDER PROFILE status: ${res.statusCode}');
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

        print('[AuthService] Cached provider profile for $ulid');
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
      print('[AuthService] GET PROVIDER PROFILE error: $e');
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
      print('[AuthService] GET PROVIDERS BY SUBCATEGORY → $uri');
      final res = await _sendWithAuthRetry(
        (headers) => http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 15)),
      );
      print(
        '[AuthService] GET PROVIDERS BY SUBCATEGORY status: ${res.statusCode}',
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
      print('[AuthService] GET PROVIDERS BY SUBCATEGORY error: $e');
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
        print('[AuthService] createJobDraft: No token available');
        return {
          'success': false,
          'message': 'Authentication required. Please log in again.',
        };
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

      print('[AuthService] CREATE JOB DRAFT → $_baseUrl/jobs');
      print('[AuthService] CREATE JOB DRAFT body: $requestBody');

      final res = await _sendWithAuthRetry(
        (headers) => http
            .post(
              Uri.parse('$_baseUrl/jobs'),
              headers: headers,
              body: requestBody,
            )
            .timeout(const Duration(seconds: 15)),
      );

      print('[AuthService] CREATE JOB DRAFT status: ${res.statusCode}');
      print('[AuthService] CREATE JOB DRAFT response: ${res.body}');

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        await _clearCache('customer_jobs');
        return {'success': true, 'data': data};
      }

      if (res.statusCode == 401) {
        await _clearStoredSession();
        return {
          'success': false,
          'auth_required': true,
          'message': 'Authentication required. Please log in again.',
        };
      }

      final data = jsonDecode(res.body);
      return {
        'success': false,
        'message': _extractMessage(data) ?? 'Failed to create job draft.',
      };
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection. Please check your network.',
      };
    } catch (e) {
      print('[AuthService] CREATE JOB DRAFT error: $e');
      return {'success': false, 'message': 'Unable to create job draft.'};
    }
  }

  static Future<Map<String, dynamic>> publishJob(String jobUlid) async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        print('[AuthService] publishJob: No token available');
        return {
          'success': false,
          'message': 'Authentication required. Please log in again.',
        };
      }

      print('[AuthService] PUBLISH JOB → $_baseUrl/jobs/$jobUlid/publish');

      final res = await _sendWithAuthRetry(
        (headers) => http
            .post(
              Uri.parse('$_baseUrl/jobs/$jobUlid/publish'),
              headers: headers,
              body: jsonEncode({}),
            )
            .timeout(const Duration(seconds: 15)),
      );

      print('[AuthService] PUBLISH JOB status: ${res.statusCode}');
      print('[AuthService] PUBLISH JOB response: ${res.body}');

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        await _clearCache('customer_jobs');
        return {'success': true, 'data': data};
      }

      if (res.statusCode == 401) {
        await _clearStoredSession();
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
      print('[AuthService] PUBLISH JOB error: $e');
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
        print('[AuthService] hireProvider: No token available');
        return {
          'success': false,
          'message': 'Authentication required. Please log in again.',
        };
      }

      print(
        '[AuthService] HIRE PROVIDER → $_baseUrl/jobs/$jobUlid/hire/$applicationUlid',
      );

      final res = await _sendWithAuthRetry(
        (headers) => http
            .post(
              Uri.parse('$_baseUrl/jobs/$jobUlid/hire/$applicationUlid'),
              headers: headers,
            )
            .timeout(const Duration(seconds: 15)),
      );

      print('[AuthService] HIRE PROVIDER status: ${res.statusCode}');
      print('[AuthService] HIRE PROVIDER response: ${res.body}');

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
      print('[AuthService] HIRE PROVIDER error: $e');
      return {'success': false, 'message': 'Unable to hire provider.'};
    }
  }

  // ── WALLET OPERATIONS ────────────────────────────────────────────

  static Future<Map<String, dynamic>> getWalletBalance() async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        print('[AuthService] getWalletBalance: No token available');
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

      print('[AuthService] GET WALLET status: ${res.statusCode}');
      print('[AuthService] GET WALLET response: ${res.body}');

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        print('[AuthService] GET WALLET decoded: $data');
        return {'success': true, 'data': data};
      }

      if (res.statusCode == 401) {
        print(
          '[AuthService] GET WALLET: 401 Unauthorized - Token may be invalid or expired',
        );
        await _clearStoredSession();
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
      print('[AuthService] GET WALLET error: $e');
      return {'success': false, 'message': 'Unable to load wallet balance.'};
    }
  }

  static Future<Map<String, dynamic>> getTransactions({
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        print('[AuthService] getTransactions: No token available');
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
                  'limit': limit.toString(),
                  'offset': offset.toString(),
                },
              ),
              headers: headers,
            )
            .timeout(const Duration(seconds: 15)),
      );

      print('[AuthService] GET TRANSACTIONS status: ${res.statusCode}');
      print('[AuthService] GET TRANSACTIONS response: ${res.body}');

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return {'success': true, 'data': data};
      }

      if (res.statusCode == 401) {
        print(
          '[AuthService] GET TRANSACTIONS: 401 Unauthorized - Token may be invalid or expired',
        );
        await _clearStoredSession();
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
      print('[AuthService] GET TRANSACTIONS error: $e');
      return {'success': false, 'message': 'Unable to load transactions.'};
    }
  }

  static Future<Map<String, dynamic>> initiateTopup({
    required double amount,
    required String paymentMethod,
  }) async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        print('[AuthService] initiateTopup: No token available');
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

      print('[AuthService] TOPUP status: ${res.statusCode}');
      print('[AuthService] TOPUP response: ${res.body}');

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        return {'success': true, 'data': data};
      }

      if (res.statusCode == 401) {
        await _clearStoredSession();
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
      print('[AuthService] TOPUP error: $e');
      return {'success': false, 'message': 'Unable to initiate top-up.'};
    }
  }

  static Future<Map<String, dynamic>> getTopupStatus(String reference) async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) {
        print('[AuthService] getTopupStatus: No token available');
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

      print('[AuthService] TOPUP STATUS status: ${res.statusCode}');
      print('[AuthService] TOPUP STATUS response: ${res.body}');

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return {'success': true, 'data': data};
      }

      if (res.statusCode == 401) {
        await _clearStoredSession();
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
      print('[AuthService] TOPUP STATUS error: $e');
      return {'success': false, 'message': 'Unable to load top-up status.'};
    }
  }
}
