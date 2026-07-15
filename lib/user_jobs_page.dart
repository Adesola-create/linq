import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'auth_service.dart';
import 'countries_data.dart';
import 'job_review_page.dart';
import 'location_service.dart';
import 'nigeria_lga_data.dart';
import 'linq_theme.dart';

enum JobStatus { draft, open, inProgress, completed, cancelled }

class UserJob {
  final String id;
  final String title;
  final String category;
  final String provider;
  final DateTime date;
  final JobStatus status;
  final double amount;
  final bool isPosted;
  final Map<String, dynamic> rawData;

  const UserJob({
    required this.id,
    required this.title,
    required this.category,
    required this.provider,
    required this.date,
    required this.status,
    required this.amount,
    required this.rawData,
    this.isPosted = false,
  });

  factory UserJob.fromJson(Map<String, dynamic> json) {
    String providerName() {
      final provider = json['provider'];
      if (provider is String && provider.isNotEmpty) return provider;
      if (provider is Map<String, dynamic>) {
        final firstName =
            provider['first_name'] ??
            provider['firstname'] ??
            provider['firstName'];
        final lastName =
            provider['last_name'] ??
            provider['lastname'] ??
            provider['lastName'];
        if (firstName != null && lastName != null) {
          return '$firstName $lastName';
        }
        return (provider['name'] ??
                provider['full_name'] ??
                provider['display_name'] ??
                provider['username'] ??
                '')
            .toString();
      }
      return '';
    }

    String categoryName() {
      final category = json['category'];
      if (category is String) return category;
      if (category is Map<String, dynamic>) {
        return (category['name'] ??
                category['title'] ??
                category['label'] ??
                '')
            .toString();
      }
      return (json['service'] ?? json['job_category'] ?? '').toString();
    }

    DateTime parseDate() {
      final value =
          json['date'] ??
          json['scheduled_at'] ??
          json['created_at'] ??
          json['updated_at'];
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is String) {
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      return DateTime.now();
    }

    JobStatus parseStatus() {
      final raw = (json['state'] ?? json['status'] ?? json['job_status'] ?? '')
          .toString()
          .toLowerCase();
      if (raw == 'draft') return JobStatus.draft;
      if (raw == 'published' || raw == 'open' || raw.contains('awaiting_bids')) {
        return JobStatus.open;
      }
      if (raw.contains('progress')) return JobStatus.inProgress;
      if (raw.contains('complete')) return JobStatus.completed;
      if (raw.contains('cancel')) return JobStatus.cancelled;
      return JobStatus.draft;
    }

    final rawStatus = (json['state'] ?? json['status'] ?? json['job_status'] ?? '')
        .toString()
        .toLowerCase();
    final bool isPosted =
        json['is_posted'] == true ||
        rawStatus == 'published' ||
        rawStatus == 'open' ||
        rawStatus.contains('awaiting_bids');

    final provider = providerName();
    return UserJob(
      id: (json['id'] ?? json['job_id'] ?? json['ulid'] ?? '').toString(),
      title: (json['title'] ?? json['description'] ?? '').toString(),
      category: categoryName(),
      provider: provider.isEmpty ? 'Open' : provider,
      date: parseDate(),
      status: parseStatus(),
      amount:
          double.tryParse(
            (json['amount'] ?? json['price'] ?? json['total'] ?? 0).toString(),
          ) ??
          0.0,
      isPosted: isPosted,
      rawData: Map<String, dynamic>.from(json),
    );
  }
}

class UserJobsPage extends StatefulWidget {
  final bool showBottomNav;

  const UserJobsPage({super.key, this.showBottomNav = true});

  @override
  State<UserJobsPage> createState() => _UserJobsPageState();
}

