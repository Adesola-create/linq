import 'package:flutter/material.dart';
import 'linq_theme.dart';

class VerificationScreen extends StatelessWidget {
  const VerificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      backgroundColor: LinqColors.bgPageApp,
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: LinqSpacing.s5, vertical: LinqSpacing.s4),
                decoration: BoxDecoration(
                  color: LinqColors.bgSurface,
                  border: const Border(
                      bottom: BorderSide(color: LinqColors.borderDefault)),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back,
                              color: LinqColors.forest500),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 8),
                        Text('LINQ',
                            style: LinqTextStyles.h4.copyWith(
                                color: LinqColors.forest500, letterSpacing: 2)),
                      ]),
                      TextButton(
                        onPressed: () {},
                        child: Text('Skip',
                            style: LinqTextStyles.bodySm
                                .copyWith(color: LinqColors.textTertiary)),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                      LinqSpacing.s6, LinqSpacing.s8, LinqSpacing.s6, 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ProgressSection(),
                      const SizedBox(height: LinqSpacing.s10),
                      Text('Verify your expertise',
                          style: LinqTextStyles.displayLg),
                      const SizedBox(height: LinqSpacing.s3),
                      Text('LINQ ensures every pro meets our high standards.',
                          style: LinqTextStyles.bodyLg),
                      const SizedBox(height: LinqSpacing.s10),
                      isDesktop
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Expanded(flex: 7, child: BasicInfoCard()),
                                SizedBox(width: LinqSpacing.s6),
                                Expanded(flex: 5, child: UploadSection()),
                              ],
                            )
                          : const Column(children: [
                              BasicInfoCard(),
                              SizedBox(height: LinqSpacing.s6),
                              UploadSection(),
                            ]),
                      const SizedBox(height: LinqSpacing.s10),
                      const CTASection(),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.only(top: 12, bottom: 22),
              decoration: BoxDecoration(
                color: LinqColors.bgSurface.withOpacity(0.95),
                border: const Border(
                    top: BorderSide(color: LinqColors.borderDefault)),
                boxShadow: LinqShadows.md,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProgressSection extends StatelessWidget {
  const ProgressSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(child: ProgressStep(step: '1', label: 'Identity', active: true)),
        Expanded(child: ProgressLine(active: true)),
        Expanded(child: ProgressStep(step: '2', label: 'Documents', active: false)),
        Expanded(child: ProgressLine(active: false)),
        Expanded(child: ProgressStep(step: '3', label: 'Expertise', active: false)),
      ],
    );
  }
}

class ProgressStep extends StatelessWidget {
  final String step;
  final String label;
  final bool active;

  const ProgressStep(
      {super.key,
      required this.step,
      required this.label,
      required this.active});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor:
              active ? LinqColors.forest500 : LinqColors.stone200,
          child: Text(step,
              style: TextStyle(
                color: active ? LinqColors.textOnBrand : LinqColors.textTertiary,
                fontWeight: FontWeight.w600,
              )),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: LinqTextStyles.labelSm.copyWith(
                color: active
                    ? LinqColors.forest500
                    : LinqColors.textTertiary)),
      ],
    );
  }
}

class ProgressLine extends StatelessWidget {
  final bool active;
  const ProgressLine({super.key, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 2,
      color: active ? LinqColors.forest500 : LinqColors.stone200,
    );
  }
}

