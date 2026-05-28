import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'countries_data.dart';
import 'linq_theme.dart';
import 'location_service.dart';

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  bool _isEditing = false;
  bool _loading = true;
  bool _saving = false;
  bool _locationLoading = false;
  String? _errorMessage;
  String _locationStatus = '';

  String _firstName = '';
  String _lastName = '';
  String _email = '';

  final _phoneCtrl = TextEditingController();
  String? _selectedCountry;
  String? _selectedState;
  final _addressCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _errorMessage = null;
      _locationStatus = '';
    });

    // If not forcing refresh, check if cached profile has required fields
    if (!forceRefresh) {
      final cached = await AuthService.getCachedProfile();
      if (cached != null) {
        final user =
            (cached['user'] is Map ? cached['user'] : cached)
                as Map<String, dynamic>;
        final firstName = user['first_name'];
        final lastName = user['last_name'];

        print('[UserProfilePage] Cached profile user: $user');
        print(
          '[UserProfilePage] Cached first_name: $firstName, last_name: $lastName',
        );

        // If cache has the name fields and they are not empty, use it
        if (firstName != null &&
            firstName.isNotEmpty &&
            lastName != null &&
            lastName.isNotEmpty) {
          setState(() {
            _firstName = firstName ?? '';
            _lastName = lastName ?? '';
            _email = user['email'] ?? '';
            _phoneCtrl.text = user['phone'] ?? '';
            _selectedCountry = _validCountry(user['country']);
            _selectedState = _validState(_selectedCountry, user['state']);
            _addressCtrl.text = user['address'] ?? '';
            _loading = false;
          });

          if (_addressCtrl.text.trim().isEmpty) {
            await _captureLocation();
          }
          return;
        }
        // If missing name fields, fall through to fetch from API
      }
    }

    final result = await AuthService.getProfile(forceRefresh: true);
    if (!mounted) return;

    if (result['success'] == true) {
      final raw = result['data'] as Map<String, dynamic>;
      final user =
          (raw['user'] is Map ? raw['user'] : raw) as Map<String, dynamic>;

      print('[UserProfilePage] API profile raw: $raw');
      print('[UserProfilePage] API profile user: $user');
      print(
        '[UserProfilePage] API first_name: ${user['first_name']}, last_name: ${user['last_name']}',
      );

      setState(() {
        _firstName = user['first_name'] ?? '';
        _lastName = user['last_name'] ?? '';
        _email = user['email'] ?? '';
        _phoneCtrl.text = user['phone'] ?? '';
        _selectedCountry = _validCountry(user['country']);
        _selectedState = _validState(_selectedCountry, user['state']);
        _addressCtrl.text = user['address'] ?? '';
        _loading = false;
      });

      if (_addressCtrl.text.trim().isEmpty) {
        await _captureLocation();
      }
    } else {
      setState(() {
        _loading = false;
        _errorMessage = result['message'];
      });
    }
  }

  Future<void> _captureLocation() async {
    if (_locationLoading) return;
    setState(() {
      _locationLoading = true;
      _locationStatus = 'Capturing your current location…';
    });

    final cached = await LocationService.getCachedLocation();
    Map<String, dynamic> result;
    if (cached != null) {
      result = {
        'success': true,
        'lat': cached['lat'],
        'lng': cached['lng'],
        'country': cached['country'],
        'state': cached['state'],
      };
    } else {
      result = await LocationService.fetchLocation();
    }

    if (!mounted) return;
    if (result['success'] == true) {
      final lat = result['lat'] as double;
      final lng = result['lng'] as double;
      final country = result['country'] as String?;
      final state = result['state'] as String?;

      if (_selectedCountry == null && country != null) {
        _selectedCountry = _validCountry(country);
      }
      if (_selectedState == null && state != null && _selectedCountry != null) {
        _selectedState = _validState(_selectedCountry, state);
      }

      final parts = [
        if (state != null && state.isNotEmpty) state,
        if (country != null && country.isNotEmpty) country,
      ];
      final addressText = parts.isNotEmpty
          ? parts.join(', ')
          : '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';

      setState(() {
        if (_addressCtrl.text.trim().isEmpty) _addressCtrl.text = addressText;
        _locationStatus = 'Location captured. You can edit it manually.';
      });
    } else {
      setState(() {
        _locationStatus =
            result['message']?.toString() ?? 'Unable to capture location.';
      });
    }

    setState(() => _locationLoading = false);
  }

  Future<void> _saveChanges() async {
    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    final result = await AuthService.updateProfile({
      'phone': _phoneCtrl.text.trim(),
      'country': _selectedCountry ?? '',
      'state': _selectedState ?? '',
      'address': _addressCtrl.text.trim(),
    });
    if (!mounted) return;
    setState(() => _saving = false);

    if (result['success'] == true) {
      // Capture current selections before reload
      final savedCountry = _selectedCountry;
      final savedState = _selectedState;
      setState(() => _isEditing = false);
      await _loadProfile(forceRefresh: true);
      // Restore selections if API response didn't include them
      if (mounted) {
        setState(() {
          _selectedCountry ??= savedCountry;
          _selectedState ??= savedState;
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Profile updated successfully!',
            style: LinqTextStyles.bodySm.copyWith(
              color: LinqColors.textOnBrand,
            ),
          ),
          backgroundColor: LinqColors.success500,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: LinqRadius.borderMd),
        ),
      );
    } else {
      setState(() => _errorMessage = result['message']);
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LinqColors.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: LinqRadius.borderLg),
        title: Text('Log out', style: LinqTextStyles.h3),
        content: Text(
          'Are you sure you want to log out of your account?',
          style: LinqTextStyles.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: LinqTextStyles.label.copyWith(
                color: LinqColors.textTertiary,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: LinqColors.danger500,
              foregroundColor: LinqColors.textOnBrand,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: LinqRadius.borderMd),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await AuthService.logout();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
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
          'My profile',
          style: LinqTextStyles.h3.copyWith(color: LinqColors.textOnBrand),
        ),
        actions: [
          IconButton(
            onPressed: () => setState(() => _isEditing = !_isEditing),
            icon: Icon(_isEditing ? Icons.close : Icons.edit),
          ),
        ],
      ),
      body: RefreshIndicator(
              onRefresh: () => _loadProfile(forceRefresh: true),
              child: _loading
                  ? SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: SizedBox(
                        height: MediaQuery.of(context).size.height * 0.75,
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: LinqColors.forest500,
                          ),
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(LinqSpacing.s5),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_errorMessage != null) ...[
                            Container(
                              padding: const EdgeInsets.all(LinqSpacing.s3),
                              decoration: BoxDecoration(
                                color: LinqColors.danger50,
                                borderRadius: LinqRadius.borderMd,
                                border: Border.all(color: LinqColors.danger100),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.error_outline,
                                    color: LinqColors.danger500,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: LinqTextStyles.bodySm.copyWith(
                                        color: LinqColors.danger700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: LinqSpacing.s4),
                          ],

                          _sectionCard(
                            title: 'Personal information',
                            children: [
                              _readOnlyRow('First name', _firstName),
                              _readOnlyRow('Last name', _lastName),
                              _readOnlyRow('Email', _email),
                              _editableRow(
                                'Phone',
                                _phoneCtrl,
                                hint: 'Add phone number',
                              ),
                            ],
                          ),
                          const SizedBox(height: LinqSpacing.s4),

                          _sectionCard(
                            title: 'Location',
                            children: [
                              _dropdownRow(
                                label: 'Country',
                                value: _selectedCountry,
                                items: countriesAndStates.keys.toList(),
                                hint: 'Select country',
                                onChanged: (val) => setState(() {
                                  _selectedCountry = val;
                                  _selectedState = null;
                                }),
                              ),
                              _dropdownRow(
                                label: 'State',
                                value: _selectedState,
                                items: _selectedCountry != null
                                    ? countriesAndStates[_selectedCountry!] ??
                                          []
                                    : [],
                                hint: _selectedCountry == null
                                    ? 'Select country first'
                                    : 'Select state',
                                onChanged: _selectedCountry == null
                                    ? null
                                    : (val) =>
                                          setState(() => _selectedState = val),
                              ),
                              if (_isEditing) _locationActionRow(),
                              _editableRow(
                                'Address',
                                _addressCtrl,
                                hint: 'Add address',
                                maxLines: 2,
                              ),
                              if (_locationStatus.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: LinqSpacing.s2,
                                  ),
                                  child: Text(
                                    _locationStatus,
                                    style: LinqTextStyles.bodyXs.copyWith(
                                      color: LinqColors.textOnBrand,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: LinqSpacing.s4),

                          // _sectionCard(
                          //   title: 'Account stats',
                          //   children: [
                          //     _statRow('Member since', 'January 2024'),
                          //     _statRow('Total bookings', '12'),
                          //     _statRow('Active jobs', '2'),
                          //   ],
                          // ),
                          const SizedBox(height: LinqSpacing.s6),

                          if (_isEditing)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: linqPrimaryButton(
                                  verticalPadding: LinqSpacing.s4,
                                ),
                                onPressed: _saving ? null : _saveChanges,
                                child: _saving
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          color: LinqColors.textOnBrand,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text(
                                        'Save changes',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                            ),

                          if (_isEditing)
                            const SizedBox(height: LinqSpacing.s3),

                          if (!_isEditing)
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: LinqColors.danger500,
                                    width: LinqBorders.thin,
                                  ),
                                  foregroundColor: LinqColors.danger500,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: LinqSpacing.s4,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: LinqRadius.borderMd,
                                  ),
                                ),
                                onPressed: _confirmLogout,
                                icon: const Icon(Icons.logout),
                                label: const Text(
                                  'Log out',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: LinqSpacing.s5),
                        ],
                      ),
                    ),
            ),
      bottomNavigationBar: const _BottomNav(),
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

  Widget _readOnlyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LinqSpacing.s4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: LinqTextStyles.bodySm),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: LinqTextStyles.label.copyWith(
                color: value.isEmpty
                    ? LinqColors.textTertiary
                    : LinqColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editableRow(
    String label,
    TextEditingController ctrl, {
    String hint = '',
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LinqSpacing.s4),
      child: _isEditing
          ? TextField(
              controller: ctrl,
              maxLines: maxLines,
              decoration: linqInputDecoration(
                label: label,
                icon: Icons.edit_outlined,
              ),
            )
          : Row(
              children: [
                SizedBox(
                  width: 100,
                  child: Text(label, style: LinqTextStyles.bodySm),
                ),
                Expanded(
                  child: Text(
                    ctrl.text.isEmpty ? '—' : ctrl.text,
                    style: LinqTextStyles.label.copyWith(
                      color: ctrl.text.isEmpty
                          ? LinqColors.textTertiary
                          : LinqColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _locationActionRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: LinqSpacing.s4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: linqPrimaryButton(verticalPadding: LinqSpacing.s3),
                  onPressed: _locationLoading ? null : _captureLocation,
                  icon: const Icon(Icons.my_location),
                  label: Text(
                    _locationLoading ? 'Capturing...' : 'Use current location',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              // const SizedBox(width: LinqSpacing.s3),
              // Expanded(
              //   child: OutlinedButton.icon(
              //     onPressed: _locationLoading
              //         ? null
              //         : () => Navigator.pushNamed(context, '/nearby-map'),
              //     style: OutlinedButton.styleFrom(
              //       side: const BorderSide(color: LinqColors.borderDefault),
              //     ),
              //     icon: const Icon(Icons.map_outlined),
              //     label: const Text('Open map'),
              //   ),
              // ),
            ],
          ),
          if (_addressCtrl.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: LinqSpacing.s3),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _locationLoading
                      ? null
                      : () => setState(() => _addressCtrl.clear()),
                  child: const Text('Clear address'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LinqSpacing.s4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: LinqTextStyles.bodySm),
          ),
          Text(
            value,
            style: LinqTextStyles.label.copyWith(color: LinqColors.forest500),
          ),
        ],
      ),
    );
  }

  Widget _dropdownRow({
    required String label,
    required String? value,
    required List<String> items,
    required String hint,
    required ValueChanged<String?>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LinqSpacing.s4),
      child: _isEditing
          ? DropdownButtonFormField<String>(
              value: value,
              decoration: linqInputDecoration(
                label: label,
                icon: Icons.location_on_outlined,
              ),
              hint: Text(
                hint,
                style: LinqTextStyles.body.copyWith(
                  color: LinqColors.textTertiary,
                ),
              ),
              isExpanded: true,
              items: items
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: onChanged,
            )
          : Row(
              children: [
                SizedBox(
                  width: 100,
                  child: Text(label, style: LinqTextStyles.bodySm),
                ),
                Expanded(
                  child: Text(
                    (value == null || value.isEmpty) ? '—' : value,
                    style: LinqTextStyles.label.copyWith(
                      color: (value == null || value.isEmpty)
                          ? LinqColors.textTertiary
                          : LinqColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  String? _validCountry(String? country) {
    if (country == null || country.isEmpty) return null;
    return countriesAndStates.containsKey(country) ? country : null;
  }

  String? _validState(String? country, String? state) {
    if (country == null || state == null || state.isEmpty) return null;
    final states = countriesAndStates[country];
    return (states != null && states.contains(state)) ? state : null;
  }
}

// ── BOTTOM NAV ───────────────────────────────────────────────────
class _BottomNav extends StatelessWidget {
  const _BottomNav();

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: 3,
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
            Navigator.pushNamed(context, '/user-jobs');
            break;
          case 2:
            Navigator.pushNamed(context, '/user-transactions');
            break;
          case 3:
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
