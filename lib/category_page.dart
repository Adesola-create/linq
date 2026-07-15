import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'location_service.dart';
import 'linq_theme.dart';

// ── Entry point ──────────────────────────────────────────────────
class CategoryPage extends StatefulWidget {
  final String category;
  final IconData icon;
  final String categoryId;
  final String categorySlug;
  final List<Map<String, dynamic>> children;

  const CategoryPage({
    super.key,
    required this.category,
    required this.icon,
    required this.categoryId,
    required this.categorySlug,
    required this.children,
  });

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  double? _lat;
  double? _lng;

  // "All" tab + one tab per subcategory
  List<Map<String, dynamic>> get _tabs_data {
    return [
      {'id': widget.categoryId, 'slug': widget.categorySlug, 'name': 'All'},
      ...widget.children,
    ];
  }

  @override
  void initState() {
    super.initState();
    final count = _tabs_data.length == 1 ? 1 : _tabs_data.length;
    _tabs = TabController(length: count, vsync: this);
    _resolveLocation();
  }

  Future<void> _resolveLocation() async {
    final result = await LocationService.fetchLocation();
    if (mounted && result['success'] == true) {
      setState(() {
        _lat = result['lat'] as double?;
        _lng = result['lng'] as double?;
      });
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs_data;
    return Scaffold(
      backgroundColor: LinqColors.bgPageApp,
      body: Column(
        children: [
          // ── Header ──────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + LinqSpacing.s4,
              bottom: 0,
              left: LinqSpacing.s5,
              right: LinqSpacing.s5,
            ),
            color: LinqColors.forest500,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.arrow_back,
                        color: LinqColors.textOnBrand,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const Spacer(),
                    Text(
                      'LINQ',
                      style: LinqTextStyles.labelSm.copyWith(
                        color: LinqColors.forest200,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: LinqSpacing.s5),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(LinqSpacing.s3),
                      decoration: BoxDecoration(
                        color: LinqColors.forest700,
                        borderRadius: LinqRadius.borderMd,
                      ),
                      child: Icon(
                        widget.icon,
                        color: LinqColors.forest200,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: LinqSpacing.s4),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.category,
                          style: LinqTextStyles.h2.copyWith(
                            color: LinqColors.textOnBrand,
                          ),
                        ),
                        Text(
                          '${tabs.length > 1 ? tabs.length - 1 : 0} subcategories',
                          style: LinqTextStyles.bodySm.copyWith(
                            color: LinqColors.forest200,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: LinqSpacing.s5),
                // ── Subcategory tabs ─────────────────────────────
                TabBar(
                  controller: _tabs,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicatorColor: LinqColors.textOnBrand,
                  indicatorWeight: 3,
                  labelColor: LinqColors.textOnBrand,
                  unselectedLabelColor: LinqColors.forest200,
                  labelStyle: LinqTextStyles.label,
                  unselectedLabelStyle: LinqTextStyles.label,
                  dividerColor: Colors.transparent,
                  tabs: tabs
                      .map((t) => Tab(text: (t['name'] ?? '').toString()))
                      .toList(),
                ),
              ],
            ),
          ),

          // ── Tab views ────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: tabs.map((t) {
                final isAllTab = t['name'] == 'All';
                return _SubcategoryProviderList(
                  subcategoryId: (t['id'] ?? '').toString(),
                  subcategorySlug: (t['slug'] ?? '').toString(),
                  subcategoryName: (t['name'] ?? '').toString(),
                  lat: _lat,
                  lng: _lng,
                  allChildIds: isAllTab
                      ? widget.children
                            .map((c) => (c['id'] ?? '').toString())
                            .where((id) => id.isNotEmpty)
                            .toList()
                      : [],
                  allChildSlugs: isAllTab
                      ? widget.children
                            .map((c) => (c['slug'] ?? '').toString())
                            .where((s) => s.isNotEmpty)
                            .toList()
                      : [],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Provider list for one subcategory tab ────────────────────────
class _SubcategoryProviderList extends StatefulWidget {
  final String subcategoryId;
  final String subcategorySlug;
  final String subcategoryName;
  final double? lat;
  final double? lng;
  final List<String> allChildIds;
  final List<String> allChildSlugs;

  const _SubcategoryProviderList({
    required this.subcategoryId,
    required this.subcategorySlug,
    required this.subcategoryName,
    required this.lat,
    required this.lng,
    required this.allChildIds,
    required this.allChildSlugs,
  });

  @override
  State<_SubcategoryProviderList> createState() =>
      _SubcategoryProviderListState();
}

class _SubcategoryProviderListState extends State<_SubcategoryProviderList>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _providers = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  String _filter = 'All';
  final _searchCtrl = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_SubcategoryProviderList old) {
    super.didUpdateWidget(old);
    if ((old.lat == null && widget.lat != null) ||
        (old.lng == null && widget.lng != null)) {
      _load();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _providerMatchesCategory(dynamic p) {
    final cats = (p['categories'] as List<dynamic>? ?? []);
    if (cats.isEmpty) return false;

    final catIds = <String>{};
    for (final c in cats) {
      if (c is Map) {
        for (final key in ['ulid', 'id', '_id', 'slug', 'category_id']) {
          final v = (c[key] ?? '').toString();
          if (v.isNotEmpty) catIds.add(v);
        }
      } else if (c is String && c.isNotEmpty) {
        catIds.add(c);
      }
    }

    // Build match set from both IDs and slugs
    if (widget.allChildIds.isNotEmpty || widget.allChildSlugs.isNotEmpty) {
      // "All" tab: match parent or any child by id or slug
      final matchSet = {
        widget.subcategoryId,
        widget.subcategorySlug,
        ...widget.allChildIds,
        ...widget.allChildSlugs,
      }..removeWhere((s) => s.isEmpty);
      return catIds.any((id) => matchSet.contains(id));
    }

    // Specific subcategory tab: match by id or slug
    return catIds.contains(widget.subcategoryId) ||
        (widget.subcategorySlug.isNotEmpty &&
            catIds.contains(widget.subcategorySlug));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final isAllTab =
        widget.allChildIds.isNotEmpty || widget.allChildSlugs.isNotEmpty;

    // For specific subcategory tabs, send the slug to the API so it pre-filters.
    // For the "All" tab, fetch without a category param and rely on client filter.
    final idParam = isAllTab
        ? ''
        : (widget.subcategorySlug.isNotEmpty
              ? widget.subcategorySlug
              : widget.subcategoryId);

    final result = await AuthService.getProvidersBySubcategory(
      subcategoryId: idParam,
      lat: widget.lat,
      lng: widget.lng,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      final raw = result['data'] as List<dynamic>;

      if (raw.isNotEmpty) {
      }

      final matched = raw.where(_providerMatchesCategory).toList();

      setState(() {
        _providers = matched.map((p) {
          final cats = p['categories'] as List<dynamic>? ?? [];
          final role = cats.isNotEmpty
              ? cats.map((c) => c['name']).join(', ')
              : 'Service provider';
          return <String, dynamic>{
            'ulid': p['ulid'] ?? '',
            'name': p['name'] ?? 'Unknown',
            'role': role,
            'bio': p['bio'] ?? '',
            'rating': p['avg_rating']?.toString() ?? '0.0',
            'distance': p['distance'] != null
                ? '${p['distance']} km'
                : 'Nearby',
            'availability': p['is_available'] == true
                ? 'Available today'
                : 'Check schedule',
            'image': _serverImageUrl(p),
            'raw': p,
          };
        }).toList();
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

  List<Map<String, dynamic>> get _filtered {
    var list = List<Map<String, dynamic>>.from(_providers);
    if (_query.isNotEmpty) {
      list = list
          .where(
            (p) =>
                p['name'].toString().toLowerCase().contains(_query) ||
                p['role'].toString().toLowerCase().contains(_query),
          )
          .toList();
    }
    switch (_filter) {
      case 'Top rated':
        list.sort(
          (a, b) => double.parse(
            b['rating'].toString(),
          ).compareTo(double.parse(a['rating'].toString())),
        );
        break;
      case 'Nearest':
        list.sort((a, b) {
          final ad =
              double.tryParse(a['distance'].toString().split(' ')[0]) ?? 999;
          final bd =
              double.tryParse(b['distance'].toString().split(' ')[0]) ?? 999;
          return ad.compareTo(bd);
        });
        break;
      case 'Available now':
        list = list
            .where((p) => p['availability'] == 'Available today')
            .toList();
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: LinqColors.forest500),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 48, color: LinqColors.stone300),
            const SizedBox(height: LinqSpacing.s4),
            Text(_error!, style: LinqTextStyles.bodySm),
            const SizedBox(height: LinqSpacing.s3),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: LinqColors.forest500,
                foregroundColor: LinqColors.textOnBrand,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: LinqRadius.borderMd,
                ),
              ),
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final results = _filtered;

    return Column(
      children: [
        // ── Search + filter bar ────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            color: LinqColors.bgSurface,
            border: Border(bottom: BorderSide(color: LinqColors.borderDefault)),
          ),
          padding: const EdgeInsets.fromLTRB(
            LinqSpacing.s4,
            LinqSpacing.s3,
            LinqSpacing.s4,
            0,
          ),
          child: Column(
            children: [
              TextField(
                controller: _searchCtrl,
                onChanged: (v) =>
                    setState(() => _query = v.toLowerCase().trim()),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: LinqColors.stone100,
                  hintText: 'Search ${widget.subcategoryName} professionals…',
                  hintStyle: LinqTextStyles.body.copyWith(
                    color: LinqColors.textTertiary,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: LinqColors.textTertiary,
                    size: 20,
                  ),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.clear,
                            color: LinqColors.textTertiary,
                            size: 18,
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
              const SizedBox(height: LinqSpacing.s2),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['All', 'Top rated', 'Nearest', 'Available now']
                      .map(
                        (f) => Padding(
                          padding: const EdgeInsets.only(right: LinqSpacing.s2),
                          child: FilterChip(
                            label: Text(f),
                            selected: _filter == f,
                            onSelected: (_) => setState(() => _filter = f),
                            selectedColor: LinqColors.forest500,
                            backgroundColor: LinqColors.stone100,
                            labelStyle: LinqTextStyles.labelSm.copyWith(
                              color: _filter == f
                                  ? LinqColors.textOnBrand
                                  : LinqColors.textBody,
                            ),
                            checkmarkColor: LinqColors.textOnBrand,
                            side: BorderSide(
                              color: _filter == f
                                  ? LinqColors.forest500
                                  : LinqColors.borderDefault,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: LinqSpacing.s1,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: LinqSpacing.s2),
            ],
          ),
        ),

        // ── Provider list ──────────────────────────────────────
        Expanded(
          child: results.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.search_off,
                        size: 56,
                        color: LinqColors.stone300,
                      ),
                      const SizedBox(height: LinqSpacing.s4),
                      Text(
                        _query.isNotEmpty
                            ? 'No results for "$_query"'
                            : 'No providers available in this subcategory.',
                        style: LinqTextStyles.h4.copyWith(
                          color: LinqColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Try a different filter or check back later.',
                        style: LinqTextStyles.bodySm,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: LinqColors.forest500,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(LinqSpacing.s4),
                    itemCount: results.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: LinqSpacing.s3),
                    itemBuilder: (context, i) =>
                        _ProviderCard(provider: results[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

// ── Provider card ────────────────────────────────────────────────
class _ProviderCard extends StatefulWidget {
  final Map<String, dynamic> provider;
  const _ProviderCard({required this.provider});

  @override
  State<_ProviderCard> createState() => _ProviderCardState();
}

class _ProviderCardState extends State<_ProviderCard> {
  bool _saved = false;
  bool _savingInProgress = false;

  String get _ulid =>
      (widget.provider['ulid'] ?? widget.provider['id'] ?? '').toString();

  @override
  void initState() {
    super.initState();
    _checkSaved();
    AuthService.savedProvidersVersion.addListener(_checkSaved);
  }

  @override
  void dispose() {
    AuthService.savedProvidersVersion.removeListener(_checkSaved);
    super.dispose();
  }

  Future<void> _checkSaved() async {
    final saved = await AuthService.isProviderSaved(_ulid);
    if (mounted) setState(() => _saved = saved);
  }

  Future<void> _toggleSave() async {
    if (_savingInProgress || _ulid.isEmpty) return;
    _savingInProgress = true;
    final wasSaved = _saved;
    setState(() => _saved = !wasSaved);

    final result = wasSaved
        ? await AuthService.unsaveProvider(_ulid)
        : await AuthService.saveProvider(_ulid);

    _savingInProgress = false;
    if (!mounted) return;
    if (result['success'] != true) {
      setState(() => _saved = wasSaved);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ?? 'Something went wrong.',
          ),
          backgroundColor: LinqColors.danger500,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    final isAvailable = provider['availability'] == 'Available today';

    return Container(
      padding: const EdgeInsets.all(LinqSpacing.s4),
      decoration: BoxDecoration(
        color: LinqColors.bgSurface,
        borderRadius: LinqRadius.borderLg,
        border: Border.all(color: LinqColors.borderDefault),
        boxShadow: LinqShadows.xs,
      ),
      child: Row(
        children: [
          linqAvatar(
            radius: 28,
            imageUrl: provider['image']?.toString(),
            backgroundColor: LinqColors.stone100,
          ),
          const SizedBox(width: LinqSpacing.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provider['name'].toString(),
                  style: LinqTextStyles.h4.copyWith(
                    color: LinqColors.forest500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  provider['role'].toString(),
                  style: LinqTextStyles.bodySm.copyWith(
                    color: LinqColors.forest400,
                  ),
                ),
                const SizedBox(height: LinqSpacing.s2),
                Row(
                  children: [
                    const Icon(Icons.star, size: 13, color: Colors.amber),
                    const SizedBox(width: 3),
                    Text(
                      provider['rating'].toString(),
                      style: LinqTextStyles.bodyXs,
                    ),
                    const SizedBox(width: LinqSpacing.s3),
                    const Icon(
                      Icons.location_on,
                      size: 13,
                      color: LinqColors.textTertiary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      provider['distance'].toString(),
                      style: LinqTextStyles.bodyXs,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: LinqSpacing.s3),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: LinqSpacing.s2_5,
                  vertical: LinqSpacing.s1,
                ),
                decoration: BoxDecoration(
                  color: isAvailable
                      ? LinqColors.success50
                      : LinqColors.warning50,
                  borderRadius: LinqRadius.borderFull,
                ),
                child: Text(
                  provider['availability'].toString(),
                  style: LinqTextStyles.bodyXs.copyWith(
                    color: isAvailable
                        ? LinqColors.success700
                        : LinqColors.warning700,
                  ),
                ),
              ),
              const SizedBox(height: LinqSpacing.s2_5),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Bookmark / save toggle
                  GestureDetector(
                    onTap: _savingInProgress ? null : _toggleSave,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _saved
                              ? LinqColors.forest500
                              : LinqColors.borderDefault,
                        ),
                        borderRadius: LinqRadius.borderMd,
                      ),
                      child: Icon(
                        _saved
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        size: 18,
                        color: _saved
                            ? LinqColors.forest500
                            : LinqColors.stone400,
                      ),
                    ),
                  ),
                  const SizedBox(width: LinqSpacing.s2),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: LinqColors.forest500,
                      foregroundColor: LinqColors.textOnBrand,
                      padding: const EdgeInsets.symmetric(
                        horizontal: LinqSpacing.s4,
                        vertical: LinqSpacing.s2,
                      ),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: LinqRadius.borderMd,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => Navigator.pushNamed(
                      context,
                      '/provider-profile',
                      arguments: provider,
                    ),
                    child: Text(
                      'Profile',
                      style: LinqTextStyles.labelSm.copyWith(
                        color: LinqColors.textOnBrand,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
