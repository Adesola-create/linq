import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'linq_theme.dart';
import 'provider_nav_bar.dart';

class ProviderJobsPage extends StatefulWidget {
  const ProviderJobsPage({super.key});

  @override
  State<ProviderJobsPage> createState() => _ProviderJobsPageState();
}

class _ProviderJobsPageState extends State<ProviderJobsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late PageController _pageController;

  List<Map<String, dynamic>> _allJobs = [];
  List<Map<String, dynamic>> _activeJobs = [];
  bool _loading = true;
  String? _errorMessage;
  int _selectedNavIndex = 1; // Jobs tab

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _pageController = PageController();
    _tabController.addListener(_onTabChanged);
    _fetchJobs();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) {
      _pageController.animateToPage(
        _tabController.index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _fetchJobs() async {
    try {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });

      // Fetch available jobs that match provider's skills
      final availableJobsResult = await AuthService.getJobs();
      print('[ProviderJobsPage] Available jobs result: $availableJobsResult');

      if (availableJobsResult['success'] == true) {
        final jobsList = availableJobsResult['data'] ?? [];
        if (jobsList is List) {
          setState(() {
            _allJobs = List<Map<String, dynamic>>.from(
              jobsList
                  .whereType<Map<String, dynamic>>()
                  .where((job) => job['status'] == 'open' || job['state'] == 'open'),
            );
          });
        }
      }

      // Fetch active jobs (jobs provider has accepted)
      final activeJobsResult = await AuthService.getProviderJobs();
      print('[ProviderJobsPage] Active jobs result: $activeJobsResult');

      if (activeJobsResult['success'] == true) {
        final jobsList = activeJobsResult['data'] ?? [];
        if (jobsList is List) {
          setState(() {
            _activeJobs = List<Map<String, dynamic>>.from(
              jobsList.whereType<Map<String, dynamic>>(),
            );
          });
        }
      }

      setState(() {
        _loading = false;
      });
    } catch (e) {
      print('[ProviderJobsPage] Error fetching jobs: $e');
      setState(() {
        _errorMessage = 'Unable to load jobs. Please try again.';
        _loading = false;
      });
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
      Navigator.pushNamed(context, route);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LinqColors.bgPageApp,
      appBar: AppBar(
        backgroundColor: LinqColors.forest500,
        foregroundColor: LinqColors.textOnBrand,
        titleTextStyle: LinqTextStyles.h4.copyWith(color: Colors.white),
        title: const Text('Jobs'),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          labelStyle: LinqTextStyles.body.copyWith(fontWeight: FontWeight.w700),
          unselectedLabelStyle: LinqTextStyles.body,
          onTap: (index) {
            _pageController.animateToPage(
              index,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          },
          tabs: const [
            Tab(text: 'All Jobs'),
            Tab(text: 'Active'),
          ],
        ),
      ),
      bottomNavigationBar: ProviderNavBar(
        selectedIndex: _selectedNavIndex,
        onNavigate: _handleNavigation,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 48,
                          color: LinqColors.danger500,
                        ),
                        const SizedBox(height: LinqSpacing.s3),
                        Text(
                          _errorMessage!,
                          style: LinqTextStyles.body
                              .copyWith(color: LinqColors.danger500),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: LinqSpacing.s4),
                        ElevatedButton(
                          onPressed: _fetchJobs,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    _tabController.index = index;
                  },
                  children: [
                    _buildAllJobsTab(),
                    _buildActiveJobsTab(),
                  ],
                ),
    );
  }

  Widget _buildAllJobsTab() {
    if (_allJobs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.work_outline,
                size: 64,
                color: LinqColors.textSecondary,
              ),
              const SizedBox(height: LinqSpacing.s4),
              Text(
                'No jobs available',
                style: LinqTextStyles.h4,
              ),
              const SizedBox(height: LinqSpacing.s2),
              Text(
                'Check back later for new opportunities.',
                style: LinqTextStyles.bodySm,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(LinqSpacing.s4),
      itemCount: _allJobs.length,
      itemBuilder: (context, index) {
        final job = _allJobs[index];
        return _buildJobCard(job, isActive: false);
      },
    );
  }

  Widget _buildActiveJobsTab() {
    if (_activeJobs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 64,
                color: LinqColors.textSecondary,
              ),
              const SizedBox(height: LinqSpacing.s4),
              Text(
                'No active jobs',
                style: LinqTextStyles.h4,
              ),
              const SizedBox(height: LinqSpacing.s2),
              Text(
                'Accept jobs to start working on them.',
                style: LinqTextStyles.bodySm,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(LinqSpacing.s4),
      itemCount: _activeJobs.length,
      itemBuilder: (context, index) {
        final job = _activeJobs[index];
        return _buildJobCard(job, isActive: true);
      },
    );
  }

  Widget _buildJobCard(Map<String, dynamic> job, {required bool isActive}) {
    final title = job['title']?.toString() ?? 'Untitled Job';
    final category = job['category'] is Map
        ? job['category']['name']?.toString() ?? 'Service'
        : job['category']?.toString() ?? 'Service';
    final budget = job['amount'] ?? job['price'] ?? 'Not specified';
    final status = job['status'] ?? job['state'] ?? 'open';
    final location = job['address_text'] ?? job['location'] ?? 'Location not specified';
    final description = job['description'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: LinqSpacing.s3),
      decoration: BoxDecoration(
        color: LinqColors.bgSurface,
        borderRadius: LinqRadius.borderLg,
        border: Border.all(color: LinqColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(LinqSpacing.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: LinqTextStyles.h4),
                          const SizedBox(height: LinqSpacing.s2),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: LinqSpacing.s2,
                                  vertical: LinqSpacing.s1,
                                ),
                                decoration: BoxDecoration(
                                  color: LinqColors.forest100,
                                  borderRadius: LinqRadius.borderSm,
                                ),
                                child: Text(
                                  category,
                                  style: LinqTextStyles.labelSm
                                      .copyWith(color: LinqColors.forest600),
                                ),
                              ),
                              const SizedBox(width: LinqSpacing.s2),
                              if (isActive)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: LinqSpacing.s2,
                                    vertical: LinqSpacing.s1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: LinqColors.success100,
                                    borderRadius: LinqRadius.borderSm,
                                  ),
                                  child: Text(
                                    'Active',
                                    style: LinqTextStyles.labelSm
                                        .copyWith(color: LinqColors.success500),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '\$$budget',
                      style: LinqTextStyles.h4.copyWith(
                        color: LinqColors.forest600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: LinqSpacing.s3),
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: LinqColors.textSecondary,
                    ),
                    const SizedBox(width: LinqSpacing.s2),
                    Expanded(
                      child: Text(
                        location,
                        style: LinqTextStyles.bodySm,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: LinqSpacing.s3),
                  Text(
                    description,
                    style: LinqTextStyles.bodySm,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: LinqSpacing.s4),
            child: Divider(color: LinqColors.borderDefault),
          ),
          Padding(
            padding: const EdgeInsets.all(LinqSpacing.s4),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pushNamed(
                    context,
                    '/job-details',
                    arguments: job,
                  );
                },
                child: Text(isActive ? 'View Details' : 'Apply Now'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
