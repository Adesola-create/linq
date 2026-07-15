import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'linq_theme.dart';
import 'provider_nav_bar.dart';

class ProviderProfilePage extends StatefulWidget {
  final Map<String, dynamic> provider;
  final bool showBottomNav;
  final bool hideHireActions;

  const ProviderProfilePage({
    super.key,
    required this.provider,
    this.showBottomNav = true,
    this.hideHireActions = false,
  });

  @override
  State<ProviderProfilePage> createState() => _ProviderProfilePageState();
}

class _ProviderProfilePageState extends State<ProviderProfilePage> {
  final _scrollCtrl = ScrollController();
  bool _collapsed = false;
  int _selectedNavIndex = 4; // Profile tab

  // Full profile loaded from API
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _full = {};
  List<Map<String, dynamic>> _reviews = [];
  List<String> _gallery = [];

  static const _expandedHeight = 300.0;
  double get _collapseThreshold => _expandedHeight - kToolbarHeight;

  // Convenience getters — fall back to the stub passed from the list
  String get _name =>
      (_full['name'] ?? widget.provider['name'] ?? 'Service Provider')
          .toString();
  String get _specialty =>
      (_full['role'] ??
              _full['specialty'] ??
              widget.provider['role'] ??
              widget.provider['specialty'] ??
              '')
          .toString();
  String get _rating =>
      (_full['avg_rating'] ?? widget.provider['rating'] ?? '0.0').toString();
  String get _distance => (widget.provider['distance'] ?? '').toString();
  String get _availability =>
      (widget.provider['availability'] ?? '').toString();
  String get _image {
    final fullImage = _serverImageUrl(_full);
    if (fullImage.isNotEmpty) return fullImage;

    final raw = widget.provider['raw'];
    if (raw is Map<String, dynamic>) {
      final rawImage = _serverImageUrl(raw);
      if (rawImage.isNotEmpty) return rawImage;
    }

    return _serverImageUrl(widget.provider);
  }

