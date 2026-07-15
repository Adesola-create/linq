import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'linq_theme.dart';

class UserVerificationPage extends StatefulWidget {
  const UserVerificationPage({super.key});

  @override
  State<UserVerificationPage> createState() => _UserVerificationPageState();
}

class _UserVerificationPageState extends State<UserVerificationPage> {
  bool _loading = true;
  String? _errorMessage;

  String _phone = '';
  String _email = '';
  bool _phoneVerified = false;
  bool _emailVerified = false;
  bool _identityVerified = false;
  bool _identityInReview = false;

  bool _sendingOtp = false;
  bool _sendingEmailLink = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static const _kycInReviewKey = 'kyc_identity_in_review';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final cachedProfile = await AuthService.getCachedProfile();
    if (cachedProfile != null) {
      final user =
          (cachedProfile['user'] is Map ? cachedProfile['user'] : cachedProfile)
              as Map<String, dynamic>;
      _phone = (user['phone'] ?? '').toString();
      _email = (user['email'] ?? '').toString();
    }

    final prefs = await SharedPreferences.getInstance();
    final savedInReview = prefs.getBool(_kycInReviewKey) ?? false;
    if (savedInReview && mounted) {
      setState(() => _identityInReview = true);
    }

    final result = await AuthService.getKycStatus();
    if (!mounted) return;

    if (result['success'] == true) {
      final data = result['data'];
      _applyStatus(data, prefs: prefs);
      setState(() => _loading = false);
      return;
    }

