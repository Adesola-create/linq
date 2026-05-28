import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'linq_theme.dart';

class BusinessSetupPage extends StatelessWidget {
  const BusinessSetupPage({super.key});

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
        child: Padding(
          padding: const EdgeInsets.all(LinqSpacing.s4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth > 900;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isDesktop) ...[
                    Expanded(flex: 5, child: _LeftHeroSection()),
                    const SizedBox(width: LinqSpacing.s6),
                  ],
                  Expanded(flex: 7, child: _BusinessForm()),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LeftHeroSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Build your professional vault.',
            style: LinqTextStyles.displayLg),
        const SizedBox(height: LinqSpacing.s3),
        Text(
          'Start your journey toward secure professional identity and trust verification.',
          style: LinqTextStyles.bodyLg,
        ),
        const SizedBox(height: LinqSpacing.s6),
        Container(
          height: 350,
          decoration: BoxDecoration(
            borderRadius: LinqRadius.borderLg,
            boxShadow: LinqShadows.sm,
            image: DecorationImage(
              image: CachedNetworkImageProvider(
                  'https://images.unsplash.com/photo-1581091870622-1e7d1b6d3c7c'),
              fit: BoxFit.cover,
            ),
          ),
        ),
      ],
    );
  }
}

class _BusinessForm extends StatefulWidget {
  @override
  State<_BusinessForm> createState() => _BusinessFormState();
}

class _BusinessFormState extends State<_BusinessForm> {
  String? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: LinqSpacing.s4, vertical: LinqSpacing.s2),
          decoration: BoxDecoration(
            color: LinqColors.forest100,
            borderRadius: LinqRadius.borderFull,
          ),
          child: Text('PROFESSIONAL IDENTITY',
              style: LinqTextStyles.labelSm
                  .copyWith(color: LinqColors.forest600)),
        ),
        const SizedBox(height: LinqSpacing.s5),
        Container(
          padding: const EdgeInsets.all(LinqSpacing.s6),
          decoration: BoxDecoration(
            color: LinqColors.bgSurface,
            borderRadius: LinqRadius.borderLg,
            border: Border.all(color: LinqColors.borderDefault),
            boxShadow: LinqShadows.sm,
          ),
          child: Column(
            children: [
              TextField(
                decoration: linqInputDecoration(
                    label: 'Business identity', icon: Icons.business_outlined),
              ),
              const SizedBox(height: LinqSpacing.s5),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      decoration: linqInputDecoration(
                          label: 'Primary category',
                          icon: Icons.category_outlined),
                      items: const [
                        DropdownMenuItem(
                            value: 'electrical', child: Text('Electrical')),
                        DropdownMenuItem(
                            value: 'plumbing', child: Text('Plumbing')),
                        DropdownMenuItem(value: 'hvac', child: Text('HVAC')),
                      ],
                      value: _selectedCategory,
                      onChanged: (val) =>
                          setState(() => _selectedCategory = val),
                    ),
                  ),
                  const SizedBox(width: LinqSpacing.s4),
                  Expanded(
                    child: TextField(
                      keyboardType: TextInputType.number,
                      decoration: linqInputDecoration(
                          label: 'Years of experience',
                          icon: Icons.work_history_outlined),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: LinqSpacing.s5),
              TextField(
                maxLines: 4,
                decoration: linqInputDecoration(
                    label: 'About your services',
                    icon: Icons.description_outlined),
              ),
              const SizedBox(height: LinqSpacing.s8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: linqPrimaryButton(verticalPadding: LinqSpacing.s4),
                  onPressed: () =>
                      Navigator.pushNamed(context, '/provider-verification'),
                  child: const Text('Next: verify business',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
