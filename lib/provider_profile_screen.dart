import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'linq_theme.dart';
import 'auth_service.dart';

// Provider Profile screen (self-contained scaffold)
// Notes: integrate `image_picker`, `flutter_riverpod` or `flutter_map` as needed.

class ProviderProfileScreen extends StatefulWidget {
  const ProviderProfileScreen({super.key});

  @override
  State<ProviderProfileScreen> createState() => _ProviderProfileScreenState();
}

class _ProviderProfileScreenState extends State<ProviderProfileScreen> {
  final _rateController = TextEditingController();
  final _bioController = TextEditingController();
  final _serviceSearchController = TextEditingController();

  // Mock model for local UI state. Replace with Riverpod/Provider in production.
  bool _isSaving = false;
  bool _isEditing = false;
  String? _avatarUrl;
  final ImagePicker _picker = ImagePicker();

  final List<String> _allServices = [
    'Electrical',
    'Plumbing',
    'Carpentry',
    'Cleaning',
    'HVAC',
    'Painting',
    'Landscaping',
    'Locksmith',
    'Appliance Repair',
  ];

  final Map<String, List<String>> _serviceCategories = {
    'Home Services': ['Cleaning', 'Painting', 'Landscaping'],
    'Trade': ['Electrical', 'Plumbing', 'Carpentry'],
    'Specialist': ['HVAC', 'Locksmith', 'Appliance Repair'],
  };

  final List<String> _selectedServices = [];
  String? _firstName;
  String? _lastName;
  String? _profileName;
  static const _profileDraftKey = 'provider_profile_draft_v1';

  String get _displayName {
    final profile = _profileName?.trim();
    if (profile?.isNotEmpty ?? false) return profile!;

    final first = _firstName?.trim();
    final last = _lastName?.trim();
    if ((first?.isNotEmpty ?? false) && (last?.isNotEmpty ?? false)) {
      return '$first $last';
    }
    if (first?.isNotEmpty ?? false) return first!;
    if (last?.isNotEmpty ?? false) return last!;
    return '';
  }

  // Availability: map day index (Mon=1) to list of ranges
  final Map<int, List<TimeRange>> _availability = {
    for (var i = 1; i <= 7; i++) i: <TimeRange>[]
  };

  String _locationAddress = '';
  double? _latitude, _longitude;

  final List<String> _photos = [];

  bool get _isDirty {
    return _avatarUrl != null ||
        _bioController.text.isNotEmpty ||
        _rateController.text.isNotEmpty ||
        _selectedServices.isNotEmpty ||
        _availability.values.any((v) => v.isNotEmpty) ||
        _locationAddress.isNotEmpty ||
        _photos.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _bioController.addListener(() => setState(() {}));
    _rateController.addListener(() => setState(() {}));
    _serviceSearchController.addListener(() => setState(() {}));
    // load saved profile from backend / cache, then offer draft restore if available
    _loadProfile().then((_) => _offerDraftRestore());
  }

