import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'linq_theme.dart';

class ServiceManagementPage extends StatelessWidget {
  const ServiceManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LinqColors.bgPageApp,
      drawer: MediaQuery.of(context).size.width < 900
          ? const Drawer(child: SidebarNavigation())
          : null,
      body: Row(
        children: [
          if (MediaQuery.of(context).size.width >= 900)
            const SizedBox(width: 260, child: SidebarNavigation()),
          Expanded(
            child: Column(
              children: [
                const TopBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(LinqSpacing.s6),
                    child: Column(
                      children: const [
                        HeroSection(),
                        SizedBox(height: LinqSpacing.s6),
                        InsightCards(),
                        SizedBox(height: LinqSpacing.s6),
                        ServiceTable(),
                        SizedBox(height: LinqSpacing.s6),
                        FooterHelpCard(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: MediaQuery.of(context).size.width < 900
          ? const MobileBottomNav()
          : null,
    );
  }
}

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: LinqSpacing.s6),
      color: LinqColors.forest500,
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundImage: CachedNetworkImageProvider('https://i.pravatar.cc/150?img=5'),
          ),
          const SizedBox(width: LinqSpacing.s4),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('LINQ-PRO',
                  style: LinqTextStyles.h4
                      .copyWith(color: LinqColors.textOnBrand)),
              Text('Service management',
                  style: LinqTextStyles.bodyXs
                      .copyWith(color: LinqColors.forest200)),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.notifications,
                color: LinqColors.textOnBrand),
            onPressed: () {},
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: LinqColors.forest700,
              foregroundColor: LinqColors.textOnBrand,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: LinqRadius.borderMd),
            ),
            onPressed: () {},
            icon: const Icon(Icons.settings, size: 16),
            label: const Text('Config'),
          ),
        ],
      ),
    );
  }
}

class SidebarNavigation extends StatelessWidget {
  const SidebarNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: LinqColors.bgSurface,
      padding: const EdgeInsets.all(LinqSpacing.s6),
      child: Column(
        children: [
          Row(children: [
            const Icon(Icons.link, color: LinqColors.forest500),
            const SizedBox(width: 10),
            Text('LINQ-TRUST',
                style: LinqTextStyles.h4
                    .copyWith(color: LinqColors.forest500)),
          ]),
          const SizedBox(height: LinqSpacing.s8),
          _navItem(Icons.business_center, 'ERP', active: true),
          _navItem(Icons.insights, 'Intel'),
          _navItem(Icons.account_balance_wallet, 'Pay'),
          _navItem(Icons.assignment, 'Jobs'),
          const Spacer(),
          const Divider(),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: LinqColors.stone100,
              child: const Icon(Icons.person, color: LinqColors.textSecondary),
            ),
            title: Text('Premium partner', style: LinqTextStyles.label),
            subtitle: linqVerifiedBadge(),
          ),
          const SizedBox(height: 10),
          Text('v2.4.0 • Enterprise engine',
              style: LinqTextStyles.bodyXs
                  .copyWith(color: LinqColors.textTertiary)),
        ],
      ),
    );
  }

  static Widget _navItem(IconData icon, String title, {bool active = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: active ? LinqColors.forest100 : Colors.transparent,
        borderRadius: LinqRadius.borderMd,
      ),
      child: ListTile(
        leading: Icon(icon,
            color: active ? LinqColors.forest500 : LinqColors.textTertiary),
        title: Text(title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: active ? LinqColors.forest500 : LinqColors.textTertiary,
            )),
      ),
    );
  }
}

class HeroSection extends StatelessWidget {
  const HeroSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              linqVerifiedBadge(),
              const SizedBox(height: LinqSpacing.s4),
              Text('Service catalogue', style: LinqTextStyles.displayLg),
              const SizedBox(height: LinqSpacing.s3),
              Text(
                'Manage your premium service packages, pricing tiers, and professional delivery schedules.',
                style: LinqTextStyles.bodyLg,
              ),
            ],
          ),
        ),
        const SizedBox(width: LinqSpacing.s5),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: LinqColors.forest500,
            foregroundColor: LinqColors.textOnBrand,
            padding: const EdgeInsets.symmetric(
                horizontal: LinqSpacing.s5, vertical: LinqSpacing.s4),
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: LinqRadius.borderMd),
          ),
          onPressed: () {},
          icon: const Icon(Icons.add),
          label: const Text('Add new service'),
        ),
      ],
    );
  }
}

