import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'linq_theme.dart';

class JobReviewPage extends StatefulWidget {
  final Map<String, dynamic> jobData;

  const JobReviewPage({super.key, required this.jobData});

  @override
  State<JobReviewPage> createState() => _JobReviewPageState();
}

class _JobReviewPageState extends State<JobReviewPage> {
  bool _isPublishing = false;
  bool _loadingFull = false;
  bool _editing = false;
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _budgetController = TextEditingController();
  final _locationController = TextEditingController();
  final _categoriesController = TextEditingController();
  DateTime? _preferredDate;
  Map<String, dynamic> _fullJobData = {};

  @override
  void initState() {
    super.initState();
    _fullJobData = _normalizeJobData(widget.jobData);
    _populateEditFields();
    _fetchFullJob();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _budgetController.dispose();
    _locationController.dispose();
    _categoriesController.dispose();
    super.dispose();
  }

  void _populateEditFields() {
    final data = _fullJobData;
    _titleController.text = _valueFromFields(data, [
      'title',
      'name',
      'job_title',
    ]);
    _descriptionController.text = _valueFromFields(data, [
      'description',
      'description_text',
      'details',
      'job_description',
      'body',
      'desc',
    ]);
    _budgetController.text = _valueFromFields(
      data['budget_min_kobo'] != null && data['budget_min_kobo'] is num
          ? ((data['budget_min_kobo'] as num) / 100).toStringAsFixed(2)
          : data['budget'] ?? data['amount'] ?? data['price'],
      ['budget', 'amount', 'price'],
    );
    _locationController.text = _valueFromFields(
      data['address_text'] ?? data['location'] ?? data['address'],
      ['address_text', 'address'],
    );
    final categories = _extractCategories(
      data['categories'] ?? data['category'] ?? data['category_slug'],
    );
    _categoriesController.text = categories.join(', ');
    final preferredDateValue = _valueFromFields(
      data['preferred_date'] ?? data['scheduled_at'] ?? data['date'],
      ['preferred_date', 'scheduled_at', 'date'],
    );
    if (preferredDateValue.isNotEmpty) {
      _preferredDate = DateTime.tryParse(preferredDateValue);
    }
  }