class _UserJobsPageState extends State<UserJobsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  List<UserJob> _jobs = [];
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    // Initial background load — don't redirect to login even if auth fails,
    // because this tab may not be visible yet (IndexedStack loads all tabs at once).
    _fetchJobs(forceRefresh: false, redirectOnAuthError: false);
  }

  Future<void> _fetchJobs({bool forceRefresh = false, bool redirectOnAuthError = true}) async {
    final result = await AuthService.getCustomerJobs(
      forceRefresh: forceRefresh,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      final rawList = result['data'] as List<dynamic>;
      for (final item in rawList) {
        if (item is Map) {
        }
      }
      final rawJobs = rawList
          .whereType<Map<String, dynamic>>()
          .map(UserJob.fromJson)
          .toList();
      setState(() {
        _jobs = rawJobs;
        _loading = false;
      });
    } else {
      final message = result['message']?.toString() ?? 'Failed to load jobs.';
      if (redirectOnAuthError &&
          (result['auth_required'] == true ||
              message.contains('Authentication required') ||
              message.contains('log in')) &&
          AuthService.claimLoginRedirect()) {
        await AuthService.logout();
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
        return;
      }
      setState(() {
        _errorMessage = message;
        _loading = false;
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: LinqColors.forest500,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: LinqColors.bgPageApp,
        appBar: AppBar(
        backgroundColor: LinqColors.forest500,
        foregroundColor: LinqColors.textOnBrand,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: LinqColors.forest500,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        title: Text(
          'Jobs',
          style: LinqTextStyles.h3.copyWith(color: LinqColors.textOnBrand),
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: LinqColors.forest200,
          labelColor: LinqColors.textOnBrand,
          unselectedLabelColor: LinqColors.forest200,
          labelStyle: LinqTextStyles.label,
          tabs: const [
            Tab(text: 'All jobs'),
            Tab(text: 'Post a job'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _JobListTab(
            jobs: _jobs,
            loading: _loading,
            errorMessage: _errorMessage,
            onRefresh: () => _fetchJobs(forceRefresh: true),
          ),
          const _PostJobTab(),
        ],
      ),
      bottomNavigationBar: widget.showBottomNav ? const _BottomNav() : null,
    ),);
  }
}

// ── JOB LIST TAB ─────────────────────────────────────────────────
class _JobListTab extends StatelessWidget {
  final List<UserJob> jobs;
  final bool loading;
  final String? errorMessage;
  final Future<void> Function() onRefresh;

  const _JobListTab({
    required this.jobs,
    required this.loading,
    this.errorMessage,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: loading
          ? SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: const Center(child: CircularProgressIndicator()),
              ),
            )
          : errorMessage != null
          ? SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: Center(
                  child: Text(errorMessage!, style: LinqTextStyles.bodySm),
                ),
              ),
            )
          : jobs.isEmpty
          ? SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: Center(
                  child: Text('No jobs yet.', style: LinqTextStyles.bodySm),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(LinqSpacing.s4),
              itemCount: jobs.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: LinqSpacing.s3),
              itemBuilder: (_, i) => _JobCard(job: jobs[i]),
            ),
    );
  }
}

class _JobCard extends StatelessWidget {
  final UserJob job;
  const _JobCard({required this.job});

  static const _statusBg = {
    JobStatus.draft: LinqColors.warning50,
    JobStatus.open: LinqColors.success50,
    JobStatus.inProgress: LinqColors.info50,
    JobStatus.completed: LinqColors.success50,
    JobStatus.cancelled: LinqColors.danger50,
  };

  static const _statusFg = {
    JobStatus.draft: LinqColors.warning700,
    JobStatus.open: LinqColors.success700,
    JobStatus.inProgress: LinqColors.info700,
    JobStatus.completed: LinqColors.success700,
    JobStatus.cancelled: LinqColors.danger700,
  };

  static const _statusLabels = {
    JobStatus.draft: 'Draft',
    JobStatus.open: 'Published',
    JobStatus.inProgress: 'In progress',
    JobStatus.completed: 'Completed',
    JobStatus.cancelled: 'Cancelled',
  };

