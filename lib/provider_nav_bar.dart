import 'package:flutter/material.dart';
import 'linq_theme.dart';

class ProviderNavBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int, String) onNavigate;

  const ProviderNavBar({
    super.key,
    required this.selectedIndex,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: selectedIndex,
      type: BottomNavigationBarType.fixed,
      backgroundColor: LinqColors.bgSurface,
      selectedItemColor: LinqColors.forest600,
      unselectedItemColor: LinqColors.textSecondary,
      elevation: 8,
      selectedLabelStyle: LinqTextStyles.bodyXs.copyWith(
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelStyle: LinqTextStyles.bodyXs,
      onTap: (index) {
        switch (index) {
          case 0:
            onNavigate(0, '/provider-dashboard');
            break;
          case 1:
            onNavigate(1, '/provider-jobs');
            break;
          case 2:
            onNavigate(2, '/provider-wallet');
            break;
          case 3:
            onNavigate(3, '/provider-messages');
            break;
          case 4:
            onNavigate(4, '/provider-account-profile');
            break;
        }
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.dashboard_rounded),
          label: 'Dashboard',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.work_rounded),
          label: 'Jobs',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.account_balance_wallet_rounded),
          label: 'Wallet',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.chat_bubble_rounded),
          label: 'Messages',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_rounded),
          label: 'Profile',
        ),
      ],
    );
  }
}
