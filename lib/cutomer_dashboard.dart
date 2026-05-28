import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'location_service.dart';
import 'auth_service.dart';
import 'linq_theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  List<Map<String, dynamic>> _categories = [];
  bool _categoriesLoading = true;
  String? _categoriesError;

  List<Map<String, dynamic>> _providers = [];
  bool _providersLoading = true;
  String? _providersError;

  late String _activeRole;
  bool _roleLoading = true;
  bool _switchingRole = false;
  int _selectedNavIndex = 0;

  static const _cacheKeyProviders = 'cached_providers';

  static String _serverImageUrl(Map<String, dynamic> provider) {
    final candidates = [
      provider['photo_url'],
      provider['profile_photo'],
      provider['profile_photo_url'],
      provider['profile_picture'],
      provider['profile_picture_url'],
      provider['picture'],
      provider['picture_url'],
      provider['avatar_url'],
      provider['image_url'],
      provider['image'],
      provider['photo'],
      provider['avatar'],
    ];

    for (final candidate in candidates) {
      final url = candidate?.toString().trim() ?? '';
      if (url.isNotEmpty && !_isGeneratedOrDocumentImage(url)) {
        return url;
      }
    }
    return '';
  }

  static bool _isGeneratedOrDocumentImage(String url) {
    final lower = url.toLowerCase();
    return lower.contains('i.pravatar.cc');
  }

  static IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('electr')) return Icons.bolt;
    if (n.contains('plumb')) return Icons.plumbing;
    if (n.contains('hair') || n.contains('barb')) return Icons.content_cut;
    if (n.contains('paint')) return Icons.brush;
    if (n.contains('clean')) return Icons.cleaning_services;
    if (n.contains('garden') || n.contains('lawn')) return Icons.yard;
    if (n.contains('carpen') || n.contains('wood')) return Icons.carpenter;
    if (n.contains('hvac') || n.contains('air')) return Icons.air;
    if (n.contains('roof')) return Icons.roofing;
    if (n.contains('tile') || n.contains('floor')) return Icons.grid_on;
    if (n.contains('mov')) return Icons.local_shipping;
    if (n.contains('it') || n.contains('tech')) return Icons.computer;
    if (n.contains('secur')) return Icons.security;
    if (n.contains('weld')) return Icons.hardware;
    return Icons.home_repair_service;
  }

  @override
  void initState() {
    super.initState();
    _loadActiveRole();
    _loadCategories();
    _loadProvidersFromCacheFirst();
  }

  Future<void> _loadActiveRole() async {
    final role = await AuthService.getActiveRole();
    print('[CustomerDashboard] Loaded active role: $role');
    if (mounted) {
      setState(() {
        _activeRole = role ?? 'customer';
        _roleLoading = false;
      });
    }
  }

  Future<void> _handleRoleSwitch(String newRole) async {
    if (newRole == _activeRole) {
      print('[CustomerDashboard] Role switch ignored - already in $newRole mode');
      return;
    }

    if (!mounted) return;
    setState(() {
      _switchingRole = true;
    });

    print('[CustomerDashboard] Initiating role switch from $_activeRole to $newRole');

    try {
      final result = await AuthService.switchRole(newRole);
      print('[CustomerDashboard] switchRole result: $result');

      if (!mounted) return;

      if (result['success'] == true) {
        print('[CustomerDashboard] Role switch successful, updating state');
        setState(() {
          _activeRole = newRole;
        });

        final targetRoute =
            newRole == 'provider' ? '/provider-dashboard' : '/customer-dashboard';
        
        print('[CustomerDashboard] Navigating to: $targetRoute');
        
        Navigator.pushNamedAndRemoveUntil(
          context,
          targetRoute,
          (route) {
            print('[CustomerDashboard] Removing route: ${route.settings.name}');
            return false;
          },
        );
      } else {
        print('[CustomerDashboard] Role switch failed: ${result['message']}');
        setState(() {
          _switchingRole = false;
        });
      }
    } catch (error) {
      print('[CustomerDashboard] Role switch error: $error');
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

  void _handleNavigation(int index, String route) {
    print('[CustomerDashboard] Navigation tapped: index=$index, route=$route');
    
    final currentRoute = ModalRoute.of(context)?.settings.name;
    print('[CustomerDashboard] Current route: $currentRoute');
    
    if (currentRoute == route) {
      print('[CustomerDashboard] Already on this route, skipping navigation');
      return;
    }

    setState(() {
      _selectedNavIndex = index;
    });

    Navigator.pushReplacementNamed(context, route);
  }

  Future<void> _loadProvidersFromCacheFirst() async {
    // First try AuthService's persistent provider cache
    final cachedProviders = await AuthService.getProvidersList();
    if (cachedProviders != null && cachedProviders.isNotEmpty) {
      if (mounted) {
        setState(() {
          _providers = cachedProviders
              .map((provider) => _mapProvider(provider))
              .toList();
          _providersLoading = false;
        });
      }
      print(
        '[Dashboard] Loaded ${cachedProviders.length} providers from persistent cache',
      );
      await _initLocation(forceRefresh: true);
      return;
    }

    // Fallback to old cache format
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKeyProviders);
    if (cached != null) {
      final List<dynamic> raw = jsonDecode(cached);
      final cachedProviders = raw.cast<Map<String, dynamic>>();
      final hasHardcodedImages = cachedProviders.any(
        (p) => (p['image'] ?? '').toString().contains('i.pravatar.cc'),
      );
      if (hasHardcodedImages) {
        await prefs.remove(_cacheKeyProviders);
        await _initLocation(forceRefresh: true);
        return;
      }
      if (mounted) {
        setState(() {
          _providers = cachedProviders;
          _providersLoading = false;
        });
      }
      await _initLocation(forceRefresh: true);
      return;
    }
    await _initLocation();
  }

  Future<void> _loadCategories({bool forceRefresh = false}) async {
    setState(() {
      _categoriesLoading = true;
      _categoriesError = null;
    });
    final result = await AuthService.getCategories(forceRefresh: forceRefresh);
    if (!mounted) return;
    if (result['success'] == true) {
      final raw = result['data'] as List<dynamic>;
      setState(() {
        _categories = raw
            .map((item) {
              final name =
                  (item['name'] ?? item['title'] ?? item['category'] ?? '')
                      .toString();
              final id = (item['ulid'] ?? item['id'] ?? item['_id'] ?? '')
                  .toString();
              final slug = (item['slug'] ?? '').toString();
              final children = (item['children'] is List
                  ? (item['children'] as List)
                        .map(
                          (c) => <String, dynamic>{
                            'id': (c['ulid'] ?? c['id'] ?? c['_id'] ?? '')
                                .toString(),
                            'slug': (c['slug'] ?? '').toString(),
                            'name': (c['name'] ?? '').toString(),
                          },
                        )
                        .toList()
                  : <Map<String, dynamic>>[]);
              print(
                '[Dashboard] category="$name" id="$id" slug="$slug" childCount=${children.length}',
              );
              return <String, dynamic>{
                'id': id,
                'slug': slug,
                'name': name,
                'icon': _iconFor(name),
                'children': children,
              };
            })
            .where((c) => (c['name'] as String).isNotEmpty)
            .toList();
        _categoriesLoading = false;
      });
    } else {
      setState(() {
        _categoriesError = result['message'] ?? 'Failed to load categories.';
        _categoriesLoading = false;
      });
    }
  }

  Map<String, dynamic> _mapProvider(Map<String, dynamic> p) {
    final categories = p['categories'] as List<dynamic>? ?? [];
    final role = categories.isNotEmpty
        ? categories.map((c) => c['name']).join(', ')
        : 'Service Provider';
    return <String, dynamic>{
      'ulid': p['ulid'] ?? '',
      'name': p['name'] ?? 'Unknown',
      'role': role,
      'bio': p['bio'] ?? '',
      'rating': p['avg_rating']?.toString() ?? p['rating']?.toString() ?? '0.0',
      'rating_count': (p['rating_count'] ?? 0).toString(),
      'distance': p['distance'] != null ? '${p['distance']} miles' : 'Nearby',
      'availability': p['is_available'] == true
          ? 'Available Today'
          : 'Check Schedule',
      'image': _serverImageUrl(p),
      'raw': p,
    };
  }

  Future<void> _initLocation({bool forceRefresh = false}) async {
    final result = await LocationService.fetchLocation();
    if (result['success'] == true) {
      await _loadProviders(
        lat: result['lat'],
        lng: result['lng'],
        forceRefresh: forceRefresh,
      );
    } else {
      await _loadProviders(forceRefresh: forceRefresh);
    }
  }

  Future<void> _loadProviders({
    double? lat,
    double? lng,
    bool forceRefresh = false,
  }) async {
    setState(() {
      _providersLoading = true;
      _providersError = null;
    });
    final result = await AuthService.getProviders(
      lat: lat,
      lng: lng,
      forceRefresh: forceRefresh,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      final raw = result['data'] as List<dynamic>;
      final mapped = raw
          .cast<Map<String, dynamic>>()
          .map(_mapProvider)
          .toList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKeyProviders, jsonEncode(mapped));

      setState(() {
        _providers = mapped;
        _providersLoading = false;
      });
    } else {
      setState(() {
        _providersError = result['message'];
        _providersLoading = false;
      });
    }
  }

  Future<void> _onRefresh() async {
    await Future.wait([
      _loadCategories(forceRefresh: true),
      _initLocation(forceRefresh: true),
    ]);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredCategories => _query.isEmpty
      ? _categories
      : _categories
            .where((c) => c['name'].toString().toLowerCase().contains(_query))
            .toList();

  List<Map<String, dynamic>> get _filteredProviders => _query.isEmpty
      ? _providers
      : _providers
            .where(
              (p) =>
                  p['name'].toString().toLowerCase().contains(_query) ||
                  p['role'].toString().toLowerCase().contains(_query),
            )
            .toList();

  @override
  Widget build(BuildContext context) {
    final noResults =
        _query.isNotEmpty &&
        _filteredCategories.isEmpty &&
        _filteredProviders.isEmpty;

    return WillPopScope(
      onWillPop: () async => false, // Prevent back button from popping to login
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: LinqColors.bgPageApp,
            bottomNavigationBar: BottomNavBar(
              selectedIndex: _selectedNavIndex,
              onNavigate: _handleNavigation,
            ),
            body: SafeArea(
              child: Column(
                children: [
                  _buildTopBar(),
                  _buildHeroSection(),
                  Expanded(
                    child: noResults
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            onRefresh: _onRefresh,
                            color: LinqColors.forest500,
                            child: SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: Column(
                                children: [
                                  _buildCategories(),
                                  _buildLinqMatchSection(),
                                  _buildTrustBanner(),
                                  const SizedBox(height: 100),
                                ],
                              ),
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
                    child: CircularProgressIndicator(
                      color: LinqColors.forest500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    final roleDisplay = _roleLoading
        ? 'Loading...'
        : (_activeRole == 'provider' ? 'Service Provider' : 'Customer');

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LinqSpacing.s5,
        vertical: LinqSpacing.s4,
      ),
      decoration: const BoxDecoration(
        color: LinqColors.bgSurface,
        border: Border(
          bottom: BorderSide(color: LinqColors.borderDefault),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: person icon + role label (tappable)
          GestureDetector(
            onTap: _showRoleMenu,
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
          // Right: LINQ brand text
          Text(
            'LINQ',
            style: LinqTextStyles.h4.copyWith(
              color: LinqColors.forest500,
              letterSpacing: 2,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(LinqSpacing.s6),
      decoration: BoxDecoration(
        color: LinqColors.forest500,
        border: const Border(
          bottom: BorderSide(color: LinqColors.borderDefault),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'Expert services,\n',
                  style: LinqTextStyles.h1.copyWith(
                    color: LinqColors.textOnBrand,
                  ),
                ),
                TextSpan(
                  text: 'secured by trust.',
                  style: LinqTextStyles.h1.copyWith(
                    color: LinqColors.forest200,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: LinqSpacing.s5),
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v.toLowerCase().trim()),
            decoration: InputDecoration(
              filled: true,
              fillColor: LinqColors.bgSurface,
              hintText: 'What service do you need?',
              hintStyle: LinqTextStyles.body.copyWith(
                color: LinqColors.textTertiary,
              ),
              prefixIcon: const Icon(
                Icons.search,
                color: LinqColors.textTertiary,
              ),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.clear,
                        color: LinqColors.textTertiary,
                      ),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: LinqRadius.borderMd,
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategories() {
    return Padding(
      padding: const EdgeInsets.only(top: LinqSpacing.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: LinqSpacing.s5),
            child: Text('Categories', style: LinqTextStyles.h3),
          ),
          const SizedBox(height: LinqSpacing.s4),
          SizedBox(
            height: 110,
            child: _categoriesLoading
                ? _buildCategoriesShimmer()
                : _categoriesError != null
                ? _buildCategoriesError()
                : _filteredCategories.isEmpty
                ? Center(
                    child: Text(
                      'No categories found.',
                      style: LinqTextStyles.bodySm,
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _filteredCategories.length,
                    padding: const EdgeInsets.symmetric(
                      horizontal: LinqSpacing.s5,
                    ),
                    itemBuilder: (context, index) {
                      final item = _filteredCategories[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: LinqSpacing.s4),
                        child: GestureDetector(
                          onTap: () => Navigator.pushNamed(
                            context,
                            '/category',
                            arguments: {
                              'category': item['name'],
                              'icon': item['icon'],
                              'categoryId': item['id'],
                              'categorySlug': item['slug'] ?? '',
                              'children':
                                  item['children'] ?? <Map<String, dynamic>>[],
                            },
                          ),
                          child: Column(
                            children: [
                              CircleAvatar(
                                radius: 30,
                                backgroundColor: LinqColors.forest100,
                                child: Icon(
                                  item['icon'],
                                  color: LinqColors.forest500,
                                  size: 26,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: 70,
                                child: Text(
                                  item['name'],
                                  style: LinqTextStyles.bodyXs.copyWith(
                                    color: LinqColors.textBody,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesShimmer() {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: 5,
      padding: const EdgeInsets.symmetric(horizontal: LinqSpacing.s5),
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(right: LinqSpacing.s4),
        child: Column(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                color: LinqColors.stone200,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 50,
              height: 10,
              decoration: BoxDecoration(
                color: LinqColors.stone200,
                borderRadius: LinqRadius.borderSm,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoriesError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(_categoriesError!, style: LinqTextStyles.bodySm),
          TextButton.icon(
            onPressed: _loadCategories,
            icon: const Icon(
              Icons.refresh,
              size: 16,
              color: LinqColors.forest500,
            ),
            label: Text(
              'Retry',
              style: LinqTextStyles.bodySm.copyWith(
                color: LinqColors.forest500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinqMatchSection() {
    return Padding(
      padding: const EdgeInsets.all(LinqSpacing.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LINQ-MATCH',
                    style: LinqTextStyles.h2.copyWith(
                      color: LinqColors.forest500,
                    ),
                  ),
                  Text('Top pros near you', style: LinqTextStyles.bodySm),
                ],
              ),
              const Icon(Icons.verified, color: LinqColors.brass500, size: 28),
            ],
          ),
          const SizedBox(height: LinqSpacing.s5),
          if (_providersLoading)
            const Center(
              child: CircularProgressIndicator(color: LinqColors.forest500),
            )
          else if (_providersError != null)
            Column(
              children: [
                Text(_providersError!, style: LinqTextStyles.bodySm),
                TextButton.icon(
                  onPressed: _loadProviders,
                  icon: const Icon(
                    Icons.refresh,
                    size: 16,
                    color: LinqColors.forest500,
                  ),
                  label: Text(
                    'Retry',
                    style: LinqTextStyles.bodySm.copyWith(
                      color: LinqColors.forest500,
                    ),
                  ),
                ),
              ],
            )
          else if (_filteredProviders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'No providers found near you.',
                style: LinqTextStyles.bodySm,
              ),
            )
          else
            ..._filteredProviders.map((pro) => _buildProviderCard(pro)),
        ],
      ),
    );
  }

  Widget _buildProviderCard(Map<String, dynamic> pro) {
    final imageUrl = (pro['image'] ?? '').toString().trim();
    return Container(
      margin: const EdgeInsets.only(bottom: LinqSpacing.s5),
      decoration: BoxDecoration(
        color: LinqColors.bgSurface,
        borderRadius: LinqRadius.borderLg,
        border: Border.all(color: LinqColors.borderDefault),
        boxShadow: LinqShadows.xs,
      ),
      child: Column(
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: imageUrl.isEmpty
                    ? Container(
                        height: 200,
                        width: double.infinity,
                        color: LinqColors.stone100,
                        child: const Icon(
                          Icons.person,
                          size: 80,
                          color: LinqColors.stone300,
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: imageUrl,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorListener: (_) {
                          CachedNetworkImage.evictFromCache(imageUrl);
                        },
                        placeholder: (_, __) =>
                            Container(height: 200, color: LinqColors.stone100),
                        errorWidget: (_, __, ___) => Container(
                          height: 200,
                          color: LinqColors.stone100,
                          child: const Icon(
                            Icons.person,
                            size: 80,
                            color: LinqColors.stone300,
                          ),
                        ),
                      ),
              ),
              Positioned(top: 12, left: 12, child: linqVerifiedBadge()),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(LinqSpacing.s4),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        pro['name'].toString(),
                        style: LinqTextStyles.h4.copyWith(
                          color: LinqColors.forest500,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.star, size: 16, color: Colors.amber),
                        const SizedBox(width: 2),
                        Text(
                          pro['rating'].toString(),
                          style: LinqTextStyles.bodySm,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    pro['role'].toString(),
                    style: LinqTextStyles.bodySm.copyWith(
                      color: LinqColors.forest400,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text('📍 ${pro['distance']}', style: LinqTextStyles.bodySm),
                    const SizedBox(width: 16),
                    Text(
                      '⏰ ${pro['availability']}',
                      style: LinqTextStyles.bodySm,
                    ),
                  ],
                ),
                const SizedBox(height: LinqSpacing.s4),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: LinqColors.forest500,
                      foregroundColor: LinqColors.textOnBrand,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: LinqRadius.borderMd,
                      ),
                    ),
                    onPressed: () => Navigator.pushNamed(
                      context,
                      '/provider-profile',
                      arguments: pro,
                    ),
                    child: const Text(
                      'View profile',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrustBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LinqSpacing.s5),
      child: Container(
        padding: const EdgeInsets.all(LinqSpacing.s5),
        decoration: BoxDecoration(
          color: LinqColors.forest100,
          borderRadius: LinqRadius.borderLg,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.verified_user,
              size: 36,
              color: LinqColors.forest500,
            ),
            const SizedBox(width: LinqSpacing.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Every pro is vetted.',
                    style: LinqTextStyles.h4.copyWith(
                      color: LinqColors.forest500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'LINQ ensures identity verification and background checks for all service providers.',
                    style: LinqTextStyles.bodySm,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off, size: 56, color: LinqColors.stone300),
          const SizedBox(height: LinqSpacing.s4),
          Text(
            'No results for "$_query"',
            style: LinqTextStyles.h4.copyWith(color: LinqColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different service or category.',
            style: LinqTextStyles.bodySm,
          ),
        ],
      ),
    );
  }
}

class _RoleSwitchSheet extends StatefulWidget {
  final String activeRole;
  final void Function(String) onSwitch;

  const _RoleSwitchSheet({
    required this.activeRole,
    required this.onSwitch,
  });

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
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: LinqSpacing.s3),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: LinqColors.stone300,
                  borderRadius: LinqRadius.borderFull,
                ),
              ),
              // Gradient header
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
                child: Row(
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
              // Role options
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: LinqSpacing.s5,
                ),
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
            child: Row(
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
                Expanded(
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
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: LinqTextStyles.bodySm,
                      ),
                    ],
                  ),
                ),
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
    );
  }
}

class BottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int, String) onNavigate;

  const BottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: selectedIndex,
      selectedItemColor: LinqColors.forest500,
      unselectedItemColor: LinqColors.textTertiary,
      backgroundColor: LinqColors.bgSurface,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      onTap: (index) {
        switch (index) {
          case 0:
            onNavigate(0, '/customer-dashboard');
            break;
          case 1:
            onNavigate(1, '/user-jobs');
            break;
          case 2:
            onNavigate(2, '/user-transactions');
            break;
          case 3:
            onNavigate(3, '/user-profile');
            break;
        }
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Discovery'),
        BottomNavigationBarItem(icon: Icon(Icons.work), label: 'Jobs'),
        BottomNavigationBarItem(
          icon: Icon(Icons.account_balance_wallet),
          label: 'Transactions',
        ),
        BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
      ],
    );
  }
}