  @override
  Widget build(BuildContext context) {
    final bg = _statusBg[job.status]!;
    final fg = _statusFg[job.status]!;

    return Container(
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
              Expanded(
                child: Text(
                  job.title,
                  style: LinqTextStyles.h4.copyWith(
                    color: LinqColors.forest500,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: LinqSpacing.s2_5,
                  vertical: LinqSpacing.s1,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: LinqRadius.borderFull,
                ),
                child: Text(
                  _statusLabels[job.status]!,
                  style: LinqTextStyles.labelSm.copyWith(color: fg),
                ),
              ),
            ],
          ),
          const SizedBox(height: LinqSpacing.s3),
          _row(Icons.category_outlined, job.category),
          const SizedBox(height: LinqSpacing.s1_5),
          _row(
            job.isPosted ? Icons.public : Icons.person_outline,
            job.isPosted ? 'Open — awaiting bids' : job.provider,
          ),
          const SizedBox(height: LinqSpacing.s1_5),
          _row(
            Icons.calendar_today_outlined,
            '${job.date.day}/${job.date.month}/${job.date.year}',
          ),
          if (job.amount > 0) ...[
            const SizedBox(height: LinqSpacing.s1_5),
            _row(Icons.payments_outlined, '₦ ${job.amount.toStringAsFixed(2)}'),
          ],
          const SizedBox(height: LinqSpacing.s3),
          if (job.isPosted) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: LinqSpacing.s3,
                vertical: LinqSpacing.s1_5,
              ),
              decoration: BoxDecoration(
                color: LinqColors.success50,
                borderRadius: LinqRadius.borderSm,
              ),
              child: Text(
                'Published — open for provider bids',
                style: LinqTextStyles.bodyXs.copyWith(
                  color: LinqColors.success700,
                ),
              ),
            ),
            const SizedBox(height: LinqSpacing.s3),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: LinqColors.forest500,
                foregroundColor: LinqColors.textOnBrand,
                padding: const EdgeInsets.symmetric(vertical: LinqSpacing.s3),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: LinqRadius.borderMd,
                ),
              ),
              onPressed: () => Navigator.pushNamed(
                context,
                '/job-details',
                arguments: job.rawData,
              ),
              child: const Text(
                'View Details',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: LinqSpacing.s3,
                vertical: LinqSpacing.s1_5,
              ),
              decoration: BoxDecoration(
                color: LinqColors.warning50,
                borderRadius: LinqRadius.borderSm,
              ),
              child: Text(
                'Draft job — not yet open to providers',
                style: LinqTextStyles.bodyXs.copyWith(
                  color: LinqColors.warning700,
                ),
              ),
            ),
            const SizedBox(height: LinqSpacing.s3),
            ElevatedButton(
              style: linqPrimaryButton(verticalPadding: LinqSpacing.s3),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => JobReviewPage(jobData: job.rawData),
                  ),
                );
              },
              child: const Text(
                'Review & Publish',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(IconData icon, String text) => Row(
    children: [
      Icon(icon, size: 15, color: LinqColors.textTertiary),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: LinqTextStyles.bodySm)),
    ],
  );
}

// ── POST JOB TAB ─────────────────────────────────────────────────
class _PostJobTab extends StatefulWidget {
  const _PostJobTab();

  @override
  State<_PostJobTab> createState() => _PostJobTabState();
}