class BasicInfoCard extends StatelessWidget {
  const BasicInfoCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(LinqSpacing.s6),
      decoration: BoxDecoration(
        color: LinqColors.bgSurface,
        borderRadius: LinqRadius.borderLg,
        border: Border.all(color: LinqColors.borderDefault),
        boxShadow: LinqShadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Basic information', style: LinqTextStyles.h3),
          const SizedBox(height: LinqSpacing.s6),
          TextField(
              decoration: linqInputDecoration(
                  label: 'Legal full name', icon: Icons.person_outline)),
          const SizedBox(height: LinqSpacing.s4),
          TextField(
              decoration: linqInputDecoration(
                  label: 'Work email', icon: Icons.email_outlined)),
          const SizedBox(height: LinqSpacing.s4),
          TextField(
              decoration: linqInputDecoration(
                  label: 'Phone number', icon: Icons.phone_outlined)),
          const SizedBox(height: LinqSpacing.s6),
          Container(
            padding: const EdgeInsets.all(LinqSpacing.s4),
            decoration: BoxDecoration(
              color: LinqColors.trustBg,
              borderRadius: LinqRadius.borderMd,
              border: Border.all(color: LinqColors.brass200),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_user, color: LinqColors.trust),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('LINQ verified status pending',
                      style: LinqTextStyles.label
                          .copyWith(color: LinqColors.trustText)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class UploadSection extends StatelessWidget {
  const UploadSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(LinqSpacing.s6),
          decoration: BoxDecoration(
            color: LinqColors.forest500,
            borderRadius: LinqRadius.borderLg,
          ),
          child: Column(
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: LinqColors.forest700,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.camera_alt,
                    color: LinqColors.textOnBrand, size: 34),
              ),
              const SizedBox(height: LinqSpacing.s5),
              Text('Upload identity',
                  style: LinqTextStyles.h3
                      .copyWith(color: LinqColors.textOnBrand)),
              const SizedBox(height: 8),
              Text('Passport or government ID',
                  style: LinqTextStyles.bodySm
                      .copyWith(color: LinqColors.forest200)),
              const SizedBox(height: LinqSpacing.s5),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: LinqSpacing.s5, vertical: LinqSpacing.s3),
                decoration: BoxDecoration(
                  color: LinqColors.forest700,
                  borderRadius: LinqRadius.borderFull,
                ),
                child: Text('SELECT FILE',
                    style: LinqTextStyles.labelSm
                        .copyWith(color: LinqColors.textOnBrand)),
              ),
            ],
          ),
        ),
        const SizedBox(height: LinqSpacing.s5),
        const TrustBadgeCard(),
      ],
    );
  }
}

class TrustBadgeCard extends StatelessWidget {
  const TrustBadgeCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(LinqSpacing.s5),
      decoration: BoxDecoration(
        color: LinqColors.stone100,
        borderRadius: LinqRadius.borderLg,
        border: Border.all(color: LinqColors.borderDefault),
      ),
      child: const TrustItem(
        icon: Icons.shield,
        title: 'Safety first',
        subtitle: 'Manual verification for all pros.',
      ),
    );
  }
}

class TrustItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const TrustItem(
      {super.key,
      required this.icon,
      required this.title,
      required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: LinqColors.forest100,
            borderRadius: LinqRadius.borderMd,
          ),
          child: Icon(icon, color: LinqColors.forest500),
        ),
        const SizedBox(width: LinqSpacing.s4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: LinqTextStyles.label),
              Text(subtitle, style: LinqTextStyles.bodySm),
            ],
          ),
        ),
      ],
    );
  }
}

class CTASection extends StatelessWidget {
  const CTASection({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(LinqSpacing.s6),
      decoration: BoxDecoration(
        color: LinqColors.stone100,
        borderRadius: LinqRadius.borderLg,
        border: Border.all(color: LinqColors.borderDefault),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 520;
          return Wrap(
            spacing: LinqSpacing.s5,
            runSpacing: LinqSpacing.s5,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: isNarrow ? constraints.maxWidth : 360,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, color: LinqColors.info500),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'By clicking continue, you agree to our Service Provider Terms. Verification may take 24–48 hours.',
                        style: LinqTextStyles.bodySm,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: isNarrow ? constraints.maxWidth : null,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: LinqColors.forest500,
                    foregroundColor: LinqColors.textOnBrand,
                    padding: const EdgeInsets.symmetric(
                        horizontal: LinqSpacing.s8, vertical: LinqSpacing.s4),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: LinqRadius.borderMd),
                  ),
                  onPressed: () =>
                      Navigator.pushNamed(context, '/provider-dashboard'),
                  child: const Text('Continue to documents',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
