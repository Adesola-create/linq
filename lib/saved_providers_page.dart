import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'linq_theme.dart';

class SavedProvidersPage extends StatefulWidget {
  final bool showBottomNav;
  const SavedProvidersPage({super.key, this.showBottomNav = true});

  @override
  State<SavedProvidersPage> createState() => _SavedProvidersPageState();
}

class _SavedProvidersPageState extends State<SavedProvidersPage> {
  List<Map<String, dynamic>> _providers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    AuthService.savedProvidersVersion.addListener(_onSavedChanged);
  }

  @override
  void dispose() {
    AuthService.savedProvidersVersion.removeListener(_onSavedChanged);
    super.dispose();
  }

  // Fires whenever any save/unsave happens anywhere in the app.
  // We do a silent background fetch — no spinner — so the list just
  // updates in place rather than flashing a full-page loading state.
  void _onSavedChanged() => _silentRefresh();

  Future<void> _silentRefresh() async {
    final result = await AuthService.getCustomerSavedProviders(forceRefresh: true);
    if (!mounted || result['success'] != true) return;
    final raw = result['data'] as List<dynamic>? ?? [];
    setState(() {
      _providers = raw.whereType<Map<String, dynamic>>().toList();
    });
  }

  void _removeProvider(String ulid) {
    if (!mounted) return;
    setState(() {
      _providers.removeWhere(
        (p) => (p['ulid'] ?? p['id'] ?? '').toString() == ulid,
      );
    });
  }

  Future<void> _load({bool forceRefresh = false, bool redirectOnAuthError = false}) async {
    if (mounted) setState(() { _loading = true; _error = null; });

    final result = await AuthService.getCustomerSavedProviders(forceRefresh: forceRefresh);

    if (!mounted) return;

    if (result['success'] == true) {
      final raw = result['data'] as List<dynamic>? ?? [];
      setState(() {
        _providers = raw.whereType<Map<String, dynamic>>().toList();
        _loading = false;
      });
    } else if (result['auth_required'] == true) {
      setState(() { _loading = false; });
      if (redirectOnAuthError && AuthService.claimLoginRedirect()) {
        await AuthService.logout();
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
        }
      }
    } else {
      setState(() {
        _loading = false;
        _error = result['message']?.toString() ?? 'Failed to load saved providers.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LinqColors.bgPageApp,
      appBar: AppBar(
        backgroundColor: LinqColors.forest500,
        foregroundColor: LinqColors.textOnBrand,
        elevation: 0,
        title: Text(
          'Saved Providers',
          style: LinqTextStyles.h3.copyWith(color: LinqColors.textOnBrand),
        ),
        automaticallyImplyLeading: !widget.showBottomNav,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: LinqColors.forest500))
          : _error != null
              ? _buildError()
              : _providers.isEmpty
                  ? _buildEmpty()
                  : RefreshIndicator(
                      onRefresh: () => _load(forceRefresh: true, redirectOnAuthError: true),
                      color: LinqColors.forest500,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(LinqSpacing.s5),
                        itemCount: _providers.length,
                        separatorBuilder: (_, _) => const SizedBox(height: LinqSpacing.s3),
                        itemBuilder: (_, i) => _ProviderCard(
                          provider: _providers[i],
                          onUnsaved: () => _removeProvider(
                            (_providers[i]['ulid'] ?? _providers[i]['id'] ?? '').toString(),
                          ),
                        ),
                      ),
                    ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LinqSpacing.s6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bookmark_border_rounded, size: 64, color: LinqColors.stone300),
            const SizedBox(height: LinqSpacing.s4),
            Text(
              'No saved providers yet',
              style: LinqTextStyles.h4.copyWith(color: LinqColors.textSecondary),
            ),
            const SizedBox(height: LinqSpacing.s2),
            Text(
              'Bookmark providers you like to find them here quickly.',
              style: LinqTextStyles.bodySm.copyWith(color: LinqColors.textTertiary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LinqSpacing.s6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 56, color: LinqColors.stone300),
            const SizedBox(height: LinqSpacing.s4),
            Text(
              _error!,
              style: LinqTextStyles.body.copyWith(color: LinqColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: LinqSpacing.s5),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: LinqColors.forest500,
                foregroundColor: LinqColors.textOnBrand,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: LinqRadius.borderMd),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              onPressed: () => _load(forceRefresh: true),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProviderCard extends StatefulWidget {
  final Map<String, dynamic> provider;
  final VoidCallback? onUnsaved;
  const _ProviderCard({required this.provider, this.onUnsaved});

  @override
  State<_ProviderCard> createState() => _ProviderCardState();
}

class _ProviderCardState extends State<_ProviderCard> {
  bool _saved = true; // cards on this page are saved by definition
  bool _savingInProgress = false;

  Map<String, dynamic> get _p =>
      widget.provider['provider'] is Map
          ? (widget.provider['provider'] as Map).cast<String, dynamic>()
          : widget.provider;

  String get _ulid => (_p['ulid'] ?? _p['id'] ?? '').toString();

  String get _name =>
      (_p['name'] ?? _p['business_name'] ?? _p['full_name'] ?? 'Service Provider').toString();

  String get _role =>
      (_p['specialty'] ?? _p['role'] ?? _p['category'] ?? _p['service_type'] ?? '').toString();

  String get _rateLabel {
    final kobo = _p['hourly_rate_kobo'];
    if (kobo == null) return '';
    final naira = (kobo as num) / 100;
    return '₦${naira.toStringAsFixed(0)}/hr';
  }

  String get _ratingLabel {
    final r = _p['rating'] ?? _p['avg_rating'] ?? _p['average_rating'];
    if (r == null) return '0.0';
    final val = double.tryParse(r.toString());
    return val != null ? val.toStringAsFixed(1) : '0.0';
  }

  String get _distanceLabel {
    final km = _p['distance_km'] ?? _p['distance'];
    if (km == null) return '';
    if (km is String) return km;
    final d = (km as num).toDouble();
    if (d == 0) return '';
    return '${d.toStringAsFixed(1)}km away';
  }

  String get _imageUrl {
    for (final key in [
      'photo_url', 'profile_photo', 'profile_photo_url',
      'avatar_url', 'image_url', 'image', 'photo', 'avatar',
    ]) {
      final val = _p[key]?.toString().trim() ?? '';
      if (val.isNotEmpty) return val;
    }
    return '';
  }

  Map<String, dynamic> get _profileArg => {'provider': _p, 'showBottomNav': false};

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
    if (result['success'] == true) {
      final nowSaved = result['saved'] == true;
      setState(() { _saved = nowSaved; });
      if (!nowSaved) widget.onUnsaved?.call();
    } else {
      setState(() { _saved = wasSaved; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['message']?.toString() ?? 'Something went wrong.'),
        backgroundColor: LinqColors.danger500,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = _imageUrl;

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
          // ── Banner image ──────────────────────────────────────────
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: imageUrl.isEmpty
                    ? Container(
                        height: 200,
                        width: double.infinity,
                        color: LinqColors.stone100,
                        child: const Icon(Icons.person, size: 80, color: LinqColors.stone300),
                      )
                    : CachedNetworkImage(
                        imageUrl: imageUrl,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (_, _) =>
                            Container(height: 200, color: LinqColors.stone100),
                        errorWidget: (_, _, _) => Container(
                          height: 200,
                          color: LinqColors.stone100,
                          child: const Icon(Icons.person, size: 80, color: LinqColors.stone300),
                        ),
                      ),
              ),
              Positioned(top: 12, left: 12, child: linqVerifiedBadge()),
            ],
          ),

          // ── Info + buttons ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(LinqSpacing.s4),
            child: Column(
              children: [
                // Name + rating row
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _name,
                        style: LinqTextStyles.h4.copyWith(color: LinqColors.forest500),
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.star, size: 16, color: Colors.amber),
                        const SizedBox(width: 2),
                        Text(_ratingLabel, style: LinqTextStyles.bodySm),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Role / rate subtitle
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _role.isNotEmpty ? _role : _rateLabel,
                    style: LinqTextStyles.bodySm.copyWith(
                      color: LinqColors.forest400,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                // Distance row (only when available)
                if (_distanceLabel.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '📍 $_distanceLabel',
                      style: LinqTextStyles.bodySm,
                    ),
                  ),
                ],

                const SizedBox(height: LinqSpacing.s4),

                // Action buttons: Profile | bookmark | Hire now
                Row(
                  children: [
                    Expanded(
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
                          arguments: _profileArg,
                        ),
                        child: const Text(
                          'Profile',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: LinqSpacing.s3),
                    Material(
                      color: LinqColors.bgSurface,
                      borderRadius: LinqRadius.borderMd,
                      child: InkWell(
                        borderRadius: LinqRadius.borderMd,
                        onTap: _savingInProgress ? null : _toggleSave,
                        child: Container(
                          width: 44,
                          height: 44,
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
                            size: 22,
                            color: _saved
                                ? LinqColors.forest500
                                : LinqColors.stone400,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: LinqSpacing.s3),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: LinqColors.forest700,
                          foregroundColor: LinqColors.textOnBrand,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: LinqRadius.borderMd,
                          ),
                        ),
                        onPressed: () => Navigator.pushNamed(
                          context,
                          '/provider-hire',
                          arguments: _p,
                        ),
                        child: const Text(
                          'Hire now',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