  @override
  void dispose() {
    _bioController.dispose();
    _rateController.dispose();
    _serviceSearchController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    if (!_isEditing) return;

    // Let user choose camera or gallery
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(ctx, null),
            ),
          ],
        ),
      ),
    );

    if (choice == null) return;

    try {
      final source = choice == 'camera' ? ImageSource.camera : ImageSource.gallery;
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 80,
      );
      if (picked != null) {
        setState(() {
          _avatarUrl = picked.path; // local file path
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Failed to pick image.'),
      ));
    }
  }

  void _toggleService(String service) {
    setState(() {
      if (_selectedServices.contains(service)) {
        _selectedServices.remove(service);
      } else {
        if (_selectedServices.length < 5) {
          _selectedServices.add(service);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Maximum of 5 services allowed'),
          ));
        }
      }
    });
  }

  Future<void> _openTimeRangeEditor(int dayIndex) async {
    // Show bottom sheet to add a time range for the selected day.
    final picked = await showModalBottomSheet<TimeRange>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        TimeOfDay start = const TimeOfDay(hour: 9, minute: 0);
        TimeOfDay end = const TimeOfDay(hour: 17, minute: 0);

        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: StatefulBuilder(builder: (c, setLocal) {
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Add availability', style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final t = await showTimePicker(
                            context: c,
                            initialTime: start,
                          );
                          if (t != null) setLocal(() => start = t);
                        },
                        child: Text('Start: ${start.format(c)}'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final t = await showTimePicker(
                            context: c,
                            initialTime: end,
                          );
                          if (t != null) setLocal(() => end = t);
                        },
                        child: Text('End: ${end.format(c)}'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            Navigator.of(c).pop(TimeRange(start, end));
                          },
                          child: const Text('Add range'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          }),
        );
      },
    );

    if (picked != null) {
      setState(() {
        _availability[dayIndex]!.add(picked);
      });
    }
  }

  Future<void> _useCurrentLocation() async {
    // TODO: integrate geolocator / permissions flow. Mocked here.
    setState(() {
      _locationAddress = 'Ikeja, Lagos, Nigeria';
      _latitude = 6.5840;
      _longitude = 3.3792;
    });
  }

  Future<void> _pickPhoto() async {
    // Let user choose camera or gallery for adding photos
    if (_photos.length >= 8) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Maximum of 8 photos allowed'),
      ));
      return;
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(ctx, null),
            ),
          ],
        ),
      ),
    );

    if (choice == null) return;

    try {
      if (choice == 'camera') {
        final picked = await _picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1200,
          maxHeight: 1200,
          imageQuality: 80,
        );
        if (picked != null) setState(() => _photos.add(picked.path));
      } else {
        final picked = await _picker.pickMultiImage(
          maxWidth: 1200,
          maxHeight: 1200,
          imageQuality: 80,
        );
        if (picked != null && picked.isNotEmpty) {
          setState(() => _photos.addAll(picked.map((p) => p.path)));
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Failed to pick photos.'),
      ));
    }
  }

  Future<void> _saveProfile() async {
    setState(() {
      _isSaving = true;
    });

    // Validate
    if (_selectedServices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Select at least one service'),
      ));
      setState(() => _isSaving = false);
      return;
    }

    // Build payload
    final payload = <String, dynamic>{
      'bio': _bioController.text.trim(),
      'hourly_rate': _rateController.text.trim(),
      'services': _selectedServices,
      'location': _locationAddress.trim(),
      // availability: serialize as list of {day: int, ranges: ['09:00-17:00']}
      'availability': _availability.entries
          .where((e) => e.value.isNotEmpty)
          .map((e) => {
                'day': e.key,
                'ranges': e.value.map((r) => r.format()).toList()
              })
          .toList(),
      'photos': _photos,
      'avatar': _avatarUrl,
    };

    // Send to backend via AuthService helper
    final result = await AuthService.updateProfile(payload);

    if (result['success'] == true) {
      await _clearDraft();
      setState(() {
        _isSaving = false;
        _isEditing = false;
      });
      // Reload profile to get new server URLs for uploaded images
      await _loadProfile();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Profile saved'),
      ));
    } else {
      setState(() => _isSaving = false);
      final msg = result['message']?.toString() ?? 'Failed to save profile';
      if (result['auth_required'] == true ||
          msg.toLowerCase().contains('log in') ||
          msg.toLowerCase().contains('login')) {
        await _saveDraft();
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Authentication required'),
            content: const Text(
                'Your changes have been saved as a draft. Please login and return to continue.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.pushNamed(context, '/login');
                },
                child: const Text('Login'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  Future<void> _loadProfile() async {
    try {
      final res = await AuthService.getProfile(forceRefresh: false);
      if (res['success'] == true) {
        final raw = res['data'];
        Map<String, dynamic>? source;
        if (raw is Map<String, dynamic>) {
          // common locations: raw, raw['data'], raw['user'], raw['provider']
          source = (raw['data'] is Map<String, dynamic>)
              ? raw['data'] as Map<String, dynamic>
              : raw;
          if (source != null && source['user'] is Map<String, dynamic>) {
            source = source['user'] as Map<String, dynamic>;
          }
          if (source != null && source['provider'] is Map<String, dynamic>) {
            source = source['provider'] as Map<String, dynamic>;
          }
        }

        if (source != null) {
          final s = source; // local non-null alias for analyzer
          // Compute important derived values before mutating state so we can log them
          final avatar = (s['avatar'] ?? s['photo_url'] ?? s['profile_photo'] ?? s['profile_photo_url']);
          final computedName = _extractProfileName(s);
          final svc = s['services'];
          final loc = (s['location'] ?? s['address'] ?? '');
          final photos = (s['photos'] is List) ? (s['photos'] as List).map((p) => p.toString()).toList() : <String>[];

          setState(() {
            _bioController.text = (s['bio'] ?? s['description'] ?? '')
                .toString();
            _rateController.text = (s['hourly_rate'] ?? s['rate'] ?? '')
                .toString();
            if (svc is List) {
              _selectedServices.clear();
              _selectedServices.addAll(svc.map((e) => e.toString()));
            }
            _locationAddress = loc?.toString() ?? '';
            _avatarUrl = avatar?.toString();
            _profileName = computedName;
            _photos
              ..clear()
              ..addAll(photos);

            // availability: try to parse if available
            final avail = s['availability'];
            if (avail is List) {
              for (final item in avail) {
                try {
                  if (item is Map<String, dynamic>) {
                    final day = (item['day'] ?? item['weekday']) as int?;
                    final ranges = item['ranges'] is List
                        ? (item['ranges'] as List).map((r) => r.toString()).toList()
                        : <String>[];
                    if (day != null && ranges.isNotEmpty) {
                      _availability[day] = ranges
                          .map((s) {
                            // Expect format '9:00 AM - 5:00 PM' or '09:00 - 17:00'
                            final parts = s.split('-').map((t) => t.trim()).toList();
                            if (parts.length == 2) {
                              // try parse times using simple split
                              final parse = (String t) {
                                final comp = t.split(RegExp(':| ')).where((x) => x.isNotEmpty).toList();
                                final hour = int.tryParse(comp[0]) ?? 9;
                                final minute = int.tryParse(comp.length > 1 ? comp[1] : '0') ?? 0;
                                return TimeOfDay(hour: hour, minute: minute);
                              };
                              return TimeRange(parse(parts[0]), parse(parts[1]));
                            }
                            return null;
                          })
                          .whereType<TimeRange>()
                          .toList();
                    }
                  }
                } catch (_) {}
              }
            }
          });
        }
      }
    } catch (e) {
      print('[ProviderProfile] load profile error: $e');
    }
  }

  Future<void> _offerDraftRestore() async {
    final prefs = await SharedPreferences.getInstance();
    final rawDraft = prefs.getString(_profileDraftKey);
    if (rawDraft == null || rawDraft.isEmpty || !mounted) return;

    final draft = jsonDecode(rawDraft) as Map<String, dynamic>?;
    if (draft == null) return;

    final restore = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved draft found'),
        content: const Text(
            'We found an unsaved profile draft from your previous session. Restore your draft?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (restore == true) {
      setState(() {
        _bioController.text = draft['bio']?.toString() ?? '';
        _rateController.text = draft['hourly_rate']?.toString() ?? '';
        _selectedServices
          ..clear()
          ..addAll((draft['services'] is List)
              ? (draft['services'] as List).map((e) => e.toString())
              : <String>[]);
        _locationAddress = draft['location']?.toString() ?? '';
        _avatarUrl = draft['avatar_url']?.toString();
        _profileName = _extractProfileName(draft);
        _photos
          ..clear()
          ..addAll((draft['photos'] is List)
              ? (draft['photos'] as List).map((e) => e.toString())
              : <String>[]);
        final avail = draft['availability'];
        if (avail is List) {
          for (final item in avail) {
            if (item is Map<String, dynamic>) {
              final day = (item['day'] as int?) ?? int.tryParse(item['day']?.toString() ?? '0');
              final ranges = (item['ranges'] is List)
                  ? (item['ranges'] as List).map((r) => r.toString()).toList()
                  : <String>[];
              if (day != null && ranges.isNotEmpty) {
                _availability[day] = ranges
                    .map((s) {
                      final parts = s.split('-').map((t) => t.trim()).toList();
                      if (parts.length == 2) {
                        final parse = (String t) {
                          final comp = t
                              .split(RegExp(':| '))
                              .where((x) => x.isNotEmpty)
                              .toList();
                          final hour = int.tryParse(comp[0]) ?? 9;
                          final minute = int.tryParse(comp.length > 1 ? comp[1] : '0') ?? 0;
                          return TimeOfDay(hour: hour, minute: minute);
                        };
                        return TimeRange(parse(parts[0]), parse(parts[1]));
                      }
                      return null;
                    })
                    .whereType<TimeRange>()
                    .toList();
              }
            }
          }
        }
      });
    }
  }

  Future<void> _saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final draft = {
      'bio': _bioController.text,
      'hourly_rate': _rateController.text,
      'services': _selectedServices,
      'location': _locationAddress,
      'avatar_url': _avatarUrl,
      'photos': _photos,
      'availability': _availability.entries
          .where((e) => e.value.isNotEmpty)
          .map((e) => {
                'day': e.key,
                'ranges': e.value.map((r) => r.format()).toList(),
              })
          .toList(),
    };
    await prefs.setString(_profileDraftKey, jsonEncode(draft));
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profileDraftKey);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
      backgroundColor: theme.colorScheme.background,
      appBar: AppBar(
        backgroundColor: LinqColors.forest500,
        foregroundColor: LinqColors.textOnBrand,
        titleTextStyle: LinqTextStyles.h4.copyWith(color: Colors.white),
        title: const Text('Provider Profile'),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_isEditing ? Icons.check : Icons.edit),
            onPressed: _isEditing ? _saveProfile : () {
              setState(() => _isEditing = true);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: const SizedBox(height: 16)),
                SliverToBoxAdapter(child: _buildAvatarHeader()),
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate(
                      [
                        // _buildHeaderCard(),
                        // const SizedBox(height: 12),
                        _buildAboutCard(),
                        const SizedBox(height: 12),
                        _buildRateCard(),
                        const SizedBox(height: 12),
                        _buildServicesCard(),
                        const SizedBox(height: 12),
                        _buildAvailabilityCard(),
                        const SizedBox(height: 12),
                        _buildLocationCard(),
                        const SizedBox(height: 12),
                        _buildPhotosCard(),
                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Sticky save bar (floating at bottom)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: AnimatedOpacity(
                opacity: _isEditing && _isDirty ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  color: theme.colorScheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _isDirty ? 'You have unsaved changes' : 'Up to date',
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isSaving ? 'Saving…' : 'Save changes to update your profile',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: _isSaving ? null : _saveProfile,
                          child: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Save Changes'),
                        ),
                      ],
                    ),
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

  Future<bool> _onWillPop() async {
    if (_isEditing && _isDirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text('You have unsaved changes. Discard them and leave?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );

      if (discard == true) {
        // reload from last-saved profile to revert unsaved fields
        await _loadProfile();
        setState(() => _isEditing = false);
        return true; // allow pop
      }

      return false; // keep on page
    }

    return true;
  }

  Widget _cardShell({required Widget child}) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(20),
      color: Theme.of(context).colorScheme.surface,
      child: ClipRRect(borderRadius: BorderRadius.circular(20), child: child),
    );
  }

  // Widget _buildHeaderCard() {
  //   return _cardShell(
  //     child: Padding(
  //       padding: const EdgeInsets.all(16),
  //       child: Column(
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         children: [
  //           Text('Provider Profile', style: Theme.of(context).textTheme.headlineSmall),
  //           const SizedBox(height: 6),
  //           Text(
  //             'Update your bio, services, and availability. Changes are visible to customers immediately.',
  //             style: Theme.of(context).textTheme.bodyMedium,
  //           ),
  //         ],
  //       ),
  //     ),
  //   );
  // }

  

  Widget _buildAboutCard() {
    final bioText = _bioController.text.trim();
    final isEmpty = bioText.isEmpty;
    return _cardShell(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('About you', style: Theme.of(context).textTheme.titleMedium),
              Text('${bioText.length}/500', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _isEditing
                ? TextField(
                    controller: _bioController,
                    maxLines: null,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      hintText: 'Experienced master electrician with 10 years in Lagos.',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  )
                : Text(
                    isEmpty
                        ? 'Share a short professional summary customers can read before booking you. Mention your experience, specialties, and service area.'
                        : bioText,
                    style: isEmpty
                        ? Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.grey)
                        : Theme.of(context).textTheme.bodyMedium,
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _buildRateCard() {
    final rateText = _rateController.text.trim();
    final isEmpty = rateText.isEmpty;
    return _cardShell(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              Text('Hourly rate', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Optional', style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _isEditing
              ? TextField(
                  controller: _rateController,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    prefixText: '₦ ',
                    hintText: 'e.g. 3,500',
                    helperText: 'An indicative rate shown on your listing card.',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                )
              : Text(
                  isEmpty
                      ? 'Set an optional hourly rate customers will see on your listing.'
                      : '₦ $rateText per hour',
                  style: isEmpty
                      ? Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.grey)
                      : Theme.of(context).textTheme.bodyMedium,
                ),
        ]),
      ),
    );
  }

  Widget _buildServicesCard() {
    final query = _serviceSearchController.text.toLowerCase();
    final filtered = _allServices.where((s) => s.toLowerCase().contains(query)).toList();
    final hasServices = _selectedServices.isNotEmpty;
    return _cardShell(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Services', style: Theme.of(context).textTheme.titleMedium),
              Text('${_selectedServices.length}/5 selected', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 8),
          if (_isEditing) ...[
            TextField(
              controller: _serviceSearchController,
              decoration: const InputDecoration(
                hintText: 'Search services',
                prefixIcon: Icon(Icons.search),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: filtered.map((s) {
                final selected = _selectedServices.contains(s);
                return ChoiceChip(
                  label: Text(s),
                  selected: selected,
                  onSelected: (_) => _toggleService(s),
                  elevation: selected ? 4 : 0,
                  selectedColor: Theme.of(context).colorScheme.primaryContainer,
                );
              }).toList(),
            ),
          ] else ...[
            Text(
              hasServices
                  ? _selectedServices.join(', ')
                  : 'Choose up to 5 services you specialize in so customers can find you faster.',
              style: hasServices
                  ? Theme.of(context).textTheme.bodyMedium
                  : Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _buildAvailabilityCard() {
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final hasAvailability = _availability.values.any((list) => list.isNotEmpty);
    return _cardShell(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Weekly availability', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_isEditing) ...[
            Wrap(
              spacing: 8,
              children: List.generate(7, (i) {
                final idx = i + 1;
                final enabled = _availability[idx]!.isNotEmpty;
                return ActionChip(
                  label: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(days[i]),
                      if (enabled)
                        Text('${_availability[idx]!.length} range(s)', style: Theme.of(context).textTheme.bodySmall)
                    ],
                  ),
                  onPressed: () => _openTimeRangeEditor(idx),
                  backgroundColor: enabled ? Theme.of(context).colorScheme.primaryContainer : null,
                );
              }),
            ),
            const SizedBox(height: 12),
            Column(
              children: _availability.entries.expand((e) {
                final dayIndex = e.key;
                final ranges = e.value;
                if (ranges.isEmpty) return <Widget>[];
                return [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_weekdayLabel(dayIndex), style: Theme.of(context).textTheme.bodyMedium),
                      TextButton(
                        onPressed: () => setState(() => _availability[dayIndex] = []),
                        child: const Text('Clear'),
                      )
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    children: ranges.map((r) => Chip(label: Text(r.format()))).toList(),
                  ),
                  const SizedBox(height: 8),
                ];
              }).toList(),
            )
          ] else ...[
            Text(
              hasAvailability
                  ? _availability.entries
                      .where((e) => e.value.isNotEmpty)
                      .map((e) => '${_weekdayLabel(e.key)}: ${e.value.map((r) => r.format()).join(', ')}')
                      .join('\n')
                  : 'Keep your booking window visible by adding availability for each day.',
              style: hasAvailability
                  ? Theme.of(context).textTheme.bodyMedium
                  : Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _buildLocationCard() {
    final locationText = _locationAddress.trim();
    final isEmpty = locationText.isEmpty;
    return _cardShell(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Workshop location', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_isEditing)
            TextFormField(
              initialValue: locationText,
              onChanged: (v) => setState(() => _locationAddress = v),
              decoration: const InputDecoration(border: InputBorder.none, hintText: 'Enter address or use current location'),
            )
          else
            Text(
              isEmpty
                  ? 'Enter your location so customers know where you can work from or meet them nearby.'
                  : locationText,
              style: isEmpty
                  ? Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey)
                  : Theme.of(context).textTheme.bodyMedium,
            ),
          const SizedBox(height: 12),
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: Text('Map preview (integrate Maps SDK)')),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: TextButton.icon(
                  onPressed: _isEditing ? _useCurrentLocation : null,
                  icon: const Icon(Icons.my_location),
                  label: const Text('Use current location'),
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Customers only see a 500m radius',
                  style: Theme.of(context).textTheme.bodySmall,
                  softWrap: true,
                ),
              ),
            ],
          )
        ]),
      ),
    );
  }

  Widget _buildPhotosCard() {
    final hasPhotos = _photos.isNotEmpty;
    return _cardShell(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Work photos', style: Theme.of(context).textTheme.titleMedium),
              Text('${_photos.length}/8', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: min(8, _photos.length + (_isEditing ? 1 : 0)),
            itemBuilder: (context, index) {
              if (index < _photos.length) {
                final url = _photos[index];
                return GestureDetector(
                  onTap: () => showDialog(
                      context: context,
                      builder: (_) => Dialog(
                            child: url.startsWith('http')
                                ? Image.network(url, fit: BoxFit.cover)
                                : Image.file(File(url), fit: BoxFit.cover),
                          )),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: url.startsWith('http')
                        ? Image.network(url, fit: BoxFit.cover)
                        : Image.file(File(url), fit: BoxFit.cover),
                  ),
                );
              }

              if (_isEditing) {
                return GestureDetector(
                  onTap: _pickPhoto,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: const Center(child: Icon(Icons.add)),
                  ),
                );
              }

              return Container();
            },
          ),
          if (!hasPhotos && !_isEditing)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Add photos of your work when you tap Edit. Customers trust providers with real examples.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _buildAvatarHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 56,
                backgroundColor: Colors.grey.shade300,
                foregroundImage: (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                    ? (_avatarUrl!.startsWith('http')
                        ? NetworkImage(_avatarUrl!) as ImageProvider
                        : (File(_avatarUrl!).existsSync()
                            ? FileImage(File(_avatarUrl!)) as ImageProvider
                            : null))
                    : null,
                child: (_avatarUrl == null || _avatarUrl!.isEmpty)
                    ? Icon(Icons.person, size: 48, color: Colors.white)
                    : null,
              ),
              if (_isEditing)
                Material(
                  color: LinqColors.forest500,
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: const Icon(Icons.photo_camera_rounded, size: 18, color: Colors.white),
                    onPressed: _pickAvatar,
                    padding: const EdgeInsets.all(10),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _displayName.isNotEmpty ? _displayName : 'Provider photo',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _extractProfileName(Map<String, dynamic> source) {
    final validName = <String?>[
      source['name']?.toString(),
      source['display_name']?.toString(),
      source['full_name']?.toString(),
      source['username']?.toString(),
      source['provider_name']?.toString(),
      source['profile_name']?.toString(),
    ]
        .whereType<String>()
        .map((value) => value.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (validName.isNotEmpty) return validName;

    final first = source['first_name']?.toString().trim() ?? '';
    final last = source['last_name']?.toString().trim() ?? '';
    if (first.isNotEmpty && last.isNotEmpty) {
      return '$first $last';
    }
    if (first.isNotEmpty) return first;
    if (last.isNotEmpty) return last;
    return '';
  }

  String _weekdayLabel(int idx) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[idx - 1];
  }
}

class TimeRange {
  final TimeOfDay start;
  final TimeOfDay end;
  TimeRange(this.start, this.end);

  String format() => '${start.formatString()} - ${end.formatString()}';
}

extension on TimeOfDay {
  String formatString() {
    final h = hourOfPeriod == 0 ? 12 : hourOfPeriod;
    final m = minute.toString().padLeft(2, '0');
    final ap = period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $ap';
  }
}
