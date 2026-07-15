import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'linq_theme.dart';
import 'provider_nav_bar.dart';

class ProviderDashboardScreen extends StatefulWidget {
  const ProviderDashboardScreen({super.key});

  @override
  State<ProviderDashboardScreen> createState() =>
      _ProviderDashboardScreenState();
}

class _ProviderDashboardScreenState extends State<ProviderDashboardScreen> {
  String _activeRole = 'provider';
  bool _roleLoading = true;
  bool _switchingRole = false;
  int _selectedNavIndex = 0;
  Map<String, dynamic> _currentProviderData = {};
  bool _online = true;

  @override
  void initState() {
    super.initState();
    _loadActiveRole();
    _loadCurrentProviderData();
  }

  Future<void> _loadActiveRole() async {
    final role = await AuthService.getActiveRole();
    if (mounted) {
      setState(() {
        _activeRole = role ?? 'provider';
        _roleLoading = false;
      });
    }
  }

  Future<void> _loadCurrentProviderData() async {
    try {
      final profile = await AuthService.getProviderAccountProfile();
      if (profile['success'] == true && mounted) {
        setState(() {
          _currentProviderData = profile['data'] ?? {};
        });
      }
    } catch (e) {
    }
  }

  String get _providerName =>
      _currentProviderData['name']?.toString() ?? 'LINQ Partner';

  String get _avatarUrl {
    final candidate =
        _currentProviderData['photo_url'] ??
        _currentProviderData['profile_photo'] ??
        _currentProviderData['avatar_url'] ??
        _currentProviderData['avatar'];
    return candidate?.toString() ?? '';
  }

  void _toggleOnlineStatus() {
    setState(() {
      _online = !_online;
    });
  }

  Future<void> _handleRoleSwitch(String newRole) async {
    if (newRole == _activeRole) return;

    if (!mounted) return;
    setState(() {
      _switchingRole = true;
    });


    try {
      final result = await AuthService.switchRole(newRole);

      if (!mounted) return;

      if (result['success'] == true) {
        setState(() {
          _activeRole = newRole;
          _selectedNavIndex = 0; // Reset nav index on role switch
        });

        // If switching to provider, check if provider account is set up
        if (newRole == 'provider') {
          final profileResult = await AuthService.getProviderAccountProfile(forceRefresh: true);

          if (profileResult['success'] == true) {
            final profileData = profileResult['data'] as Map<String, dynamic>?;
            if (!AuthService.hasProviderAccountProfileData(profileData)) {
              if (mounted) {
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/provider-setup',
                  (route) => false,
                );
              }
              return;
            }
          } else if (profileResult['statusCode'] == 404) {
            if (mounted) {
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/provider-setup',
                (route) => false,
              );
            }
            return;
          }
        }

        final targetRoute = newRole == 'provider'
            ? '/provider-dashboard'
            : '/customer-dashboard';


        Navigator.pushNamedAndRemoveUntil(context, targetRoute, (route) {
          return false;
        });
      } else {

        final status = result['statusCode'] is int ? result['statusCode'] as int : null;
        if (status == 409) {
          // Account already linked for that role. If we have customer data cached, navigate there.
          final cached = await AuthService.getCachedProfile();
          var hasCustomer = false;
          if (cached != null) {
            if (cached['role'] is String && cached['role'] == 'customer') hasCustomer = true;
            if (!hasCustomer && cached['user'] is Map) {
              final user = cached['user'] as Map<String, dynamic>;
              if (user['role'] is String && user['role'] == 'customer') hasCustomer = true;
            }
          }

          if (hasCustomer) {
            // Persist the role change even though the switch endpoint returned 409
            await AuthService.setActiveRole('customer');
            if (!mounted) return;
            setState(() {
              _activeRole = 'customer';
            });
            Navigator.pushNamedAndRemoveUntil(
              context,
              '/customer-dashboard',
              (route) => false,
            );
            return;
          } else {
            // Show dialog informing the user their account is already linked
            if (mounted) {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Account Linked'),
                  content: Text(result['message']?.toString() ?? 'An account is already linked for that role.'),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        setState(() { _switchingRole = false; });
                      },
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
              return;
            }
          }
        }

