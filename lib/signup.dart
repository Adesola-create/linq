import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'linq_theme.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _agreed = false;
  String? _selectedRole;
  bool _loading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _googleSignIn() async {
    setState(() { _loading = true; _errorMessage = null; });
    final result = await AuthService.signInWithGoogle();
    if (!mounted) return;
    setState(() => _loading = false);
    if (result['success'] == true) {
      final route = result['role'] == 'provider' ? '/provider-dashboard' : '/customer-dashboard';
      Navigator.pushNamedAndRemoveUntil(context, route, (_) => false);
    } else {
      setState(() => _errorMessage = result['message']);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreed) {
      setState(() => _errorMessage = 'You must agree to the Terms of Service.');
      return;
    }
    setState(() { _loading = true; _errorMessage = null; });

    final result = await AuthService.register(
      firstName: _firstNameCtrl.text.trim(),
      lastName: _lastNameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      password: _passwordCtrl.text,
      role: _selectedRole!,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (result['success'] == true) {
      final route = result['role'] == 'provider'
          ? '/provider-dashboard'
          : '/customer-dashboard';
      Navigator.pushNamedAndRemoveUntil(context, route, (_) => false);
    } else {
      setState(() => _errorMessage = result['message']);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LinqColors.bgPageApp,
      appBar: AppBar(
        backgroundColor: LinqColors.bgPageApp,
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.verified_user, color: LinqColors.forest500),
            const SizedBox(width: 8),
            Text('LINQ', style: LinqTextStyles.h4.copyWith(color: LinqColors.forest500, letterSpacing: 2)),
          ],
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 900;
          return Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: isDesktop
                  ? Row(children: [Expanded(child: _leftPanel()), Expanded(child: _rightPanel())])
                  : _rightPanel(),
            ),
          );
        },
      ),
    );
  }

  Widget _leftPanel() {
    return Container(
      color: LinqColors.forest500,
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              linqVerifiedBadge(),
              const SizedBox(height: 20),
              Text('The gold standard for secure service.',
                  style: LinqTextStyles.h2.copyWith(color: LinqColors.textOnBrand)),
              const SizedBox(height: 12),
              Text(
                'Join an elite network of verified professionals and clients.',
                style: LinqTextStyles.body.copyWith(color: LinqColors.forest100),
              ),
            ],
          ),
          Row(
            children: [
              CircleAvatar(backgroundImage: CachedNetworkImageProvider('https://i.pravatar.cc/150?img=12')),
              const SizedBox(width: 10),
              Text('Join 2,400+ verified partners today.',
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
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Text('Create account', style: LinqTextStyles.h2.copyWith(color: LinqColors.forest500)),
                  const SizedBox(height: 4),
                  Text('Start your secure journey with LINQ today.',
                      style: LinqTextStyles.bodySm.copyWith(color: LinqColors.textSecondary)),
                  const SizedBox(height: 16),

                  SizedBox(width: double.infinity, child: _googleBtn()),
                  const SizedBox(height: 14),

                  const Row(children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text("OR", style: TextStyle(color: Colors.black38)),
                    ),
                    Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 14),

                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
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
                            child: Text(_errorMessage!,
                                style: LinqTextStyles.bodySm.copyWith(color: LinqColors.danger700)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // First & Last name row
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _firstNameCtrl,
                          decoration: linqInputDecoration(label: 'First name', icon: Icons.person_outline),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required.' : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _lastNameCtrl,
                          decoration: linqInputDecoration(label: 'Last name', icon: Icons.person_outline),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required.' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Email
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: linqInputDecoration(label: 'Email address', icon: Icons.email_outlined),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Email is required.';
                      if (!RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(v.trim())) return 'Enter a valid email.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),

                  // Phone
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: linqInputDecoration(label: 'Phone number', icon: Icons.phone_outlined),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Phone number is required.' : null,
                  ),
                  const SizedBox(height: 10),

                  // Role
                  DropdownButtonFormField<String>(
                    value: _selectedRole,
                    decoration: linqInputDecoration(label: 'I am a...', icon: Icons.work_outline),
                    items: const [
                      DropdownMenuItem(value: 'user', child: Text('User — Hire a Pro')),
                      DropdownMenuItem(value: 'provider', child: Text('Service Provider')),
                    ],
                    onChanged: (val) => setState(() => _selectedRole = val),
                    validator: (v) => v == null ? 'Please select your role.' : null,
                  ),
                  const SizedBox(height: 10),

                  // Password
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: _obscurePassword,
                    decoration: linqInputDecoration(
                      label: 'Password',
                      icon: Icons.lock_outline,
                      helper: 'Min 10 chars, 1 uppercase, 1 lowercase',
                      suffix: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility : Icons.visibility_off,
                          color: LinqColors.forest500, size: 20,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Password is required.';
                      if (v.length < 10) return 'Min 10 characters required.';
                      if (!RegExp(r'[A-Z]').hasMatch(v)) return 'Add at least one uppercase letter (A-Z).';
                      if (!RegExp(r'[a-z]').hasMatch(v)) return 'Add at least one lowercase letter (a-z).';
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),

                  // Terms
                  Row(
                    children: [
                      Checkbox(
                        value: _agreed,
                        activeColor: LinqColors.forest500,
                        onChanged: (v) => setState(() => _agreed = v ?? false),
                      ),
                      Expanded(
                        child: Text(
                          'I agree to the Terms of Service and Privacy Policy.',
                          style: LinqTextStyles.bodySm.copyWith(color: LinqColors.textBody),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: linqPrimaryButton(verticalPadding: 16),
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Sign up', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 14),

                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/login'),
                      style: TextButton.styleFrom(foregroundColor: LinqColors.forest500),
                      child: Text('Already have an account? Log in',
                          style: LinqTextStyles.bodySm.copyWith(color: LinqColors.forest500, fontWeight: FontWeight.w500)),
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
        errorWidget: (_, __, ___) => const Icon(Icons.g_mobiledata, color: Color(0xFF001B44)),
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