class _PostJobTabState extends State<_PostJobTab> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();
  String? _selectedManualState;
  String? _selectedManualLga;
  DateTime? _preferredDate;
  final List<String> _selectedCategories = [];
  bool _saving = false;
  bool _useManualLocation = false;
  String? _currentLocationAddress;
  String? _currentLocationState;
  String? _currentLocationLga;
  String? _currentLocationArea;
  List<Map<String, dynamic>> _availableCategories = [];
  bool _categoriesLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
    _loadCategories();
    _offerDraftRestore();
  }

  Future<void> _offerDraftRestore() async {
    final draft = await AuthService.getPendingCustomerJobDraft(
      email: await AuthService.getCurrentAccountEmail(),
    );
    if (draft == null || !mounted) return;

    final restore = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved job draft found'),
        content: const Text(
          'We found a pending job post from your previous session. Restore it now?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (restore != true || !mounted) return;

    setState(() {
      _titleCtrl.text = draft['title']?.toString() ?? '';
      _descCtrl.text = draft['description']?.toString() ?? '';
      _budgetCtrl.text = draft['budget']?.toString() ?? '';
      _addressCtrl.text = draft['location_address']?.toString() ?? draft['address_text']?.toString() ?? '';
      _preferredDate = draft['preferred_date'] != null
          ? DateTime.tryParse(draft['preferred_date'].toString())
          : null;
      _selectedCategories
        ..clear()
        ..addAll((draft['categories'] is List)
            ? (draft['categories'] as List).map((item) => item.toString())
            : const []);
      _useManualLocation = draft['use_manual_location'] == true;
      _currentLocationAddress = draft['current_location_address']?.toString() ?? _currentLocationAddress;
      _selectedManualState = draft['manual_state']?.toString();
      _selectedManualLga = draft['manual_lga']?.toString();
      _areaCtrl.text = draft['manual_area']?.toString() ?? '';
    });
  }

  Future<void> _loadCurrentLocation() async {
    Map<String, dynamic>? location = await LocationService.getCachedLocation();
    if (location == null) {
      final fetched = await LocationService.fetchLocation();
      if (fetched['success'] == true) location = fetched;
    }
    if (location == null || !mounted) return;
    setState(() {
      _currentLocationState = location!['state'] as String?;
      _currentLocationLga = location['lga'] as String?;
      _currentLocationArea = location['area'] as String?;
      _currentLocationAddress = _composeLocationLabel(
        area: _currentLocationArea,
        lga: _currentLocationLga,
        state: _currentLocationState,
      );
    });
  }

  /// Joins area/LGA/state into a single human-readable label, e.g.
  /// "Ikeja, Ikeja LGA, Lagos". Falls back to a generic label if reverse
  /// geocoding didn't return any of these.
  String _composeLocationLabel({String? area, String? lga, String? state}) {
    final parts = [area, lga, state]
        .where((p) => p != null && p.trim().isNotEmpty)
        .map((p) => p!.trim())
        .toList();
    return parts.isEmpty ? 'Current Location (Auto-detected)' : parts.join(', ');
  }

  Future<void> _loadCategories() async {
    setState(() => _categoriesLoading = true);
    final result = await AuthService.getCategories();
    if (!mounted) return;

    if (result['success'] == true) {
      final categories = (result['data'] as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList();
      setState(() {
        _availableCategories = categories;
        _categoriesLoading = false;
      });
    } else {
      setState(() => _categoriesLoading = false);
    }
  }

  Future<bool?> _showLocationChoiceDialog() async {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LinqColors.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: LinqRadius.borderLg),
        title: Text('Job Location', style: LinqTextStyles.h3),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How would you like to set the job location?',
              style: LinqTextStyles.body,
            ),
            const SizedBox(height: LinqSpacing.s4),
            if (_currentLocationAddress != null) ...[
              Container(
                padding: const EdgeInsets.all(LinqSpacing.s3),
                decoration: BoxDecoration(
                  color: LinqColors.forest50,
                  borderRadius: LinqRadius.borderMd,
                  border: Border.all(color: LinqColors.forest200),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.my_location,
                      color: LinqColors.forest500,
                      size: 20,
                    ),
                    const SizedBox(width: LinqSpacing.s2),
                    Expanded(
                      child: Text(
                        _currentLocationAddress!,
                        style: LinqTextStyles.bodySm.copyWith(
                          color: LinqColors.forest700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: LinqSpacing.s3),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Use Current Location',
              style: LinqTextStyles.label.copyWith(color: LinqColors.forest500),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: LinqColors.forest500,
              foregroundColor: LinqColors.textOnBrand,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: LinqRadius.borderMd),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enter Address Manually'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(
            context,
          ).colorScheme.copyWith(primary: LinqColors.forest500),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _preferredDate = picked);
  }

  String _toSlug(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r"[^a-z0-9]+"), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'(^-|-$)'), '');
  }

  String _getCategorySlug(String categoryName) {
    final category = _availableCategories.firstWhere(
      (cat) => cat['name'] == categoryName,
      orElse: () => {'slug': _toSlug(categoryName)},
    );
    return category['slug'] as String? ?? _toSlug(categoryName);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    Map<String, dynamic>? locationCoords;
    String? addressText;

    if (_useManualLocation) {
      final landmark = _addressCtrl.text.trim();
      final area = _areaCtrl.text.trim();
      final lga = _selectedManualLga ?? '';
      final state = _selectedManualState ?? '';

      if (state.isEmpty || lga.isEmpty || area.isEmpty) {
        if (!mounted) return;
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Please select the state and enter the LGA and area/city/town.',
              style: LinqTextStyles.bodySm.copyWith(
                color: LinqColors.textOnBrand,
              ),
            ),
            backgroundColor: LinqColors.danger500,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: LinqRadius.borderMd),
          ),
        );
        return;
      }

      addressText = [
        if (landmark.isNotEmpty) landmark,
        area,
        '$lga LGA',
        '$state State',
      ].join(', ');

      // Default to a fallback Lagos coordinate, then try to refine it by
      // geocoding the entered address.
      locationCoords = {
        'lat': 6.5244,
        'lng': 3.3792,
      };
      try {
        final results = await locationFromAddress(addressText);
        if (results.isNotEmpty) {
          locationCoords = {
            'lat': results.first.latitude,
            'lng': results.first.longitude,
          };
        }
      } catch (_) {}
    } else {
      // Automatic location
      final cachedLocation = await LocationService.getCachedLocation();
      if (cachedLocation != null) {
        locationCoords = {
          'lat': cachedLocation['lat'] as double,
          'lng': cachedLocation['lng'] as double,
        };
      }

      if (locationCoords == null) {
        final locationResult = await LocationService.fetchLocation();
        if (locationResult['success'] != true) {
          if (!mounted) return;
          setState(() => _saving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                locationResult['message']?.toString() ??
                    'Unable to get location.',
                style: LinqTextStyles.bodySm.copyWith(
                  color: LinqColors.textOnBrand,
                ),
              ),
              backgroundColor: LinqColors.danger500,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: LinqRadius.borderMd),
            ),
          );
          return;
        }
        locationCoords = {
          'lat': (locationResult['lat'] as double?) ?? 0.0,
          'lng': (locationResult['lng'] as double?) ?? 0.0,
        };
      }

      addressText = _currentLocationAddress ?? 'Current Location';
    }

    final budgetValue = _budgetCtrl.text.isNotEmpty
        ? double.tryParse(_budgetCtrl.text.trim())
        : null;
    final budgetMinKobo = budgetValue != null
        ? (budgetValue * 100).round()
        : null;

    if (_selectedCategories.isEmpty) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please select at least one service category before saving the job.',
            style: LinqTextStyles.bodySm.copyWith(
              color: LinqColors.textOnBrand,
            ),
          ),
          backgroundColor: LinqColors.danger500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: LinqRadius.borderMd),
        ),
      );
      return;
    }

    final categorySlug = _getCategorySlug(_selectedCategories.first);


    final pendingDraft = {
      'title': _titleCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'budget': _budgetCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'preferred_date': _preferredDate?.toIso8601String(),
      'categories': _selectedCategories,
      'use_manual_location': _useManualLocation,
      'current_location_address': _currentLocationAddress,
      'manual_state': _selectedManualState,
      'manual_lga': _selectedManualLga,
      'manual_area': _areaCtrl.text.trim(),
    };

    final result = await AuthService.createJobDraft(
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      categories: _selectedCategories,
      categorySlug: categorySlug,
      preferredDate: _preferredDate,
      budget: budgetValue,
      budgetMode: budgetValue != null ? 'fixed' : null,
      budgetMinKobo: budgetMinKobo,
      locationLat: locationCoords!['lat'],
      locationLng: locationCoords['lng'],
      locationAddressText: addressText,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (result['success'] == true) {
      await AuthService.clearPendingCustomerJobDraft();
      final jobData = Map<String, dynamic>.from(
        result['data'] as Map<String, dynamic>,
      );
      if (!mounted) return;

      final reviewData = {
        ...jobData,
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        if (_selectedCategories.isNotEmpty) 'categories': _selectedCategories,
        if (_preferredDate != null)
          'preferred_date': _preferredDate!.toIso8601String(),
        if (budgetValue != null) 'budget': budgetValue,
        'location': {
          'lat': locationCoords['lat'],
          'lng': locationCoords['lng'],
          'address_text': addressText,
        },
      };

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => JobReviewPage(jobData: reviewData),
        ),
      ).then((result) {
        if (result == true) {
          _formKey.currentState!.reset();
          _titleCtrl.clear();
          _descCtrl.clear();
          _budgetCtrl.clear();
          _addressCtrl.clear();
          _areaCtrl.clear();
          setState(() {
            _selectedCategories.clear();
            _preferredDate = null;
            _useManualLocation = false;
            _selectedManualState = null;
            _selectedManualLga = null;
          });
        }
      });
    } else {
      final message =
          result['message']?.toString() ?? 'Failed to save job draft.';
      if (message.contains('Authentication required') ||
          message.contains('log in')) {
        await AuthService.savePendingCustomerJobDraft(pendingDraft);
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: LinqTextStyles.bodySm.copyWith(
              color: LinqColors.textOnBrand,
            ),
          ),
          backgroundColor: LinqColors.danger500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: LinqRadius.borderMd),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(LinqSpacing.s5),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(LinqSpacing.s4),
              decoration: BoxDecoration(
                color: LinqColors.forest100,
                borderRadius: LinqRadius.borderMd,
                border: Border.all(color: LinqColors.forest200),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.post_add,
                    color: LinqColors.forest500,
                    size: 26,
                  ),
                  const SizedBox(width: LinqSpacing.s3),
                  Expanded(
                    child: Text(
                      "Can't find your service? Post a custom job and let qualified providers come to you.",
                      style: LinqTextStyles.bodySm.copyWith(
                        color: LinqColors.forest600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: LinqSpacing.s6),

            _label('Job title *'),
            TextFormField(
              controller: _titleCtrl,
              decoration: linqInputDecoration(
                label: 'e.g. Install custom shelving unit',
                icon: Icons.work_outline,
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: LinqSpacing.s4),

            _label('Job description *'),
            TextFormField(
              controller: _descCtrl,
              maxLines: 4,
              decoration: linqInputDecoration(
                label: 'Describe scope, materials, access requirements…',
                icon: Icons.description_outlined,
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: LinqSpacing.s4),

            _label('Service categories'),
            const SizedBox(height: LinqSpacing.s2),
            _categoriesLoading
                ? const Center(child: CircularProgressIndicator())
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _availableCategories.map((category) {
                      final name = category['name'] as String? ?? '';
                      final selected = _selectedCategories.contains(name);
                      return FilterChip(
                        label: Text(name),
                        selected: selected,
                        selectedColor: LinqColors.forest500,
                        backgroundColor: LinqColors.stone100,
                        labelStyle: LinqTextStyles.labelSm.copyWith(
                          color: selected
                              ? LinqColors.textOnBrand
                              : LinqColors.textBody,
                        ),
                        checkmarkColor: LinqColors.textOnBrand,
                        side: BorderSide(
                          color: selected
                              ? LinqColors.forest500
                              : LinqColors.borderDefault,
                        ),
                        onSelected: (val) => setState(() {
                          val
                              ? _selectedCategories.add(name)
                              : _selectedCategories.remove(name);
                        }),
                      );
                    }).toList(),
                  ),
            const SizedBox(height: LinqSpacing.s4),

            _label('Job location'),
            if (!_useManualLocation) ...[
              Container(
                padding: const EdgeInsets.all(LinqSpacing.s4),
                decoration: BoxDecoration(
                  color: LinqColors.forest50,
                  border: Border.all(color: LinqColors.forest200),
                  borderRadius: LinqRadius.borderMd,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.my_location,
                      color: LinqColors.forest500,
                      size: 20,
                    ),
                    const SizedBox(width: LinqSpacing.s3),
                    Expanded(
                      child: Text(
                        _currentLocationAddress ?? 'Detecting your location...',
                        style: LinqTextStyles.bodySm.copyWith(
                          color: LinqColors.forest700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        FocusScope.of(context).unfocus();
                        final useManual = await _showLocationChoiceDialog();
                        if (useManual != null) {
                          setState(() => _useManualLocation = useManual);
                        }
                      },
                      child: Text(
                        'Change',
                        style: LinqTextStyles.label.copyWith(
                          color: LinqColors.forest500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              DropdownButtonFormField<String>(
                value: _selectedManualState,
                decoration: linqInputDecoration(
                  label: 'State',
                  icon: Icons.map_outlined,
                ),
                isExpanded: true,
                items: (countriesAndStates['Nigeria'] ?? [])
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (val) => setState(() {
                  _selectedManualState = val;
                  _selectedManualLga = null;
                }),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Select a state' : null,
              ),
              const SizedBox(height: LinqSpacing.s4),
              DropdownButtonFormField<String>(
                value: _selectedManualLga,
                decoration: linqInputDecoration(
                  label: 'Local Government Area (LGA)',
                  icon: Icons.location_city_outlined,
                ),
                isExpanded: true,
                items: (nigeriaLgasByState[_selectedManualState] ?? [])
                    .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                    .toList(),
                onChanged: _selectedManualState == null
                    ? null
                    : (val) => setState(() => _selectedManualLga = val),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Select an LGA' : null,
              ),
              const SizedBox(height: LinqSpacing.s4),
              TextFormField(
                controller: _areaCtrl,
                decoration: linqInputDecoration(
                  label: 'Area / City / Town',
                  icon: Icons.location_on_outlined,
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Area/city/town is required'
                    : null,
              ),
              const SizedBox(height: LinqSpacing.s4),
              TextFormField(
                controller: _addressCtrl,
                maxLines: 2,
                decoration: linqInputDecoration(
                  label: 'Street address or landmark (optional)',
                  icon: Icons.signpost_outlined,
                ),
              ),
              const SizedBox(height: LinqSpacing.s2),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      setState(() => _useManualLocation = false);
                    },
                    icon: const Icon(Icons.my_location, size: 16),
                    label: Text(
                      'Use Current Location',
                      style: LinqTextStyles.label.copyWith(
                        color: LinqColors.forest500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: LinqSpacing.s4),

            _label('Preferred date'),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: LinqSpacing.s4,
                  vertical: LinqSpacing.s3,
                ),
                decoration: BoxDecoration(
                  color: LinqColors.stone100,
                  border: Border.all(color: LinqColors.borderDefault),
                  borderRadius: LinqRadius.borderMd,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 18,
                      color: LinqColors.textTertiary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _preferredDate == null
                          ? 'Select a date (optional)'
                          : '${_preferredDate!.day}/${_preferredDate!.month}/${_preferredDate!.year}',
                      style: LinqTextStyles.body.copyWith(
                        color: _preferredDate == null
                            ? LinqColors.textTertiary
                            : LinqColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: LinqSpacing.s4),

            _label('Budget'),
            TextFormField(
              controller: _budgetCtrl,
              keyboardType: TextInputType.number,
              decoration: linqInputDecoration(
                label: 'e.g. 20000',
                icon: Icons.payments_outlined,
              ),
              validator: (v) {
                if (v != null && v.isNotEmpty && double.tryParse(v) == null) {
                  return 'Enter a valid number';
                }
                return null;
              },
            ),
            const SizedBox(height: LinqSpacing.s8),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: linqPrimaryButton(verticalPadding: LinqSpacing.s4),
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: LinqColors.textOnBrand,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.send),
                label: Text(
                  _saving ? 'Saving draft...' : 'Continue',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: LinqSpacing.s5),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: LinqSpacing.s2),
    child: Text(text, style: LinqTextStyles.label),
  );
}

// ── BOTTOM NAV ───────────────────────────────────────────────────
class _BottomNav extends StatelessWidget {
  const _BottomNav();

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: 1,
      selectedItemColor: LinqColors.forest500,
      unselectedItemColor: LinqColors.textTertiary,
      backgroundColor: LinqColors.bgSurface,
      elevation: 0,
      type: BottomNavigationBarType.fixed,
      onTap: (index) {
        switch (index) {
          case 0:
            Navigator.pushNamed(context, '/customer-dashboard');
            break;
          case 1:
            break;
          case 2:
            Navigator.pushNamed(context, '/user-transactions');
            break;
          case 3:
            Navigator.pushNamed(context, '/user-profile');
            break;
        }
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.work), label: 'Jobs'),
        BottomNavigationBarItem(
          icon: Icon(Icons.account_balance_wallet),
          label: 'Wallet',
        ),
        BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
      ],
    );
  }
}