        setState(() {
          _switchingRole = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _switchingRole = false;
        });
      }
    }
  }

  void _showRoleMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RoleSwitchSheet(
        activeRole: _activeRole,
        onSwitch: (role) {
          Navigator.pop(ctx);
          _handleRoleSwitch(role);
        },
      ),
    );
  }

  Future<void> _handleLogout() async {
    setState(() {
      _switchingRole = true;
    });

    try {
      await AuthService.logout();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _switchingRole = false;
        });
      }
    }
  }

  void _handleNavigation(int index, String route) {
    final currentRoute = ModalRoute.of(context)?.settings.name;

    if (currentRoute == route) return;

    setState(() {
      _selectedNavIndex = index;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (route == '/provider-account-profile' &&
          _currentProviderData.isNotEmpty) {
        Navigator.pushNamed(
          context,
          route,
          arguments: _currentProviderData,
        );
      } else {
        Navigator.pushNamed(context, route);
      }
    });
  }
  @override
  Widget build(BuildContext context) {

    if (_roleLoading) {
      return Scaffold(
        backgroundColor: LinqColors.bgPageApp,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return WillPopScope(
      onWillPop: () async => false,
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: LinqColors.bgPageApp,
            bottomNavigationBar: ProviderNavBar(
              selectedIndex: _selectedNavIndex,
              onNavigate: _handleNavigation,
            ),
            body: SafeArea(
              child: Column(
                children: [
                  DashboardTopBar(
                    activeRole: _activeRole,
                    providerName: _providerName,
                    avatarUrl: _avatarUrl,
                    online: _online,
                    onRoleMenuTap: _showRoleMenu,
                    onToggleOnline: _toggleOnlineStatus,
                    onNotificationsTap: () {},
                    onLogoutTap: _handleLogout,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LinqSpacing.s5,
                      vertical: LinqSpacing.s4,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pushNamed(context, '/provider-setup');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: LinqColors.forest500,
                        ),
                        child: const Text('Open provider setup (temp)'),
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 100),
                      child: Column(
                        children: const [
                          SizedBox(height: LinqSpacing.s8),
                          ServiceManagementSection(),
                          //SizedBox(height: LinqSpacing.s5),
                          //LinqIntelInsightsSection(),
                          //SizedBox(height: LinqSpacing.s5),
                          //HeroPerformanceSection(),
                          SizedBox(height: LinqSpacing.s8),
                          QuickActionsSection(),
                          //SizedBox(height: LinqSpacing.s8),
                          //ActiveJobsSection(),
                          //SizedBox(height: LinqSpacing.s8),
                          //PerformanceAnalyticsSection(),
                          //SizedBox(height: LinqSpacing.s8),
                          //WalletPreviewSection(),
                          SizedBox(height: LinqSpacing.s8),
                          ReviewsReputationSection(),
                          SizedBox(height: LinqSpacing.s8),
                          //CalendarAvailabilitySection(),
                          //SizedBox(height: LinqSpacing.s8),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_switchingRole)
            Positioned.fill(
              child: AbsorbPointer(
                absorbing: true,
                child: Container(
                  color: LinqColors.stone900.withOpacity(0.6),
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DashboardTopBar extends StatelessWidget {
  final String activeRole;
  final String providerName;
  final String avatarUrl;
  final bool online;
  final VoidCallback onRoleMenuTap;
  final VoidCallback onNotificationsTap;
  final VoidCallback onToggleOnline;
  final VoidCallback onLogoutTap;

  const DashboardTopBar({
    super.key,
    required this.activeRole,
    required this.providerName,
    required this.avatarUrl,
    required this.online,
    required this.onRoleMenuTap,
    required this.onNotificationsTap,
    required this.onToggleOnline,
    required this.onLogoutTap,
  });

  String _getRoleDisplay(String role) {
    return role == 'provider' ? 'Service Provider' : 'Customer';
  }

  @override
  Widget build(BuildContext context) {
    final roleDisplay = _getRoleDisplay(activeRole);
    return Container(
      decoration: const BoxDecoration(
        color: LinqColors.bgSurface,
        border: Border(
          bottom: BorderSide(color: LinqColors.borderDefault),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: LinqSpacing.s5,
        vertical: LinqSpacing.s4,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'LINQ',
            style: LinqTextStyles.h4.copyWith(
              color: LinqColors.forest500,
              letterSpacing: 2,
              fontWeight: FontWeight.w900,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: onRoleMenuTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: LinqSpacing.s3,
                    vertical: LinqSpacing.s2,
                  ),
                  decoration: BoxDecoration(
                    color: LinqColors.forest50,
                    border: Border.all(color: LinqColors.forest200),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: LinqColors.forest500,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person,
                          color: LinqColors.textOnBrand,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: LinqSpacing.s2),
                      Text(
                        roleDisplay,
                        style: LinqTextStyles.label.copyWith(
                          color: LinqColors.forest500,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: LinqSpacing.s1),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: LinqColors.forest500,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: LinqSpacing.s3),
              IconButton(
                onPressed: onNotificationsTap,
                icon: const Icon(Icons.notifications_none_rounded),
                color: LinqColors.forest500,
              ),
              IconButton(
                onPressed: onLogoutTap,
                icon: const Icon(Icons.logout_rounded),
                color: LinqColors.forest500,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleSwitchSheet extends StatefulWidget {
  final String activeRole;
  final void Function(String) onSwitch;

  const _RoleSwitchSheet({required this.activeRole, required this.onSwitch});

  @override
  State<_RoleSwitchSheet> createState() => _RoleSwitchSheetState();
}

class _RoleSwitchSheetState extends State<_RoleSwitchSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          decoration: const BoxDecoration(
            color: LinqColors.bgSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: LinqSpacing.s3),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: LinqColors.stone300,
                  borderRadius: LinqRadius.borderFull,
                ),
              ),
              Container(
                margin: const EdgeInsets.all(LinqSpacing.s5),
                padding: const EdgeInsets.all(LinqSpacing.s5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [LinqColors.forest500, LinqColors.forest700],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: LinqRadius.borderXl,
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(LinqSpacing.s3),
                        decoration: BoxDecoration(
                          color: LinqColors.forest700,
                          borderRadius: LinqRadius.borderLg,
                        ),
                        child: const Icon(
                          Icons.swap_horiz_rounded,
                          color: LinqColors.textOnBrand,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: LinqSpacing.s4),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Switch Account Mode',
                            style: LinqTextStyles.h4.copyWith(
                              color: LinqColors.textOnBrand,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'One account, two powerful modes',
                        style: LinqTextStyles.bodySm.copyWith(
                          color: LinqColors.forest200,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: LinqSpacing.s5),
                child: Column(
                  children: [
                    _RoleOptionTile(
                      title: 'Customer',
                      subtitle: 'Browse and book services near you',
                      icon: Icons.explore_rounded,
                      isActive: widget.activeRole == 'customer',
                      onTap: () => widget.onSwitch('customer'),
                    ),
                    const SizedBox(height: LinqSpacing.s3),
                    _RoleOptionTile(
                      title: 'Service Provider',
                      subtitle: 'Manage your services and jobs',
                      icon: Icons.business_center_rounded,
                      isActive: widget.activeRole == 'provider',
                      onTap: () => widget.onSwitch('provider'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: LinqSpacing.s8),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleOptionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _RoleOptionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: isActive ? LinqColors.forest50 : LinqColors.bgPageApp,
        border: Border.all(
          color: isActive ? LinqColors.forest500 : LinqColors.borderDefault,
          width: isActive ? 2 : 1,
        ),
        borderRadius: LinqRadius.borderLg,
        boxShadow: isActive ? LinqShadows.sm : LinqShadows.none,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: LinqRadius.borderLg,
          child: Padding(
            padding: const EdgeInsets.all(LinqSpacing.s4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(LinqSpacing.s3),
                    decoration: BoxDecoration(
                      color: isActive
                          ? LinqColors.forest500
                          : LinqColors.stone100,
                      borderRadius: LinqRadius.borderMd,
                    ),
                    child: Icon(
                      icon,
                      color: isActive
                          ? LinqColors.textOnBrand
                          : LinqColors.textTertiary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: LinqSpacing.s4),
                  SizedBox(
                    width: 200,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: LinqTextStyles.h4.copyWith(
                            color: isActive
                                ? LinqColors.forest500
                                : LinqColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: LinqTextStyles.bodySm,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: LinqSpacing.s4),
                  if (isActive)
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: LinqColors.forest500,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: LinqColors.textOnBrand,
                        size: 14,
                      ),
                    )
                  else
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        border: Border.all(color: LinqColors.borderDefault),
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// class HeroPerformanceSection extends StatelessWidget {
//   const HeroPerformanceSection({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: LinqSpacing.s5),
//       child: Column(
//         children: [
//           Container(
//             width: double.infinity,
//             padding: const EdgeInsets.all(LinqSpacing.s6),
//             decoration: BoxDecoration(
//               color: LinqColors.forest500,
//               borderRadius: LinqRadius.borderXl,
//             ),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   'TOTAL EARNINGS',
//                   style: LinqTextStyles.labelSm.copyWith(
//                     color: LinqColors.forest200,
//                   ),
//                 ),
//                 const SizedBox(height: LinqSpacing.s4),
//                 Text(
//                   '₦ 14,280.50',
//                   style: LinqTextStyles.moneyStyle(
//                     fontSize: 42,
//                     color: LinqColors.textOnBrand,
//                   ),
//                 ),
//                 const SizedBox(height: LinqSpacing.s8),
//                 Container(
//                   padding: const EdgeInsets.symmetric(
//                     horizontal: LinqSpacing.s4,
//                     vertical: LinqSpacing.s2_5,
//                   ),
//                   decoration: BoxDecoration(
//                     color: LinqColors.forest700,
//                     borderRadius: LinqRadius.borderFull,
//                   ),
//                   child: Row(
//                     mainAxisSize: MainAxisSize.min,
//                     children: [
//                       const Icon(
//                         Icons.trending_up,
//                         color: LinqColors.forest200,
//                         size: 18,
//                       ),
//                       const SizedBox(width: 8),
//                       Text(
//                         '+12% vs last month',
//                         style: LinqTextStyles.bodySm.copyWith(
//                           color: LinqColors.textOnBrand,
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               ],
//             ),
//           ),
//           const SizedBox(height: LinqSpacing.s5),
//           Container(
//             width: double.infinity,
//             padding: const EdgeInsets.all(LinqSpacing.s6),
//             decoration: BoxDecoration(
//               color: LinqColors.forest100,
//               borderRadius: LinqRadius.borderXl,
//             ),
//             child: Column(
//               children: [
//                 const Icon(
//                   Icons.work_history,
//                   size: 42,
//                   color: LinqColors.forest500,
//                 ),
//                 const SizedBox(height: LinqSpacing.s3),
//                 Text(
//                   '24',
//                   style: LinqTextStyles.moneyStyle(
//                     fontSize: 40,
//                     color: LinqColors.forest500,
//                   ),
//                 ),
//                 Text(
//                   'Active jobs',
//                   style: LinqTextStyles.label.copyWith(
//                     color: LinqColors.forest600,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

class QuickActionsSection extends StatelessWidget {
  const QuickActionsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final actions = [
      {
        'icon': Icons.work_outline_rounded,
        'title': 'Active Jobs',
        'subtitle': 'See your current appointments',
      },
      {
        'icon': Icons.local_offer_rounded,
        'title': 'Promotions',
        'subtitle': 'Update your service offers',
      },
      {
        'icon': Icons.book,
        'title': 'Portfolio',
        'subtitle': 'Edit your work samples',
      },
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LinqSpacing.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Quick actions', style: LinqTextStyles.h3),
              // Text(
              //   'Manage',
              //   style: LinqTextStyles.bodySm.copyWith(
              //     color: LinqColors.forest500,
              //   ),
              // ),
            ],
          ),
          const SizedBox(height: LinqSpacing.s4),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: actions.map((action) {
              return SizedBox(
                width: MediaQuery.of(context).size.width / 2.4,
                child: Container(
                  padding: const EdgeInsets.all(LinqSpacing.s4),
                  decoration: BoxDecoration(
                    color: LinqColors.bgSurface,
                    borderRadius: LinqRadius.borderXl,
                    border: Border.all(
                      color: LinqColors.borderDefault,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        action['icon'] as IconData,
                        color: LinqColors.forest500,
                      ),
                      const SizedBox(height: LinqSpacing.s3),
                      Text(
                        action['title'] as String,
                        style: LinqTextStyles.label,
                      ),
                      const SizedBox(height: LinqSpacing.s2),
                      Text(
                        action['subtitle'] as String,
                        textAlign: TextAlign.center,
                        style: LinqTextStyles.bodyXs,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// class ActiveJobsSection extends StatelessWidget {
//   const ActiveJobsSection({super.key});

//   @override
//   Widget build(BuildContext context) {
//     final stats = [
//       {'label': 'In progress', 'value': '8', 'color': LinqColors.forest500},
//       {'label': 'New requests', 'value': '5', 'color': LinqColors.forest400},
//       {'label': 'Completed', 'value': '18', 'color': LinqColors.forest300},
//     ];

//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: LinqSpacing.s5),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Text('Active jobs', style: LinqTextStyles.h3),
//           const SizedBox(height: LinqSpacing.s4),
//           Wrap(
//             spacing: 12,
//             runSpacing: 12,
//             children: stats.map((stat) {
//               return SizedBox(
//                 width: MediaQuery.of(context).size.width / 3.4,
//                 child: Container(
//                   padding: const EdgeInsets.all(LinqSpacing.s4),
//                   decoration: BoxDecoration(
//                     color: LinqColors.bgSurface,
//                     borderRadius: LinqRadius.borderXl,
//                     border: Border.all(
//                       color: LinqColors.borderDefault,
//                     ),
//                   ),
//                   child: Column(
//                     children: [
//                       Text(
//                         stat['value'] as String,
//                         style: LinqTextStyles.h3.copyWith(
//                           color: stat['color'] as Color,
//                         ),
//                       ),
//                       const SizedBox(height: LinqSpacing.s2),
//                       Text(
//                         stat['label'] as String,
//                         textAlign: TextAlign.center,
//                         style: LinqTextStyles.bodySm,
//                       ),
//                     ],
//                   ),
//                 ),
//               );
//             }).toList(),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class PerformanceAnalyticsSection extends StatelessWidget {
//   const PerformanceAnalyticsSection({super.key});

//   @override
//   Widget build(BuildContext context) {
//     final entries = [
//       {'title': 'Response time', 'value': '95%', 'subtitle': 'Within 30 mins'},
//       {
//         'title': 'Success rate',
//         'value': '89%',
//         'subtitle': 'On-time completion',
//       },
//     ];

//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: LinqSpacing.s5),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Text('Performance analytics', style: LinqTextStyles.h3),
//           const SizedBox(height: LinqSpacing.s4),
//           Container(
//             width: double.infinity,
//             padding: const EdgeInsets.all(LinqSpacing.s5),
//             decoration: BoxDecoration(
//               color: LinqColors.bgSurface,
//               borderRadius: LinqRadius.borderXl,
//               border: Border.all(color: LinqColors.borderDefault),
//             ),
//             child: Column(
//               children: entries.map((entry) {
//                 return Padding(
//                   padding: const EdgeInsets.only(bottom: LinqSpacing.s4),
//                   child: Wrap(
//   spacing: 12,
//   runSpacing: 12,
//   alignment: WrapAlignment.spaceBetween,
//   crossAxisAlignment: WrapCrossAlignment.center,
//   children: [
//                       Column(
//                         crossAxisAlignment: CrossAxisAlignment.start,
//                         children: [
//                           Text(
//                             entry['title'] as String,
//                             style: LinqTextStyles.label,
//                           ),
//                           const SizedBox(height: LinqSpacing.s1),
//                           Text(
//                             entry['subtitle'] as String,
//                             style: LinqTextStyles.bodyXs,
//                           ),
//                         ],
//                       ),
//                       Text(entry['value'] as String, style: LinqTextStyles.h4),
//                     ],
//                   ),
//                 );
//               }).toList(),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

class WalletPreviewSection extends StatelessWidget {
  const WalletPreviewSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LinqSpacing.s5),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(LinqSpacing.s6),
        decoration: BoxDecoration(
          color: LinqColors.stone100,
          borderRadius: LinqRadius.borderXl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Wallet overview', style: LinqTextStyles.h3),
            const SizedBox(height: LinqSpacing.s4),
            Text('₦ 5,930.20', style: LinqTextStyles.moneyStyle(fontSize: 34)),
            const SizedBox(height: LinqSpacing.s4),
            Wrap(
  spacing: 12,
  runSpacing: 12,
  alignment: WrapAlignment.spaceBetween,
  crossAxisAlignment: WrapCrossAlignment.center,
  children: [
                Text('Available balance', style: LinqTextStyles.bodySm),
                ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: LinqColors.forest600,
                    shape: RoundedRectangleBorder(
                      borderRadius: LinqRadius.borderXl,
                    ),
                  ),
                  child: const Text('Withdraw'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ReviewsReputationSection extends StatelessWidget {
  const ReviewsReputationSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LinqSpacing.s5),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(LinqSpacing.s6),
        decoration: BoxDecoration(
          color: LinqColors.bgSurface,
          borderRadius: LinqRadius.borderXl,
          border: Border.all(color: LinqColors.borderDefault),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reviews & reputation', style: LinqTextStyles.h3),
            const SizedBox(height: LinqSpacing.s4),
            Wrap(
  spacing: 12,
  runSpacing: 12,
  crossAxisAlignment: WrapCrossAlignment.center,
  children: [
    Text('4.9', style: LinqTextStyles.moneyStyle(fontSize: 38)),
    SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Average rating', style: LinqTextStyles.bodySm),
          const SizedBox(height: LinqSpacing.s1),
          Text('275 reviews', style: LinqTextStyles.bodyXs),
        ],
      ),
    ),
  ],
),],
        ),
      ),
    );
  }
}

class ServiceManagementSection extends StatelessWidget {
  const ServiceManagementSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LinqSpacing.s5),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(LinqSpacing.s6),
        decoration: BoxDecoration(
          color: LinqColors.forest500,
          borderRadius: LinqRadius.borderXl,
          border: Border.all(color: LinqColors.borderDefault),
          boxShadow: LinqShadows.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Service management', style: LinqTextStyles.h2.copyWith(color: LinqColors.textOnBrand)),
            const SizedBox(height: LinqSpacing.s4),
            Text(
              'Keep your services up-to-date, control availability, and stay responsive to customer demand.',
              style: LinqTextStyles.bodySm.copyWith(color: LinqColors.textOnBrand),
            ),
            const SizedBox(height: LinqSpacing.s5),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Expanded(
                //   child: Wrap(
                //     spacing: 8,
                //     runSpacing: 8,
                //     children: [
                //       _statusChip('12 active services'),
                //       _statusChip('4 pending requests'),
                //       _statusChip('24 upcoming bookings'),
                //     ],
                //   ),
                // ),
                const SizedBox(width: LinqSpacing.s4),
                TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(
                    backgroundColor: LinqColors.forest200,
                    foregroundColor: LinqColors.textOnBrand,
                    padding: const EdgeInsets.symmetric(
                      horizontal: LinqSpacing.s4,
                      vertical: LinqSpacing.s3,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: LinqRadius.borderXl,
                    ),
                  ),
                  child: const Text('View'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LinqSpacing.s3,
        vertical: LinqSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: LinqColors.bgSurface,
        borderRadius: LinqRadius.borderFull,
        border: Border.all(color: LinqColors.borderDefault),
      ),
      child: Text(
        label,
        style: LinqTextStyles.bodyXs.copyWith(
          color: LinqColors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class CalendarAvailabilitySection extends StatelessWidget {
  const CalendarAvailabilitySection({super.key});

  @override
  Widget build(BuildContext context) {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LinqSpacing.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Calendar availability', style: LinqTextStyles.h3),
          const SizedBox(height: LinqSpacing.s4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: days.map((day) {
              final selected = day == 'Fri';

              return Container(
                width: 48,
                padding: const EdgeInsets.symmetric(
                  vertical: LinqSpacing.s3,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? LinqColors.forest500
                      : LinqColors.bgSurface,
                  borderRadius: LinqRadius.borderMd,
                ),
                child: Text(
                  day,
                  textAlign: TextAlign.center,
                  style: LinqTextStyles.bodySm.copyWith(
                    color: selected
                        ? LinqColors.textOnBrand
                        : LinqColors.textPrimary,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class UpcomingAppointmentsSection extends StatelessWidget {
  const UpcomingAppointmentsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final appointments = [
      {
        'name': 'Marcus Richardson',
        'location': 'Upper East Side, Lagos',
        'service': 'Emergency Plumbing',
        'time': '02:30 PM',
        'image': 'https://i.pravatar.cc/150?img=11',
      },
      {
        'name': 'Elena Rodriguez',
        'location': 'Victoria Island',
        'service': 'Smart Home Setup',
        'time': '05:00 PM',
        'image': 'https://i.pravatar.cc/150?img=20',
      },
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LinqSpacing.s5),
      child: Column(
        children: [
          Wrap(
  spacing: 12,
  runSpacing: 12,
  alignment: WrapAlignment.spaceBetween,
  crossAxisAlignment: WrapCrossAlignment.center,
  children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Upcoming appointments', style: LinqTextStyles.h3),
                  Text('Today and tomorrow', style: LinqTextStyles.bodySm),
                ],
              ),
              TextButton(
                onPressed: () {},
                child: Text(
                  'View calendar',
                  style: LinqTextStyles.bodySm.copyWith(
                    color: LinqColors.forest500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: LinqSpacing.s5),
          ...appointments.map((item) => AppointmentCard(data: item)),
        ],
      ),
    );
  }
}

class AppointmentCard extends StatelessWidget {
  final Map data;
  const AppointmentCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: LinqSpacing.s4),
      padding: const EdgeInsets.all(LinqSpacing.s4),
      decoration: BoxDecoration(
        color: LinqColors.bgSurface,
        borderRadius: LinqRadius.borderLg,
        border: Border.all(color: LinqColors.borderDefault),
        boxShadow: LinqShadows.xs,
      ),
      child: Row(
        children: [
          linqAvatar(radius: 28, imageUrl: data['image']?.toString()),
          const SizedBox(width: LinqSpacing.s4),
          SizedBox(
  width: MediaQuery.of(context).size.width * 0.42,
  child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data['name'],
                  style: LinqTextStyles.h4.copyWith(
                    color: LinqColors.forest500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(data['location'], style: LinqTextStyles.bodySm),
                const SizedBox(height: 4),
                Text(
                  data['service'],
                  style: LinqTextStyles.label.copyWith(
                    color: LinqColors.forest400,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                data['time'],
                style: LinqTextStyles.h4.copyWith(
                  color: LinqColors.textPrimary,
                ),
              ),
              const SizedBox(height: LinqSpacing.s2_5),
              CircleAvatar(
                backgroundColor: LinqColors.forest500,
                radius: 16,
                child: const Icon(
                  Icons.chevron_right,
                  color: LinqColors.textOnBrand,
                  size: 18,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class LinqIntelInsightsSection extends StatelessWidget {
  const LinqIntelInsightsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final heights = [40.0, 60.0, 45.0, 85.0, 55.0, 70.0];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LinqSpacing.s5),
      child: Container(
        padding: const EdgeInsets.all(LinqSpacing.s6),
        decoration: BoxDecoration(
          color: LinqColors.stone100,
          borderRadius: LinqRadius.borderXl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.analytics, color: LinqColors.forest500),
                  const SizedBox(width: 8),
                  Text('Analytic insights', style: LinqTextStyles.h3),
                ],
              ),
            ),
            const SizedBox(height: LinqSpacing.s6),
            Container(
              padding: const EdgeInsets.all(LinqSpacing.s5),
              decoration: BoxDecoration(
                color: LinqColors.bgSurface,
                borderRadius: LinqRadius.borderLg,
                border: Border.all(color: LinqColors.borderDefault),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MARKET DEMAND TREND',
                    style: LinqTextStyles.labelSm.copyWith(
                      color: LinqColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: LinqSpacing.s5),
                  SizedBox(
                    height: 120,
                    width: double.infinity,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final barWidth = (constraints.maxWidth / heights.length) - 4;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: heights.map((h) {
                            return SizedBox(
                              width: barWidth.clamp(0, constraints.maxWidth),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: Container(
                                  height: h,
                                  decoration: BoxDecoration(
                                    color: h == 85
                                        ? LinqColors.forest500
                                        : LinqColors.forest200,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(4),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: LinqSpacing.s4),
                  Text(
                    'Demand for HVAC maintenance is up 32% in your area.',
                    style: LinqTextStyles.bodySm,
                  ),
                ],
              ),
            ),
            const SizedBox(height: LinqSpacing.s6),
            _insightTile(
              Icons.payments,
              LinqColors.forest500,
              'Earnings optimisation',
              'Recommended rate increase: +₦500/hr based on local market.',
            ),
            const SizedBox(height: LinqSpacing.s4),
            _insightTile(
              Icons.map,
              LinqColors.forest400,
              'Hotspot alert',
              'Victoria Island is showing high request volume for home security installs today.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _insightTile(IconData icon, Color bg, String title, String subtitle) {
    return Container(
      decoration: BoxDecoration(
        color: LinqColors.bgSurface,
        borderRadius: LinqRadius.borderLg,
        border: Border.all(color: LinqColors.borderDefault),
      ),
      padding: const EdgeInsets.all(LinqSpacing.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(LinqSpacing.s3),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: LinqRadius.borderLg,
            ),
            child: Icon(icon, color: LinqColors.textOnBrand),
          ),
          const SizedBox(width: LinqSpacing.s4),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: LinqTextStyles.label),
                const SizedBox(height: 2),
                Text(subtitle, style: LinqTextStyles.bodySm),
              ],
            ),
          ),
        ],
      ),
    );
  }
}