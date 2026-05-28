import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'linq_theme.dart';
import 'provider_nav_bar.dart';

class WalletDashboard extends StatelessWidget {
  const WalletDashboard({
    super.key,
    this.isProvider = false,
  });

  final bool isProvider;

  void _handleProviderNav(int index, String route, BuildContext context) {
    if (ModalRoute.of(context)?.settings.name != route) {
      Navigator.pushNamed(context, route);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 900;
        return Scaffold(
          backgroundColor: LinqColors.bgPageApp,
          appBar: AppBar(
            backgroundColor: LinqColors.forest500,
            foregroundColor: LinqColors.textOnBrand,
            elevation: 0,
            title: Text('LINQ-PAY',
                style: LinqTextStyles.h4.copyWith(
                    color: LinqColors.textOnBrand, letterSpacing: 1)),
            // actions: [
            //   const Icon(Icons.notifications),
            //   const SizedBox(width: 12),
            //   CircleAvatar(
            //     backgroundImage: CachedNetworkImageProvider(
            //         'https://i.pravatar.cc/150?img=5'),
            //   ),
            //   const SizedBox(width: 16),
            // ],
          ),
          body: Row(
            children: [
              if (isDesktop) const SideMenu(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(LinqSpacing.s5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      WalletHeader(),
                      SizedBox(height: LinqSpacing.s5),
                      WalletCardsRow(),
                      SizedBox(height: LinqSpacing.s5),
                      TransactionSection(),
                      //SizedBox(height: LinqSpacing.s5),
                      //EarningsSidebar(),
                    ],
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: isDesktop
              ? null
              : isProvider
                  ? ProviderNavBar(
                      selectedIndex: 2,
                      onNavigate: (index, route) =>
                          _handleProviderNav(index, route, context),
                    )
                  : const BottomNav(),
        );
      },
    );
  }
}

class WalletHeader extends StatelessWidget {
  const WalletHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(LinqSpacing.s6),
      decoration: BoxDecoration(
        color: LinqColors.forest500,
        borderRadius: LinqRadius.borderXl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TOTAL EARNINGS',
              style: LinqTextStyles.labelSm
                  .copyWith(color: LinqColors.forest200)),
          const SizedBox(height: LinqSpacing.s3),
          Text('₦ 14,280.50',
              style: LinqTextStyles.moneyStyle(
                  fontSize: 36, color: LinqColors.textOnBrand)),
          const SizedBox(height: LinqSpacing.s5),
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.account_balance),
            label: const Text('Withdraw funds'),
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

class WalletCardsRow extends StatelessWidget {
  const WalletCardsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 640;
        final cardWidth = isNarrow
            ? constraints.maxWidth
            : (constraints.maxWidth / 2) - LinqSpacing.s4;

        return Wrap(
          spacing: LinqSpacing.s4,
          runSpacing: LinqSpacing.s4,
          children: [
            SizedBox(
              width: cardWidth,
              child: const InfoCard(
                title: 'Pending escrow',
                value: '₦ 3,450.00',
                subtitle: 'Funds released after client approval.',
                icon: Icons.lock_clock,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: const InfoCard(
                title: 'Next payout',
                value: 'Oct 24, 2025',
                subtitle: 'GTBank account ****9012',
                icon: Icons.calendar_today,
              ),
            ),
          ],
        );
      },
    );
  }
}

class InfoCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;

  const InfoCard({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: LinqTextStyles.label),
              Icon(icon, color: LinqColors.forest500),
            ],
          ),
          const SizedBox(height: LinqSpacing.s3),
          Text(value,
              style: LinqTextStyles.moneyStyle(
                  fontSize: 20, color: LinqColors.textPrimary)),
          const SizedBox(height: 6),
          Text(subtitle, style: LinqTextStyles.bodySm),
        ],
      ),
    );
  }
}

