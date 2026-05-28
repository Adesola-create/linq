import 'package:flutter/material.dart';
import 'linq_theme.dart';

class OtpVerificationPage extends StatefulWidget {
  const OtpVerificationPage({super.key});

  @override
  State<OtpVerificationPage> createState() => _OtpVerificationPageState();
}

class _OtpVerificationPageState extends State<OtpVerificationPage> {
  final List<TextEditingController> controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> focusNodes = List.generate(6, (_) => FocusNode());

  @override
  void dispose() {
    for (var c in controllers) c.dispose();
    for (var f in focusNodes) f.dispose();
    super.dispose();
  }

  Widget _otpBox(int index, {bool isDash = false}) {
    if (isDash) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text('-',
            style: LinqTextStyles.h3.copyWith(color: LinqColors.textSecondary)),
      );
    }
    return SizedBox(
      width: 50,
      height: 56,
      child: TextField(
        controller: controllers[index],
        focusNode: focusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: LinqTextStyles.h3,
        decoration: InputDecoration(
          counterText: '',
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
                color: LinqColors.forest500, width: LinqBorders.medium),
          ),
        ),
        onChanged: (value) {
          if (value.isNotEmpty && index < 5) {
            FocusScope.of(context).requestFocus(focusNodes[index + 1]);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LinqColors.bgPageApp,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(LinqSpacing.s4),
              child: Row(
                children: [
                  const Icon(Icons.shield, color: LinqColors.forest500),
                  const SizedBox(width: 8),
                  Text('LINQ',
                      style: LinqTextStyles.h4.copyWith(
                          color: LinqColors.forest500, letterSpacing: 2)),
                ],
              ),
            ),
            const Spacer(),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: LinqSpacing.s5),
              padding: const EdgeInsets.all(LinqSpacing.s6),
              decoration: BoxDecoration(
                color: LinqColors.bgSurface,
                borderRadius: LinqRadius.borderLg,
                border: Border.all(color: LinqColors.borderDefault),
                boxShadow: LinqShadows.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: LinqColors.forest100,
                        ),
                        child: const Icon(Icons.mail,
                            size: 36, color: LinqColors.forest500),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: LinqColors.brass500,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.verified_user,
                              size: 14, color: LinqColors.textOnBrand),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: LinqSpacing.s5),
                  Text('Check your email', style: LinqTextStyles.h2),
                  const SizedBox(height: LinqSpacing.s3),
                  Text(
                    "We've sent a secure 6-digit verification code to u***r@example.com",
                    textAlign: TextAlign.center,
                    style: LinqTextStyles.bodySm,
                  ),
                  const SizedBox(height: LinqSpacing.s8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _otpBox(0),
                      _otpBox(1),
                      _otpBox(2),
                      _otpBox(0, isDash: true),
                      _otpBox(3),
                      _otpBox(4),
                      _otpBox(5),
                    ],
                  ),
                  const SizedBox(height: LinqSpacing.s8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: linqPrimaryButton(verticalPadding: LinqSpacing.s4),
                      onPressed: () =>
                          Navigator.pushNamed(context, '/complete-profile'),
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Verify & continue',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: LinqSpacing.s5),
                  TextButton(
                    onPressed: () {},
                    child: Text('Resend code',
                        style: LinqTextStyles.label
                            .copyWith(color: LinqColors.forest500)),
                  ),
                ],
              ),
            ),
            const Spacer(),
            const SizedBox(height: LinqSpacing.s5),
          ],
        ),
      ),
    );
  }
}
