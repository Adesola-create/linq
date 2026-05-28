import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'linq_theme.dart';
import 'provider_nav_bar.dart';

class ActiveJobDetailsScreen extends StatefulWidget {
  final Map<String, dynamic>? jobData;

  const ActiveJobDetailsScreen({super.key, this.jobData});

  @override
  State<ActiveJobDetailsScreen> createState() => _ActiveJobDetailsScreenState();
}

class _ActiveJobDetailsScreenState extends State<ActiveJobDetailsScreen> {
  Map<String, dynamic>? _jobDetails;
  bool _loading = true;
  String? _errorMessage;
  int _selectedNavIndex = 1; // Jobs tab

  @override
  void initState() {
    super.initState();
    _loadJobDetails();
  }

  Future<void> _loadJobDetails() async {
    final jobId = _extractJobId(widget.jobData);
    if (jobId.isEmpty) {
      setState(() {
        _errorMessage = 'Job ID was not provided.';
        _loading = false;
      });
      return;
    }

    try {
      final response = await AuthService.getJobDetails(jobId);
      if (response['success'] == true && response['data'] is Map<String, dynamic>) {
        final jobData = Map<String, dynamic>.from(response['data'] as Map);
        await AuthService.saveCustomerJob(jobData);
        if (!mounted) return;
        setState(() {
          _jobDetails = jobData;
          _loading = false;
        });
      } else {
        setState(() {
          _errorMessage = _stringify(response['message'])
              .isNotEmpty
              ? _stringify(response['message'])
              : 'Unable to load job details.';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Unable to load job details.';
        _loading = false;
      });
    }
  }

  String _extractJobId(Map<String, dynamic>? data) {
    return _valueFromKeys(data, ['id', 'ulid', 'job_id', 'jobId']);
  }

  String _valueFromKeys(Map<String, dynamic>? data, List<String> keys) {
    if (data == null) return '';
    for (final key in keys) {
      final value = _stringify(data[key]);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _stringify(dynamic raw) {
    if (raw == null) return '';
    if (raw is String) return raw.trim();
    if (raw is num || raw is bool) return raw.toString();
    if (raw is List) {
      return raw.map(_stringify).where((item) => item.isNotEmpty).join(', ');
    }
    if (raw is Map) {
      return raw.entries
          .map((entry) => '${entry.key}: ${_stringify(entry.value)}')
          .where((item) => item.isNotEmpty)
          .join(', ');
    }
    return raw.toString().trim();
  }

  Widget _labelValueRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              '$label:',
              style: LinqTextStyles.label.copyWith(color: LinqColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : 'Not specified',
              style: LinqTextStyles.body,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(LinqSpacing.s5),
      decoration: BoxDecoration(
        color: LinqColors.bgSurface,
        borderRadius: LinqRadius.borderLg,
        border: Border.all(color: LinqColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: LinqTextStyles.h4),
          const SizedBox(height: LinqSpacing.s3),
          ...children,
        ],
      ),
    );
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
    final title = _valueFromKeys(
      _jobDetails ?? widget.jobData,
      ['title', 'name', 'job_title'],
    );

    return Scaffold(
      backgroundColor: LinqColors.bgPageApp,
      appBar: AppBar(
        backgroundColor: LinqColors.forest500,
        foregroundColor: LinqColors.textOnBrand,
        title: Text(title.isNotEmpty ? title : 'Job Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
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
                    child: Text(
                      _errorMessage!,
                      style: LinqTextStyles.body.copyWith(color: LinqColors.danger500),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _buildDetailsView(),
    );
  }

  Widget _buildDetailsView() {
    final job = _jobDetails ?? widget.jobData ?? {};
    final title = _valueFromKeys(job, ['title', 'name', 'job_title']);
    //final jobId = _valueFromKeys(job, ['id', 'ulid', 'job_id', 'jobId']);
    final status = _valueFromKeys(job, ['status', 'state']);
    final category = _valueFromKeys(job, ['category', 'service', 'job_category']);
    final budget = _formatBudget(job);
   // final customer = _valueFromKeys(job, ['customer_name', 'customer', 'client_name']);
    final description = _valueFromKeys(job, ['description', 'job_description', 'details', 'body']);
    final location = _valueFromKeys(job, ['address_text', 'address', 'location']);
    final createdAt = _valueFromKeys(job, ['created_at', 'createdAt', 'posted_at']);
    final scheduled = _valueFromKeys(job, ['scheduled_at', 'due_date', 'start_date', 'startAt']);
    //final contactEmail = _valueFromKeys(job, ['customer_email', 'email']);
    //final contactPhone = _valueFromKeys(job, ['customer_phone', 'phone', 'contact_number']);
    //final provider = _valueFromKeys(job, ['provider_name', 'posted_by', 'created_by']);

    final remainingFields = job.entries
        .where((entry) => !_excludedKeys.contains(entry.key))
        .map((entry) => MapEntry(entry.key, _stringify(entry.value)))
        .where((entry) => entry.value.isNotEmpty)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(LinqSpacing.s5),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionCard(
                'Job overview',
                [
                  _labelValueRow('Title', title),
                  //_labelValueRow('Job ID', jobId),
                  _labelValueRow('Status', status),
                  _labelValueRow('Category', category),
                  _labelValueRow('Budget', budget),
                  _labelValueRow('Location', location),
                  _labelValueRow('Created', createdAt),
                  _labelValueRow('Schedule', scheduled),
                ],
              ),
              // const SizedBox(height: LinqSpacing.s5),
              // _sectionCard(
              //   'Customer details',
              //   [
              //     _labelValueRow('Name', customer),
              //     _labelValueRow('Provider', provider),
              //     _labelValueRow('Email', contactEmail),
              //     _labelValueRow('Phone', contactPhone),
              //   ],
              // ),
              const SizedBox(height: LinqSpacing.s5),
              _sectionCard(
                'Description',
                [
                  Text(
                    description.isNotEmpty ? description : 'No description was provided for this job.',
                    style: LinqTextStyles.body,
                  ),
                ],
              ),
              // if (remainingFields.isNotEmpty) ...[
              //   const SizedBox(height: LinqSpacing.s5),
              //   _sectionCard(
              //     'More details',
              //     remainingFields
              //         .map((entry) => _labelValueRow(_prettifyKey(entry.key), entry.value))
              //         .toList(),
              //   ),
              // ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatBudget(Map<String, dynamic> job) {
    final budgetKobo = job['budget_min_kobo'];
    if (budgetKobo is num) {
      return '₦${(budgetKobo / 100).toStringAsFixed(2)}';
    }
    final budget = _valueFromKeys(job, ['budget', 'amount', 'price', 'budget_min']);
    return budget.isNotEmpty ? budget : 'Not specified';
  }

  String _prettifyKey(String key) {
    return key
        .replaceAll('_', ' ')
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (match) => '${match.group(1)} ${match.group(2)}')
        .splitMapJoin(
          RegExp(r'\b'),
          onMatch: (m) => m.group(0)!.replaceFirst(m.group(0)!, m.group(0)!.toUpperCase()),
          onNonMatch: (n) => n,
        )
        .trim();
  }

  final List<String> _excludedKeys = [
    'id',
    'ulid',
    'job_id',
    'jobId',
    'title',
    'name',
    'job_title',
    'status',
    'state',
    'category',
    'service',
    'job_category',
    'budget',
    'amount',
    'price',
    'budget_min_kobo',
    'budget_min',
    'description',
    'job_description',
    'details',
    'body',
    'address_text',
    'address',
    'location',
    'customer_name',
    'customer',
    'client_name',
    'customer_email',
    'email',
    'customer_phone',
    'phone',
    'contact_number',
    'provider_name',
    'posted_by',
    'created_by',
    'created_at',
    'createdAt',
    'posted_at',
    'scheduled_at',
    'due_date',
    'start_date',
    'startAt',
  ];
}