class TransactionSection extends StatelessWidget {
  const TransactionSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Text('Transaction history', style: LinqTextStyles.h3),
          const SizedBox(height: LinqSpacing.s4),
          _tx(
            title: 'Cloud infrastructure audit',
            client: 'NexaCore Solutions',
            amount: '+₦ 2,400',
            status: 'Completed',
            statusColor: LinqColors.success500,
            icon: Icons.payments,
            iconBg: LinqColors.success50,
          ),
          _tx(
            title: 'Full-stack development sprint',
            client: 'Innovate LLC',
            amount: '₦ 1,200',
            status: 'In escrow',
            statusColor: LinqColors.info500,
            icon: Icons.hourglass_empty,
            iconBg: LinqColors.info50,
          ),
          _tx(
            title: 'Withdrawal to GTBank',
            client: 'ID: LQP-98231',
            amount: '-₦ 5,000',
            status: 'Paid out',
            statusColor: LinqColors.textTertiary,
            icon: Icons.output,
            iconBg: LinqColors.stone100,
          ),
        ],
      ),
    );
  }

  Widget _tx({
    required String title,
    required String client,
    required String amount,
    required String status,
    required Color statusColor,
    required IconData icon,
    required Color iconBg,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: iconBg,
        child: Icon(icon, color: statusColor),
      ),
      title: Text(title, style: LinqTextStyles.label),
      subtitle: Text(client, style: LinqTextStyles.bodySm),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(amount,
              style: LinqTextStyles.label
                  .copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(height: 2),
          Text(status,
              style: LinqTextStyles.bodyXs.copyWith(color: statusColor)),
        ],
      ),
    );
  }
}

// class EarningsSidebar extends StatelessWidget {
//   const EarningsSidebar({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return Column(
//       children: [
//         Container(
//           padding: const EdgeInsets.all(LinqSpacing.s4),
//           decoration: BoxDecoration(
//             color: LinqColors.bgSurface,
//             borderRadius: LinqRadius.borderLg,
//             border: Border.all(color: LinqColors.borderDefault),
//           ),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text('Security vault', style: LinqTextStyles.h4),
//               const SizedBox(height: LinqSpacing.s3),
//               Text('✔ 256-bit AES encryption',
//                   style: LinqTextStyles.bodySm),
//               Text('✔ LINQ-TRUST verification',
//                   style: LinqTextStyles.bodySm),
//             ],
//           ),
//         ),
//         const SizedBox(height: LinqSpacing.s4),
//         Container(
//           padding: const EdgeInsets.all(LinqSpacing.s4),
//           decoration: BoxDecoration(
//             color: LinqColors.forest500,
//             borderRadius: LinqRadius.borderLg,
//           ),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text('Earnings growth',
//                   style: LinqTextStyles.label
//                       .copyWith(color: LinqColors.textOnBrand)),
//               const SizedBox(height: LinqSpacing.s3),
//               Row(
//                 crossAxisAlignment: CrossAxisAlignment.end,
//                 children: List.generate(6, (i) {
//                   return Expanded(
//                     child: Container(
//                       margin: const EdgeInsets.symmetric(horizontal: 2),
//                       height: (30 + i * 15).toDouble(),
//                       decoration: BoxDecoration(
//                         color: LinqColors.forest200,
//                         borderRadius: const BorderRadius.vertical(
//                             top: Radius.circular(4)),
//                       ),
//                     ),
//                   );
//                 }),
//               ),
//             ],
//           ),
//         ),
//       ],
//     );
//   }
// }

class SideMenu extends StatelessWidget {
  const SideMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: LinqColors.stone100,
      child: Column(
        children: [
          const SizedBox(height: 80),
          _navItem(Icons.business, 'ERP'),
          _navItem(Icons.insights, 'Intel'),
          _navItem(Icons.payment, 'Pay', active: true),
          _navItem(Icons.work, 'Jobs'),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, {bool active = false}) {
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
              color: active ? LinqColors.forest500 : LinqColors.textTertiary,
              fontWeight: FontWeight.w600,
            )),
      ),
    );
  }
}

class BottomNav extends StatelessWidget {
  const BottomNav({super.key});

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: 2,
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
