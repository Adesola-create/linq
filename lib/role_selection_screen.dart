import 'package:flutter/material.dart';
import 'linq_theme.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: LinqColors.bgPageApp,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: LinqSpacing.s6, vertical: LinqSpacing.s4),
            decoration: BoxDecoration(
              color: LinqColors.bgSurface,
              border: const Border(
                  bottom: BorderSide(color: LinqColors.borderDefault)),
              boxShadow: LinqShadows.xs,
            ),
            child: SafeArea(
              bottom: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('LINQ',
                      style: LinqTextStyles.h2.copyWith(
                          color: LinqColors.forest500, letterSpacing: 2)),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  LinqSpacing.s6, LinqSpacing.s10, LinqSpacing.s6, LinqSpacing.s10),
              child: Column(
                children: [
                  Text('How will you use LINQ?',
                      textAlign: TextAlign.center,
                      style: LinqTextStyles.displayLg),
                  const SizedBox(height: LinqSpacing.s5),
                  SizedBox(
                    width: 700,
                    child: Text(
                      'Choose the path that fits your needs. Our secure ecosystem supports both seekers and providers with full transparency.',
                      textAlign: TextAlign.center,
                      style: LinqTextStyles.bodyLg,
                    ),
                  ),
                  const SizedBox(height: LinqSpacing.s12),
                  isDesktop
                      ? Row(children: const [
                          Expanded(child: CustomerCard()),
                          SizedBox(width: LinqSpacing.s6),
                          Expanded(child: ProviderCard()),
                        ])
                      : Column(children: const [
                          CustomerCard(),
                          SizedBox(height: LinqSpacing.s6),
                          ProviderCard(),
                        ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CustomerCard extends StatelessWidget {
  const CustomerCard({super.key});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.pushNamed(context, '/register'),
      borderRadius: LinqRadius.borderXl,
      child: Container(
        padding: const EdgeInsets.all(LinqSpacing.s6),
        decoration: BoxDecoration(
          color: LinqColors.bgSurface,
          borderRadius: LinqRadius.borderXl,
          border: Border.all(color: LinqColors.borderDefault),
          boxShadow: LinqShadows.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _iconBox(Icons.search, LinqColors.forest100, LinqColors.forest500),
            const SizedBox(height: LinqSpacing.s6),
            Text('I want to hire a pro', style: LinqTextStyles.h2),
            const SizedBox(height: LinqSpacing.s4),
            Text(
              'Browse verified professionals, get instant quotes, and manage bookings with a single tap.',
              style: LinqTextStyles.bodyLg,
            ),
            const SizedBox(height: LinqSpacing.s6),
            linqVerifiedBadge(),
            const SizedBox(height: LinqSpacing.s8),
            Row(children: [
              Text('Continue as customer',
                  style: LinqTextStyles.label
                      .copyWith(color: LinqColors.forest500)),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward,
                  color: LinqColors.forest500, size: 18),
            ]),
          ],
        ),
      ),
    );
  }
}

class ProviderCard extends StatelessWidget {
  const ProviderCard({super.key});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.pushNamed(context, '/register'),
      borderRadius: LinqRadius.borderXl,
      child: Container(
        padding: const EdgeInsets.all(LinqSpacing.s6),
        decoration: BoxDecoration(
          color: LinqColors.forest500,
          borderRadius: LinqRadius.borderXl,
          boxShadow: LinqShadows.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _iconBox(Icons.work, LinqColors.forest700, LinqColors.textOnBrand),
            const SizedBox(height: LinqSpacing.s6),
            Text('I want to grow my business',
                style: LinqTextStyles.h2
                    .copyWith(color: LinqColors.textOnBrand)),
            const SizedBox(height: LinqSpacing.s4),
            Text(
              'Scale with LINQ-ERP tools. Automated invoicing, secure lead generation, and premium analytics.',
              style: LinqTextStyles.bodyLg
                  .copyWith(color: LinqColors.forest100),
            ),
            const SizedBox(height: LinqSpacing.s6),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: const [
                FeatureChip(icon: Icons.analytics, label: 'Advanced CRM'),
                FeatureChip(icon: Icons.payments, label: 'Escrow pay'),
              ],
            ),
            const SizedBox(height: LinqSpacing.s8),
            Row(children: [
              Text('Continue as provider',
                  style: LinqTextStyles.label
                      .copyWith(color: LinqColors.forest200)),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward,
                  color: LinqColors.forest200, size: 18),
            ]),
          ],
        ),
      ),
    );
  }
}

Widget _iconBox(IconData icon, Color bg, Color iconColor) {
  return Container(
    width: 56,
    height: 56,
    decoration: BoxDecoration(color: bg, borderRadius: LinqRadius.borderLg),
    child: Icon(icon, color: iconColor, size: 28),
  );
}

class FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const FeatureChip({super.key, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: LinqSpacing.s4, vertical: LinqSpacing.s2_5),
      decoration: BoxDecoration(
        color: LinqColors.forest700,
        borderRadius: LinqRadius.borderMd,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: LinqColors.forest200, size: 16),
          const SizedBox(width: 8),
          Text(label,
              style: LinqTextStyles.labelSm
                  .copyWith(color: LinqColors.forest100)),
        ],
      ),
    );
  }
}
