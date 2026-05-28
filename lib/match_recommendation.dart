import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'linq_theme.dart';

class MatchScreen extends StatelessWidget {
  const MatchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LinqColors.bgPageApp,
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
          Container(color: LinqColors.forest900.withOpacity(0.08)),
          _topBar(),
          _content(context),
          _bottomNav(context),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Positioned(
      top: 48,
      left: LinqSpacing.s4,
      right: LinqSpacing.s4,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: const [
          Icon(Icons.menu, color: LinqColors.forest500),
          CircleAvatar(
            backgroundImage:
                CachedNetworkImageProvider('https://i.pravatar.cc/150?img=5'),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    return Positioned(
      top: 100,
      left: LinqSpacing.s4,
      right: LinqSpacing.s4,
      bottom: 80,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('LINQ-MATCH recommendation', style: LinqTextStyles.h2),
            const SizedBox(height: 6),
            Text('Finding trusted emergency plumbing near you.',
                style: LinqTextStyles.bodySm),
            const SizedBox(height: LinqSpacing.s5),
            _mainProCard(),
            const SizedBox(height: LinqSpacing.s5),
            Text('Other nearby options', style: LinqTextStyles.h3),
            const SizedBox(height: LinqSpacing.s3),
            _proTile('David Chen', '4.8', '1.2 miles', '30 mins'),
            _proTile('Sarah Miller', '5.0', '2.1 miles', '45 mins'),
            const SizedBox(height: LinqSpacing.s5),
            _mapPreview(),
          ],
        ),
      ),
    );
  }

  Widget _mainProCard() {
    return Container(
      padding: const EdgeInsets.all(LinqSpacing.s4),
      decoration: BoxDecoration(
        color: LinqColors.bgSurface,
        borderRadius: LinqRadius.borderLg,
        border: Border.all(color: LinqColors.borderDefault),
        boxShadow: LinqShadows.md,
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundImage:
                    CachedNetworkImageProvider('https://i.pravatar.cc/150?img=10'),
              ),
              const SizedBox(width: LinqSpacing.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Marcus Thompson',
                        style: LinqTextStyles.h4
                            .copyWith(color: LinqColors.forest500)),
                    Text('Master plumber • Licensed',
                        style: LinqTextStyles.bodySm),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: LinqSpacing.s2_5, vertical: LinqSpacing.s1),
                decoration: BoxDecoration(
                  color: LinqColors.warning50,
                  borderRadius: LinqRadius.borderFull,
                ),
                child: Text('4.9 ⭐',
                    style: LinqTextStyles.labelSm
                        .copyWith(color: LinqColors.warning700)),
              ),
            ],
          ),
          const SizedBox(height: LinqSpacing.s5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _stat('Distance', '0.4 mi'),
              _stat('ETA', '15 min'),
              _stat('Jobs', '1.2k+'),
            ],
          ),
          const SizedBox(height: LinqSpacing.s5),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: linqPrimaryButton(verticalPadding: LinqSpacing.s3),
              onPressed: () {},
              child: const Text('Request now',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String title, String value) {
    return Column(
      children: [
        Text(title, style: LinqTextStyles.bodyXs),
        const SizedBox(height: 4),
        Text(value,
            style: LinqTextStyles.h4
                .copyWith(color: LinqColors.textPrimary)),
      ],
    );
  }

  Widget _proTile(
      String name, String rating, String distance, String eta) {
    return Container(
      margin: const EdgeInsets.only(bottom: LinqSpacing.s3),
      padding: const EdgeInsets.all(LinqSpacing.s3),
      decoration: BoxDecoration(
        color: LinqColors.bgSurface,
        borderRadius: LinqRadius.borderLg,
        border: Border.all(color: LinqColors.borderDefault),
        boxShadow: LinqShadows.xs,
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundImage:
                CachedNetworkImageProvider('https://i.pravatar.cc/150?u=$name'),
          ),
          const SizedBox(width: LinqSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: LinqTextStyles.label),
                Text('⭐ $rating • $distance away',
                    style: LinqTextStyles.bodySm),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Available', style: LinqTextStyles.bodyXs),
              Text(eta, style: LinqTextStyles.label),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mapPreview() {
    return ClipRRect(
      borderRadius: LinqRadius.borderLg,
      child: CachedNetworkImage(
        imageUrl: 'https://images.unsplash.com/photo-1524661135-423995f22d0b?w=600',
        height: 150,
        width: double.infinity,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          height: 150,
          color: LinqColors.stone100,
        ),
        errorWidget: (_, __, ___) => Container(
          height: 150,
          color: LinqColors.stone100,
          child: const Icon(Icons.map, size: 60, color: LinqColors.stone300),
        ),
      ),
    );
  }

  Widget _bottomNav(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: BottomNavigationBar(
        selectedItemColor: LinqColors.forest500,
        unselectedItemColor: LinqColors.textTertiary,
        backgroundColor: LinqColors.bgSurface,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          switch (index) {
            case 0:
              Navigator.pushNamed(context, '/match-recommendation');
              break;
            case 1:
              Navigator.pushNamed(context, '/job-details');
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
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Requests'),
          BottomNavigationBarItem(
              icon: Icon(Icons.favorite), label: 'Saved'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
