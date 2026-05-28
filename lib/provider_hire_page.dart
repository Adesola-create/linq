import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'job_review_page.dart';
import 'linq_theme.dart';
import 'location_service.dart';

class ProviderHirePage extends StatefulWidget {
  final Map<String, dynamic> provider;

  const ProviderHirePage({super.key, required this.provider});

  @override
  State<ProviderHirePage> createState() => _ProviderHirePageState();
}

class _ProviderHirePageState extends State<ProviderHirePage> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  DateTime? _preferredDate;
  bool _sending = false;
  bool _useManualLocation = false;
  bool _alsoOpenToCategory = false;
  String? _currentLocationAddress;
  List<Map<String, dynamic>> _availableCategories = [];
  final List<String> _selectedCategories = [];
  bool _categoriesLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
    _loadCategories();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _budgetCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentLocation() async {
    final cachedLocation = await LocationService.getCachedLocation();
    if (cachedLocation != null) {
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
              shape:
                  RoundedRectangleBorder(borderRadius: LinqRadius.borderMd),
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
          colorScheme: Theme.of(context)
              .colorScheme
              .copyWith(primary: LinqColors.forest500),
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

  String get _providerName =>
      (widget.provider['name'] ?? widget.provider['business_name'] ??
              widget.provider['provider_name'] ??
              'Service Provider')
          .toString();

  String get _providerSpecialty =>
      (widget.provider['role'] ?? widget.provider['specialty'] ?? '')
          .toString();

  String get _providerRating =>
      (widget.provider['rating'] ?? widget.provider['avg_rating'] ?? '0.0')
          .toString();

  String get _providerImage {
    final image = widget.provider['photo_url'] ??
        widget.provider['profile_photo'] ??
        widget.provider['image_url'] ??
        widget.provider['avatar_url'];
    return image?.toString() ?? '';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _sending = true);

    Map<String, dynamic>? locationCoords;
    String? addressText;

    if (_useManualLocation) {
      addressText = _addressCtrl.text.trim();
      if (addressText.length < 5) {
        if (!mounted) return;
        setState(() => _sending = false);
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
      locationCoords = {
        'lat': 6.5244,
        'lng': 3.3792,
      };
    } else {
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
          setState(() => _sending = false);
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

    final selectedCategories = _selectedCategories.isNotEmpty
        ? _selectedCategories
        : (_availableCategories.isNotEmpty
            ? [
                _availableCategories.first['name']?.toString() ?? 'general',
              ]
            : <String>[]);

    final categorySlug = selectedCategories.isNotEmpty
        ? _getCategorySlug(selectedCategories.first)
        : _toSlug(_providerSpecialty.isNotEmpty
            ? _providerSpecialty
            : 'general');

    final providerUlid = (widget.provider['ulid'] ??
            widget.provider['id'] ??
            widget.provider['provider_id'])
        .toString();
    if (providerUlid.isEmpty) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to identify the selected provider.',
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

    final result = await AuthService.createJobDraft(
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      categories: selectedCategories,
      categorySlug: categorySlug,
      preferredDate: _preferredDate,
      budget: budgetValue,
      budgetMode: budgetValue != null ? 'fixed' : 'negotiable',
      budgetMinKobo: budgetMinKobo,
      locationLat: locationCoords['lat'],
      locationLng: locationCoords['lng'],
      locationAddressText: addressText,
      targetProviderUlid: providerUlid,
      openToCategoryProviders: _alsoOpenToCategory,
    );

    if (!mounted) return;
    setState(() => _sending = false);

    if (result['success'] == true) {
      final jobData = Map<String, dynamic>.from(result['data'] as Map<String, dynamic>);
      final reviewData = {
        ...jobData,
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        if (selectedCategories.isNotEmpty) 'categories': selectedCategories,
        if (_preferredDate != null)
          'preferred_date': _preferredDate!.toIso8601String(),
        if (budgetValue != null) 'budget': budgetValue,
        if (locationCoords != null)
          'location': {
            'lat': locationCoords['lat'],
            'lng': locationCoords['lng'],
            'address_text': addressText,
          },
        'target_provider_ulid': providerUlid,
        if (_alsoOpenToCategory) 'open_to_category_providers': true,
        'provider': widget.provider,
      };

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => JobReviewPage(jobData: reviewData),
        ),
      );
    } else {
      final message = result['message']?.toString() ?? 'Failed to save job draft.';
      if (message.contains('Authentication required') ||
          message.contains('log in')) {
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
        return;
      }
      if (!mounted) return;
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

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: LinqSpacing.s2),
        child: Text(text, style: LinqTextStyles.label),
      );

  Widget _providerSummary() {
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
          CircleAvatar(
            radius: 32,
            backgroundColor: LinqColors.forest100,
            backgroundImage: _providerImage.isNotEmpty
                ? CachedNetworkImageProvider(_providerImage)
                : null,
            child: _providerImage.isEmpty
                ? const Icon(Icons.person, size: 28, color: LinqColors.forest500)
                : null,
          ),
          const SizedBox(width: LinqSpacing.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_providerName, style: LinqTextStyles.h3),
                const SizedBox(height: LinqSpacing.s1),
                Text(
                  _providerSpecialty.isNotEmpty
                      ? _providerSpecialty
                      : 'Selected provider',
                  style: LinqTextStyles.bodySm.copyWith(
                    color: LinqColors.textSecondary,
                  ),
                ),
                const SizedBox(height: LinqSpacing.s2),
                Row(
                  children: [
                    const Icon(Icons.star, size: 16, color: Colors.amber),
                    const SizedBox(width: 6),
                    Text(_providerRating, style: LinqTextStyles.bodySm),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Hire ${_providerName.split(' ').first}'),
        backgroundColor: LinqColors.forest500,
      ),
      backgroundColor: LinqColors.bgPageApp,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(LinqSpacing.s5),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _providerSummary(),
              const SizedBox(height: LinqSpacing.s5),
              Text(
                'Create a job for this provider and choose whether it should also be open to other providers in the same category.',
                style: LinqTextStyles.bodySm.copyWith(color: LinqColors.textSecondary),
              ),
              const SizedBox(height: LinqSpacing.s5),
              _label('Job title *'),
              TextFormField(
                controller: _titleCtrl,
                decoration: linqInputDecoration(
                  label: 'e.g. Install custom shelving unit',
                  icon: Icons.work_outline,
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
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
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
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
                                  : LinqColors.borderDefault),
                          onSelected: (val) => setState(() {
                            if (val) {
                              _selectedCategories.add(name);
                            } else {
                              _selectedCategories.remove(name);
                            }
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
                    label: 'Enter job address or landmark',
                    icon: Icons.location_on_outlined,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Location address is required';
                    }
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
                      onPressed: () => setState(() => _useManualLocation = false),
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
              const SizedBox(height: LinqSpacing.s4),
              CheckboxListTile(
                value: _alsoOpenToCategory,
                activeColor: LinqColors.forest500,
                title: Text(
                  'Also open to same-category providers',
                  style: LinqTextStyles.body,
                ),
                subtitle: Text(
                  'This job will still be sent directly to this provider, but it will also be visible for bids from other providers in the same category.',
                  style: LinqTextStyles.bodySm.copyWith(color: LinqColors.textSecondary),
                ),
                onChanged: (value) => setState(() {
                  _alsoOpenToCategory = value ?? false;
                }),
              ),
              const SizedBox(height: LinqSpacing.s4),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: linqPrimaryButton(verticalPadding: LinqSpacing.s4),
                  onPressed: _sending ? null : _submit,
                  icon: _sending
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
                    _sending ? 'Saving job...' : 'Save & review',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
