import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'linq_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<String> _resolveLoginRoute(Map<String, dynamic> result) async {
    final responseRole = result['role']?.toString().toLowerCase();
    final savedRole = (await AuthService.getActiveRole())?.toLowerCase();
    final lastMode = (await AuthService.getLastAccountMode())?.toLowerCase();
    final resolvedRole = (responseRole?.isNotEmpty == true)
        ? responseRole
        : (savedRole?.isNotEmpty == true)
            ? savedRole
            : lastMode;
    return resolvedRole == 'provider' ? '/provider-dashboard' : '/customer-dashboard';
  }

  Future<void> _googleSignIn() async {
    setState(() { _loading = true; _errorMessage = null; });
    final result = await AuthService.signInWithGoogle();
    if (!mounted) return;
    setState(() => _loading = false);
    if (result['success'] == true) {
      final route = await _resolveLoginRoute(result);
      Navigator.pushNamedAndRemoveUntil(context, route, (_) => false);
    } else {
      setState(() => _errorMessage = result['message']);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _errorMessage = null; });

    final result = await AuthService.login(
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (result['success'] == true) {
      final route = await _resolveLoginRoute(result);
      Navigator.pushNamedAndRemoveUntil(context, route, (_) => false);
    } else {
      setState(() => _errorMessage = result['message']);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LinqColors.bgPageApp,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 900;
          return Row(
            children: [
              if (isDesktop) Expanded(child: _leftPanel()),
              Expanded(child: _rightPanel()),
            ],
          );
        },
      ),
    );
  }

  Widget _leftPanel() {
    return Container(
      color: LinqColors.forest500,
      padding: const EdgeInsets.all(48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LINQ',
              style: LinqTextStyles.h2.copyWith(
                  color: LinqColors.textOnBrand, letterSpacing: 2)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              linqVerifiedBadge(),
              const SizedBox(height: 24),
              Text('Welcome\nback.',
                  style: LinqTextStyles.h1.copyWith(
                      fontSize: 48, color: LinqColors.textOnBrand, height: 1.1)),
              const SizedBox(height: 16),
              Text(
                'Your trusted marketplace for every service. Sign in to continue.',
                style: LinqTextStyles.body.copyWith(color: LinqColors.forest100, height: 1.6),
              ),
            ],
          ),
          Row(
            children: [
              CircleAvatar(
                backgroundImage: CachedNetworkImageProvider('https://i.pravatar.cc/150?img=5'),
              ),
              const SizedBox(width: 12),
              Text('Join 12,000+ verified users.',
                  style: LinqTextStyles.bodySm.copyWith(color: LinqColors.forest200)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rightPanel() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sign in', style: LinqTextStyles.h2.copyWith(color: LinqColors.forest500)),
                  const SizedBox(height: 6),
                  Text('Enter your credentials to continue.',
                      style: LinqTextStyles.bodySm.copyWith(color: LinqColors.textSecondary)),
                  const SizedBox(height: 8),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/customer-dashboard', (_) => false),
                        child: Text('Skip as user', style: LinqTextStyles.bodyXs.copyWith(color: LinqColors.textTertiary)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/provider-dashboard', (_) => false),
                        child: Text('Skip as provider', style: LinqTextStyles.bodyXs.copyWith(color: LinqColors.textTertiary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  SizedBox(width: double.infinity, child: _googleBtn()),
                  const SizedBox(height: 24),

                  Row(
                    children: [
                      const Expanded(child: Divider(color: LinqColors.borderDefault)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('OR', style: LinqTextStyles.labelSm.copyWith(color: LinqColors.textTertiary)),
                      ),
                      const Expanded(child: Divider(color: LinqColors.borderDefault)),
                    ],
                  ),
                  const SizedBox(height: 24),

                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: LinqColors.danger50,
                        borderRadius: LinqRadius.borderMd,
                        border: Border.all(color: LinqColors.danger100),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: LinqColors.danger500, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: LinqTextStyles.bodySm.copyWith(color: LinqColors.danger700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: linqInputDecoration(label: 'Email address', icon: Icons.email_outlined),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Email is required.';
                      if (!RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(v.trim())) {
                        return 'Enter a valid email address.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: _obscurePassword,
                    decoration: linqInputDecoration(
                      label: 'Password',
                      icon: Icons.lock_outline,
                      suffix: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          color: LinqColors.forest500,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Password is required.';
                      if (v.length < 6) return 'Password must be at least 6 characters.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),

                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {},
                      child: Text('Forgot password?',
                          style: LinqTextStyles.bodySm.copyWith(color: LinqColors.forest500)),
                    ),
                  ),
                  const SizedBox(height: 8),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: linqPrimaryButton(verticalPadding: 16),
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Sign in', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),

                  const SizedBox(height: 20),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/register'),
                      child: Text.rich(
                        TextSpan(
                          text: "Don't have an account? ",
                          style: LinqTextStyles.bodySm.copyWith(color: LinqColors.textSecondary),
                          children: [
                            TextSpan(
                              text: 'Sign up',
                              style: TextStyle(color: LinqColors.forest500, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _googleBtn() {
    return OutlinedButton.icon(
      onPressed: _loading ? null : _googleSignIn,
      icon: CachedNetworkImage(
        imageUrl: 'https://www.google.com/favicon.ico',
        height: 20,
        width: 20,
        fit: BoxFit.contain,
        errorWidget: (_, __, ___) => Icon(Icons.g_mobiledata, color: LinqColors.forest500),
      ),
      label: Text('Continue with Google',
          style: LinqTextStyles.label.copyWith(color: LinqColors.forest500)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: LinqColors.borderDefault),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: LinqRadius.borderMd),
      ),
    );
  }
}
