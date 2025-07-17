import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '/main.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _InfoBox extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoBox({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(2, 2)),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center, // Dikey ortalama
        children: [
          Icon(icon, size: 24, color: colorScheme.onSurface),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _HomeScreenState extends State<HomeScreen> {
  late GoogleMapController mapController;
  LatLng? _currentPosition;
  TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _suggestions = [];

  Set<Marker> _markers = {};
  String? _selectedMarkerId;

  final String apiKey = 'AIzaSyCjlbhruDy4N0y6zUjrC9Ktguc3BAQ14uk';

  LatLng? _trackingTarget;
  bool _isTracking = false;
  double _distanceThreshold = 100.0;
  Timer? _trackingTimer;
  bool _showTrackingBar = false;

  bool _vibrationEnabled = true;
  String _alarmSound = 'sounds/alarm.mp3';
  CameraPosition? _lastCameraPosition;

  bool get _isDarkMode =>
      Provider.of<ThemeNotifier>(context, listen: false).isDarkMode;

  Set<Polyline> _polylines = {};
  int _routePolylineId = 1;

  double? _currentDistance;
  double? _currentSpeed;
  Duration? _estimatedArrivalTime;
  List<double> _recentSpeeds = [];

  Widget _buildInfoBox(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadSavedAlarmSound();
    _loadSavedVibrationPreference();
    _loadDarkModePreference(); // << eklenen satır
    _determinePosition().then((_) {
      _searchTransitStationsForCity("İstanbul");
      _searchTransitStationsForCity("Sakarya");
    });
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
    super.dispose();
  }

  void _toggleDarkMode() async {
    Provider.of<ThemeNotifier>(context, listen: false).toggleTheme();

    if (mapController != null) {
      if (_isDarkMode) {
        final darkStyle = await rootBundle.loadString(
          'assets/maps/dark_map.json',
        );
        mapController.setMapStyle(darkStyle);
      } else {
        mapController.setMapStyle(null);
      }
    }
  }

  Future<void> _determinePosition() async {
    final status = await Permission.location.request();
    if (status.isGranted) {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Konum izni reddedildi")));
    }
  }

  Future<void> _drawRoute(LatLng origin, LatLng destination) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=${origin.latitude},${origin.longitude}'
      '&destination=${destination.latitude},${destination.longitude}'
      '&mode=walking'
      '&key=$apiKey',
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['status'] == 'OK') {
        final points = data['routes'][0]['overview_polyline']['points'];
        final decodedPoints = _decodePolyline(points);

        setState(() {
          _polylines = {
            Polyline(
              polylineId: PolylineId('route_$_routePolylineId'),
              points: decodedPoints,
              color: Colors.blue,
              width: 5,
            ),
          };
          _routePolylineId++;
        });
      } else {
        print("Rota bulunamadı: ${data['status']}");
      }
    } else {
      print("HTTP Hatası: ${response.statusCode}");
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> polylineCoordinates = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;

      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      polylineCoordinates.add(LatLng(lat / 1E5, lng / 1E5));
    }

    return polylineCoordinates;
  }

  Future<void> _searchTransitStationsForCity(String city) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/textsearch/json?query=otobüs+ve+metro+durakları+$city&key=$apiKey&language=tr',
    );
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final results = data['results'] as List;
      Set<Marker> newMarkers = Set.from(_markers);
      for (var place in results) {
        final name = place['name'];
        final lat = place['geometry']['location']['lat'];
        final lng = place['geometry']['location']['lng'];
        final id = place['place_id'];
        newMarkers.add(
          Marker(
            markerId: MarkerId(id),
            position: LatLng(lat, lng),
            infoWindow: InfoWindow(title: name),
            onTap: () => _removeMarker(id),
          ),
        );
      }
      setState(() {
        _markers = newMarkers;
      });
    }
  }

  Future<void> _getSuggestions(String input) async {
    if (input.length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$input&key=$apiKey&language=tr&components=country:tr',
    );
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final predictions = data['predictions'] as List;
      setState(() {
        _suggestions = predictions.map((p) {
          return {
            'description': p['description'],
            'place_id': p['place_id'],
            'types': p['types'] ?? [],
          };
        }).toList();
      });
    }
  }

  Future<void> _goToPlace(String placeId) async {
    FocusScope.of(context).unfocus(); // <<--- Klavyeyi kapatır

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$apiKey&language=tr',
    );
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final location = data['result']['geometry']['location'];
      final latLng = LatLng(location['lat'], location['lng']);
      mapController.animateCamera(CameraUpdate.newLatLngZoom(latLng, 14));

      final markerId = 'single_marker';
      setState(() {
        _markers.clear();
        _markers.add(
          Marker(
            markerId: MarkerId(markerId),
            position: latLng,
            infoWindow: InfoWindow(title: data['result']['name']),
            onTap: () => _removeMarker(markerId),
          ),
        );
        _selectedMarkerId = markerId;
        _trackingTarget = latLng;
        _showTrackingBar = true;
        _isTracking = false;
        _searchController.text = data['result']['name'];
        _suggestions = [];
      });
    }
  }

  Future<void> pickAlarmSound() async {
    if (Platform.isAndroid) {
      var permission = await Permission.audio.request();
      if (!permission.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ses dosyasına erişim izni reddedildi')),
        );
        return;
      }
    }

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav'],
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _alarmSound = result.files.single.path!;
      });

      // 🔐 KAYDET
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('alarm_sound', _alarmSound);
    } else {
      print('Dosya seçimi iptal edildi.');
    }
  }

  Future<void> _loadSavedAlarmSound() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? savedSound = prefs.getString('alarm_sound');
    if (savedSound != null && File(savedSound).existsSync()) {
      setState(() {
        _alarmSound = savedSound;
      });
    }
  }

  Future<void> _loadSavedVibrationPreference() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool? savedVibration = prefs.getBool('vibration_enabled');
    if (savedVibration != null) {
      setState(() {
        _vibrationEnabled = savedVibration;
      });
    }
  }

  Future<void> _loadDarkModePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('dark_mode') ?? false;

    Provider.of<ThemeNotifier>(context, listen: false).setDarkMode(isDark);
  }

  void _onMapCreated(GoogleMapController controller) async {
    mapController = controller;

    if (_isDarkMode) {
      final darkStyle = await rootBundle.loadString(
        'assets/maps/dark_map.json',
      );
      mapController.setMapStyle(darkStyle);
    }
  }

  void debugCamera() {
    print('Last Camera Position: $_lastCameraPosition');
    print('Markers: ${_markers.length}');
  }

  void _handleMapTap(LatLng tappedPoint) {
    final markerId = 'single_marker';

    if (_lastCameraPosition != null) {
      mapController.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: tappedPoint,
            zoom: _lastCameraPosition!.zoom,
            tilt: _lastCameraPosition!.tilt,
            bearing: _lastCameraPosition!.bearing,
          ),
        ),
      );
    } else {
      mapController.animateCamera(CameraUpdate.newLatLngZoom(tappedPoint, 14));
    }

    setState(() {
      _markers.clear();
      _markers.add(
        Marker(
          markerId: MarkerId(markerId),
          position: tappedPoint,
          infoWindow: InfoWindow(title: "Seçilen Konum"),
          onTap: () => _removeMarker(markerId),
        ),
      );
      _selectedMarkerId = markerId;
      _trackingTarget = tappedPoint;
      _isTracking = false;
      _showTrackingBar = true;
    });

    debugCamera();
  }

  void _removeMarker(String markerId) {
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == markerId);
      if (_selectedMarkerId == markerId) {
        _selectedMarkerId = null;
        _trackingTarget = null;
        _isTracking = false;
        _trackingTimer?.cancel();
        _showTrackingBar = false;
      }
    });
  }

  void _stopTracking() async {
    _trackingTimer?.cancel();
    _trackingTimer = null;

    setState(() {
      _isTracking = false;
      _showTrackingBar = true;
      _polylines.clear();
      _currentDistance = null;
      _currentSpeed = null;
      _estimatedArrivalTime = null;
    });

    await AudioPlayer().stop(); // Alarmı durdur
    Vibration.cancel(); // Titreşimi durdur
  }

  void _startTracking() {
    if (_trackingTarget == null) return;

    setState(() {
      _isTracking = true;
      _showTrackingBar = false;
    });

    final player = AudioPlayer();
    player.setReleaseMode(ReleaseMode.loop);

    _trackingTimer?.cancel();
    _trackingTimer = Timer.periodic(Duration(seconds: 5), (_) async {
      if (!_isTracking || _trackingTarget == null) return;

      final position = await Geolocator.getCurrentPosition();
      double speed = position.speed;

      if (speed < 0.5) speed = 0; // çok küçük hızları sıfır say
      _recentSpeeds.add(speed);
      if (_recentSpeeds.length > 3) _recentSpeeds.removeAt(0);
      final avgSpeed =
          _recentSpeeds.reduce((a, b) => a + b) / _recentSpeeds.length;

      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        _trackingTarget!.latitude,
        _trackingTarget!.longitude,
      );

      Duration? estimatedTime;
      if (avgSpeed > 0) {
        estimatedTime = Duration(seconds: (distance / avgSpeed).round());
      }

      setState(() {
        _currentDistance = distance;
        _currentSpeed = avgSpeed;
        _estimatedArrivalTime = estimatedTime;
      });

      await _drawRoute(
        LatLng(position.latitude, position.longitude),
        _trackingTarget!,
      );

      if (distance <= _distanceThreshold) {
        _trackingTimer?.cancel();
        setState(() => _isTracking = false);

        if (_alarmSound.startsWith('sounds/')) {
          await player.play(AssetSource(_alarmSound));
        } else {
          await player.play(DeviceFileSource(_alarmSound));
        }

        if (_vibrationEnabled && (await Vibration.hasVibrator() ?? false)) {
          Vibration.vibrate(pattern: [500, 1000, 500, 1000], repeat: 0);
        }

        if (context.mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => AlertDialog(
              title: Text("📍 Hedefe Ulaştınız"),
              content: Text("Belirlediğiniz noktaya yaklaştınız!"),
              actions: [
                TextButton(
                  child: Text("Alarmı Durdur"),
                  onPressed: () async {
                    final markerId = 'single_marker';
                    await player.stop();
                    Vibration.cancel();
                    Navigator.of(context).pop();
                    _polylines.clear();
                    _removeMarker(markerId);

                    // Temizle
                    setState(() {
                      _currentDistance = null;
                      _currentSpeed = null;
                      _estimatedArrivalTime = null;
                      _recentSpeeds.clear();
                    });
                  },
                ),
              ],
            ),
          );
        }
      }
    });
  }

  bool _isTransitStop(Map<String, dynamic> suggestion) {
    final types = suggestion['types'] as List<dynamic>? ?? [];
    final description = suggestion['description'].toLowerCase();
    return types.any(
          (t) =>
              t == "bus_station" ||
              t == "transit_station" ||
              t == "subway_station" ||
              t == "train_station",
        ) ||
        description.contains("durak");
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      endDrawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: colorScheme.primary),
              child: Text(
                'Ayarlar',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  backgroundColor: colorScheme.primary,
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.music_note),
              title: Text('Alarm Sesi Seç'),
              onTap: () async {
                await pickAlarmSound();
                if (context.mounted) Navigator.pop(context);
              },
              subtitle: Text(
                _alarmSound.contains('/')
                    ? _alarmSound.split('/').last
                    : _alarmSound,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            SwitchListTile(
              title: Text('Titreşim'),
              value: _vibrationEnabled,
              onChanged: (val) async {
                setState(() => _vibrationEnabled = val);

                //  Tercihi kaydet
                SharedPreferences prefs = await SharedPreferences.getInstance();
                await prefs.setBool('vibration_enabled', val);
              },
              secondary: Icon(Icons.vibration),
            ),
            ListTile(
              title: Text('Tema Seç'),
              trailing: Switch(
                value: Provider.of<ThemeNotifier>(
                  context,
                ).isDarkMode, // direkt provider'dan oku
                onChanged: (value) async {
                  Provider.of<ThemeNotifier>(
                    context,
                    listen: false,
                  ).toggleTheme();

                  if (mapController != null) {
                    if (value) {
                      final darkStyle = await rootBundle.loadString(
                        'assets/maps/dark_map.json',
                      );
                      mapController.setMapStyle(darkStyle);
                    } else {
                      mapController.setMapStyle(null);
                    }
                  }
                },
                thumbIcon: MaterialStateProperty.resolveWith<Icon?>((
                  Set<MaterialState> states,
                ) {
                  if (states.contains(MaterialState.selected)) {
                    return const Icon(
                      Icons.dark_mode,
                      size: 18,
                      color: Colors.white,
                    );
                  }
                  return const Icon(
                    Icons.wb_sunny,
                    size: 18,
                    color: Colors.orange,
                  );
                }),
              ),
              subtitle: Text(
                Provider.of<ThemeNotifier>(context).isDarkMode
                    ? "Karanlık"
                    : "Açık",
              ),
            ),
          ],
        ),
      ),
          ],
        ),
      ),
      body: _currentPosition == null
          ? Center(child: CircularProgressIndicator())
          : GestureDetector(
              behavior:
                  HitTestBehavior.translucent, // boş alanlarda da çalışsın
              onTap: () {
                FocusScope.of(context).unfocus(); // klavyeyi kapat
              },
              child: Stack(
                children: [
                  // Google Harita
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _currentPosition!,
                      zoom: 14,
                    ),
                    onMapCreated: _onMapCreated,
                    onCameraMove: (position) => _lastCameraPosition = position,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    compassEnabled: false,
                    markers: _markers,
                    polylines: _polylines,
                    onTap: (LatLng position) {
                      final hasFocus = FocusScope.of(context).hasFocus;
                      final hasSuggestions = _suggestions.isNotEmpty;

                      //  Klavye ya da öneri kutusu açıksa sadece onları kapat
                      if (hasFocus || hasSuggestions) {
                        FocusScope.of(context).unfocus();
                        setState(() => _suggestions = []);
                        return;
                      }

                      // 🟢 Gerçek tıklama → marker koy
                      _handleMapTap(position);
                    },
                  ),

                  // Arama Kutusu ve Öneriler
                  Positioned(
                    top: 50,
                    left: 15,
                    right: 15,
                    child: SafeArea(
                      child: Builder(
                        builder: (context) {
                          final colorScheme = Theme.of(context).colorScheme;
                          return Column(
                            children: [
                              Material(
                                elevation: 8,
                                borderRadius: BorderRadius.circular(8),
                                child: TextField(
                                  controller: _searchController,
                                  onChanged: _getSuggestions,
                                  style: TextStyle(
                                    color: colorScheme.onSurface,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Yer ara...',
                                    prefixIcon: Icon(
                                      Icons.search,
                                      color: colorScheme.onSurface,
                                    ),
                                    contentPadding: const EdgeInsets.all(12),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide.none,
                                    ),
                                    filled: true,
                                    fillColor: colorScheme.surface,
                                  ),
                                ),
                              ),
                              if (_suggestions.isNotEmpty)
                                Stack(
                                  children: [
                                    Positioned.fill(
                                      child: GestureDetector(
                                        onTap: () {
                                          FocusScope.of(context).unfocus();
                                          setState(() => _suggestions = []);
                                        },
                                        child: Container(
                                          color: Colors.transparent,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      constraints: const BoxConstraints(
                                        maxHeight: 200,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colorScheme.surface,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: ListView.builder(
                                        shrinkWrap: true,
                                        itemCount: _suggestions.length,
                                        itemBuilder: (context, index) {
                                          final suggestion =
                                              _suggestions[index];
                                          return ListTile(
                                            leading: _isTransitStop(suggestion)
                                                ? Icon(
                                                    Icons.directions_bus,
                                                    color: colorScheme.primary,
                                                  )
                                                : Icon(
                                                    Icons.location_on,
                                                    color: colorScheme.onSurface
                                                        .withOpacity(0.6),
                                                  ),
                                            title: Text(
                                              suggestion['description'],
                                              style: TextStyle(
                                                color: colorScheme.onSurface,
                                              ),
                                            ),
                                            onTap: () => _goToPlace(
                                              suggestion['place_id'],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),

                  // Ayarlar Butonu
                  Positioned(
                    top: 10,
                    right: 10,
                    child: SafeArea(
                      child: Builder(
                        builder: (context) => IconButton(
                          icon: Icon(
                            Icons.settings,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          onPressed: () {
                            FocusScope.of(context).unfocus(); // klavyeyi kapat
                            Scaffold.of(context).openEndDrawer(); // drawer'ı aç
                          },
                        ),
                      ),
                    ),
                  ),

                  // Konum ve Pusula Butonları
                  Positioned(
                    bottom: _showTrackingBar ? 180 : 120,
                    right: 15,
                    child: Builder(
                      builder: (context) {
                        final colorScheme = Theme.of(context).colorScheme;
                        return Column(
                          children: [
                            FloatingActionButton(
                              heroTag: "myLocation",
                              onPressed: () async {
                                final pos =
                                    await Geolocator.getCurrentPosition();
                                final latLng = LatLng(
                                  pos.latitude,
                                  pos.longitude,
                                );
                                mapController.animateCamera(
                                  CameraUpdate.newLatLngZoom(latLng, 14),
                                );
                              },

                              backgroundColor: colorScheme.surface,
                              foregroundColor: colorScheme.onSurface,

                              child: const Icon(Icons.my_location),
                              tooltip: 'Konuma Git',
                            ),
                            const SizedBox(height: 12),
                            FloatingActionButton(
                              heroTag: "compassReset",
                              onPressed: () {
                                if (_lastCameraPosition != null) {
                                  mapController.animateCamera(
                                    CameraUpdate.newCameraPosition(
                                      CameraPosition(
                                        target: _lastCameraPosition!.target,
                                        zoom: _lastCameraPosition!.zoom,
                                        tilt: _lastCameraPosition!.tilt,
                                        bearing: 0,
                                      ),
                                    ),
                                  );
                                }
                              },
                              backgroundColor: colorScheme.surface,
                              foregroundColor: colorScheme.onSurface,
                              child: const Icon(Icons.explore),
                              tooltip: 'Kuzeye Dön',
                            ),
                          ],
                        );
                      },
                    ),
                  ),

                  // Takip Barı
                  if (_showTrackingBar)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Builder(
                        builder: (context) {
                          final colorScheme = Theme.of(context).colorScheme;
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(16),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  blurRadius: 10,
                                  color: colorScheme.onBackground.withOpacity(
                                    0.3,
                                  ),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  "Yaklaşım mesafesi: ${_distanceThreshold.toInt()} m",
                                  style: TextStyle(
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                Slider(
                                  min: 50,
                                  max: 1000,
                                  divisions: 19,
                                  value: _distanceThreshold,
                                  label: "${_distanceThreshold.toInt()} m",
                                  onChanged: (value) => setState(
                                    () => _distanceThreshold = value,
                                  ),
                                ),
                                ElevatedButton.icon(
                                  onPressed: _isTracking
                                      ? null
                                      : _startTracking,
                                  icon: const Icon(Icons.notifications_active),
                                  label: const Text("Takibi Başlat"),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),

                  if (_isTracking)
                    Positioned(
                      bottom: _showTrackingBar ? 180 : 120,
                      left: 15,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _InfoBox(
                            icon: Icons.speed,
                            label: _currentSpeed != null
                                ? "${(_currentSpeed! * 3.6).toStringAsFixed(1)} km/h"
                                : "- km/h",
                          ),
                          const SizedBox(height: 12),
                          _InfoBox(
                            icon: Icons.straighten,
                            label: _currentDistance != null
                                ? "${_currentDistance!.toStringAsFixed(0)} m"
                                : "- m",
                          ),
                          const SizedBox(height: 12),
                          _InfoBox(
                            icon: Icons.access_time,
                            label: _estimatedArrivalTime != null
                                ? "${_estimatedArrivalTime!.inMinutes} dk ${_estimatedArrivalTime!.inSeconds % 60} sn"
                                : "- dk",
                          ),
                        ],
                      ),
                    ),

                  if (_isTracking)
                    Positioned(
                      bottom: 30, // Sedye gibi biraz yukarıda olsun
                      left: 0,
                      right: 0,
                      child: Center(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                          onPressed: _stopTracking,
                          icon: const Icon(Icons.cancel),
                          label: const Text("Takibi Durdur"),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
