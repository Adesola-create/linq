import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'job_review_page.dart';
import 'location_service.dart';
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
    print('[UserJob] id=${json['ulid'] ?? json['id']} state="${json['state']}" rawStatus="$rawStatus"');
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
  const UserJobsPage({super.key});

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
    _fetchJobs(forceRefresh: true);
  }

  Future<void> _fetchJobs({bool forceRefresh = false}) async {
    print('[UserJobsPage] _fetchJobs forceRefresh=$forceRefresh');
    final result = await AuthService.getCustomerJobs(
      forceRefresh: forceRefresh,
    );
    print('[UserJobsPage] _fetchJobs result: success=${result["success"]} fromCache=${result["fromCache"]}');
    if (!mounted) return;
    if (result['success'] == true) {
      final rawList = result['data'] as List<dynamic>;
      print('[UserJobsPage] raw jobs count: ${rawList.length}');
      for (final item in rawList) {
        if (item is Map) {
          print('[UserJobsPage] job id=${item["ulid"] ?? item["id"]} state="${item["state"]}" status="${item["status"]}" is_posted=${item["is_posted"]}');
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
      if (message.contains('Authentication required') ||
          message.contains('log in')) {
        // Token is invalid/expired, redirect to login
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
    return Scaffold(
      backgroundColor: LinqColors.bgPageApp,
      appBar: AppBar(
        backgroundColor: LinqColors.forest500,
        foregroundColor: LinqColors.textOnBrand,
        elevation: 0,
        title: Text(
          'My jobs',
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
      bottomNavigationBar: const _BottomNav(),
    );
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
  DateTime? _preferredDate;
  final List<String> _selectedCategories = [];
  bool _saving = false;
  bool _useManualLocation = false;
  String? _currentLocationAddress;
  List<Map<String, dynamic>> _availableCategories = [];
  bool _categoriesLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
    _loadCategories();
  }

  Future<void> _loadCurrentLocation() async {
    final cachedLocation = await LocationService.getCachedLocation();
    if (cachedLocation != null) {
      // For demo purposes, we'll use a placeholder address
      // In a real app, you'd reverse geocode the coordinates
      setState(
        () => _currentLocationAddress = 'Current Location (Auto-detected)',
      );
    }
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
      // Manual location - validate address exists on map
      addressText = _addressCtrl.text.trim();

      // Basic geocoding validation - in a real app, you'd call a geocoding service
      // For now, we'll just ensure it's a reasonable address length
      if (addressText.length < 5) {
        if (!mounted) return;
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Please enter a valid address that can be found on the map.',
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

      // For manual addresses, we'd typically geocode them here
      // For demo purposes, we'll use a placeholder location
      locationCoords = {
        'lat': 6.5244,
        'lng': 3.3792,
      }; // Lagos coordinates as example
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

    print('[UserJobsPage] Selected categories: $_selectedCategories');
    print(
      '[UserJobsPage] First category: ${_selectedCategories.first}',
    );
    print('[UserJobsPage] Category slug: $categorySlug');

    final result = await AuthService.createJobDraft(
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      categories: _selectedCategories,
      categorySlug: categorySlug,
      preferredDate: _preferredDate,
      budget: budgetValue,
      budgetMode: budgetValue != null ? 'fixed' : null,
      budgetMinKobo: budgetMinKobo,
      locationLat: locationCoords['lat'],
      locationLng: locationCoords['lng'],
      locationAddressText: addressText,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (result['success'] == true) {
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
        if (locationCoords != null)
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
          setState(() {
            _selectedCategories.clear();
            _preferredDate = null;
            _useManualLocation = false;
          });
        }
      });
    } else {
      final message =
          result['message']?.toString() ?? 'Failed to save job draft.';
      if (message.contains('Authentication required') ||
          message.contains('log in')) {
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
              TextFormField(
                controller: _addressCtrl,
                maxLines: 2,
                decoration: linqInputDecoration(
                  label: 'Enter job address or landmark (must exist on map)',
                  icon: Icons.location_on_outlined,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Location address is required';
                  }
                  // Basic validation - in a real app, you'd geocode here
                  if (v.trim().length < 5) {
                    return 'Please enter a valid address';
                  }
                  return null;
                },
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

            _label('Budget (optional)'),
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
                  _saving ? 'Saving draft...' : 'Save & review',
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
