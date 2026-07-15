$file = 'c:\flutterapp\linq\lib\auth_service.dart'
$content = Get-Content $file -Raw

# Find the line number where saved providers section starts
$lines = Get-Content $file
$startLine = 0
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'SAVED PROVIDERS OPERATIONS') {
        $startLine = $i
        break
    }
}

# Keep everything before the saved providers section
$before = ($lines[0..($startLine-1)] -join "`r`n")

$newSection = @'
  // -- SAVED PROVIDERS --

  static Future<bool> saveProvider(String providerUlid) async {
    try {
      final res = await _sendWithAuthRetry(
        (headers) => http
            .post(
              Uri.parse('$_baseUrl/customer/saved-providers/$providerUlid'),
              headers: headers,
            )
            .timeout(const Duration(seconds: 15)),
      );
      print('[AuthService] SAVE PROVIDER status: ${res.statusCode}');
      print('[AuthService] SAVE PROVIDER response: ${res.body}');
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      print('[AuthService] SAVE PROVIDER error: $e');
      return false;
    }
  }

  static Future<bool> unsaveProvider(String providerUlid) async {
    try {
      final res = await _sendWithAuthRetry(
        (headers) => http
            .delete(
              Uri.parse('$_baseUrl/customer/saved-providers/$providerUlid'),
              headers: headers,
            )
            .timeout(const Duration(seconds: 15)),
      );
      print('[AuthService] UNSAVE PROVIDER status: ${res.statusCode}');
      print('[AuthService] UNSAVE PROVIDER response: ${res.body}');
      return res.statusCode == 200 || res.statusCode == 204;
    } catch (e) {
      print('[AuthService] UNSAVE PROVIDER error: $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getSavedProviders() async {
    try {
      final res = await _sendWithAuthRetry(
        (headers) => http
            .get(
              Uri.parse('$_baseUrl/customer/saved-providers'),
              headers: headers,
            )
            .timeout(const Duration(seconds: 15)),
      );
      print('[AuthService] GET SAVED PROVIDERS status: ${res.statusCode}');
      print('[AuthService] GET SAVED PROVIDERS response: ${res.body}');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic> raw =
            (data is List ? data : null) ??
            (data['data'] is List ? data['data'] : null) ??
            (data['providers'] is List ? data['providers'] : null) ??
            [];
        return raw.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('[AuthService] GET SAVED PROVIDERS error: $e');
      return [];
    }
  }
}
'@

$result = $before + "`r`n" + $newSection
Set-Content -Path $file -Value $result -NoNewline
Write-Host "Done"
