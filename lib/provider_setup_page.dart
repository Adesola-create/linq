import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'linq_theme.dart';
import 'auth_service.dart';

class BusinessSetupPage extends StatefulWidget {
  const BusinessSetupPage({super.key});

  @override
  State<BusinessSetupPage> createState() => _BusinessSetupPageState();
}

class _BusinessSetupPageState extends State<BusinessSetupPage> {
  int _currentStep = 0;
  final _yearsController = TextEditingController();
  final _aboutController = TextEditingController();
  final _serviceSearchController = TextEditingController();
  final Map<String, TimeOfDay?> _dayStartTimes = {
    'Mon': const TimeOfDay(hour: 8, minute: 0),
    'Tue': null,
    'Wed': null,
    'Thu': null,
    'Fri': null,
  };
  final Map<String, TimeOfDay?> _dayEndTimes = {
    'Mon': const TimeOfDay(hour: 17, minute: 0),
    'Tue': null,
    'Wed': null,
    'Thu': null,
    'Fri': null,
  };
  final _locationController = TextEditingController();
  final _locationSearchController = TextEditingController();
  final _hourlyRateController = TextEditingController();
  final _portfolioController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final List<Map<String, String>> _availableCategories = [];
  final List<Map<String, String>> _primaryCategories = [];
  final List<Map<String, dynamic>> _rawCategories = [];
  String? _selectedCategory;
  final List<String> _selectedServiceCategories = [];
  XFile? _profilePhoto;
  Uint8List? _profilePhotoBytes;
  final List<XFile> _portfolioPhotos = [];
  final List<Uint8List> _portfolioPhotoBytes = [];
  String? _selectedLocationAddress;
  double? _selectedLocationLatitude;
  double? _selectedLocationLongitude;
  bool _categoriesLoading = false;
  String? _categoriesError;
  bool _isSaving = false;

  @override
  void dispose() {
    _yearsController.dispose();
    _aboutController.dispose();
    _serviceSearchController.dispose();
    _locationController.dispose();
    _locationSearchController.dispose();
    _hourlyRateController.dispose();
    _portfolioController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _serviceSearchController.addListener(() => setState(() {}));
    _loadCategories();
    _restorePendingFormData();
  }

  /// Restore provider setup form data that was cached before authentication failure
  Future<void> _restorePendingFormData() async {
    try {
      final cached = await AuthService.getPendingProviderSetup(
        email: await AuthService.getCurrentAccountEmail(),
      );
      if (cached == null || !mounted) return;

      setState(() {
        // Restore text fields
        if (cached['years_experience'] is String) {
          _yearsController.text = cached['years_experience'];
        }
        if (cached['description'] is String) {
          _aboutController.text = cached['description'];
        }
        if (cached['location'] is String) {
          _selectedLocationAddress = cached['location'];
          _locationController.text = cached['location'];
        }
        if (cached['location_latitude'] is num) {
          _selectedLocationLatitude = (cached['location_latitude'] as num).toDouble();
        }
        if (cached['location_longitude'] is num) {
          _selectedLocationLongitude = (cached['location_longitude'] as num).toDouble();
        }
        if (cached['hourly_rate'] is String) {
          _hourlyRateController.text = cached['hourly_rate'];
        }

        // Restore selections
        if (cached['primary_category'] is String) {
          _selectedCategory = cached['primary_category'];
        }
        if (cached['service_categories'] is List) {
          _selectedServiceCategories.clear();
          _selectedServiceCategories.addAll(
            (cached['service_categories'] as List).whereType<String>(),
          );
        }
      });

    } catch (e) {
    }
  }

  /// Cache form data before submission to preserve on auth failure
  Future<void> _savePendingFormData() async {
    try {
      final formData = <String, dynamic>{
        'primary_category': _selectedCategory,
        'service_categories': _selectedServiceCategories,
        'years_experience': _yearsController.text.trim(),
        'description': _aboutController.text.trim(),
        'location': _selectedLocationAddress,
        'location_latitude': _selectedLocationLatitude,
        'location_longitude': _selectedLocationLongitude,
        'hourly_rate': _hourlyRateController.text.trim(),
      };
      await AuthService.savePendingProviderSetup(formData);
    } catch (e) {
    }
  }