class InsightCards extends StatelessWidget {
  const InsightCards({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(flex: 2, child: _performanceCard()),
        const SizedBox(width: LinqSpacing.s5),
        Expanded(child: _safetyCard()),
      ],
    );
  }

  Widget _performanceCard() {
    return Container(
      padding: const EdgeInsets.all(LinqSpacing.s6),
      decoration: BoxDecoration(
        color: LinqColors.bgSurface,
        borderRadius: LinqRadius.borderLg,
        border: Border.all(color: LinqColors.borderDefault),
        boxShadow: LinqShadows.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Service performance', style: LinqTextStyles.h3),
          const SizedBox(height: 8),
          Text('Aggregate metrics for active inspections and repairs.',
              style: LinqTextStyles.bodySm),
          const SizedBox(height: LinqSpacing.s8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              children: const [
                MetricItem('Active packages', '12'),
                SizedBox(width: LinqSpacing.s4),
                MetricItem('Avg. duration', '4.2h'),
                SizedBox(width: LinqSpacing.s4),
                MetricItem('Revenue/mo', '₦ 8.4k'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _safetyCard() {
    return Container(
      padding: const EdgeInsets.all(LinqSpacing.s6),
      decoration: BoxDecoration(
        color: LinqColors.forest500,
        borderRadius: LinqRadius.borderLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield, color: LinqColors.forest200, size: 40),
          const SizedBox(height: LinqSpacing.s5),
          Text('Safety standards',
              style: LinqTextStyles.h3
                  .copyWith(color: LinqColors.textOnBrand)),
          const SizedBox(height: LinqSpacing.s3),
          Text(
            'All services are currently compliant with IEEE Standard 1010-2023.',
            style: LinqTextStyles.bodySm
                .copyWith(color: LinqColors.forest100),
          ),
          const SizedBox(height: LinqSpacing.s5),
          Text('VIEW AUDIT LOG →',
              style: LinqTextStyles.labelSm
                  .copyWith(color: LinqColors.forest200)),
        ],
      ),
    );
  }
}

class MetricItem extends StatelessWidget {
  final String title;
  final String value;

  const MetricItem(this.title, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(),
            style: LinqTextStyles.labelSm
                .copyWith(color: LinqColors.textTertiary)),
        const SizedBox(height: 6),
        Text(value,
            style: LinqTextStyles.moneyStyle(
                fontSize: 28, color: LinqColors.forest500)),
      ],
    );
  }
}

class ServiceTable extends StatelessWidget {
  const ServiceTable({super.key});

  @override
  Widget build(BuildContext context) {
    final services = [
      ['Standard electrical inspection', '₦ 299.00', '3.5 hours', true],
      ['Emergency wiring repair', '₦ 185.00', 'Varies', true],
      ['Solar panel commissioning', '₦ 850.00', '8.0 hours', false],
    ];

    return Container(
      decoration: BoxDecoration(
        color: LinqColors.bgSurface,
        borderRadius: LinqRadius.borderLg,
        border: Border.all(color: LinqColors.borderDefault),
      ),
      child: DataTable(
        columns: [
          DataColumn(label: Text('Service name', style: LinqTextStyles.label)),
          DataColumn(label: Text('Pricing', style: LinqTextStyles.label)),
          DataColumn(label: Text('Duration', style: LinqTextStyles.label)),
          DataColumn(label: Text('Visible', style: LinqTextStyles.label)),
          DataColumn(label: Text('Actions', style: LinqTextStyles.label)),
        ],
        rows: services.map((item) {
          return DataRow(cells: [
            DataCell(Text(item[0] as String, style: LinqTextStyles.body)),
            DataCell(Text(item[1] as String,
                style: LinqTextStyles.label.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()]))),
            DataCell(Text(item[2] as String, style: LinqTextStyles.bodySm)),
            DataCell(Switch(
              value: item[3] as bool,
              activeColor: LinqColors.forest500,
              onChanged: (_) {},
            )),
            DataCell(Row(children: [
              IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.edit,
                      size: 18, color: LinqColors.textSecondary)),
              IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.delete,
                      size: 18, color: LinqColors.danger500)),
            ])),
          ]);
        }).toList(),
      ),
    );
  }
}

class FooterHelpCard extends StatelessWidget {
  const FooterHelpCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(LinqSpacing.s6),
      decoration: BoxDecoration(
        color: LinqColors.forest100,
        borderRadius: LinqRadius.borderLg,
        border: Border.all(color: LinqColors.forest200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: LinqColors.bgSurface,
            child: const Icon(Icons.lightbulb,
                color: LinqColors.forest500, size: 28),
          ),
          const SizedBox(width: LinqSpacing.s5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Need to bundle services?', style: LinqTextStyles.h4),
                const SizedBox(height: 6),
                Text(
                  'Create multi-service packages with custom discounts through the Project Builder in the Intel tab.',
                  style: LinqTextStyles.bodySm,
                ),
              ],
            ),
          ),
          const SizedBox(width: LinqSpacing.s4),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: LinqColors.forest500,
              side: const BorderSide(color: LinqColors.forest500),
              shape: RoundedRectangleBorder(
                  borderRadius: LinqRadius.borderMd),
            ),
            onPressed: () =>
                Navigator.pushNamed(context, '/market-analytics'),
            child: const Text('Access project builder'),
          ),
        ],
      ),
    );
  }
}

class MobileBottomNav extends StatelessWidget {
  const MobileBottomNav({super.key});

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: 0,
      selectedItemColor: LinqColors.forest500,
      unselectedItemColor: LinqColors.textTertiary,
      backgroundColor: LinqColors.bgSurface,
      elevation: 0,
      type: BottomNavigationBarType.fixed,
      onTap: (index) {
        switch (index) {
          case 0:
            Navigator.pushNamed(context, '/service-catalogue');
            break;
          case 1:
            Navigator.pushNamed(context, '/market-analytics');
            break;
          case 2:
            Navigator.pushNamed(context, '/wallet');
            break;
          case 3:
            Navigator.pushNamed(context, '/match-recommendation');
            break;
        }
      },
      items: const [
        BottomNavigationBarItem(
            icon: Icon(Icons.business_center), label: 'ERP'),
        BottomNavigationBarItem(icon: Icon(Icons.insights), label: 'Intel'),
        BottomNavigationBarItem(icon: Icon(Icons.payments), label: 'Pay'),
        BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble), label: 'Jobs'),
      ],
    );
  }
}
