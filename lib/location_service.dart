import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocationService {
  static const _keyLat = 'user_lat';
  static const _keyLng = 'user_lng';
  static const _keyCountry = 'user_country';
  static const _keyState = 'user_state';
  static const _keyLga = 'user_lga';
  static const _keyArea = 'user_area';

  /// Requests permission and fetches current position with reverse geocoding.
  /// Saves to local storage and returns the position with country/state/lga/area.
  static Future<Map<String, dynamic>> fetchLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return {
          'success': false,
          'message':
              'Location services are disabled. Please enable them in settings.',
        };
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return {'success': false, 'message': 'Location permission denied.'};
        }
      }
      if (permission == LocationPermission.deniedForever) {
        return {
          'success': false,
          'message':
              'Location permission permanently denied. Please enable it in app settings.',
        };
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      // Reverse geocode to get country and state
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      final placemark = placemarks.isNotEmpty ? placemarks.first : null;
      String? country = placemark?.country;
      String? state = placemark?.administrativeArea;
      String? lga = placemark?.subAdministrativeArea;
      String? area = (placemark?.locality?.isNotEmpty ?? false)
          ? placemark!.locality
          : placemark?.subLocality;

      await _saveLocation(
          position.latitude, position.longitude, country, state, lga, area);

      return {
        'success': true,
        'lat': position.latitude,
        'lng': position.longitude,
        'country': country,
        'state': state,
        'lga': lga,
        'area': area,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to get location. Please try again.',
      };
    }
  }

  /// Returns cached location from local storage without requesting again.
  static Future<Map<String, dynamic>?> getCachedLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(_keyLat);
    final lng = prefs.getDouble(_keyLng);
    if (lat == null || lng == null) return null;
    return {
      'lat': lat,
      'lng': lng,
      'country': prefs.getString(_keyCountry),
      'state': prefs.getString(_keyState),
      'lga': prefs.getString(_keyLga),
      'area': prefs.getString(_keyArea),
    };
  }

  static Future<void> _saveLocation(double lat, double lng, String? country,
      String? state, String? lga, String? area) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyLat, lat);
    await prefs.setDouble(_keyLng, lng);
    if (country != null) await prefs.setString(_keyCountry, country);
    if (state != null) await prefs.setString(_keyState, state);
    if (lga != null) await prefs.setString(_keyLga, lga);
    if (area != null) await prefs.setString(_keyArea, area);
  }
}
