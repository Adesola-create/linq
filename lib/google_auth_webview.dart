import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'linq_theme.dart';

/// Opens [authUrl] (a Google OAuth consent screen) in an embedded WebView.
/// Google's registered redirect URI is a plain HTTPS backend page, not a
/// custom app scheme, so a native app can't intercept it via the OS. Instead
/// this watches outgoing navigation requests and, the moment one targets
/// [callbackUrlPrefix], cancels the navigation and pops the page with that
/// URL's query parameters (`code`, `state`, or `error`) instead of letting
/// the WebView actually load the backend page.
class GoogleAuthWebViewPage extends StatefulWidget {
  final String authUrl;
  final String callbackUrlPrefix;

  const GoogleAuthWebViewPage({
    super.key,
    required this.authUrl,
    required this.callbackUrlPrefix,
  });

  @override
  State<GoogleAuthWebViewPage> createState() => _GoogleAuthWebViewPageState();
}

class _GoogleAuthWebViewPageState extends State<GoogleAuthWebViewPage> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (request) {
            if (request.url.startsWith(widget.callbackUrlPrefix)) {
              _finish(Uri.tryParse(request.url)?.queryParameters);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.authUrl));
  }

  void _finish(Map<String, String>? params) {
    if (_popped) return;
    _popped = true;
    Navigator.pop(context, params);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: LinqColors.forest500,
        foregroundColor: LinqColors.textOnBrand,
        title: const Text(
          'Sign in with Google',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => _finish(null),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const LinearProgressIndicator(color: LinqColors.forest500),
        ],
      ),
    );
  }
}