  Future<void> _pickProfilePhoto() async {
    final photo = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 80,
    );
    if (photo == null) return;
    final bytes = await photo.readAsBytes();
    setState(() {
      _profilePhoto = photo;
      _profilePhotoBytes = bytes;
    });
  }

  Future<void> _loadCategories() async {
    setState(() {
      _categoriesLoading = true;
      _categoriesError = null;
    });

    try {
      final res = await AuthService.getCategories(forceRefresh: false);
      if (!mounted) return;
      if (res['success'] == true) {
        final raw = res['data'];
        final list = (raw is List ? raw : <dynamic>[])
            .whereType<Map<String, dynamic>>();
        setState(() {
          _primaryCategories.clear();
          _availableCategories.clear();
          _rawCategories.clear();

          for (final category in list) {
            final label =
                (category['name'] ??
                        category['title'] ??
                        category['label'] ??
                        category['slug'])
                    ?.toString() ??
                '';
            final slug =
                (category['slug'] ?? category['id'] ?? category['category_id'])
                    ?.toString() ??
                label.toLowerCase().replaceAll(' ', '-');
            if (label.isNotEmpty) {
              _primaryCategories.add({'slug': slug, 'name': label});
              _availableCategories.add({'slug': slug, 'name': label});
            }
            // preserve raw hierarchical data for UI rendering
            try {
              _rawCategories.add(Map<String, dynamic>.from(category));
            } catch (_) {
              // ignore malformed entries
            }

            final children = category['children'];
            if (children is List) {
              for (final child in children.whereType<Map<String, dynamic>>()) {
                final childLabel =
                    (child['name'] ??
                            child['title'] ??
                            child['label'] ??
                            child['slug'])
                        ?.toString() ??
                    '';
                final childSlug =
                    (child['slug'] ?? child['id'] ?? child['category_id'])
                        ?.toString() ??
                    childLabel.toLowerCase().replaceAll(' ', '-');
                if (childLabel.isNotEmpty) {
                  _availableCategories.add({
                    'slug': childSlug,
                    'name': childLabel,
                  });
                }
              }
            }
          }
        });
      } else {
        setState(() {
          _categoriesError =
              res['message']?.toString() ?? 'Unable to load categories.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _categoriesError = 'Unable to load categories.';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _categoriesLoading = false;
      });
    }
  }

  final List<_SetupStep> _steps = [
    _SetupStep(number: 1, title: 'Welcome', subtitle: 'Get started'),
    _SetupStep(number: 2, title: 'Profile photo', subtitle: 'Your photo'),
    _SetupStep(number: 3, title: 'Describe yourself', subtitle: 'Bio'),
    _SetupStep(number: 4,
      title: 'What do you offer?',
      subtitle: 'What you offer',
    ),
    _SetupStep(
      number: 5,
      title: 'When are you available?',
      subtitle: 'Working hours',
    ),
    _SetupStep(
      number: 6,
      title: 'Where do you work from?',
      subtitle: 'Base location',
    ),
    _SetupStep(number: 7, title: 'Set your hourly rate', subtitle: 'Your rate'),
    _SetupStep(number: 8, title: 'Showcase your work', subtitle: 'Work photos'),
    _SetupStep(number: 9, title: 'Review', subtitle: 'Submit profile'),
  ];

  Future<void> _submit() async {
    final hasProviderSetupData = _aboutController.text.trim().isNotEmpty ||
        _selectedServiceCategories.isNotEmpty ||
        _selectedLocationAddress != null ||
        _hourlyRateController.text.trim().isNotEmpty ||
        _dayStartTimes.keys.any((day) =>
            _dayStartTimes[day] != null && _dayEndTimes[day] != null) ||
        _profilePhoto != null ||
        _portfolioPhotos.isNotEmpty;

    if (!hasProviderSetupData) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete your provider profile before submitting.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    // Cache form data before submission in case auth fails
    await _savePendingFormData();

    final payload = <String, dynamic>{
      'primary_category': _selectedCategory,
      'services': _selectedServiceCategories,
      'service_categories': _selectedServiceCategories,
      'years_experience': _yearsController.text.trim(),
      'bio': _aboutController.text.trim(),
      'description': _aboutController.text.trim(),
      'availability': _dayStartTimes.keys
          .where((day) => _dayStartTimes[day] != null && _dayEndTimes[day] != null)
          .map((day) =>
              '$day: ${_dayStartTimes[day]!.format(context)} - ${_dayEndTimes[day]!.format(context)}')
          .toList(),
      'location': _selectedLocationAddress,
      'location_latitude': _selectedLocationLatitude,
      'location_longitude': _selectedLocationLongitude,
      'hourly_rate': _hourlyRateController.text.trim(),
      'avatar': _profilePhoto?.path,
      'photos': _portfolioPhotos.map((photo) => photo.path).toList(),
      'portfolio_photo_count': _portfolioPhotos.length,
      'photo_uploaded': _profilePhoto != null,
    };

    final res = await AuthService.updateProfile(payload);

    setState(() => _isSaving = false);

    if (res['success'] == true) {
      // Clear cached pending form data on successful submission
      await AuthService.clearPendingProviderSetup();
      
      // Cache the submitted profile data immediately so dashboard has it
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('provider_account_profile', jsonEncode(payload));
      
      // Also force refresh the provider profile from backend for latest data
      await AuthService.getProviderAccountProfile(forceRefresh: true);
      
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Provider account saved successfully!')));
      if (!mounted) return;
      
      // Navigate to provider dashboard
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/provider-dashboard',
        (route) => false,
      );
    } else {
      final msg =
          res['message']?.toString() ?? 'Failed to save provider account';
      // On failure, keep the cached pending form data so it's available after re-login
      if (res['auth_required'] == true || msg.contains('401') || msg.contains('authentication') || msg.contains('expired')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            duration: const Duration(seconds: 4),
          ),
        );
        await AuthService.logout();
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  void _nextStep() {
    if (_currentStep < _steps.length - 1) {
      setState(() => _currentStep++);
    } else {
      _submit();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_currentStep == 0) {
          return true;
        }
        _previousStep();
        return false;
      },
      child: Scaffold(
        backgroundColor: LinqColors.bgPageApp,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth > 1000;
              final horizontalPadding = isDesktop
                  ? LinqSpacing.s8
                  : LinqSpacing.s6;
              final verticalPadding = LinqSpacing.s8;

              Widget content;
              if (_currentStep == 0 && isDesktop) {
                content = _buildWelcomeDesktop();
              } else if (_currentStep == 0) {
                content = _buildWelcomeMobile();
              } else {
                content = Row(
                  children: [
                    if (isDesktop)
                      Padding(
                        padding: const EdgeInsets.only(right: LinqSpacing.s4),
                        child: SizedBox(width: 280, child: _buildSidebar()),
                      ),
                    Expanded(child: _buildStepContent()),
                  ],
                );
              }

              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: verticalPadding,
                ),
                child: content,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeDesktop() {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [LinqColors.forest500, LinqColors.forest600],
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LinqSpacing.s8,
                      vertical: LinqSpacing.s6,
                    ),
                    child: Row(
                      children: [
                        Expanded(flex: 1, child: _buildWelcomeHero()),
                        const SizedBox(width: LinqSpacing.s8),
                        Expanded(flex: 1, child: _buildBenefitsCard()),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(LinqSpacing.s6),
                child: SizedBox(
                  width: 300,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: LinqColors.stone100,
                      foregroundColor: LinqColors.forest600,
                      padding: const EdgeInsets.symmetric(
                        vertical: LinqSpacing.s4,
                      ),
                    ),
                    onPressed: _nextStep,
                    child: const Text(
                      'Get started',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWelcomeMobile() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [LinqColors.forest500, LinqColors.forest600],
        ),
      ),
      child: SafeArea(
        minimum: const EdgeInsets.only(top: LinqSpacing.s8),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: LinqSpacing.s6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: LinqSpacing.s6),
                _buildWelcomeHero(),
                const SizedBox(height: LinqSpacing.s6),
                _buildBenefitsCard(),
                const SizedBox(height: LinqSpacing.s6),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: LinqColors.stone100,
                      foregroundColor: LinqColors.forest700,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    onPressed: _nextStep,
                    child: const Text(
                      'Get started',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: LinqSpacing.s8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeHero() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Provider setup - 5 minutes',
          style: LinqTextStyles.h1.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: LinqSpacing.s4),
        Text(
          "Let's build a profile customers can trust.",
          style: LinqTextStyles.displayLg.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: LinqSpacing.s4),
        Text(
          'We\'ll walk you through adding your photo, services, availability, and rates. Providers with complete profiles get booked significantly more often.',
          style: LinqTextStyles.body.copyWith(
            color: LinqColors.stone100,
            height: 1.55,
          ),
        ),
      ],
    );
  }

  Widget _buildBenefitsCard() {
    return Container(
      padding: const EdgeInsets.all(LinqSpacing.s5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: LinqRadius.borderLg,
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _benefitItem(
            icon: Icons.search,
            title: 'Get discovered',
            desc:
                'Appear in search results when customers look for your skills.',
          ),
          const SizedBox(height: LinqSpacing.s4),
          _benefitItem(
            icon: Icons.work,
            title: 'Receive real bookings',
            desc:
                'Accept job requests, set your terms, and get paid on completion.',
          ),
          const SizedBox(height: LinqSpacing.s4),
          _benefitItem(
            icon: Icons.star,
            title: 'Build lasting trust',
            desc:
                'A complete profile with photos and reviews earns 3× more bookings.',
          ),
          const SizedBox(height: LinqSpacing.s4),
          _benefitItem(
            icon: Icons.security,
            title: 'Protected payments',
            desc:
                'Escrow holds funds until you complete the job — always get paid.',
          ),
        ],
      ),
    );
  }

  Widget _benefitItem({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: LinqColors.stone100, size: 24),
        const SizedBox(width: LinqSpacing.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: LinqTextStyles.label.copyWith(color: Colors.white),
              ),
              const SizedBox(height: LinqSpacing.s1),
              Text(
                desc,
                style: LinqTextStyles.bodySm.copyWith(
                  color: LinqColors.stone100,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSidebar() {
    return Container(
      decoration: BoxDecoration(
        color: LinqColors.bgSurface,
        border: Border(right: BorderSide(color: LinqColors.borderDefault)),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(LinqSpacing.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Onboarding',
                style: LinqTextStyles.labelSm.copyWith(
                  color: LinqColors.stone600,
                ),
              ),
              const SizedBox(height: LinqSpacing.s3),
              ..._steps.asMap().entries.map((e) {
                final isActive = e.key == _currentStep;
                final isCompleted = e.key < _currentStep;
                return _stepItem(e.value, isActive, isCompleted);
              }).toList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepItem(_SetupStep step, bool isActive, bool isCompleted) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LinqSpacing.s2),
      child: GestureDetector(
        onTap: () {
          if (isCompleted) {
            setState(() => _currentStep = step.number - 1);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: LinqSpacing.s3,
            vertical: LinqSpacing.s2,
          ),
          decoration: BoxDecoration(
            color: isActive
                ? LinqColors.forest100
                : isCompleted
                ? LinqColors.stone100
                : Colors.transparent,
            borderRadius: LinqRadius.borderMd,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isActive
                      ? LinqColors.forest500
                      : isCompleted
                      ? LinqColors.stone600
                      : LinqColors.borderDefault,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: isCompleted
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : Text(
                          step.number.toString(),
                          style: TextStyle(
                            color: isActive
                                ? Colors.white
                                : LinqColors.stone700,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: LinqSpacing.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.title,
                      style: LinqTextStyles.labelSm.copyWith(
                        color: isActive
                            ? LinqColors.forest600
                            : LinqColors.stone700,
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                    Text(
                      step.subtitle,
                      style: LinqTextStyles.bodyXs.copyWith(
                        color: LinqColors.stone600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    // Responsive padding: respect safe area bottom + consistent spacing
    final mq = MediaQuery.of(context);
    final isDesktop = mq.size.width > 1000;
    final horizontal = isDesktop ? LinqSpacing.s8 : LinqSpacing.s6;
    final bottom = mq.viewPadding.bottom + LinqSpacing.s6;

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontal,
          LinqSpacing.s6,
          horizontal,
          bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Step ${_currentStep + 1} of ${_steps.length}',
                  style: LinqTextStyles.label.copyWith(
                    color: LinqColors.stone600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: LinqSpacing.s4),
            _buildFormContent(),
            const SizedBox(height: LinqSpacing.s6),
            Row(
              children: [
                if (_currentStep > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _previousStep,
                      child: const Text('Back'),
                    ),
                  ),
                if (_currentStep > 0) const SizedBox(width: LinqSpacing.s3),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _nextStep,
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _currentStep == _steps.length - 1
                                ? 'Submit profile'
                                : 'Next',
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormContent() {
    switch (_currentStep) {
      case 1:
        return _buildProfilePhotoStep();
      case 2:
        return _buildBusinessIdentityStep();
      case 3:
        return _buildServicesStep();
      case 4:
        return _buildAvailabilityStep();
      case 5:
        return _buildLocationStep();
      case 6:
        return _buildPricingStep();
      case 7:
        return _buildPortfolioStep();
      case 8:
        return _buildReviewStep();
      default:
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: LinqSpacing.s6),
            child: Column(
              children: [
                Icon(Icons.check_circle, size: 64, color: LinqColors.forest500),
                const SizedBox(height: LinqSpacing.s4),
                Text('Step coming soon', style: LinqTextStyles.h2),
              ],
            ),
          ),
        );
    }
  }

  Widget _buildCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(LinqSpacing.s5),
      decoration: BoxDecoration(
        color: LinqColors.bgSurface,
        borderRadius: LinqRadius.borderLg,
        border: Border.all(color: LinqColors.borderDefault),
        boxShadow: LinqShadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: LinqTextStyles.h3),
          const SizedBox(height: LinqSpacing.s2),
          Text(
            subtitle,
            style: LinqTextStyles.body.copyWith(color: LinqColors.stone600),
          ),
          const SizedBox(height: LinqSpacing.s5),
          child,
        ],
      ),
    );
  }

  Widget _buildProfilePhotoStep() {
    return _buildCard(
      title: 'Add a profile photo',
      subtitle:
          'A clear, professional photo helps customers feel confident booking you.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: double.infinity,
              height: 220,
              color: LinqColors.stone100,
              child: _profilePhoto != null && _profilePhotoBytes != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(_profilePhotoBytes!, fit: BoxFit.cover),
                        Positioned(
                          right: LinqSpacing.s4,
                          top: LinqSpacing.s4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: LinqSpacing.s3,
                              vertical: LinqSpacing.s1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Change',
                              style: LinqTextStyles.bodySm.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.camera_alt_outlined,
                            size: 48,
                            color: LinqColors.stone400,
                          ),
                          const SizedBox(height: LinqSpacing.s3),
                          Text(
                            'Choose a photo',
                            style: LinqTextStyles.body.copyWith(
                              color: LinqColors.stone500,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          const SizedBox(height: LinqSpacing.s5),
          Text(
            'JPG, PNG or WebP · Max 5 MB · Square photo works best',
            style: LinqTextStyles.bodySm.copyWith(color: LinqColors.stone600),
          ),
          const SizedBox(height: LinqSpacing.s4),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _pickProfilePhoto,
              child: const Text('Browse files'),
            ),
          ),
          const SizedBox(height: LinqSpacing.s4),
          Text(
            'Providers with a profile photo receive 3× more booking requests than those without. Customers want to know who is coming to their home.',
            style: LinqTextStyles.bodySm.copyWith(
              color: LinqColors.stone600,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessIdentityStep() {
    return _buildCard(
      title: 'Describe yourself',
      subtitle:
          'Your bio appears on your public profile. Write clearly about your skills and experience.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // TextField(
          //   controller: _businessController,
          //   decoration: linqInputDecoration(
          //     label: 'Business identity',
          //     icon: Icons.business_outlined,
          //   ),
          // ),
          // const SizedBox(height: LinqSpacing.s4),
          const SizedBox(height: LinqSpacing.s2),
          const SizedBox(height: LinqSpacing.s4),
          TextField(
            controller: _aboutController,
            maxLines: 6,
            maxLength: 323,
            decoration: linqInputDecoration(
              label: 'Professional bio',
              icon: Icons.person_outline,
              helper: 'Looks good — clear and professional.',
            ),
          ),
          const SizedBox(height: LinqSpacing.s4),
          Text(
            'Tips for a great bio',
            style: LinqTextStyles.labelSm.copyWith(
              color: LinqColors.stone700,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: LinqSpacing.s3),
          _buildBullet('Mention your years of experience'),
          _buildBullet('List the specific services you offer'),
          _buildBullet('Note your service area or willingness to travel'),
          _buildBullet('Include any certifications or accreditations'),
          _buildBullet('Keep it professional — this is your first impression'),
          const SizedBox(height: LinqSpacing.s5),
          Text(
            'Example',
            style: LinqTextStyles.labelSm.copyWith(
              color: LinqColors.stone700,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: LinqSpacing.s3),
          Text(
            'Certified electrician with 8 years of experience across residential and commercial projects in Nigeria. Specialise in rewiring, fault diagnosis, and solar installations. All work is to code and fully insured.',
            style: LinqTextStyles.body.copyWith(
              color: LinqColors.stone600,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServicesStep() {
    final query = _serviceSearchController.text.toLowerCase();
    // Build a list of parent categories to display, filtered by search
    final List<Map<String, dynamic>> parents = [];
    for (final p in _rawCategories) {
      final pname = (p['name'] ?? p['title'] ?? p['label'] ?? p['slug'])?.toString().toLowerCase() ?? '';
      final children = (p['children'] is List) ? (p['children'] as List).whereType<Map<String, dynamic>>().toList() : <Map<String,dynamic>>[];
      if (query.isEmpty) {
        parents.add(p);
        continue;
      }
      // include parent if it matches or any child matches
      var matched = pname.contains(query);
      if (!matched) {
        for (final c in children) {
          final cname = (c['name'] ?? c['title'] ?? c['label'] ?? c['slug'])?.toString().toLowerCase() ?? '';
          if (cname.contains(query)) {
            matched = true;
            break;
          }
        }
      }
      if (matched) parents.add(p);
    }

    return _buildCard(
      title: 'What do you offer?',
      subtitle:
          'Select the services you provide. You can choose up to 5. Customers search by category, so be specific.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _serviceSearchController,
            decoration: linqInputDecoration(
              label: 'Search category',
              icon: Icons.search_outlined,
            ),
          ),
          const SizedBox(height: LinqSpacing.s4),
          Wrap(
            spacing: LinqSpacing.s2,
            runSpacing: LinqSpacing.s2,
            children: _selectedServiceCategories
                .map(
                  (slug) => Chip(
                    label: Text(_serviceLabel(slug)),
                    onDeleted: () =>
                        setState(() => _selectedServiceCategories.remove(slug)),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: LinqSpacing.s4),
          Text(
            '${_selectedServiceCategories.length}/5 selected',
            style: LinqTextStyles.bodySm.copyWith(color: LinqColors.stone600),
          ),
          const SizedBox(height: LinqSpacing.s4),
          if (parents.isEmpty)
            Text(
              'No matching categories yet. Try another search term.',
              style: LinqTextStyles.bodySm.copyWith(color: LinqColors.stone600),
            )
          else
            Column(
              children: parents.map((parent) {
                final parentLabel = (parent['name'] ?? parent['title'] ?? parent['label'] ?? parent['slug'])?.toString() ?? '';
                final parentSlug = (parent['slug'] ?? parent['id'] ?? parent['ulid'])?.toString() ?? parentLabel.toLowerCase().replaceAll(' ', '-');
                final children = (parent['children'] is List) ? (parent['children'] as List).whereType<Map<String, dynamic>>().toList() : <Map<String,dynamic>>[];

                if (children.isEmpty) {
                  final selected = _selectedServiceCategories.contains(parentSlug);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(parentLabel),
                    trailing: selected
                        ? const Icon(
                            Icons.check_circle,
                            color: LinqColors.forest600,
                          )
                        : const Icon(Icons.add_circle_outline),
                    onTap: () {
                      setState(() {
                        if (selected) {
                          _selectedServiceCategories.remove(parentSlug);
                        } else if (_selectedServiceCategories.length < 5) {
                          _selectedServiceCategories.add(parentSlug);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('You can select up to 5 services.'),
                            ),
                          );
                        }
                      });
                    },
                  );
                }

                return ExpansionTile(
                  title: Row(
                    children: [
                      Expanded(child: Text(parentLabel)),
                      if (_selectedServiceCategories.contains(parentSlug))
                        const Icon(Icons.check, color: Colors.green),
                    ],
                  ),
                  children: [
                    ListTile(
                      title: Text('All ${parentLabel}'),
                      leading: const Icon(Icons.folder_open),
                      trailing: _selectedServiceCategories.contains(parentSlug) ? const Icon(Icons.check, color: Colors.green) : null,
                      onTap: () {
                        setState(() {
                          if (_selectedServiceCategories.contains(parentSlug)) {
                            _selectedServiceCategories.remove(parentSlug);
                          } else if (_selectedServiceCategories.length < 5) {
                            _selectedServiceCategories.add(parentSlug);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('You can select up to 5 services.'),
                              ),
                            );
                          }
                        });
                      },
                    ),
                    ...children.map((child) {
                      final childLabel = (child['name'] ?? child['title'] ?? child['label'] ?? child['slug'])?.toString() ?? '';
                      final childSlug = (child['slug'] ?? child['id'] ?? child['ulid'])?.toString() ?? childLabel.toLowerCase().replaceAll(' ', '-');
                      final selected = _selectedServiceCategories.contains(childSlug);
                      return ListTile(
                        contentPadding: EdgeInsets.only(left: 16),
                        title: Text(childLabel),
                        trailing: selected
                            ? const Icon(
                                Icons.check_circle,
                                color: LinqColors.forest600,
                              )
                            : const Icon(Icons.add_circle_outline),
                        onTap: () {
                          setState(() {
                            if (selected) {
                              _selectedServiceCategories.remove(childSlug);
                            } else if (_selectedServiceCategories.length < 5) {
                              _selectedServiceCategories.add(childSlug);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('You can select up to 5 services.'),
                                ),
                              );
                            }
                          });
                        },
                      );
                    }).toList(),
                  ],
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildAvailabilityStep() {
    return _buildCard(
      title: 'When are you available?',
      subtitle:
          'Set the days and hours you typically work. Customers will use this to know when to reach you.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: LinqSpacing.s3,
            runSpacing: LinqSpacing.s2,
            children: [
              TextButton(
                onPressed: _copyMondayHoursToWeekdays,
                child: const Text('Copy Monday hours to all weekdays'),
              ),
              TextButton(
                onPressed: _clearAvailability,
                child: const Text('Clear all'),
              ),
            ],
          ),
          const SizedBox(height: LinqSpacing.s4),
          ..._dayStartTimes.keys
              .map((day) => _buildAvailabilityRow(day))
              .toList(),
          const SizedBox(height: LinqSpacing.s5),
          Text(
            'Your schedule',
            style: LinqTextStyles.labelSm.copyWith(
              color: LinqColors.stone700,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: LinqSpacing.s3),
          if (_dayStartTimes.values.every((time) => time == null) &&
              _dayEndTimes.values.every((time) => time == null))
            Text(
              'No schedule set yet. Add your work hours above.',
              style: LinqTextStyles.bodySm.copyWith(color: LinqColors.stone600),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _dayStartTimes.keys.map((day) {
                final start = _dayStartTimes[day];
                final end = _dayEndTimes[day];
                if (start == null || end == null) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: LinqSpacing.s2),
                  child: Text(
                    '$day ${start.format(context)} - ${end.format(context)}',
                    style: LinqTextStyles.body.copyWith(
                      color: LinqColors.stone700,
                    ),
                  ),
                );
              }).whereType<Widget>().toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildLocationStep() {
    return _buildCard(
      title: 'Where do you work from?',
      subtitle:
          'Your base location helps us match you with nearby jobs. Customers only see an approximate area — not your exact address.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _locationSearchController,
            decoration: linqInputDecoration(
              label: 'Search address',
              icon: Icons.search_outlined,
              helper: 'Search within a Nigerian state',
            ),
          ),
          const SizedBox(height: LinqSpacing.s4),
          Wrap(
            spacing: LinqSpacing.s3,
            runSpacing: LinqSpacing.s2,
            children: [
              SizedBox(
                width: 180,
                child: ElevatedButton(
                  onPressed: _selectLocation,
                  child: const Text('Use this location'),
                ),
              ),
              SizedBox(
                width: 120,
                child: OutlinedButton(
                  onPressed: _clearLocation,
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
          if (_selectedLocationAddress != null) ...[
            const SizedBox(height: LinqSpacing.s5),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(LinqSpacing.s4),
              decoration: BoxDecoration(
                color: LinqColors.stone100,
                borderRadius: LinqRadius.borderMd,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selected location',
                    style: LinqTextStyles.labelSm.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: LinqSpacing.s2),
                  Text(
                    _selectedLocationAddress!,
                    style: LinqTextStyles.body.copyWith(
                      color: LinqColors.stone700,
                    ),
                  ),
                  if (_selectedLocationLatitude != null &&
                      _selectedLocationLongitude != null)
                    Padding(
                      padding: const EdgeInsets.only(top: LinqSpacing.s2),
                      child: Text(
                        'Coordinates: ${_selectedLocationLatitude!.toStringAsFixed(4)}, ${_selectedLocationLongitude!.toStringAsFixed(4)}',
                        style: LinqTextStyles.bodySm.copyWith(
                          color: LinqColors.stone600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: LinqSpacing.s5),
          Text(
            'Your privacy is protected',
            style: LinqTextStyles.labelSm.copyWith(
              color: LinqColors.stone700,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: LinqSpacing.s2),
          Text(
            'Customers only see a 500-metre radius around your location — never your exact address. Precise coordinates are used only for job proximity matching.',
            style: LinqTextStyles.bodySm.copyWith(
              color: LinqColors.stone600,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPricingStep() {
    return _buildCard(
      title: 'Set your hourly rate',
      subtitle:
          'This appears on your profile as a guide. Actual pricing is agreed on each job. You can change it at any time.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _hourlyRateController,
            keyboardType: TextInputType.number,
            decoration: linqInputDecoration(
              label: 'Your rate (per hour)',
              prefix: Text(
                '₦ ',
                style: LinqTextStyles.body.copyWith(
                  color: LinqColors.stone700,
                  fontWeight: FontWeight.w700,
                ),
              ),
              suffix: Text(
                '/ hr',
                style: LinqTextStyles.bodySm.copyWith(
                  color: LinqColors.stone600,
                ),
              ),
            ),
          ),
          const SizedBox(height: LinqSpacing.s5),
          Text(
            'Market rates',
            style: LinqTextStyles.labelSm.copyWith(
              color: LinqColors.stone700,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: LinqSpacing.s3),
          _buildMarketRateRow('Electrician', '₦ 3,000 – 8,000'),
          _buildMarketRateRow('Plumber', '₦ 3,500 – 7,000'),
          _buildMarketRateRow('AC technician', '₦ 5,000 – 12,000'),
          _buildMarketRateRow('Carpenter', '₦ 4,000 – 10,000'),
          _buildMarketRateRow('House cleaner', '₦ 2,500 – 5,000'),
          _buildMarketRateRow('Painter', '₦ 3,000 – 7,000'),
        ],
      ),
    );
  }

  Widget _buildPortfolioStep() {
    return _buildCard(
      title: 'Showcase your work',
      subtitle:
          'Upload photos of completed jobs. Customers browse portfolios before booking. Up to 8 photos.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _pickPortfolioPhotos,
              child: const Text('Upload work photos'),
            ),
          ),
          const SizedBox(height: LinqSpacing.s3),
          Text(
            'Drag and drop, or click to browse · JPG, PNG, WebP · Max 10 MB each',
            style: LinqTextStyles.bodySm.copyWith(color: LinqColors.stone600),
          ),
          const SizedBox(height: LinqSpacing.s4),
          Text(
            '${8 - _portfolioPhotos.length} slots remaining',
            style: LinqTextStyles.labelSm.copyWith(color: LinqColors.stone600),
          ),
          const SizedBox(height: LinqSpacing.s4),
          if (_portfolioPhotos.isEmpty)
            Text(
              'No photos yet. Upload finished work to showcase your skills.',
              style: LinqTextStyles.body.copyWith(color: LinqColors.stone600),
            )
          else
            Wrap(
              spacing: LinqSpacing.s3,
              runSpacing: LinqSpacing.s3,
              children: _portfolioPhotos
                  .asMap()
                  .entries
                  .map(
                    (entry) => Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.memory(
                            _portfolioPhotoBytes[entry.key],
                            width: 96,
                            height: 96,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _portfolioPhotos.removeAt(entry.key);
                              _portfolioPhotoBytes.removeAt(entry.key);
                            }),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black54,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: LinqSpacing.s5),
          Text(
            'This step is optional — you can add photos later.',
            style: LinqTextStyles.bodySm.copyWith(color: LinqColors.stone600),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewStep() {
    final sectionCount = 7;
    final completeSections = _reviewCompletionCount();
    final progress = ((completeSections / sectionCount) * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCard(
          title: 'Review your profile',
          subtitle:
              'Check everything looks right before submitting. Required sections must be complete.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Profile completeness',
                style: LinqTextStyles.labelSm.copyWith(
                  color: LinqColors.stone600,
                ),
              ),
              const SizedBox(height: LinqSpacing.s3),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: completeSections / sectionCount,
                      minHeight: 10,
                      color: LinqColors.forest500,
                      backgroundColor: LinqColors.stone100,
                    ),
                  ),
                  const SizedBox(width: LinqSpacing.s3),
                  Text(
                    '$progress%',
                    style: LinqTextStyles.label.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: LinqSpacing.s3),
              Text(
                '$completeSections of $sectionCount sections complete.',
                style: LinqTextStyles.bodySm.copyWith(
                  color: LinqColors.stone600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: LinqSpacing.s5),
        _buildReviewItem(
          label: 'Profile photo',
          value: _profilePhoto != null
              ? 'Photo added'
              : 'No photo added (optional)',
          stepIndex: 1,
        ),
        _buildReviewItem(
          label: 'About you',
          value: _aboutController.text.isNotEmpty
              ? _aboutController.text
              : 'No description added',
          stepIndex: 2,
        ),
        _buildReviewItem(
          label: 'Services',
          value: _selectedServiceCategories.isNotEmpty
              ? _selectedServiceCategories.map(_serviceLabel).join(', ')
              : 'No service selected',
          stepIndex: 3,
        ),
        _buildReviewItem(
          label: 'Availability',
          value: _dayStartTimes.keys.any(
                  (day) => _dayStartTimes[day] != null && _dayEndTimes[day] != null)
              ? _dayStartTimes.keys
                    .where((day) =>
                        _dayStartTimes[day] != null && _dayEndTimes[day] != null)
                    .map((day) =>
                        '$day ${_dayStartTimes[day]!.format(context)} - ${_dayEndTimes[day]!.format(context)}')
                    .join('\n')
              : 'No availability set',
          stepIndex: 4,
        ),
        _buildReviewItem(
          label: 'Location',
          value: _selectedLocationAddress != null
              ? _selectedLocationAddress!
              : 'No location set (optional)',
          stepIndex: 5,
        ),
        _buildReviewItem(
          label: 'Pricing',
          value: _hourlyRateController.text.isNotEmpty
              ? '₦${_hourlyRateController.text.trim()} / hr'
              : 'No rate set (optional)',
          stepIndex: 6,
        ),
        _buildReviewItem(
          label: 'Portfolio',
          value: _portfolioPhotos.isNotEmpty
              ? '${_portfolioPhotos.length} photo(s) added'
              : 'No photos added (optional)',
          stepIndex: 7,
        ),
        const SizedBox(height: LinqSpacing.s5),
        _buildCard(
          title: 'Ready to go live',
          subtitle:
              'Your profile goes live immediately. Complete KYC verification afterwards to unlock job matching.',
          child: const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildReviewItem({
    required String label,
    required String value,
    required int stepIndex,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: LinqSpacing.s4),
      padding: const EdgeInsets.all(LinqSpacing.s4),
      decoration: BoxDecoration(
        color: LinqColors.bgSurface,
        borderRadius: LinqRadius.borderMd,
        border: Border.all(color: LinqColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: LinqTextStyles.label.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _currentStep = stepIndex),
                child: const Text('Edit'),
              ),
            ],
          ),
          const SizedBox(height: LinqSpacing.s2),
          Text(
            value,
            style: LinqTextStyles.body.copyWith(
              color: LinqColors.stone700,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  int _reviewCompletionCount() {
    var count = 0;
    if (_profilePhoto != null) count++;
    if (_aboutController.text.trim().isNotEmpty) count++;
    if (_selectedServiceCategories.isNotEmpty) count++;
    if (_dayStartTimes.keys.any(
      (day) => _dayStartTimes[day] != null && _dayEndTimes[day] != null,
    ))
      count++;
    if (_selectedLocationAddress != null &&
        _selectedLocationAddress!.isNotEmpty)
      count++;
    if (_hourlyRateController.text.trim().isNotEmpty) count++;
    if (_portfolioPhotos.isNotEmpty) count++;
    return count;
  }

  Widget _buildBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LinqSpacing.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 16)),
          Expanded(
            child: Text(
              text,
              style: LinqTextStyles.bodySm.copyWith(color: LinqColors.stone600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailabilityRow(String day) {
    final start = _dayStartTimes[day];
    final end = _dayEndTimes[day];
    final hasTimes = start != null && end != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: LinqSpacing.s3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              day,
              style: LinqTextStyles.body.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: LinqSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickTime(day, isStart: true),
                        child: Text(start?.format(context) ?? 'Start'),
                      ),
                    ),
                    const SizedBox(width: LinqSpacing.s2),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickTime(day, isStart: false),
                        child: Text(end?.format(context) ?? 'End'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: LinqSpacing.s2),
                Text(
                  hasTimes
                      ? '${start!.format(context)} - ${end!.format(context)}'
                      : 'Select start and end times',
                  style: LinqTextStyles.bodySm.copyWith(
                    color: LinqColors.stone600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTime(String day, {required bool isStart}) async {
    final initialTime = isStart
        ? _dayStartTimes[day] ?? const TimeOfDay(hour: 8, minute: 0)
        : _dayEndTimes[day] ?? const TimeOfDay(hour: 17, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null) return;

    setState(() {
      if (isStart) {
        _dayStartTimes[day] = picked;
        if (_dayEndTimes[day] == null ||
            picked.hour > _dayEndTimes[day]!.hour ||
            (picked.hour == _dayEndTimes[day]!.hour &&
                picked.minute >= _dayEndTimes[day]!.minute)) {
          _dayEndTimes[day] = TimeOfDay(hour: picked.hour + 1, minute: picked.minute);
        }
      } else {
        _dayEndTimes[day] = picked;
        if (_dayStartTimes[day] == null ||
            picked.hour < _dayStartTimes[day]!.hour ||
            (picked.hour == _dayStartTimes[day]!.hour &&
                picked.minute <= _dayStartTimes[day]!.minute)) {
          _dayStartTimes[day] = TimeOfDay(hour: picked.hour - 1, minute: picked.minute);
        }
      }
    });
  }

  void _copyMondayHoursToWeekdays() {
    final mondayStart = _dayStartTimes['Mon'];
    final mondayEnd = _dayEndTimes['Mon'];
    if (mondayStart == null || mondayEnd == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select Monday hours before copying.')),
      );
      return;
    }
    setState(() {
      for (final day in ['Tue', 'Wed', 'Thu', 'Fri']) {
        _dayStartTimes[day] = mondayStart;
        _dayEndTimes[day] = mondayEnd;
      }
    });
  }

  void _clearAvailability() {
    setState(() {
      for (final day in _dayStartTimes.keys) {
        _dayStartTimes[day] = null;
        _dayEndTimes[day] = null;
      }
    });
  }

  void _selectLocation() {
    final query = _locationSearchController.text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a location to search.')),
      );
      return;
    }
    setState(() {
      _selectedLocationAddress = query;
      _selectedLocationLatitude = 6.5244;
      _selectedLocationLongitude = 3.3792;
      _locationController.text = query;
    });
  }

  void _clearLocation() {
    setState(() {
      _locationSearchController.clear();
      _selectedLocationAddress = null;
      _selectedLocationLatitude = null;
      _selectedLocationLongitude = null;
      _locationController.clear();
    });
  }

  Future<void> _pickPortfolioPhotos() async {
    final picked = await _imagePicker.pickMultiImage(
      maxWidth: 1200,
      imageQuality: 80,
    );
    if (picked == null || picked.isEmpty) return;

    final maxCount = 8 - _portfolioPhotos.length;
    final toAdd = picked.take(maxCount);
    final selectedImages = <XFile>[];
    final selectedBytes = <Uint8List>[];

    for (final file in toAdd) {
      final bytes = await file.readAsBytes();
      selectedImages.add(file);
      selectedBytes.add(bytes);
    }

    setState(() {
      _portfolioPhotos.addAll(selectedImages);
      _portfolioPhotoBytes.addAll(selectedBytes);
    });
  }

  Widget _buildMarketRateRow(String label, String rate) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LinqSpacing.s2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: LinqTextStyles.body.copyWith(
              color: LinqColors.stone700,
            ),
          ),
          Text(
            rate,
            style: LinqTextStyles.bodySm.copyWith(
              color: LinqColors.stone600,
            ),
          ),
        ],
      ),
    );
  }

  String _serviceLabel(String slug) {
    return _availableCategories
            .firstWhere(
              (item) => item['slug'] == slug,
              orElse: () => {'name': slug},
            )['name']!
            .toString() ??
        slug;
  }
}

class _SetupStep {
  final int number;
  final String title;
  final String subtitle;

  _SetupStep({
    required this.number,
    required this.title,
    required this.subtitle,
  });
}

// class _BusinessForm extends StatefulWidget {
//   final TextEditingController businessController;
//   final TextEditingController yearsController;
//   final TextEditingController aboutController;
//   final List<Map<String, String>> availableCategories;
//   final String? selectedCategory;
//   final Function(String?) onCategoryChanged;

//   const _BusinessForm({
//     required this.businessController,
//     required this.yearsController,
//     required this.aboutController,
//     required this.availableCategories,
//     required this.selectedCategory,
//     required this.onCategoryChanged,
//   });

//   @override
//   State<_BusinessForm> createState() => _BusinessFormState();
// }

// class _BusinessFormState extends State<_BusinessForm> {
//   @override
//   Widget build(BuildContext context) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text('Business identity', style: LinqTextStyles.h3),
//         const SizedBox(height: LinqSpacing.s2),
//         Text(
//           'Tell us about your business so customers can learn more about your services.',
//           style: LinqTextStyles.body.copyWith(color: LinqColors.stone600),
//         ),
//         const SizedBox(height: LinqSpacing.s5),
//         TextField(
//           controller: widget.businessController,
//           decoration: linqInputDecoration(
//             label: 'Business identity',
//             icon: Icons.business_outlined,
//           ),
//         ),

//         const SizedBox(height: LinqSpacing.s5),
//         SizedBox(
//           width: double.infinity,
//           child: Row(
//             children: [
//               Expanded(
//                 child: DropdownButtonFormField<String>(
//                   decoration: linqInputDecoration(
//                     label: 'Primary category',
//                     icon: Icons.category_outlined,
//                   ),
//                   items: widget.availableCategories
//                       .map(
//                         (category) => DropdownMenuItem(
//                           value: category['slug'],
//                           child: Text(category['name'] ?? ''),
//                         ),
//                       )
//                       .toList(),
//                   value: widget.selectedCategory,
//                   onChanged: widget.onCategoryChanged,
//                   isExpanded: true,
//                 ),
//               ),
//               const SizedBox(width: LinqSpacing.s4),
//               Expanded(
//                 child: TextField(
//                   controller: widget.yearsController,
//                   keyboardType: TextInputType.number,
//                   decoration: linqInputDecoration(
//                     label: 'Years of experience',
//                     icon: Icons.work_history_outlined,
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         ),
//         const SizedBox(height: LinqSpacing.s5),
//         TextField(
//           controller: widget.aboutController,
//           maxLines: 4,
//           decoration: linqInputDecoration(
//             label: 'About your services',
//             icon: Icons.description_outlined,
//           ),
//         ),
//       ],
//     );
//   }
// }
