import 'package:flutter/material.dart';
import 'linq_theme.dart';
import 'provider_nav_bar.dart';

class ProviderMessagesPage extends StatefulWidget {
  const ProviderMessagesPage({super.key});

  @override
  State<ProviderMessagesPage> createState() => _ProviderMessagesPageState();
}

class _ProviderMessagesPageState extends State<ProviderMessagesPage> {
  int _selectedNavIndex = 3; // Messages tab

  void _handleNavigation(int index, String route) {
    final currentRoute = ModalRoute.of(context)?.settings.name;

    if (currentRoute == route) return;

    setState(() {
      _selectedNavIndex = index;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushNamed(context, route);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LinqColors.bgPageApp,
      appBar: AppBar(
        backgroundColor: LinqColors.forest500,
        foregroundColor: LinqColors.textOnBrand,
        titleTextStyle: LinqTextStyles.h4.copyWith(color: Colors.white),
        title: const Text('Messages'),
        elevation: 0,
      ),
      bottomNavigationBar: ProviderNavBar(
        selectedIndex: _selectedNavIndex,
        onNavigate: _handleNavigation,
      ),
      body: Container(
        color: LinqColors.bgPageApp,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: LinqSpacing.s5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 72,
                  color: LinqColors.forest500,
                ),
                // const SizedBox(height: LinqSpacing.s4),
                // Text(
                //   'Your inbox',
                //   style: LinqTextStyles.h3.copyWith(
                //     color: LinqColors.textPrimary,
                //   ),
                //   textAlign: TextAlign.center,
                // ),
                const SizedBox(height: LinqSpacing.s2),
                Text(
                  'Messages from customers and service requests will appear here.',
                  style: LinqTextStyles.bodySm,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