    if (result['auth_required'] == true) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      return;
    }

    setState(() {
      _errorMessage =
          result['message']?.toString() ?? 'Failed to load verification status.';
      _loading = false;
    });
  }

  void _applyStatus(dynamic data, {SharedPreferences? prefs}) {
    final status = data is Map
        ? (data['data'] is Map ? data['data'] as Map : data)
        : <String, dynamic>{};

    bool boolField(List<String> keys) {
      for (final key in keys) {
        final value = status[key];
        if (value is bool) return value;
        if (value is String) {
          final lower = value.toLowerCase();
          if (lower == 'verified' || lower == 'approved') return true;
        }
      }
      return false;
    }

    bool statusIsOneOf(List<String> keys, List<String> values) {
      for (final key in keys) {
        final value = status[key];
        if (value is String && values.contains(value.toLowerCase())) return true;
      }
      return false;
    }

    final kycLevel = status['kyc_level'];
    final kycLevelInt = kycLevel is int
        ? kycLevel
        : kycLevel is num
            ? kycLevel.toInt()
            : int.tryParse(kycLevel?.toString() ?? '') ?? 0;

    final identityVerified = kycLevelInt >= 2 ||
        boolField([
          'identity_verified',
          'is_identity_verified',
          'kyc_verified',
          'kyc_status',
          'identity_status',
          'status',
        ]);

    final identityInReview = !identityVerified &&
        statusIsOneOf(
          ['kyc_status', 'identity_status', 'status'],
          ['pending', 'in_review', 'under_review', 'submitted', 'review'],
        );

    if (identityVerified && prefs != null) {
      prefs.remove(_kycInReviewKey);
    }

    setState(() {
      _phoneVerified = boolField(['phone_verified', 'is_phone_verified']);
      _emailVerified = boolField(['email_verified', 'is_email_verified']);
      _identityVerified = identityVerified;
      _identityInReview = identityVerified ? false : (_identityInReview || identityInReview);
      if ((status['phone'] ?? '').toString().isNotEmpty) {
        _phone = status['phone'].toString();
      }
      if ((status['email'] ?? '').toString().isNotEmpty) {
        _email = status['email'].toString();
      }
    });
  }

  int get _currentLevelIndex {
    if (_identityVerified) return 2;
    if (_phoneVerified && _emailVerified) return 1;
    return 0;
  }

  String _maskPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.length < 7) return phone.isEmpty ? 'Not provided' : phone;
    final last4 = digits.substring(digits.length - 4);
    final prefixLength = digits.startsWith('+') ? 4 : 3;
    final prefix = digits.substring(0, prefixLength);
    return '$prefix ••••••$last4';
  }

  String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2 || parts[0].isEmpty) {
      return email.isEmpty ? 'Not provided' : email;
    }
    return '${parts[0][0]}•••@${parts[1]}';
  }

  Future<void> _sendOtp() async {
    if (_sendingOtp) return;
    setState(() => _sendingOtp = true);

    final result = await AuthService.sendPhoneOtp();
    if (!mounted) return;
    setState(() => _sendingOtp = false);

    if (result['auth_required'] == true) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result['success'] == true
              ? 'A 6-digit code has been sent to your phone.'
              : (result['message']?.toString() ??
                  'Failed to send verification code.'),
        ),
        backgroundColor: result['success'] == true
            ? LinqColors.success500
            : LinqColors.danger500,
      ),
    );

    if (result['success'] == true) {
      _openOtpEntrySheet();
    }
  }

  Future<void> _openOtpEntrySheet() async {
    final verified = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OtpEntrySheet(phone: _phone),
    );

    if (!mounted) return;
    if (verified == true) {
      setState(() => _phoneVerified = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Phone number verified successfully.'),
          backgroundColor: LinqColors.success500,
        ),
      );
      _load();
    }
  }

  Future<void> _sendEmailLink() async {
    if (_sendingEmailLink) return;
    setState(() => _sendingEmailLink = true);

    final result = await AuthService.sendEmailVerificationLink();
    if (!mounted) return;
    setState(() => _sendingEmailLink = false);

    if (result['auth_required'] == true) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result['success'] == true
              ? 'A verification link has been sent to your email.'
              : (result['message']?.toString() ??
                  'Failed to send verification link.'),
        ),
        backgroundColor: result['success'] == true
            ? LinqColors.success500
            : LinqColors.danger500,
      ),
    );

    if (result['success'] == true) {
      _openEmailTokenEntrySheet();
    }
  }

  Future<void> _openEmailTokenEntrySheet() async {
    final verified = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EmailTokenEntrySheet(email: _email),
    );

    if (!mounted) return;
    if (verified == true) {
      setState(() => _emailVerified = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email verified successfully.'),
          backgroundColor: LinqColors.success500,
        ),
      );
      _load();
    }
  }

  Future<void> _startIdentityVerification() async {
    final submitted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const _IdentityDocumentsPage()),
    );
    if (submitted == true) {
      setState(() => _identityInReview = true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kycInReviewKey, true);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LinqColors.bgPageApp,
      appBar: AppBar(
        backgroundColor: LinqColors.forest500,
        foregroundColor: LinqColors.textOnBrand,
        elevation: 0,
        title: Text(
          'Verification',
          style: LinqTextStyles.h3.copyWith(color: LinqColors.textOnBrand),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: LinqColors.forest500),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(LinqSpacing.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: LinqColors.danger500,
              ),
              const SizedBox(height: LinqSpacing.s4),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: LinqTextStyles.bodySm.copyWith(
                  color: LinqColors.textSecondary,
                ),
              ),
              const SizedBox(height: LinqSpacing.s5),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: LinqColors.forest500,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(LinqSpacing.s5),
        children: [
          _buildLevelProgress(),
          const SizedBox(height: LinqSpacing.s6),
          _buildRegisteredCard(),
          const SizedBox(height: LinqSpacing.s4),
          _buildPhoneEmailCard(),
          const SizedBox(height: LinqSpacing.s4),
          _buildIdentityCard(),
        ],
      ),
    );
  }

  Widget _buildLevelProgress() {
    final current = _currentLevelIndex;
    return Row(
      children: [
        _LevelStep(label: 'L0', sublabel: 'Registered', active: current >= 0),
        Expanded(child: _LevelLine(active: current >= 1)),
        _LevelStep(
          label: 'L1',
          sublabel: 'Phone & Email',
          active: current >= 1,
        ),
        Expanded(child: _LevelLine(active: current >= 2)),
        _LevelStep(label: 'L2', sublabel: 'Identity', active: current >= 2),
      ],
    );
  }

  Widget _buildRegisteredCard() {
    return _verificationSectionCard(
      icon: Icons.how_to_reg_rounded,
      iconColor: LinqColors.forest500,
      iconBackground: LinqColors.forest100,
      title: 'L0 — Registered',
      statusBadge: _statusBadge('Complete', LinqColors.success500, LinqColors.success100),
      children: [
        _checklistRow('Account created', done: true),
        _checklistRow('Profile information added', done: true),
        _checklistRow('Account secured with a password', done: true),
      ],
    );
  }

  Widget _buildPhoneEmailCard() {
    final verified = _phoneVerified && _emailVerified;
    return _verificationSectionCard(
      icon: Icons.phonelink_lock_rounded,
      iconColor: LinqColors.forest500,
      iconBackground: LinqColors.forest100,
      title: 'L1 — Phone & Email Verified',
      statusBadge: verified
          ? _statusBadge('Complete', LinqColors.success500, LinqColors.success100)
          : _statusBadge('Action required', LinqColors.warning500, LinqColors.warning100),
      children: [
        Text(
          'Confirm your phone number and email address to activate your LINQ account.',
          style: LinqTextStyles.bodySm.copyWith(color: LinqColors.textSecondary),
        ),
        const SizedBox(height: LinqSpacing.s4),
        _unlocksRow('Access to the LINQ platform'),
        const SizedBox(height: LinqSpacing.s4),
        _verificationItem(
          icon: Icons.sms_outlined,
          label: _maskPhone(_phone),
          description: 'Verify via a 6-digit SMS code.',
          verified: _phoneVerified,
          actionLabel: 'Send OTP',
          loading: _sendingOtp,
          onPressed: _sendOtp,
        ),
        const SizedBox(height: LinqSpacing.s3),
        _verificationItem(
          icon: Icons.alternate_email_rounded,
          label: _maskEmail(_email),
          description: 'Confirm your email via a verification link.',
          verified: _emailVerified,
          actionLabel: 'Send link',
          loading: _sendingEmailLink,
          onPressed: _sendEmailLink,
        ),
      ],
    );
  }

  Widget _buildIdentityCard() {
    return _verificationSectionCard(
      icon: Icons.fingerprint_rounded,
      iconColor: LinqColors.trust,
      iconBackground: LinqColors.trustBg,
      title: 'L2 — Identity',
      statusBadge: _identityVerified
          ? _statusBadge('Complete', LinqColors.success500, LinqColors.success100)
          : _identityInReview
              ? _statusBadge('In review', LinqColors.trust, LinqColors.trustBg)
              : _statusBadge('Action required', LinqColors.warning500, LinqColors.warning100),
      children: [
        Text(
          'NIN, BVN, and a live selfie for identity verification.',
          style: LinqTextStyles.bodySm.copyWith(color: LinqColors.textSecondary),
        ),
        const SizedBox(height: LinqSpacing.s4),
        _unlocksRow('Full platform access and transaction limits'),
        if (_identityInReview && !_identityVerified) ...[
          const SizedBox(height: LinqSpacing.s3),
          Container(
            padding: const EdgeInsets.all(LinqSpacing.s3),
            decoration: BoxDecoration(
              color: LinqColors.trustBg,
              borderRadius: LinqRadius.borderMd,
              border: Border.all(color: LinqColors.brass200),
            ),
            child: Row(
              children: [
                const Icon(Icons.hourglass_top_rounded, color: LinqColors.trust, size: 18),
                const SizedBox(width: LinqSpacing.s2_5),
                Expanded(
                  child: Text(
                    'Your documents are under review. This usually takes 24–48 hours.',
                    style: LinqTextStyles.bodyXs.copyWith(color: LinqColors.trustText),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: LinqSpacing.s5),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: linqPrimaryButton(verticalPadding: LinqSpacing.s4),
            onPressed: (_identityVerified || _identityInReview) ? null : _startIdentityVerification,
            child: Text(
              _identityVerified
                  ? 'Verified'
                  : _identityInReview
                      ? 'In review'
                      : 'Start Verification',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  Widget _verificationSectionCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBackground,
    required String title,
    required Widget statusBadge,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(LinqSpacing.s5),
      decoration: BoxDecoration(
        color: LinqColors.bgSurface,
        borderRadius: LinqRadius.borderLg,
        border: Border.all(color: LinqColors.borderDefault),
        boxShadow: LinqShadows.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: LinqRadius.borderMd,
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: LinqSpacing.s3),
              Expanded(
                child: Text(title, style: LinqTextStyles.h4),
              ),
              statusBadge,
            ],
          ),
          const SizedBox(height: LinqSpacing.s4),
          ...children,
        ],
      ),
    );
  }

  Widget _statusBadge(String label, Color color, Color background) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LinqSpacing.s2_5,
        vertical: LinqSpacing.s1,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: LinqRadius.borderFull,
      ),
      child: Text(
        label,
        style: LinqTextStyles.bodyXs.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _checklistRow(String label, {required bool done}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LinqSpacing.s2),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 18,
            color: done ? LinqColors.success500 : LinqColors.textTertiary,
          ),
          const SizedBox(width: LinqSpacing.s2),
          Text(label, style: LinqTextStyles.bodySm),
        ],
      ),
    );
  }

  Widget _unlocksRow(String label) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lock_open_rounded, size: 16, color: LinqColors.trust),
        const SizedBox(width: LinqSpacing.s2),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: LinqTextStyles.bodySm.copyWith(color: LinqColors.textSecondary),
              children: [
                const TextSpan(
                  text: 'Unlocks: ',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: label),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _verificationItem({
    required IconData icon,
    required String label,
    required String description,
    required bool verified,
    required String actionLabel,
    required bool loading,
    required VoidCallback onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(LinqSpacing.s4),
      decoration: BoxDecoration(
        color: LinqColors.stone100,
        borderRadius: LinqRadius.borderMd,
        border: Border.all(color: LinqColors.borderDefault),
      ),
      child: Row(
        children: [
          Icon(icon, color: LinqColors.forest500, size: 22),
          const SizedBox(width: LinqSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: LinqTextStyles.label.copyWith(
                    color: LinqColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: LinqSpacing.s1),
                Text(
                  description,
                  style: LinqTextStyles.bodyXs.copyWith(
                    color: LinqColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: LinqSpacing.s3),
          if (verified)
            const Icon(Icons.check_circle_rounded, color: LinqColors.success500)
          else
            IntrinsicWidth(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: LinqColors.forest500,
                  side: const BorderSide(color: LinqColors.forest500, width: LinqBorders.thin),
                  shape: RoundedRectangleBorder(borderRadius: LinqRadius.borderMd),
                  padding: const EdgeInsets.symmetric(horizontal: LinqSpacing.s4),
                ),
                onPressed: loading ? null : onPressed,
                child: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(actionLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
    );
  }
}

class _LevelStep extends StatelessWidget {
  final String label;
  final String sublabel;
  final bool active;

  const _LevelStep({
    required this.label,
    required this.sublabel,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: active ? LinqColors.forest500 : LinqColors.stone200,
          child: active
              ? const Icon(Icons.check_rounded, color: LinqColors.textOnBrand, size: 18)
              : Text(
                  label,
                  style: const TextStyle(
                    color: LinqColors.textTertiary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
        const SizedBox(height: LinqSpacing.s2),
        Text(
          sublabel,
          textAlign: TextAlign.center,
          style: LinqTextStyles.bodyXs.copyWith(
            color: active ? LinqColors.forest500 : LinqColors.textTertiary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _LevelLine extends StatelessWidget {
  final bool active;
  const _LevelLine({required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 2,
      margin: const EdgeInsets.only(bottom: LinqSpacing.s5),
      color: active ? LinqColors.forest500 : LinqColors.stone200,
    );
  }
}

class _OtpEntrySheet extends StatefulWidget {
  final String phone;
  const _OtpEntrySheet({required this.phone});

  @override
  State<_OtpEntrySheet> createState() => _OtpEntrySheetState();
}

class _OtpEntrySheetState extends State<_OtpEntrySheet> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _verifying = false;
  bool _resending = false;
  String? _errorMessage;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _code => _controllers.map((c) => c.text).join();

  Future<void> _verify() async {
    final code = _code;
    if (code.length != 6) {
      setState(() => _errorMessage = 'Enter the 6-digit code sent to your phone.');
      return;
    }

    setState(() {
      _verifying = true;
      _errorMessage = null;
    });

    final result = await AuthService.verifyPhoneOtp(code);
    if (!mounted) return;

    if (result['auth_required'] == true) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      return;
    }

    setState(() => _verifying = false);

    if (result['success'] == true) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _errorMessage =
          result['message']?.toString() ?? 'Invalid or expired code.';
    });
  }

  Future<void> _resend() async {
    if (_resending) return;
    setState(() => _resending = true);

    final result = await AuthService.sendPhoneOtp();
    if (!mounted) return;
    setState(() => _resending = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result['success'] == true
              ? 'A new code has been sent to your phone.'
              : (result['message']?.toString() ?? 'Failed to resend code.'),
        ),
        backgroundColor: result['success'] == true
            ? LinqColors.success500
            : LinqColors.danger500,
      ),
    );
  }

  Widget _otpBox(int index) {
    return SizedBox(
      width: 46,
      height: 54,
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: LinqTextStyles.h4,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          counterText: '',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: LinqSpacing.s3),
          filled: true,
          fillColor: LinqColors.stone100,
          border: OutlineInputBorder(
            borderRadius: LinqRadius.borderMd,
            borderSide: const BorderSide(color: LinqColors.borderDefault),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: LinqRadius.borderMd,
            borderSide: const BorderSide(color: LinqColors.borderDefault),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: LinqRadius.borderMd,
            borderSide: const BorderSide(
              color: LinqColors.forest500,
              width: LinqBorders.medium,
            ),
          ),
        ),
        onChanged: (value) {
          if (value.isNotEmpty && index < 5) {
            FocusScope.of(context).requestFocus(_focusNodes[index + 1]);
          } else if (value.isEmpty && index > 0) {
            FocusScope.of(context).requestFocus(_focusNodes[index - 1]);
          }
          if (_errorMessage != null) {
            setState(() => _errorMessage = null);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          LinqSpacing.s5,
          LinqSpacing.s5,
          LinqSpacing.s5,
          LinqSpacing.s6,
        ),
        decoration: const BoxDecoration(
          color: LinqColors.bgSurface,
          borderRadius: BorderRadius.vertical(top: LinqRadius.lg),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: LinqColors.stone200,
                  borderRadius: LinqRadius.borderFull,
                ),
              ),
            ),
            const SizedBox(height: LinqSpacing.s5),
            Text('Enter verification code', style: LinqTextStyles.h4),
            const SizedBox(height: LinqSpacing.s1),
            Text(
              widget.phone.isNotEmpty
                  ? 'We sent a 6-digit code to ${widget.phone}'
                  : 'We sent a 6-digit code to your registered phone number.',
              style: LinqTextStyles.bodySm.copyWith(color: LinqColors.textSecondary),
            ),
            const SizedBox(height: LinqSpacing.s5),

            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(LinqSpacing.s3),
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
              const SizedBox(height: LinqSpacing.s4),
            ],

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(6, (index) => _otpBox(index)),
            ),
            const SizedBox(height: LinqSpacing.s5),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: linqPrimaryButton(verticalPadding: LinqSpacing.s4),
                onPressed: _verifying ? null : _verify,
                child: _verifying
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: LinqColors.textOnBrand,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Verify',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
            const SizedBox(height: LinqSpacing.s3),

            Center(
              child: TextButton(
                onPressed: _resending ? null : _resend,
                child: _resending
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        "Didn't get a code? Resend",
                        style: LinqTextStyles.bodySm.copyWith(
                          color: LinqColors.forest500,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmailTokenEntrySheet extends StatefulWidget {
  final String email;
  const _EmailTokenEntrySheet({required this.email});

  @override
  State<_EmailTokenEntrySheet> createState() => _EmailTokenEntrySheetState();
}

class _EmailTokenEntrySheetState extends State<_EmailTokenEntrySheet> {
  final _tokenCtrl = TextEditingController();

  bool _verifying = false;
  bool _resending = false;
  String? _errorMessage;

  @override
  void dispose() {
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final token = _tokenCtrl.text.trim();
    if (token.isEmpty) {
      setState(() => _errorMessage = 'Paste the verification token from your email.');
      return;
    }

    setState(() {
      _verifying = true;
      _errorMessage = null;
    });

    final result = await AuthService.confirmEmailVerification(token);
    if (!mounted) return;

    if (result['auth_required'] == true) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      return;
    }

    setState(() => _verifying = false);

    if (result['success'] == true) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _errorMessage =
          result['message']?.toString() ?? 'Invalid or expired verification token.';
    });
  }

  Future<void> _resend() async {
    if (_resending) return;
    setState(() => _resending = true);

    final result = await AuthService.sendEmailVerificationLink();
    if (!mounted) return;
    setState(() => _resending = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result['success'] == true
              ? 'A new verification link has been sent to your email.'
              : (result['message']?.toString() ?? 'Failed to resend link.'),
        ),
        backgroundColor: result['success'] == true
            ? LinqColors.success500
            : LinqColors.danger500,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          LinqSpacing.s5,
          LinqSpacing.s5,
          LinqSpacing.s5,
          LinqSpacing.s6,
        ),
        decoration: const BoxDecoration(
          color: LinqColors.bgSurface,
          borderRadius: BorderRadius.vertical(top: LinqRadius.lg),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: LinqColors.stone200,
                  borderRadius: LinqRadius.borderFull,
                ),
              ),
            ),
            const SizedBox(height: LinqSpacing.s5),
            Text('Confirm your email', style: LinqTextStyles.h4),
            const SizedBox(height: LinqSpacing.s1),
            Text(
              widget.email.isNotEmpty
                  ? 'Open the verification email sent to ${widget.email}, copy the verification token, and paste it below.'
                  : 'Open the verification email we sent you, copy the verification token, and paste it below.',
              style: LinqTextStyles.bodySm.copyWith(color: LinqColors.textSecondary),
            ),
            const SizedBox(height: LinqSpacing.s5),

            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(LinqSpacing.s3),
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
              const SizedBox(height: LinqSpacing.s4),
            ],

            Text('Verification token', style: LinqTextStyles.label),
            const SizedBox(height: LinqSpacing.s2),
            TextField(
              controller: _tokenCtrl,
              maxLines: 3,
              minLines: 1,
              style: LinqTextStyles.body,
              decoration: linqInputDecoration(
                label: 'Paste the token from your email',
                icon: Icons.vpn_key_outlined,
              ),
              onChanged: (_) {
                if (_errorMessage != null) {
                  setState(() => _errorMessage = null);
                }
              },
            ),
            const SizedBox(height: LinqSpacing.s5),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: linqPrimaryButton(verticalPadding: LinqSpacing.s4),
                onPressed: _verifying ? null : _verify,
                child: _verifying
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: LinqColors.textOnBrand,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Verify',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
            const SizedBox(height: LinqSpacing.s3),

            Center(
              child: TextButton(
                onPressed: _resending ? null : _resend,
                child: _resending
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        "Didn't get a link? Resend",
                        style: LinqTextStyles.bodySm.copyWith(
                          color: LinqColors.forest500,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdentityDocumentsPage extends StatefulWidget {
  const _IdentityDocumentsPage();

  @override
  State<_IdentityDocumentsPage> createState() => _IdentityDocumentsPageState();
}

class _IdentityDocumentsPageState extends State<_IdentityDocumentsPage> {
  final _formKey = GlobalKey<FormState>();
  final _ninCtrl = TextEditingController();
  final _bvnCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  DateTime? _selectedDob;

  final ImagePicker _imagePicker = ImagePicker();
  XFile? _selfie;
  Uint8List? _selfieBytes;

  static const _selfieMime = 'image/webp';

  bool _capturingSelfie = false;
  bool _submitting = false;
  String? _submittingStage;
  String? _errorMessage;

  @override
  void dispose() {
    _ninCtrl.dispose();
    _bvnCtrl.dispose();
    _dobCtrl.dispose();
    super.dispose();
  }

  Future<void> _captureSelfie() async {
    if (_capturingSelfie) return;
    setState(() => _capturingSelfie = true);

    try {
      final photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 1280,
        imageQuality: 85,
      );
      if (photo == null) return;

      final rawBytes = await photo.readAsBytes();
      final webpBytes = await FlutterImageCompress.compressWithList(
        rawBytes,
        format: CompressFormat.webp,
        quality: 85,
      );
      if (!mounted) return;
      setState(() {
        _selfie = photo;
        _selfieBytes = webpBytes;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Unable to process the selfie. Please try again.');
    } finally {
      if (mounted) setState(() => _capturingSelfie = false);
    }
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
    );
    if (picked != null) {
      final dd = picked.day.toString().padLeft(2, '0');
      final mm = picked.month.toString().padLeft(2, '0');
      setState(() {
        _selectedDob = picked;
        _dobCtrl.text = '$dd/$mm/${picked.year}';
      });
    }
  }

  String? _isoDob() {
    final picked = _selectedDob;
    if (picked == null) return null;
    final yyyy = picked.year.toString().padLeft(4, '0');
    final mm = picked.month.toString().padLeft(2, '0');
    final dd = picked.day.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd';
  }

  Future<void> _submitForReview() async {
    if (!_formKey.currentState!.validate()) return;

    final isoDob = _isoDob();
    if (isoDob == null) {
      setState(() => _errorMessage = 'Select your date of birth.');
      return;
    }

    final selfie = _selfie;
    final selfieBytes = _selfieBytes;
    if (selfie == null || selfieBytes == null) {
      setState(() => _errorMessage = 'Take a live selfie to continue.');
      return;
    }

    setState(() {
      _submitting = true;
      _submittingStage = 'Uploading your selfie…';
      _errorMessage = null;
    });

    final signed = await AuthService.getR2PutUrl(
      purpose: 'kyc_selfie',
      mime: _selfieMime,
      sizeBytes: selfieBytes.length,
    );

    if (!mounted) return;

    if (signed['auth_required'] == true) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      return;
    }

    if (signed['success'] != true) {
      setState(() {
        _submitting = false;
        _submittingStage = null;
        _errorMessage = signed['message']?.toString() ?? 'Failed to prepare selfie upload.';
      });
      return;
    }

    final signedData = signed['data'];
    final uploadInfo = signedData is Map ? signedData : <String, dynamic>{};
    final uploadUrl = (uploadInfo['upload_url'] ?? '').toString();
    final objectUrl = (uploadInfo['object_url'] ?? uploadInfo['object_key'] ?? '').toString();
    final uploadHeaders = uploadInfo['headers'] is Map
        ? Map<String, dynamic>.from(uploadInfo['headers'] as Map)
        : <String, dynamic>{'Content-Type': _selfieMime};

    if (uploadUrl.isEmpty || objectUrl.isEmpty) {
      setState(() {
        _submitting = false;
        _submittingStage = null;
        _errorMessage = 'Failed to prepare selfie upload.';
      });
      return;
    }

    final uploadResult = await AuthService.uploadBytesToUrl(
      uploadUrl: uploadUrl,
      headers: uploadHeaders,
      bytes: selfieBytes,
    );

    if (!mounted) return;

    if (uploadResult['success'] != true) {
      setState(() {
        _submitting = false;
        _submittingStage = null;
        _errorMessage = uploadResult['message']?.toString() ?? 'Failed to upload selfie.';
      });
      return;
    }

    setState(() => _submittingStage = 'Submitting for review…');

    final result = await AuthService.submitKycVerification(
      nin: _ninCtrl.text.trim(),
      bvn: _bvnCtrl.text.trim(),
      dob: isoDob,
      selfieUrl: objectUrl,
    );

    if (!mounted) return;
    setState(() {
      _submitting = false;
      _submittingStage = null;
    });

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Submitted for review. This usually takes 24–48 hours.',
          ),
          backgroundColor: LinqColors.success500,
        ),
      );
      Navigator.pop(context, true);
      return;
    }

    if (result['auth_required'] == true) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      return;
    }

    setState(() {
      _errorMessage = result['message']?.toString() ??
          'Failed to submit identity verification.';
    });
  }

  String? _validateDigits(String? value, {required int length, required String label}) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Enter your $length-digit $label';
    if (trimmed.length != length || int.tryParse(trimmed) == null) {
      return '$label must be $length digits';
    }
    return null;
  }

  Widget _selfiePreview() {
    final bytes = _selfieBytes;

    if (bytes == null) {
      return InkWell(
        onTap: _capturingSelfie ? null : _captureSelfie,
        borderRadius: LinqRadius.borderMd,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(LinqSpacing.s5),
          decoration: BoxDecoration(
            color: LinqColors.stone100,
            borderRadius: LinqRadius.borderMd,
            border: Border.all(color: LinqColors.borderDefault, style: BorderStyle.solid),
          ),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: LinqColors.trustBg,
                  shape: BoxShape.circle,
                ),
                child: _capturingSelfie
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.camera_alt_outlined, color: LinqColors.trust, size: 26),
              ),
              const SizedBox(height: LinqSpacing.s3),
              Text(
                _capturingSelfie ? 'Opening camera…' : 'Take a live selfie',
                style: LinqTextStyles.label.copyWith(color: LinqColors.textPrimary),
              ),
              const SizedBox(height: LinqSpacing.s1),
              Text(
                'Tap to open your camera',
                style: LinqTextStyles.bodyXs.copyWith(color: LinqColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(LinqSpacing.s3),
      decoration: BoxDecoration(
        color: LinqColors.stone100,
        borderRadius: LinqRadius.borderMd,
        border: Border.all(color: LinqColors.borderDefault),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: LinqRadius.borderMd,
            child: Image.memory(
              bytes,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: LinqSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: LinqColors.success500, size: 16),
                    const SizedBox(width: LinqSpacing.s1),
                    Text(
                      'Selfie captured',
                      style: LinqTextStyles.label.copyWith(color: LinqColors.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: LinqSpacing.s1),
                Text(
                  'Looks good? You can retake if needed.',
                  style: LinqTextStyles.bodyXs.copyWith(color: LinqColors.textSecondary),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _capturingSelfie ? null : _captureSelfie,
            child: Text(
              'Retake',
              style: LinqTextStyles.bodySm.copyWith(
                color: LinqColors.forest500,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LinqColors.bgPageApp,
      appBar: AppBar(
        backgroundColor: LinqColors.forest500,
        foregroundColor: LinqColors.textOnBrand,
        elevation: 0,
        title: Text(
          'Identity Documents',
          style: LinqTextStyles.h3.copyWith(color: LinqColors.textOnBrand),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(LinqSpacing.s5),
            children: [
              Container(
                padding: const EdgeInsets.all(LinqSpacing.s4),
                decoration: BoxDecoration(
                  color: LinqColors.trustBg,
                  borderRadius: LinqRadius.borderMd,
                  border: Border.all(color: LinqColors.brass200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline_rounded, color: LinqColors.trust, size: 20),
                    const SizedBox(width: LinqSpacing.s3),
                    Expanded(
                      child: Text(
                        'Your NIN and BVN are AES-256 encrypted and never stored in plain text.',
                        style: LinqTextStyles.bodyXs.copyWith(color: LinqColors.trustText),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: LinqSpacing.s5),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(LinqSpacing.s3),
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
                const SizedBox(height: LinqSpacing.s4),
              ],

              Text('National Identity Number (NIN)', style: LinqTextStyles.label),
              const SizedBox(height: LinqSpacing.s2),
              TextFormField(
                controller: _ninCtrl,
                keyboardType: TextInputType.number,
                maxLength: 11,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: linqInputDecoration(
                  label: 'Enter your 11-digit NIN',
                  icon: Icons.badge_outlined,
                ),
                validator: (value) =>
                    _validateDigits(value, length: 11, label: 'NIN'),
              ),
              const SizedBox(height: LinqSpacing.s4),

              Text('Bank Verification Number (BVN)', style: LinqTextStyles.label),
              const SizedBox(height: LinqSpacing.s2),
              TextFormField(
                controller: _bvnCtrl,
                keyboardType: TextInputType.number,
                maxLength: 11,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: linqInputDecoration(
                  label: 'Enter your 11-digit BVN',
                  icon: Icons.account_balance_outlined,
                ),
                validator: (value) =>
                    _validateDigits(value, length: 11, label: 'BVN'),
              ),
              const SizedBox(height: LinqSpacing.s4),

              Text('Date of Birth', style: LinqTextStyles.label),
              const SizedBox(height: LinqSpacing.s2),
              TextFormField(
                controller: _dobCtrl,
                readOnly: true,
                onTap: _pickDateOfBirth,
                decoration: linqInputDecoration(
                  label: 'dd/mm/yyyy',
                  icon: Icons.calendar_today_outlined,
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Select your date of birth' : null,
              ),
              const SizedBox(height: LinqSpacing.s5),

              Text('Live Selfie', style: LinqTextStyles.label),
              const SizedBox(height: LinqSpacing.s2),
              Text(
                'Take a clear, well-lit selfie of your face. This is the last step of identity verification.',
                style: LinqTextStyles.bodyXs.copyWith(color: LinqColors.textSecondary),
              ),
              const SizedBox(height: LinqSpacing.s3),
              _selfiePreview(),
              const SizedBox(height: LinqSpacing.s6),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: linqPrimaryButton(verticalPadding: LinqSpacing.s4),
                  onPressed: _submitting ? null : _submitForReview,
                  child: _submitting
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: LinqColors.textOnBrand,
                                strokeWidth: 2,
                              ),
                            ),
                            if (_submittingStage != null) ...[
                              const SizedBox(width: LinqSpacing.s3),
                              Text(
                                _submittingStage!,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ],
                        )
                      : const Text(
                          'Submit for review',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
              const SizedBox(height: LinqSpacing.s5),
            ],
          ),
        ),
      ),
    );
  }
}