  Future<void> _fetchFullJob() async {
    final ulid = (_fullJobData['ulid'] ?? _fullJobData['id'] ?? '').toString();
    if (ulid.isEmpty) return;
    setState(() => _loadingFull = true);
    final result = await AuthService.getJobDetails(ulid);
    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {
        _fullJobData = _normalizeJobData(
          result['data'] as Map<String, dynamic>,
        );
        _loadingFull = false;
      });
      _populateEditFields();
    } else {
      setState(() => _loadingFull = false);
    }
  }

  void _startEditing() {
    setState(() {
      _editing = true;
    });
  }

  void _cancelEditing() {
    _populateEditFields();
    setState(() {
      _editing = false;
    });
  }

  void _saveEditedDetails() {
    if (!_formKey.currentState!.validate()) return;

    final updatedData = Map<String, dynamic>.from(_fullJobData);
    updatedData['title'] = _titleController.text.trim();
    updatedData['description'] = _descriptionController.text.trim();
    updatedData['budget'] =
        double.tryParse(_budgetController.text.trim()) ?? updatedData['budget'];
    updatedData['address_text'] = _locationController.text.trim();
    updatedData['categories'] = _categoriesController.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (_preferredDate != null) {
      updatedData['preferred_date'] = _preferredDate!.toIso8601String();
    }

    setState(() {
      _fullJobData = updatedData;
      _editing = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Job details updated. Review the job again before publishing.',
          style: LinqTextStyles.bodySm.copyWith(color: LinqColors.textOnBrand),
        ),
        backgroundColor: LinqColors.success500,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: LinqRadius.borderMd),
      ),
    );
  }

  Future<void> _pickPreferredDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _preferredDate ?? DateTime.now().add(const Duration(days: 1)),
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

    if (picked != null) {
      setState(() {
        _preferredDate = picked;
      });
    }
  }

  bool get _isAlreadyPublished {
    for (final data in [widget.jobData, _fullJobData]) {
      final state = (data['state'] ?? data['status'] ?? '')
          .toString()
          .toLowerCase();
      if (state == 'published' ||
          state == 'open' ||
          state.contains('awaiting_bids')) {
        return true;
      }
    }
    return false;
  }

  Future<void> _publishJob() async {
    if (_isAlreadyPublished) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'This job is already published and open to providers.',
            style: LinqTextStyles.bodySm.copyWith(
              color: LinqColors.textOnBrand,
            ),
          ),
          backgroundColor: LinqColors.info500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: LinqRadius.borderMd),
        ),
      );
      return;
    }

    setState(() => _isPublishing = true);

    final normalizedData = _normalizeJobData(widget.jobData);
    final ulid = normalizedData['ulid'] ?? normalizedData['id'] ?? '';
    if (ulid.toString().isEmpty) {
      setState(() => _isPublishing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to publish this job because its ID is missing.',
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

    final result = await AuthService.publishJob(ulid.toString());

    if (!mounted) return;
    setState(() => _isPublishing = false);

    if (result['success'] == true) {
      await AuthService.clearJobsCache();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Job published successfully! Providers can now see and apply for this job.',
            style: LinqTextStyles.bodySm.copyWith(
              color: LinqColors.textOnBrand,
            ),
          ),
          backgroundColor: LinqColors.success500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: LinqRadius.borderMd),
        ),
      );
      Navigator.pushNamedAndRemoveUntil(context, '/user-jobs', (_) => false);
    } else if (result['already_published'] == true) {
      await AuthService.clearJobsCache();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'This job is already published and open to providers.',
            style: LinqTextStyles.bodySm.copyWith(
              color: LinqColors.textOnBrand,
            ),
          ),
          backgroundColor: LinqColors.info500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: LinqRadius.borderMd),
        ),
      );
      Navigator.pushNamedAndRemoveUntil(context, '/user-jobs', (_) => false);
    } else {
      final message = result['message']?.toString() ?? 'Failed to publish job.';
      if (message.contains('Authentication required') ||
          message.contains('log in')) {
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

  String _valueFromFields(dynamic raw, List<String> keys) {
    if (raw == null) return '';
    if (raw is String) return raw.trim();
    if (raw is num || raw is bool) return raw.toString();
    if (raw is List) {
      for (final item in raw) {
        final value = _valueFromFields(item, keys);
        if (value.isNotEmpty) return value;
      }
      return '';
    }
    if (raw is Map<String, dynamic>) {
      for (final key in keys) {
        final value = _valueFromFields(raw[key], keys);
        if (value.isNotEmpty) return value;
      }
      return '';
    }
    return raw.toString().trim();
  }

  List<String> _extractCategories(dynamic raw) {
    if (raw == null) return [];
    if (raw is String) {
      return raw
          .split(RegExp(r'[;,|]'))
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
    }
    if (raw is List) {
      return raw
          .map((item) {
            if (item is String) return item.trim();
            if (item is Map<String, dynamic>) {
              return _valueFromFields(item, [
                'name',
                'title',
                'label',
                'slug',
                'category',
              ]);
            }
            return item?.toString().trim() ?? '';
          })
          .where((value) => value.isNotEmpty)
          .toList();
    }
    if (raw is Map<String, dynamic>) {
      final value = _valueFromFields(raw, [
        'name',
        'title',
        'label',
        'slug',
        'category',
      ]);
      return value.isEmpty ? [] : [value];
    }
    return [raw.toString().trim()];
  }

  Map<String, dynamic>? _extractLocation(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is String) return {'address_text': raw};
    return null;
  }

  Map<String, dynamic> _normalizeJobData(Map<String, dynamic> rawData) {
    if (rawData['data'] is Map<String, dynamic>) {
      return _normalizeJobData(rawData['data'] as Map<String, dynamic>);
    }
    if (rawData['job'] is Map<String, dynamic>) {
      return _normalizeJobData(rawData['job'] as Map<String, dynamic>);
    }
    return rawData;
  }

  @override
  Widget build(BuildContext context) {
    final jobData = _fullJobData;
    final title = _valueFromFields(jobData, ['title', 'name', 'job_title']);
    final description = _valueFromFields(jobData, [
      'description',
      'description_text',
      'details',
      'job_description',
      'body',
      'desc',
    ]);
    final categories = _extractCategories(
      jobData['categories'] ?? jobData['category'] ?? jobData['category_slug'],
    );
    final preferredDate = _valueFromFields(
      jobData['preferred_date'] ?? jobData['scheduled_at'] ?? jobData['date'],
      ['preferred_date', 'scheduled_at', 'date'],
    );
    final budgetKobo = jobData['budget_min_kobo'];
    final budgetDisplay = budgetKobo != null && budgetKobo is num
        ? '₦${(budgetKobo / 100).toStringAsFixed(2)}'
        : _valueFromFields(
            jobData['budget'] ?? jobData['amount'] ?? jobData['price'],
            ['budget', 'amount', 'price'],
          );
    final locationAddress = _valueFromFields(
      jobData['address_text'] ?? jobData['location'] ?? jobData['address'],
      ['address_text', 'address'],
    );

    return Scaffold(
      backgroundColor: LinqColors.bgPageApp,
      appBar: AppBar(
        backgroundColor: LinqColors.forest500,
        foregroundColor: LinqColors.textOnBrand,
        elevation: 0,
        title: Text(
          'Review Job',
          style: LinqTextStyles.h3.copyWith(color: LinqColors.textOnBrand),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loadingFull
          ? const Center(
              child: CircularProgressIndicator(color: LinqColors.forest500),
            )
          : _editing
          ? _buildEditForm()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(LinqSpacing.s5),
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
                          Icons.visibility,
                          color: LinqColors.forest500,
                          size: 26,
                        ),
                        const SizedBox(width: LinqSpacing.s3),
                        Expanded(
                          child: Text(
                            'Please review your job details before publishing. Once published, providers will be able to see and apply for this job.',
                            style: LinqTextStyles.bodySm.copyWith(
                              color: LinqColors.forest600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: LinqSpacing.s6),

                  if (title.isNotEmpty) _reviewRow('Title', title),
                  if (description.isNotEmpty)
                    _reviewRow('Description', description),
                  if (categories.isNotEmpty)
                    _reviewRow('Categories', categories.join(', ')),
                  if (locationAddress.isNotEmpty)
                    _reviewRow('Location', locationAddress),
                  if (preferredDate.isNotEmpty)
                    _reviewRow('Preferred Date', _formatDate(preferredDate)),
                  if (budgetDisplay.isNotEmpty)
                    _reviewRow('Budget', budgetDisplay),

                  const SizedBox(height: LinqSpacing.s4),

                  Container(
                    padding: const EdgeInsets.all(LinqSpacing.s4),
                    decoration: BoxDecoration(
                      color: LinqColors.warning50,
                      borderRadius: LinqRadius.borderMd,
                      border: Border.all(color: LinqColors.warning500),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: LinqColors.warning500,
                          size: 20,
                        ),
                        const SizedBox(width: LinqSpacing.s3),
                        Expanded(
                          child: Text(
                            'Publishing this job will make it visible to qualified providers in your area.',
                            style: LinqTextStyles.bodyXs.copyWith(
                              color: LinqColors.warning700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: LinqSpacing.s6),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                              color: LinqColors.borderDefault,
                            ),
                            foregroundColor: LinqColors.textPrimary,
                            padding: const EdgeInsets.symmetric(
                              vertical: LinqSpacing.s4,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: LinqRadius.borderMd,
                            ),
                          ),
                          onPressed: _isAlreadyPublished
                              ? () => Navigator.pop(context)
                              : _startEditing,
                          child: Text(
                            _isAlreadyPublished ? 'Back' : 'Edit Details',
                          ),
                        ),
                      ),
                      if (!_isAlreadyPublished) ...[
                        const SizedBox(width: LinqSpacing.s3),
                        Expanded(
                          child: ElevatedButton(
                            style: linqPrimaryButton(
                              verticalPadding: LinqSpacing.s4,
                            ),
                            onPressed: _isPublishing ? null : _publishJob,
                            child: _isPublishing
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      color: LinqColors.textOnBrand,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'Publish Job',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildEditForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(LinqSpacing.s5),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Edit Job Details',
              style: LinqTextStyles.h3.copyWith(color: LinqColors.forest500),
            ),
            const SizedBox(height: LinqSpacing.s4),
            Text(
              'Update your draft before publishing. Your current draft values are already loaded below.',
              style: LinqTextStyles.body.copyWith(
                color: LinqColors.textSecondary,
              ),
            ),
            const SizedBox(height: LinqSpacing.s6),
            TextFormField(
              controller: _titleController,
              decoration: linqInputDecoration(
                label: 'Job title',
                icon: Icons.work_outline,
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Title is required'
                  : null,
            ),
            const SizedBox(height: LinqSpacing.s4),
            TextFormField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: linqInputDecoration(
                label: 'Job description',
                icon: Icons.description_outlined,
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Description is required'
                  : null,
            ),
            const SizedBox(height: LinqSpacing.s4),
            TextFormField(
              controller: _categoriesController,
              decoration: linqInputDecoration(
                label: 'Categories',
                icon: Icons.category_outlined,
                helper: 'Separate multiple categories with commas.',
              ),
            ),
            const SizedBox(height: LinqSpacing.s4),
            TextFormField(
              controller: _locationController,
              decoration: linqInputDecoration(
                label: 'Location address',
                icon: Icons.location_on_outlined,
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Location is required'
                  : null,
            ),
            const SizedBox(height: LinqSpacing.s4),
            TextFormField(
              controller: _budgetController,
              keyboardType: TextInputType.number,
              decoration: linqInputDecoration(
                label: 'Budget',
                icon: Icons.payments_outlined,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return null;
                return double.tryParse(value.trim()) == null
                    ? 'Enter a valid number'
                    : null;
              },
            ),
            const SizedBox(height: LinqSpacing.s4),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: linqPrimaryButton(verticalPadding: LinqSpacing.s4),
                onPressed: _pickPreferredDate,
                child: Text(
                  _preferredDate == null
                      ? 'Pick preferred date'
                      : 'Preferred date: ${_preferredDate!.day}/${_preferredDate!.month}/${_preferredDate!.year}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: LinqSpacing.s6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: LinqColors.borderDefault),
                      foregroundColor: LinqColors.textPrimary,
                      padding: const EdgeInsets.symmetric(
                        vertical: LinqSpacing.s4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: LinqRadius.borderMd,
                      ),
                    ),
                    onPressed: _cancelEditing,
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: LinqSpacing.s3),
                Expanded(
                  child: ElevatedButton(
                    style: linqPrimaryButton(verticalPadding: LinqSpacing.s4),
                    onPressed: _saveEditedDetails,
                    child: const Text('Save changes'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: LinqSpacing.s5),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(LinqSpacing.s5),
      decoration: BoxDecoration(
        color: LinqColors.bgSurface,
        borderRadius: LinqRadius.borderLg,
        border: Border.all(color: LinqColors.borderDefault),
        boxShadow: LinqShadows.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: LinqTextStyles.h4),
          const SizedBox(height: LinqSpacing.s4),
          ...children,
        ],
      ),
    );
  }

  Widget _reviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LinqSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: LinqTextStyles.bodySm.copyWith(
              color: LinqColors.textTertiary,
            ),
          ),
          const SizedBox(height: LinqSpacing.s1),
          Text(value, style: LinqTextStyles.body),
        ],
      ),
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return '';
    if (date is String) {
      try {
        final parsed = DateTime.parse(date);
        return '${parsed.day}/${parsed.month}/${parsed.year}';
      } catch (_) {
        return date;
      }
    }
    if (date is DateTime) {
      return '${date.day}/${date.month}/${date.year}';
    }
    return date.toString();
  }
}
