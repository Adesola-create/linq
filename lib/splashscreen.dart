import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'linq_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    final token = await AuthService.getToken();
    print('[SplashScreen] Token: ${token != null ? '[REDACTED]' : 'null'}');
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    // Use active role (current operating role) for routing
    final activeRole = await AuthService.getActiveRole();
    print('[SplashScreen] Active role: $activeRole');
    final cachedProfile = await AuthService.getCachedProfile();
    final fallbackRole =
        (cachedProfile != null
                ? (cachedProfile['user'] is Map
                      ? cachedProfile['user']['role']
                      : cachedProfile['role'])
                : null)
            ?.toString()
            .toLowerCase();

    final effectiveRole = (activeRole != null && activeRole.isNotEmpty)
        ? activeRole
        : (fallbackRole == 'provider' ? 'provider' : 'customer');

    print('[SplashScreen] Effective role: $effectiveRole');
    if (!mounted) return;
    final route = effectiveRole == 'provider'
        ? '/provider-dashboard'
        : '/customer-dashboard';
    Navigator.pushReplacementNamed(context, route);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          /// Background Gradient
          Container(color: LinqColors.forest500),

          /// Floating Glow Effects
          Positioned(top: -100, left: -100, child: _glowCircle(300)),
          Positioned(bottom: 100, right: -80, child: _glowCircle(250)),

          /// Main Content
          SafeArea(
            child: Column(
              children: [
                /// Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'LINQ',
                        style: LinqTextStyles.h1.copyWith(
                          color: LinqColors.textOnBrand,
                          letterSpacing: 2,
                        ),
                      ),
                      // TextButton(
                      //   onPressed: () {
                      //     Navigator.pushNamed(context, '/role-selection');
                      //   },
                      //   child: const Text(
                      //     "Skip",
                      //     style: TextStyle(
                      //       color: Colors.white,
                      //       fontWeight: FontWeight.bold,
                      //     ),
                      //   ),
                      // )
                    ],
                  ),
                ),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        bool isDesktop = constraints.maxWidth > 900;

                        return isDesktop
                            ? Row(
                                children: [
                                  Expanded(child: _leftContent(context)),
                                  const SizedBox(width: 40),
                                  Expanded(child: _rightVisuals()),
                                ],
                              )
                            : _leftContent(context);
                      },
                    ),
                  ),
                ),

                /// Footer
                // Padding(
                //   padding:
                //       const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                //   child: Column(
                //     children: [
                //       const Text(
                //         "© 2024 LINQ-TRUST TECHNOLOGIES",
                //         style: TextStyle(
                //           color: Colors.white54,
                //           fontSize: 11,
                //           letterSpacing: 1.2,
                //         ),
                //       ),
                //       const SizedBox(height: 12),
                //       Row(
                //         mainAxisAlignment: MainAxisAlignment.center,
                //         children: const [
                //           FooterItem("Privacy"),
                //           FooterItem("Terms"),
                //           FooterItem("Security"),
                //         ],
                //       )
                //     ],
                //   ),
                // )
              ],
            ),
          ),

          /// Mobile Bottom Nav
          // Positioned(
          //   bottom: 0,
          //   left: 0,
          //   right: 0,
          //   child: MediaQuery.of(context).size.width < 768
          //       ? Container(
          //           padding: const EdgeInsets.only(bottom: 20, top: 12),
          //           decoration: BoxDecoration(
          //             color: Colors.white.withOpacity(0.85),
          //             borderRadius: const BorderRadius.vertical(
          //               top: Radius.circular(30),
          //             ),
          //           ),
          //           // child: Row(
          //           //   mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          //           //   children: const [
          //           //     BottomNavItem(Icons.help_outline, "Help"),
          //           //     BottomNavItem(Icons.contact_support, "Support"),
          //           //   ],
          //           // ),
          //         )
          //       : const SizedBox(),
          // ),
        ],
      ),
    );
  }

  Widget _leftContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        /// Badge
        // Container(
        //   padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        //   decoration: BoxDecoration(
        //     color: const Color(0xFF003744),
        //     borderRadius: BorderRadius.circular(30),
        //   ),
        //   // child: Row(
        //   //   mainAxisSize: MainAxisSize.min,
        //   //   children: const [
        //   //     Icon(Icons.verified_user,
        //   //         color: Color(0xFF00A8C9), size: 18),
        //   //     SizedBox(width: 8),
        //   //     Text(
        //   //       "LINQ-TRUST VERIFIED",
        //   //       style: TextStyle(
        //   //         color: Color(0xFF00A8C9),
        //   //         fontSize: 12,
        //   //         fontWeight: FontWeight.bold,
        //   //       ),
        //   //     )
        //   //   ],
        //   // ),
        // ),
        const SizedBox(height: 30),

        /// Headline
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: 'Your world,\n',
                style: LinqTextStyles.displayLg.copyWith(
                  fontSize: 48,
                  color: LinqColors.textOnBrand,
                  height: 1.15,
                ),
              ),
              TextSpan(
                text: 'connected.',
                style: LinqTextStyles.displayLg.copyWith(
                  fontSize: 48,
                  color: LinqColors.forest200,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        /// Subtitle
        SizedBox(
          width: 500,
          child: Text(
            'A standard and trusted marketplace for every service. '
            'Experience the gold standard of professional connectivity and secure transactions.',
            style: LinqTextStyles.bodyLg.copyWith(color: LinqColors.forest100),
          ),
        ),

        const SizedBox(height: 40),

        /// Buttons
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            ElevatedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/login'),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Get started'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 60,
                  vertical: 20,
                ),
                backgroundColor: LinqColors.forest600,
                foregroundColor: LinqColors.textOnBrand,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: LinqRadius.borderMd,
                ),
              ),
            ),
            // OutlinedButton(
            //   onPressed: () {},
            //   style: OutlinedButton.styleFrom(
            //     side: const BorderSide(color: Colors.white24),
            //     padding:
            //         const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
            //     shape: RoundedRectangleBorder(
            //       borderRadius: BorderRadius.circular(16),
            //     ),
            //   ),
            //   child: const Text(
            //     "Learn More",
            //     style: TextStyle(color: Colors.white),
            //   ),
            // ),
          ],
        ),
      ],
    );
  }

  Widget _rightVisuals() {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              _imageCard(
                "https://images.unsplash.com/photo-1521737604893-d14cc237f11d",
                height: 220,
              ),
              const SizedBox(height: 16),
              _infoCard(icon: Icons.shield, text: "Encrypted Protocols"),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            children: [
              _statsCard(),
              const SizedBox(height: 16),
              _imageCard(
                "https://images.unsplash.com/photo-1518770660439-4636190af475",
                height: 250,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _imageCard(String url, {required double height}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        image: DecorationImage(
          image: CachedNetworkImageProvider(url),
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _infoCard({required IconData icon, required String text}) {
    return Container(
      height: 120,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Icon(icon, color: Color(0xFF94CCFF)),
          const SizedBox(height: 12),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsCard() {
    return Container(
      height: 160,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: LinqColors.forest200,
        borderRadius: LinqRadius.borderX2l,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 20, child: Text("+12k")),
          Spacer(),
          Text(
            'Join 1,000+ verified professionals',
            style: LinqTextStyles.label.copyWith(color: LinqColors.forest700),
          ),
        ],
      ),
    );
  }

  Widget _glowCircle(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.lightBlueAccent.withOpacity(0.08),
        boxShadow: [
          BoxShadow(
            color: Colors.lightBlueAccent.withOpacity(0.12),
            blurRadius: 100,
            spreadRadius: 20,
          ),
        ],
      ),
    );
  }
}

class FooterItem extends StatelessWidget {
  final String text;
  const FooterItem(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
    );
  }
}

class BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const BottomNavItem(this.icon, this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.grey),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
