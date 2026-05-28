import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'linq_theme.dart';

class MapScreen extends StatelessWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: CachedNetworkImageProvider(
                    'https://images.unsplash.com/photo-1524661135-423995f22d0b?w=800'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Container(color: LinqColors.forest900.withOpacity(0.06)),
          _buildTopBar(),
          _buildSearchBar(),
          _buildFloatingButtons(),
          _buildPins(),
          _buildUserLocation(),
          _buildBottomSheet(),
          _buildFAB(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 48,
      left: LinqSpacing.s4,
      right: LinqSpacing.s4,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: LinqSpacing.s3, vertical: LinqSpacing.s2),
            decoration: BoxDecoration(
              color: LinqColors.bgSurface,
              borderRadius: LinqRadius.borderMd,
              boxShadow: LinqShadows.sm,
            ),
            child: Row(children: [
              const Icon(Icons.menu, color: LinqColors.forest500, size: 20),
              const SizedBox(width: 8),
              Text('LINQ',
                  style: LinqTextStyles.h4.copyWith(
                      color: LinqColors.forest500, letterSpacing: 2)),
            ]),
          ),
          Row(children: [
            Container(
              padding: const EdgeInsets.all(LinqSpacing.s2),
              decoration: BoxDecoration(
                color: LinqColors.bgSurface,
                shape: BoxShape.circle,
                boxShadow: LinqShadows.sm,
              ),
              child: const Icon(Icons.notifications,
                  color: LinqColors.textSecondary, size: 20),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 18,
              backgroundImage:
                  CachedNetworkImageProvider('https://i.pravatar.cc/150?img=3'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Positioned(
      top: 110,
      left: LinqSpacing.s4,
      right: LinqSpacing.s4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: LinqSpacing.s3),
        decoration: BoxDecoration(
          color: LinqColors.bgSurface,
          borderRadius: LinqRadius.borderMd,
          boxShadow: LinqShadows.sm,
        ),
        child: Row(
          children: [
            const Icon(Icons.search, color: LinqColors.textTertiary),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search services near you…',
                  hintStyle: LinqTextStyles.body
                      .copyWith(color: LinqColors.textTertiary),
                  border: InputBorder.none,
                  filled: false,
                ),
              ),
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.tune,
                  color: LinqColors.textSecondary, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingButtons() {
    return Positioned(
      top: 180,
      right: LinqSpacing.s4,
      child: Column(
        children: [
          FloatingActionButton(
            heroTag: 'location',
            mini: true,
            backgroundColor: LinqColors.bgSurface,
            foregroundColor: LinqColors.forest500,
            elevation: 2,
            onPressed: () {},
            child: const Icon(Icons.my_location),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'layers',
            mini: true,
            backgroundColor: LinqColors.bgSurface,
            foregroundColor: LinqColors.textSecondary,
            elevation: 2,
            onPressed: () {},
            child: const Icon(Icons.layers),
          ),
        ],
      ),
    );
  }

  Widget _buildPins() {
    return Stack(
      children: [
        _pin(0.30, 0.25, LinqColors.info500, Icons.plumbing),
        _pin(0.55, 0.60, LinqColors.warning500, Icons.electrical_services),
        _pin(0.42, 0.45, LinqColors.forest500, Icons.ac_unit),
      ],
    );
  }

  Widget _pin(double top, double left, Color color, IconData icon) {
    return Positioned(
      top: MediaQueryData.fromView(
                WidgetsBinding.instance.platformDispatcher.views.first,
              ).size.height *
              top,
      left: MediaQueryData.fromView(
                WidgetsBinding.instance.platformDispatcher.views.first,
              ).size.width *
              left,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: LinqColors.bgSurface, width: 2),
          boxShadow: LinqShadows.sm,
        ),
        child: Icon(icon, color: LinqColors.textOnBrand, size: 16),
      ),
    );
  }

  Widget _buildUserLocation() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.circle, size: 14, color: LinqColors.forest500),
          SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildBottomSheet() {
    return Positioned(
      bottom: 80,
      left: LinqSpacing.s4,
      right: LinqSpacing.s4,
      child: Container(
        padding: const EdgeInsets.all(LinqSpacing.s4),
        decoration: BoxDecoration(
          color: LinqColors.bgSurface,
          borderRadius: LinqRadius.borderXl,
          boxShadow: LinqShadows.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: LinqColors.stone300,
                borderRadius: LinqRadius.borderFull,
              ),
            ),
            const SizedBox(height: LinqSpacing.s4),
            Text('34 pros active in your area',
                style: LinqTextStyles.h3),
            const SizedBox(height: LinqSpacing.s3),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: linqPrimaryButton(verticalPadding: LinqSpacing.s3),
                onPressed: () {},
                child: const Text('View list',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFAB() {
    return Positioned(
      bottom: 160,
      right: LinqSpacing.s4,
      child: FloatingActionButton(
        heroTag: 'add',
        backgroundColor: LinqColors.forest500,
        foregroundColor: LinqColors.textOnBrand,
        elevation: 2,
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return BottomNavigationBar(
      selectedItemColor: LinqColors.forest500,
      unselectedItemColor: LinqColors.textTertiary,
      backgroundColor: LinqColors.bgSurface,
      elevation: 0,
      type: BottomNavigationBarType.fixed,
      onTap: (index) {
        switch (index) {
          case 0:
            Navigator.pushNamed(context, '/nearby-map');
            break;
          case 1:
            Navigator.pushNamed(context, '/match-recommendation');
            break;
          case 2:
            Navigator.pushNamed(context, '/wallet');
            break;
          case 3:
            Navigator.pushNamed(context, '/provider-profile');
            break;
        }
      },
      items: const [
        BottomNavigationBarItem(
            icon: Icon(Icons.explore), label: 'Explore'),
        BottomNavigationBarItem(
            icon: Icon(Icons.assignment), label: 'Jobs'),
        BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet), label: 'Wallet'),
        BottomNavigationBarItem(
            icon: Icon(Icons.person), label: 'Profile'),
      ],
    );
  }
}