  String get _bio => (_full['bio'] ?? widget.provider['bio'] ?? '').toString();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(() {
      final isCollapsed = _scrollCtrl.offset >= _collapseThreshold;
      if (isCollapsed != _collapsed) setState(() => _collapsed = isCollapsed);
    });
    _loadFullProfile(forceRefresh: true);
  }

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

  Future<void> _loadFullProfile({bool forceRefresh = false}) async {
    final ulid = (widget.provider['ulid'] ?? '').toString();
    if (ulid.isEmpty) {
      // No ulid — nothing to fetch, just render with stub data
      setState(() => _loading = false);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await AuthService.getProviderProfile(
      ulid,
      forceRefresh: forceRefresh,
    );
    if (!mounted) return;

    if (result['success'] == true) {
      final data = result['data'] as Map<String, dynamic>;

      // ── Gallery ────────────────────────────────────────────────
      // Accept: gallery_photos: [ { url: '...' }, ... ]  OR  gallery_photos: [ '...', ... ]
      final gallery = _extractGallery(data);

      // ── Reviews ────────────────────────────────────────────────
      // Accept: reviews: [ { author/reviewer, rating, comment/body }, ... ]
      final rawReviews = data['reviews'];
      final List<Map<String, dynamic>> reviews = [];
      if (rawReviews is List) {
        for (final r in rawReviews) {
          if (r is Map) {
            reviews.add({
              'author':
                  (r['author'] ??
                          r['reviewer'] ??
                          r['user']?['name'] ??
                          'Anonymous')
                      .toString(),
              'rating': (r['rating'] ?? r['score']) is int
                  ? (r['rating'] ?? r['score']) as int
                  : int.tryParse(
                          (r['rating'] ?? r['score'] ?? '0').toString(),
                        ) ??
                        0,
              'comment': (r['comment'] ?? r['body'] ?? r['review'] ?? '')
                  .toString(),
            });
          }
        }
      }

      setState(() {
        _full = data;
        _gallery = gallery;
        _reviews = reviews;
        _loading = false;
      });
    } else {
      setState(() {
        _error = result['message'];
        _loading = false;
      });
    }
  }

  String _serverImageUrl(Map<String, dynamic> provider) {
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

  bool _isGeneratedOrDocumentImage(String url) {
    final lower = url.toLowerCase();
    return lower.contains('i.pravatar.cc');
  }

  List<String> _extractGallery(Map<String, dynamic> data) {
    final values = <dynamic>[
      data['gallery_photos'],
      data['gallery'],
      data['portfolio'],
      data['portfolio_photos'],
      data['portfolio_images'],
      data['work_photos'],
      data['photos'],
      data['images'],
    ];

    final gallery = <String>[];
    for (final value in values) {
      _addGalleryValue(value, gallery);
    }

    return gallery.toSet().toList();
  }

  void _addGalleryValue(dynamic value, List<String> gallery) {
    if (value is String) {
      final url = value.trim();
      if (url.isNotEmpty && !_isGeneratedOrDocumentImage(url)) {
        gallery.add(url);
      }
      return;
    }

    if (value is List) {
      for (final item in value) {
        _addGalleryValue(item, gallery);
      }
      return;
    }

    if (value is Map) {
      final url =
          (value['url'] ??
                  value['secure_url'] ??
                  value['image_url'] ??
                  value['photo_url'] ??
                  value['path'] ??
                  value['src'])
              ?.toString()
              .trim();
      if (url != null && url.isNotEmpty && !_isGeneratedOrDocumentImage(url)) {
        gallery.add(url);
        return;
      }

      for (final nested in value.values) {
        if (nested is List) {
          _addGalleryValue(nested, gallery);
        }
      }
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LinqColors.bgPageApp,
      body: RefreshIndicator(
        onRefresh: () => _loadFullProfile(forceRefresh: true),
        child: CustomScrollView(
          controller: _scrollCtrl,
          slivers: [
            _buildAppBar(context),
            SliverToBoxAdapter(
              child: _loading
                  ? _buildShimmer()
                  : _error != null
                  ? _buildErrorState()
                  : Column(
                      children: [
                        const SizedBox(height: LinqSpacing.s4),
                        _buildBio(),
                        const SizedBox(height: LinqSpacing.s4),
                        _buildRatingsSection(),
                        if (_reviews.isNotEmpty) _buildReviews(),
                        _buildPortfolio(),
                        if (!widget.hideHireActions) _buildHireSection(),
                        //_buildLogoutSection(),
                        const SizedBox(height: 100),
                      ],
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: widget.showBottomNav
          ? ProviderNavBar(
              selectedIndex: _selectedNavIndex,
              onNavigate: _handleNavigation,
            )
          : null,
    );
  }

  // ── APP BAR ────────────────────────────────────────────────────
  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: _expandedHeight,
      pinned: true,
      backgroundColor: LinqColors.forest500,
      foregroundColor: LinqColors.textOnBrand,
      titleSpacing: 0,
      title: _collapsed
          ? Row(
              children: [
                linqAvatar(
                  radius: 16,
                  imageUrl: _image,
                  backgroundColor: LinqColors.forest700,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _name,
                    style: LinqTextStyles.h4.copyWith(
                      color: LinqColors.textOnBrand,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            )
          : null,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: EdgeInsets.zero,
        title: const SizedBox.shrink(),
        background: Stack(
          fit: StackFit.expand,
          children: [
            _image.isEmpty
                ? Container(
                    color: LinqColors.forest700,
                    child: const Center(
                      child: Icon(
                        Icons.person,
                        size: 96,
                        color: LinqColors.forest100,
                      ),
                    ),
                  )
                : CachedNetworkImage(
                    imageUrl: _image,
                    fit: BoxFit.cover,
                    errorListener: (_) {
                      CachedNetworkImage.evictFromCache(_image);
                    },
                    placeholder: (_, __) =>
                        Container(color: LinqColors.forest700),
                    errorWidget: (_, __, ___) =>
                        Container(color: LinqColors.forest700),
                  ),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xCC1F4E48)],
                ),
              ),
            ),
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  linqVerifiedBadge(),
                  const SizedBox(height: 8),
                  Text(
                    _name,
                    style: LinqTextStyles.h3.copyWith(
                      color: LinqColors.textOnBrand,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _specialty,
                    style: LinqTextStyles.bodySm.copyWith(
                      color: LinqColors.forest200,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _chip(Icons.star, _rating, Colors.amber),
                      const SizedBox(width: 8),
                      if (_distance.isNotEmpty) ...[
                        _chip(
                          Icons.location_on,
                          _distance,
                          LinqColors.forest100,
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (_availability.isNotEmpty)
                        _chip(
                          _availability == 'Available today' ||
                                  _availability == 'Available Today'
                              ? Icons.check_circle
                              : Icons.schedule,
                          _availability,
                          _availability == 'Available today' ||
                                  _availability == 'Available Today'
                              ? LinqColors.success100
                              : LinqColors.warning100,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ── SHIMMER ────────────────────────────────────────────────────
  Widget _buildShimmer() {
    return Padding(
      padding: const EdgeInsets.all(LinqSpacing.s5),
      child: Column(
        children: List.generate(
          3,
          (_) => Container(
            margin: const EdgeInsets.only(bottom: LinqSpacing.s4),
            height: 100,
            decoration: BoxDecoration(
              color: LinqColors.stone100,
              borderRadius: LinqRadius.borderLg,
            ),
          ),
        ),
      ),
    );
  }

  // ── ERROR STATE ────────────────────────────────────────────────
  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.all(LinqSpacing.s8),
      child: Column(
        children: [
          const Icon(Icons.wifi_off, size: 48, color: LinqColors.stone300),
          const SizedBox(height: LinqSpacing.s4),
          Text(_error!, style: LinqTextStyles.bodySm),
          const SizedBox(height: LinqSpacing.s4),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: LinqColors.forest500,
              foregroundColor: LinqColors.textOnBrand,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: LinqRadius.borderMd),
            ),
            onPressed: _loadFullProfile,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // ── BIO ────────────────────────────────────────────────────────
  Widget _buildBio() {
    if (_bio.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: LinqSpacing.s5),
      padding: const EdgeInsets.all(LinqSpacing.s5),
      decoration: BoxDecoration(
        color: LinqColors.bgSurface,
        borderRadius: LinqRadius.borderLg,
        border: Border.all(color: LinqColors.borderDefault),
        boxShadow: LinqShadows.xs,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 140),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('About', style: LinqTextStyles.h3),
            const SizedBox(height: LinqSpacing.s3),
            Text(_bio, style: LinqTextStyles.body),
          ],
        ),
      ),
    );
  }

  // ── RATINGS ────────────────────────────────────────────────────
  Widget _buildRatingsSection() {
    final ratingVal = double.tryParse(_rating) ?? 0.0;
    final fullStars = ratingVal.floor();
    final hasHalf = (ratingVal - fullStars) >= 0.5;
    final reviewCount = _reviews.length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: LinqSpacing.s5),
      padding: const EdgeInsets.all(LinqSpacing.s5),
      decoration: BoxDecoration(
        color: LinqColors.bgSurface,
        borderRadius: LinqRadius.borderLg,
        border: Border.all(color: LinqColors.borderDefault),
        boxShadow: LinqShadows.xs,
      ),
      child: Row(
        children: [
          Column(
            children: [
              Text(
                _rating,
                style: LinqTextStyles.h1.copyWith(
                  fontSize: 48,
                  color: LinqColors.forest500,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: List.generate(5, (i) {
                  if (i < fullStars) {
                    return const Icon(
                      Icons.star,
                      color: Colors.amber,
                      size: 20,
                    );
                  }
                  if (i == fullStars && hasHalf) {
                    return const Icon(
                      Icons.star_half,
                      color: Colors.amber,
                      size: 20,
                    );
                  }
                  return const Icon(
                    Icons.star_border,
                    color: Colors.amber,
                    size: 20,
                  );
                }),
              ),
              const SizedBox(height: 4),
              Text(
                '$reviewCount review${reviewCount == 1 ? '' : 's'}',
                style: LinqTextStyles.bodyXs,
              ),
            ],
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              children: [5, 4, 3, 2, 1].map((star) {
                final count = _reviews.where((r) => r['rating'] == star).length;
                final fraction = reviewCount == 0 ? 0.0 : count / reviewCount;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Text('$star', style: LinqTextStyles.bodyXs),
                      const SizedBox(width: 4),
                      const Icon(Icons.star, size: 12, color: Colors.amber),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: LinqRadius.borderSm,
                          child: LinearProgressIndicator(
                            value: fraction,
                            backgroundColor: LinqColors.stone200,
                            color: LinqColors.forest500,
                            minHeight: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('$count', style: LinqTextStyles.bodyXs),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── REVIEWS ────────────────────────────────────────────────────
  Widget _buildReviews() {
    return Padding(
      padding: const EdgeInsets.all(LinqSpacing.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reviews', style: LinqTextStyles.h3),
          const SizedBox(height: LinqSpacing.s3),
          ..._reviews.map(
            (r) => Container(
              margin: const EdgeInsets.only(bottom: LinqSpacing.s3),
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
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: LinqColors.forest100,
                        child: Text(
                          (r['author'] as String).isNotEmpty
                              ? (r['author'] as String)[0].toUpperCase()
                              : '?',
                          style: LinqTextStyles.label.copyWith(
                            color: LinqColors.forest500,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          r['author'] as String,
                          style: LinqTextStyles.label,
                        ),
                      ),
                      Row(
                        children: List.generate(
                          r['rating'] as int,
                          (_) => const Icon(
                            Icons.star,
                            size: 14,
                            color: Colors.amber,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if ((r['comment'] as String).isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      r['comment'] as String,
                      style: LinqTextStyles.bodySm.copyWith(
                        color: LinqColors.textBody,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── PORTFOLIO ──────────────────────────────────────────────────
  Widget _buildPortfolio() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LinqSpacing.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Portfolio', style: LinqTextStyles.h3),
          const SizedBox(height: LinqSpacing.s3),
          if (_gallery.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(LinqSpacing.s6),
              decoration: BoxDecoration(
                color: LinqColors.stone100,
                borderRadius: LinqRadius.borderLg,
                border: Border.all(color: LinqColors.borderDefault),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.photo_library_outlined,
                    size: 40,
                    color: LinqColors.stone300,
                  ),
                  const SizedBox(height: LinqSpacing.s3),
                  Text(
                    'No portfolio photos yet.',
                    style: LinqTextStyles.bodySm.copyWith(
                      color: LinqColors.textTertiary,
                    ),
                  ),
                ],
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _gallery.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemBuilder: (context, i) => GestureDetector(
                onTap: () => _openPhoto(context, i),
                child: ClipRRect(
                  borderRadius: LinqRadius.borderLg,
                  child: CachedNetworkImage(
                    imageUrl: _gallery[i],
                    fit: BoxFit.cover,
                    memCacheWidth: 700,
                    maxWidthDiskCache: 900,
                    errorListener: (_) {
                      CachedNetworkImage.evictFromCache(_gallery[i]);
                    },
                    placeholder: (_, __) => Container(
                      color: LinqColors.stone100,
                      child: const Icon(
                        Icons.image_outlined,
                        color: LinqColors.stone300,
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: LinqColors.stone100,
                      child: const Icon(
                        Icons.image_not_supported,
                        color: LinqColors.stone300,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHireSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LinqSpacing.s5),
      child: Column(
        children: [
          const SizedBox(height: LinqSpacing.s5),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: LinqColors.forest100,
                    foregroundColor: LinqColors.forest500,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: LinqRadius.borderMd,
                      side: const BorderSide(color: LinqColors.forest500),
                    ),
                  ),
                  onPressed: () => _openMessages(),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                  label: const Text(
                    'Message',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: LinqSpacing.s3),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: LinqColors.forest500,
                    foregroundColor: LinqColors.textOnBrand,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: LinqRadius.borderMd,
                    ),
                  ),
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      '/provider-hire',
                      arguments: widget.provider,
                    );
                  },
                  icon: const Icon(Icons.handshake_outlined, size: 18),
                  label: const Text(
                    'Hire now',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: LinqSpacing.s4),
          Text(
            'Hire ${_name.split(' ').first} directly, or allow other providers in the same category to bid.',
            style: LinqTextStyles.bodySm.copyWith(
              color: LinqColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _openMessages() async {
    final providerUlid = (widget.provider['ulid'] ?? widget.provider['id'] ?? '').toString();
    if (providerUlid.isEmpty) return;

    final loadingCtrl = ScaffoldMessenger.of(context);
    loadingCtrl.showSnackBar(const SnackBar(
      content: Text('Opening conversation…'),
      duration: Duration(seconds: 2),
    ));

    final result = await AuthService.getOrCreateDirectThread(providerUlid);
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (result['success'] == true) {
      final threadData = result['data'];
      final thread = Map<String, dynamic>.from(
        threadData is Map<String, dynamic>
            ? threadData
            : (threadData is Map
                ? threadData.cast<String, dynamic>()
                : <String, dynamic>{}),
      );
      // Ensure the thread carries provider identity so ChatPage can show
      // the right name and avatar regardless of whether the API returns participants.
      final existingParticipants = thread['participants'];
      final hasProviderParticipant = existingParticipants is List &&
          existingParticipants.any(
            (p) => p is Map &&
                (p['role'] ?? '').toString().toUpperCase() == 'PROV',
          );
      if (!hasProviderParticipant) {
        thread['participants'] = [
          {
            'role': 'PROV',
            'name': _name,
            'photo_url': _image,
            'ulid': providerUlid,
          },
          if (existingParticipants is List) ...existingParticipants,
        ];
      }
      Navigator.pushNamed(context, '/chat', arguments: thread);
    } else if (result['auth_required'] == true) {
      if (AuthService.claimLoginRedirect()) {
        await AuthService.logout();
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['message']?.toString() ?? 'Unable to open conversation.'),
        backgroundColor: LinqColors.danger500,
      ));
    }
  }

  // Widget _buildLogoutSection() {
  //   return Padding(
  //     padding: const EdgeInsets.symmetric(horizontal: LinqSpacing.s5),
  //     child: Column(
  //       children: [
  //         const SizedBox(height: LinqSpacing.s4),
  //         SizedBox(
  //           width: double.infinity,
  //           child: OutlinedButton.icon(
  //             style: OutlinedButton.styleFrom(
  //               side: const BorderSide(
  //                 color: LinqColors.danger500,
  //                 width: LinqBorders.thin,
  //               ),
  //               foregroundColor: LinqColors.danger500,
  //               padding: const EdgeInsets.symmetric(vertical: LinqSpacing.s4),
  //               shape: RoundedRectangleBorder(
  //                 borderRadius: LinqRadius.borderMd,
  //               ),
  //             ),
  //             onPressed: _confirmLogout,
  //             icon: const Icon(Icons.logout),
  //             label: const Text(
  //               'Log out',
  //               style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
  //             ),
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  // Full-screen photo viewer
  void _openPhoto(BuildContext context, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _PhotoViewer(images: _gallery, initialIndex: initialIndex),
      ),
    );
  }

  // Future<void> _confirmLogout() async {
  //   final shouldLogout = await showDialog<bool>(
  //     context: context,
  //     builder: (ctx) => AlertDialog(
  //       title: const Text('Log out'),
  //       content: const Text('Are you sure you want to log out?'),
  //       actions: [
  //         TextButton(
  //           onPressed: () => Navigator.of(ctx).pop(false),
  //           child: const Text('Cancel'),
  //         ),
  //         TextButton(
  //           onPressed: () => Navigator.of(ctx).pop(true),
  //           child: const Text('Log out'),
  //         ),
  //       ],
  //     ),
  //   );

  //   if (shouldLogout == true) {
  //     await AuthService.logout();
  //     if (!mounted) return;
  //     Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  //   }
  // }

  // ── BOOKING BAR ────────────────────────────────────────────────
  // Removed in favor of ProviderNavBar for consistent bottom navigation
}

// ── Full-screen photo viewer ────────────────────────────────────
class _PhotoViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const _PhotoViewer({required this.images, required this.initialIndex});

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _page;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _page = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_current + 1} / ${widget.images.length}',
          style: LinqTextStyles.label.copyWith(color: Colors.white),
        ),
      ),
      body: PageView.builder(
        controller: _page,
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (_, i) => InteractiveViewer(
          child: Center(
            child: CachedNetworkImage(
              imageUrl: widget.images[i],
              fit: BoxFit.contain,
              memCacheWidth: 1200,
              maxWidthDiskCache: 1400,
              errorListener: (_) {
                CachedNetworkImage.evictFromCache(widget.images[i]);
              },
              placeholder: (_, _) => const Center(
                child: CircularProgressIndicator(
                  color: LinqColors.forest500,
                  strokeWidth: 2,
                ),
              ),
              errorWidget: (_, _, _) => const Icon(
                Icons.image_not_supported,
                color: Colors.white54,
                size: 64,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
