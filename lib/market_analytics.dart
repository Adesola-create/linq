import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'linq_theme.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;
        return Scaffold(
          backgroundColor: LinqColors.bgPageApp,
          appBar: AppBar(
            backgroundColor: LinqColors.forest500,
            foregroundColor: LinqColors.textOnBrand,
            elevation: 0,
            title: Text('LINQ-PRO',
                style: LinqTextStyles.h4
                    .copyWith(color: LinqColors.textOnBrand)),
            actions: [
              IconButton(
                icon: const Icon(Icons.notifications),
                onPressed: () {},
              ),
              const SizedBox(width: 10),
              CircleAvatar(
                backgroundImage: CachedNetworkImageProvider(
                    'https://i.pravatar.cc/150?img=5'),
              ),
              const SizedBox(width: 16),
            ],
          ),
          drawer: isDesktop ? null : const AppDrawer(),
          body: Row(
            children: [
              if (isDesktop) const AppSidebar(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(LinqSpacing.s5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const HeroHeader(),
                      const SizedBox(height: LinqSpacing.s5),
                      Wrap(
                        spacing: LinqSpacing.s4,
                        runSpacing: LinqSpacing.s4,
                        children: const [
                          InsightCard(),
                          HeatMapCard(),
                          EarningsCard(),
                          ServiceVelocityCard(),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: isDesktop ? null : const BottomNav(),
        );
      },
    );
  }
}

class HeroHeader extends StatelessWidget {
  const HeroHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        linqVerifiedBadge(),
        const SizedBox(height: LinqSpacing.s3),
        Text('Market analytics', style: LinqTextStyles.h1),
        const SizedBox(height: 6),
        Text('Intelligence-driven insights for service providers.',
            style: LinqTextStyles.bodySm),
      ],
    );
  }
}

class InsightCard extends StatelessWidget {
  const InsightCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 350,
      padding: const EdgeInsets.all(LinqSpacing.s4),
      decoration: BoxDecoration(
        color: LinqColors.forest500,
        borderRadius: LinqRadius.borderLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Actionable insight',
              style: LinqTextStyles.labelSm
                  .copyWith(color: LinqColors.forest200)),
          const SizedBox(height: LinqSpacing.s3),
          Text('Demand for plumbing is up 15% in your area.',
              style: LinqTextStyles.h3
                  .copyWith(color: LinqColors.textOnBrand)),
          const SizedBox(height: LinqSpacing.s5),
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.trending_up),
            label: const Text('Adjust rates'),
            style: ElevatedButton.styleFrom(
              backgroundColor: LinqColors.forest700,
              foregroundColor: LinqColors.textOnBrand,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: LinqRadius.borderMd),
            ),
          ),
        ],
      ),
    );
  }
}

class HeatMapCard extends StatelessWidget {
  const HeatMapCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 500,
      padding: const EdgeInsets.all(LinqSpacing.s4),
      decoration: BoxDecoration(
        color: LinqColors.bgSurface,
        borderRadius: LinqRadius.borderLg,
        border: Border.all(color: LinqColors.borderDefault),
        boxShadow: LinqShadows.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Demand heatmap', style: LinqTextStyles.h3),
          const SizedBox(height: LinqSpacing.s3),
          ClipRRect(
            borderRadius: LinqRadius.borderMd,
            child: CachedNetworkImage(
              imageUrl: 'https://images.unsplash.com/photo-1524661135-423995f22d0b?w=600',
              height: 200,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                height: 200,
                color: LinqColors.stone100,
              ),
              errorWidget: (_, __, ___) => Container(
                height: 200,
                color: LinqColors.stone100,
                child: const Icon(Icons.map,
                    size: 60, color: LinqColors.stone300),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EarningsCard extends StatelessWidget {
  const EarningsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 400,
      padding: const EdgeInsets.all(LinqSpacing.s4),
      decoration: BoxDecoration(
        color: LinqColors.bgSurface,
        borderRadius: LinqRadius.borderLg,
        border: Border.all(color: LinqColors.borderDefault),
        boxShadow: LinqShadows.xs,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Weekly earnings', style: LinqTextStyles.h4),
              Text('₦ 14,280',
                  style: LinqTextStyles.label.copyWith(
                      color: LinqColors.success500,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
          const SizedBox(height: LinqSpacing.s5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) {
              final heights = [40, 65, 85, 95, 55, 30, 45];
              return Container(
                width: 20,
                height: heights[i].toDouble(),
                decoration: BoxDecoration(
                  color: i == 3
                      ? LinqColors.forest500
                      : LinqColors.forest100,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4)),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class ServiceVelocityCard extends StatelessWidget {
  const ServiceVelocityCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 400,
      padding: const EdgeInsets.all(LinqSpacing.s4),
      decoration: BoxDecoration(
        color: LinqColors.bgSurface,
        borderRadius: LinqRadius.borderLg,
        border: Border.all(color: LinqColors.borderDefault),
        boxShadow: LinqShadows.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Service velocity', style: LinqTextStyles.h4),
          const SizedBox(height: LinqSpacing.s5),
          const ServiceRow(title: 'Emergency plumbing', level: 'High'),
          const ServiceRow(title: 'Electrical systems', level: 'Med'),
          const ServiceRow(title: 'HVAC maintenance', level: 'Low'),
        ],
      ),
    );
  }
}

class ServiceRow extends StatelessWidget {
  final String title;
  final String level;

  const ServiceRow({super.key, required this.title, required this.level});

  @override
  Widget build(BuildContext context) {
    final color = level == 'High'
        ? LinqColors.success500
        : level == 'Med'
            ? LinqColors.warning500
            : LinqColors.textTertiary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: LinqTextStyles.body),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: LinqSpacing.s2_5, vertical: LinqSpacing.s1),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: LinqRadius.borderSm,
            ),
            child: Text(level,
                style: LinqTextStyles.labelSm.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}

class AppSidebar extends StatelessWidget {
  const AppSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: LinqColors.stone100,
      child: Column(
        children: [
          const SizedBox(height: 80),
          _item(Icons.business, 'ERP'),
          _item(Icons.insights, 'Intel', active: true),
          _item(Icons.wallet, 'Pay'),
          _item(Icons.work, 'Jobs'),
        ],
      ),
    );
  }

  Widget _item(IconData icon, String label, {bool active = false}) {
    return Container(
      margin: const EdgeInsets.symmetric(
          horizontal: LinqSpacing.s3, vertical: 2),
      decoration: BoxDecoration(
        color: active ? LinqColors.forest100 : Colors.transparent,
        borderRadius: LinqRadius.borderMd,
      ),
      child: ListTile(
        leading: Icon(icon,
            color: active ? LinqColors.forest500 : LinqColors.textTertiary),
        title: Text(label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: active ? LinqColors.forest500 : LinqColors.textTertiary,
            )),
      ),
    );
  }
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return const Drawer(child: AppSidebar());
  }
}

class BottomNav extends StatelessWidget {
  const BottomNav({super.key});

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: 1,
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
        BottomNavigationBarItem(icon: Icon(Icons.business), label: 'ERP'),
        BottomNavigationBarItem(icon: Icon(Icons.insights), label: 'Intel'),
        BottomNavigationBarItem(icon: Icon(Icons.payment), label: 'Pay'),
        BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Jobs'),
      ],
    );
  }
}
