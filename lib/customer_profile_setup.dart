import 'package:flutter/material.dart';
import 'linq_theme.dart';

class CompleteProfilePage extends StatelessWidget {
  const CompleteProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LinqColors.bgPageApp,
      appBar: AppBar(
        title: Row(children: [
          const Icon(Icons.verified_user, color: LinqColors.forest500),
          const SizedBox(width: 8),
          Text('LINQ',
              style: LinqTextStyles.h4
                  .copyWith(color: LinqColors.forest500, letterSpacing: 2)),
        ]),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(LinqSpacing.s6),
              color: LinqColors.forest500,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: LinqSpacing.s4),
                  Text('Complete your LINQ profile.',
                      style: LinqTextStyles.h1
                          .copyWith(color: LinqColors.textOnBrand)),
                  const SizedBox(height: LinqSpacing.s3),
                  Text(
                    'Help us verify your identity to unlock secure services.',
                    style: LinqTextStyles.body
                        .copyWith(color: LinqColors.forest100),
                  ),
                ],
              ),
            ),
            const SizedBox(height: LinqSpacing.s5),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: LinqSpacing.s4),
              child: Container(
                padding: const EdgeInsets.all(LinqSpacing.s5),
                decoration: BoxDecoration(
                  color: LinqColors.bgSurface,
                  borderRadius: LinqRadius.borderLg,
                  border: Border.all(color: LinqColors.borderDefault),
                  boxShadow: LinqShadows.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundColor: LinqColors.stone100,
                            child: const Icon(Icons.person,
                                size: 40, color: LinqColors.stone400),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: LinqColors.forest500,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.camera_alt,
                                  color: LinqColors.textOnBrand, size: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: LinqSpacing.s5),
                    Text('Identity image', style: LinqTextStyles.label),
                    const SizedBox(height: LinqSpacing.s5),
                    TextField(
                      decoration: linqInputDecoration(
                          label: 'Full legal name', icon: Icons.person_outline),
                    ),
                    const SizedBox(height: LinqSpacing.s4),
                    TextField(
                      keyboardType: TextInputType.phone,
                      decoration: linqInputDecoration(
                          label: 'Phone number', icon: Icons.phone_outlined),
                    ),
                    const SizedBox(height: LinqSpacing.s4),
                    TextField(
                      decoration: linqInputDecoration(
                          label: 'Primary service location',
                          icon: Icons.location_on_outlined),
                    ),
                    const SizedBox(height: LinqSpacing.s6),
                    Container(
                      padding: const EdgeInsets.all(LinqSpacing.s4),
                      decoration: BoxDecoration(
                        color: LinqColors.info50,
                        borderRadius: LinqRadius.borderMd,
                        border: const Border(
                          left: BorderSide(
                              color: LinqColors.info500, width: LinqBorders.thick),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock, color: LinqColors.info500),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Your data is encrypted and never shared without consent.',
                              style: LinqTextStyles.bodySm,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: LinqSpacing.s6),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: linqPrimaryButton(verticalPadding: LinqSpacing.s4),
                        onPressed: () =>
                            Navigator.pushNamed(context, '/customer-dashboard'),
                        child: const Text('Complete setup',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: LinqSpacing.s10),
          ],
        ),
      ),
    );
  }
}
