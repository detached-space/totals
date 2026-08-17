import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/_redesign/screens/todays_transactions_page.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/_redesign/widgets/category_filter_chip.dart';
import 'package:totals/l10n/app_localizations.dart';
import 'package:totals/models/category.dart';
import 'package:totals/models/summary_models.dart';
import 'package:totals/models/transaction_location.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/repositories/transaction_location_repository.dart';
import 'package:totals/utils/account_sort.dart';
import 'package:totals/utils/category_filter_utils.dart';

const _ethiopiaCenter = LatLng(9.145, 40.4897);
final _ethiopiaMapBounds = LatLngBounds(
  southwest: const LatLng(3, 32.5),
  northeast: const LatLng(15.5, 48.5),
);

const _darkRoadMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#202124"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"on"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#9AA0A6"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#202124"},{"weight":2}]},
  {"featureType":"administrative","elementType":"geometry.stroke","stylers":[{"color":"#5F6368"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#25272B"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#173226"}]},
  {"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#81C995"}]},
  {"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#303134"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#202124"}]},
  {"featureType":"road.highway","elementType":"geometry.fill","stylers":[{"color":"#3C4043"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#DADCE0"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#2B2D31"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#172A3A"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#8AB4F8"}]}
]
''';

const _mapDisplayModePreferenceKey = 'spending_map_display_mode';

enum _MapDisplayMode { roadmap, satellite }

enum _MapOptionsAction { roadmap, satellite, deleteLocations }

class _SpendingMapFilters {
  const _SpendingMapFilters({
    this.type,
    this.bankId,
    this.accountKey,
    this.categoryIds = const <int>{},
    this.minAmount,
    this.maxAmount,
    this.startDate,
    this.endDate,
  });

  final String? type;
  final int? bankId;
  final String? accountKey;
  final Set<int> categoryIds;
  final double? minAmount;
  final double? maxAmount;
  final DateTime? startDate;
  final DateTime? endDate;

  int get activeCount {
    var count = 0;
    if (type != null) count += 1;
    if (bankId != null) count += 1;
    if (accountKey != null) count += 1;
    if (categoryIds.isNotEmpty) count += 1;
    if (minAmount != null || maxAmount != null) count += 1;
    if (startDate != null || endDate != null) count += 1;
    return count;
  }

  bool get hasTransactionFilters =>
      type != null ||
      bankId != null ||
      accountKey != null ||
      categoryIds.isNotEmpty;

  bool matchesLocation(TransactionLocation location) {
    final amount = (location.amount ?? 0).abs();
    if (minAmount != null && amount < minAmount!) return false;
    if (maxAmount != null && amount > maxAmount!) return false;

    final occurredAt =
        (location.transactionTime ?? location.capturedAt).toLocal();
    if (startDate != null) {
      final startOfDay = DateTime(
        startDate!.year,
        startDate!.month,
        startDate!.day,
      );
      if (occurredAt.isBefore(startOfDay)) return false;
    }
    if (endDate != null) {
      final dayAfterEnd = DateTime(
        endDate!.year,
        endDate!.month,
        endDate!.day + 1,
      );
      if (!occurredAt.isBefore(dayAfterEnd)) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is _SpendingMapFilters &&
      other.type == type &&
      other.bankId == bankId &&
      other.accountKey == accountKey &&
      setEquals(other.categoryIds, categoryIds) &&
      other.minAmount == minAmount &&
      other.maxAmount == maxAmount &&
      other.startDate == startDate &&
      other.endDate == endDate;

  @override
  int get hashCode => Object.hash(
        type,
        bankId,
        accountKey,
        Object.hashAllUnordered(categoryIds),
        minAmount,
        maxAmount,
        startDate,
        endDate,
      );
}

String _mapAccountKey(AccountSummary account) {
  return '${account.bankId}:${account.accountNumber}';
}

String _mapOtherAccountKey(int bankId) => 'other:$bankId';

int? _mapOtherAccountBankId(String key) {
  if (!key.startsWith('other:')) return null;
  return int.tryParse(key.substring('other:'.length));
}

class _KnownPlace {
  const _KnownPlace(this.name, this.position, {required this.detailRadiusKm});

  final String name;
  final LatLng position;
  final double detailRadiusKm;
}

const _knownEthiopianPlaces = <_KnownPlace>[
  // Addis Ababa landmarks and commonly used neighborhood anchors.
  _KnownPlace('Bole', LatLng(8.997, 38.787), detailRadiusKm: 4.5),
  _KnownPlace('Meskel Square', LatLng(9.01, 38.763), detailRadiusKm: 3),
  _KnownPlace('Megenagna', LatLng(9.02, 38.802), detailRadiusKm: 3.5),
  _KnownPlace('Piazza', LatLng(9.035, 38.752), detailRadiusKm: 3),
  _KnownPlace('Merkato', LatLng(9.03, 38.735), detailRadiusKm: 3.5),
  _KnownPlace('Kazanchis', LatLng(9.019, 38.77), detailRadiusKm: 3),
  _KnownPlace('Mexico Square', LatLng(9.01, 38.746), detailRadiusKm: 3),
  _KnownPlace('Sar Bet', LatLng(8.986, 38.735), detailRadiusKm: 3.5),
  _KnownPlace('CMC', LatLng(9.033, 38.842), detailRadiusKm: 4),
  _KnownPlace('Ayat', LatLng(9.035, 38.88), detailRadiusKm: 4.5),
  _KnownPlace('Entoto', LatLng(9.087, 38.76), detailRadiusKm: 5),
  _KnownPlace('Addis Ababa', LatLng(9.03, 38.74), detailRadiusKm: 28),

  // Major cities and well-known destinations across Ethiopia.
  _KnownPlace('Adama', LatLng(8.54, 39.27), detailRadiusKm: 25),
  _KnownPlace('Bahir Dar', LatLng(11.574, 37.361), detailRadiusKm: 24),
  _KnownPlace('Bishoftu', LatLng(8.75, 38.99), detailRadiusKm: 18),
  _KnownPlace('Dire Dawa', LatLng(9.6, 41.85), detailRadiusKm: 25),
  _KnownPlace('Hawassa', LatLng(7.05, 38.47), detailRadiusKm: 24),
  _KnownPlace('Gondar', LatLng(12.603, 37.452), detailRadiusKm: 24),
  _KnownPlace('Mekelle', LatLng(13.496, 39.476), detailRadiusKm: 25),
  _KnownPlace('Jimma', LatLng(7.67, 36.83), detailRadiusKm: 22),
  _KnownPlace('Dessie', LatLng(11.13, 39.63), detailRadiusKm: 20),
  _KnownPlace('Harar', LatLng(9.31, 42.12), detailRadiusKm: 18),
  _KnownPlace('Jigjiga', LatLng(9.35, 42.8), detailRadiusKm: 24),
  _KnownPlace('Arba Minch', LatLng(6.04, 37.55), detailRadiusKm: 20),
  _KnownPlace('Shashamane', LatLng(7.2, 38.59), detailRadiusKm: 18),
  _KnownPlace('Debre Birhan', LatLng(9.68, 39.53), detailRadiusKm: 18),
  _KnownPlace('Kombolcha', LatLng(11.08, 39.74), detailRadiusKm: 18),
  _KnownPlace('Nekemte', LatLng(9.09, 36.55), detailRadiusKm: 20),
  _KnownPlace('Asella', LatLng(7.95, 39.13), detailRadiusKm: 18),
  _KnownPlace('Axum', LatLng(14.12, 38.72), detailRadiusKm: 18),
  _KnownPlace('Lalibela', LatLng(12.03, 39.04), detailRadiusKm: 18),
  _KnownPlace('Semera', LatLng(11.79, 41), detailRadiusKm: 24),
  _KnownPlace('Gambela', LatLng(8.25, 34.59), detailRadiusKm: 22),
  _KnownPlace('Assosa', LatLng(10.07, 34.53), detailRadiusKm: 20),
];

class _SpendingZone {
  const _SpendingZone({
    required this.id,
    required this.name,
    required this.center,
    required this.transactionCount,
    required this.transactionReferences,
    required this.customPlaceName,
  });

  final String id;
  final String name;
  final LatLng center;
  final int transactionCount;
  final List<String> transactionReferences;
  final String? customPlaceName;
}

class _ZoneAccumulator {
  double latitudeTotal = 0;
  double longitudeTotal = 0;
  int count = 0;
  final Set<String> transactionReferences = <String>{};
  final List<TransactionLocation> locations = <TransactionLocation>[];

  void add(TransactionLocation location) {
    latitudeTotal += location.latitude;
    longitudeTotal += location.longitude;
    count += 1;
    transactionReferences.add(location.transactionReference);
    locations.add(location);
  }

  String? get customPlaceName {
    String? selectedName;
    String? selectedKey;
    for (final location in locations) {
      final name = location.placeName;
      if (name == null) continue;
      final key = name.toLowerCase();
      if (selectedKey != null && selectedKey != key) return null;
      selectedName ??= name;
      selectedKey ??= key;
    }
    return selectedName;
  }
}

class SpendingMapPage extends StatefulWidget {
  const SpendingMapPage({super.key});

  @override
  State<SpendingMapPage> createState() => _SpendingMapPageState();
}

class _SpendingMapPageState extends State<SpendingMapPage> {
  final TransactionLocationRepository _repository =
      TransactionLocationRepository();

  TransactionProvider? _transactionProvider;
  List<TransactionLocation> _locations = const [];
  _SpendingMapFilters _filters = const _SpendingMapFilters();
  Map<String, BitmapDescriptor> _puckIcons = const {};
  int _puckGeneration = 0;
  double _zoomLevel = 10;
  double _pendingZoomLevel = 10;
  GoogleMapController? _mapController;
  bool _loading = true;
  bool _mapReady = false;
  bool _locatingUser = false;
  String? _openingZoneId;
  _MapDisplayMode _mapDisplayMode = _MapDisplayMode.roadmap;
  Object? _loadError;

  List<TransactionLocation> get _ethiopiaLocations => _locations
      .where(
        (location) => _ethiopiaMapBounds.contains(
          LatLng(location.latitude, location.longitude),
        ),
      )
      .toList(growable: false);

  List<TransactionLocation> get _filteredLocations {
    final locationFiltered = _ethiopiaLocations
        .where(_filters.matchesLocation)
        .toList(growable: false);
    final provider = _transactionProvider;
    if (provider == null || !_filters.hasTransactionFilters) {
      return locationFiltered;
    }

    final transactionsByReference = {
      for (final transaction in provider.allTransactions)
        transaction.reference: transaction,
    };
    return locationFiltered.where((location) {
      final transaction =
          transactionsByReference[location.transactionReference];
      if (transaction == null) return false;
      if (_filters.type != null &&
          transaction.type?.trim().toUpperCase() != _filters.type) {
        return false;
      }
      if (_filters.bankId != null && transaction.bankId != _filters.bankId) {
        return false;
      }
      if (_filters.accountKey != null) {
        final account = provider.accountSummaryForTransaction(transaction);
        final otherBankId = _mapOtherAccountBankId(_filters.accountKey!);
        if (otherBankId != null) {
          if (account != null || transaction.bankId != otherBankId) {
            return false;
          }
        } else if (account == null ||
            _mapAccountKey(account) != _filters.accountKey) {
          return false;
        }
      }
      return provider.matchesCategoryFilterSelection(
        transaction,
        _filters.categoryIds,
      );
    }).toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _transactionProvider =
        Provider.of<TransactionProvider>(context, listen: false);
  }

  Future<void> _loadLocations() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      var displayMode = _MapDisplayMode.roadmap;
      try {
        final preferences = await SharedPreferences.getInstance();
        if (preferences.getString(_mapDisplayModePreferenceKey) ==
            _MapDisplayMode.satellite.name) {
          displayMode = _MapDisplayMode.satellite;
        }
      } catch (_) {
        // A display preference should never prevent the map from loading.
      }
      final locations = await _repository.getTransactionLocations();
      if (!mounted) return;
      setState(() {
        _locations = locations;
        _mapDisplayMode = displayMode;
        _loading = false;
      });
      await _refreshPuckIcons();
      await _fitVisibleLocations();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  List<_SpendingZone> _buildZones(List<TransactionLocation> locations) {
    final zoomBucket = _zoomBucketFor(_zoomLevel);
    final cellSize = _cellSizeForZoom(_zoomLevel);
    final buckets = <String, _ZoneAccumulator>{};
    for (final location in locations) {
      final latitudeCell = (location.latitude / cellSize).floor();
      final longitudeCell = (location.longitude / cellSize).floor();
      final id = '$zoomBucket-$latitudeCell-$longitudeCell';
      buckets.putIfAbsent(id, _ZoneAccumulator.new).add(location);
    }

    final zones = buckets.entries.map((entry) {
      final bucket = entry.value;
      final center = LatLng(
        bucket.latitudeTotal / bucket.count,
        bucket.longitudeTotal / bucket.count,
      );
      final customPlaceName = bucket.customPlaceName;
      return _SpendingZone(
        id: entry.key,
        name: customPlaceName ?? _approximatePlaceName(center),
        center: center,
        transactionCount: bucket.count,
        transactionReferences: List<String>.unmodifiable(
          bucket.transactionReferences,
        ),
        customPlaceName: customPlaceName,
      );
    }).toList(growable: true);

    zones.sort((first, second) {
      return second.transactionCount.compareTo(first.transactionCount);
    });
    return zones;
  }

  int _zoomBucketFor(double zoom) {
    if (zoom < 6) return 0;
    if (zoom < 7.5) return 1;
    if (zoom < 9) return 2;
    if (zoom < 10.5) return 3;
    if (zoom < 12) return 4;
    if (zoom < 13.5) return 5;
    if (zoom < 15) return 6;
    return 7;
  }

  double _cellSizeForZoom(double zoom) {
    return switch (_zoomBucketFor(zoom)) {
      0 => 3,
      1 => 1.2,
      2 => 0.45,
      3 => 0.18,
      4 => 0.07,
      5 => 0.03,
      6 => 0.012,
      _ => 0.0045,
    };
  }

  String _approximatePlaceName(LatLng point) {
    var nearest = _knownEthiopianPlaces.first;
    var nearestDistance = _distanceKm(point, nearest.position);
    for (final place in _knownEthiopianPlaces.skip(1)) {
      final distance = _distanceKm(point, place.position);
      if (distance < nearestDistance) {
        nearest = place;
        nearestDistance = distance;
      }
    }
    if (nearestDistance <= nearest.detailRadiusKm) {
      return '${nearest.name} area';
    }
    if (nearestDistance <= 70) return 'Near ${nearest.name}';
    if (point.latitude >= 12) return 'Northern Ethiopia';
    if (point.longitude >= 41) return 'Eastern Ethiopia';
    if (point.longitude <= 36) return 'Western Ethiopia';
    if (point.latitude <= 7.5) return 'Southern Ethiopia';
    return 'Central Ethiopia';
  }

  double _distanceKm(LatLng first, LatLng second) {
    const earthRadiusKm = 6371.0;
    final latitudeDelta = _toRadians(second.latitude - first.latitude);
    final longitudeDelta = _toRadians(second.longitude - first.longitude);
    final firstLatitude = _toRadians(first.latitude);
    final secondLatitude = _toRadians(second.latitude);
    final haversine =
        math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
            math.cos(firstLatitude) *
                math.cos(secondLatitude) *
                math.sin(longitudeDelta / 2) *
                math.sin(longitudeDelta / 2);
    return earthRadiusKm *
        2 *
        math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
  }

  double _toRadians(double degrees) => degrees * math.pi / 180;

  Set<Marker> _buildZoneMarkers(List<_SpendingZone> zones) {
    return zones
        .take(50)
        .where((zone) => _puckIcons[zone.id] != null)
        .map((zone) {
      return Marker(
        markerId: MarkerId('zone-puck-${zone.id}'),
        position: zone.center,
        anchor: const Offset(0.5, 0.5),
        icon: _puckIcons[zone.id]!,
        consumeTapEvents: true,
        infoWindow: InfoWindow(
          title: zone.name,
          snippet: '${zone.transactionCount} transactions',
        ),
        onTap: () => _openZone(zone),
      );
    }).toSet();
  }

  String _puckLabel(_SpendingZone zone) {
    return NumberFormat.compact(locale: 'en').format(zone.transactionCount);
  }

  Future<void> _refreshPuckIcons() async {
    final generation = ++_puckGeneration;
    final zones = _buildZones(_filteredLocations).take(50).toList();
    final entries = await Future.wait(
      zones.map((zone) async {
        return MapEntry(
          zone.id,
          await _createPuckIcon(label: _puckLabel(zone)),
        );
      }),
    );
    if (!mounted || generation != _puckGeneration) return;
    setState(
        () => _puckIcons = Map<String, BitmapDescriptor>.fromEntries(entries));
  }

  Future<BitmapDescriptor> _createPuckIcon({required String label}) async {
    const imageSize = 160.0;
    const center = Offset(imageSize / 2, imageSize / 2);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final shadowPath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: 58));
    canvas.drawShadow(shadowPath, AppColors.black, 7, true);
    canvas.drawCircle(center, 60, Paint()..color = AppColors.white);
    canvas.drawCircle(center, 54, Paint()..color = AppColors.primaryLight);
    canvas.drawCircle(
      center,
      54,
      Paint()
        ..color = AppColors.primaryDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    final fontSize = switch (label.length) {
      <= 2 => 48.0,
      3 => 42.0,
      4 => 35.0,
      _ => 28.0,
    };
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: AppColors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.5,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: 100);
    textPainter.paint(
      canvas,
      Offset(
        center.dx - (textPainter.width / 2),
        center.dy - (textPainter.height / 2),
      ),
    );

    final image = await recorder.endRecording().toImage(
          imageSize.toInt(),
          imageSize.toInt(),
        );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final data = bytes?.buffer.asUint8List() ?? Uint8List(0);
    return BitmapDescriptor.bytes(data, width: 54, height: 54);
  }

  Future<String> _savePlaceName(
    _SpendingZone zone,
    String? placeName,
  ) async {
    final normalizedName = normalizeTransactionPlaceName(placeName);
    final references = zone.transactionReferences.toSet();
    await _repository.setPlaceNameForTransactionReferences(
      references,
      normalizedName,
    );
    if (!mounted) {
      return normalizedName ?? _approximatePlaceName(zone.center);
    }

    setState(() {
      _locations = _locations.map((location) {
        if (!references.contains(location.transactionReference)) {
          return location;
        }
        return location.copyWith(
          placeName: normalizedName,
          clearPlaceName: normalizedName == null,
        );
      }).toList(growable: false);
    });
    return normalizedName ?? _approximatePlaceName(zone.center);
  }

  Future<void> _openZone(_SpendingZone zone) async {
    if (_openingZoneId != null) return;
    _openingZoneId = zone.id;
    try {
      if (!mounted) return;
      final transactionLabel = context.l10nTextRead(
        zone.transactionCount == 1 ? 'transaction' : 'transactions',
      );
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TodaysTransactionsPage(
            transactionReferences: Set<String>.unmodifiable(
              zone.transactionReferences,
            ),
            title: zone.name,
            subtitle: '${zone.transactionCount} $transactionLabel',
            editableTitleValue: zone.customPlaceName,
            onTitleChanged: (placeName) => _savePlaceName(zone, placeName),
          ),
        ),
      );
    } finally {
      _openingZoneId = null;
    }
  }

  void _showLocationMessage(
    String message, {
    Future<void> Function()? openSettings,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(context.l10nTextRead(message)),
        behavior: SnackBarBehavior.floating,
        action: openSettings == null
            ? null
            : SnackBarAction(
                label: context.l10nTextRead('Settings'),
                onPressed: () => unawaited(openSettings()),
              ),
      ),
    );
  }

  Future<void> _goToCurrentLocation() async {
    if (_locatingUser) return;
    setState(() => _locatingUser = true);

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!mounted) return;
        _showLocationMessage(
          'Turn on device location to find your current position.',
          openSettings: Geolocator.openLocationSettings,
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (!mounted) return;

      if (permission == LocationPermission.deniedForever) {
        _showLocationMessage(
          'Location access is blocked. Allow it in system settings.',
          openSettings: Geolocator.openAppSettings,
        );
        return;
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        _showLocationMessage(
          'Location access is needed to show your current position.',
        );
        return;
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
      } on TimeoutException {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null &&
            DateTime.now().difference(lastKnown.timestamp).abs() <=
                const Duration(minutes: 5)) {
          position = lastKnown;
        }
      }
      if (!mounted) return;
      if (position == null) {
        _showLocationMessage('Could not get your current location.');
        return;
      }

      final target = LatLng(position.latitude, position.longitude);
      if (!_ethiopiaMapBounds.contains(target)) {
        _showLocationMessage(
          'Your current location is outside the Ethiopia map area.',
        );
        return;
      }

      final controller = _mapController;
      if (controller == null) return;
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: target, zoom: 16),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _showLocationMessage('Could not get your current location.');
    } finally {
      if (mounted) setState(() => _locatingUser = false);
    }
  }

  Future<void> _fitVisibleLocations() async {
    final controller = _mapController;
    final filtered = _filteredLocations;
    if (controller == null) return;
    if (filtered.isEmpty) {
      try {
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(_ethiopiaCenter, 5.5),
        );
      } catch (_) {
        // The platform view can be disposed while an animation is in flight.
      }
      return;
    }

    final points = filtered
        .map((location) => LatLng(location.latitude, location.longitude))
        .toList(growable: false);
    try {
      if (points.length == 1 || points.toSet().length == 1) {
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(points.first, 14),
        );
        return;
      }
      final minLatitude =
          points.map((point) => point.latitude).reduce(math.min);
      final maxLatitude =
          points.map((point) => point.latitude).reduce(math.max);
      final minLongitude =
          points.map((point) => point.longitude).reduce(math.min);
      final maxLongitude =
          points.map((point) => point.longitude).reduce(math.max);
      if ((maxLatitude - minLatitude).abs() < 0.002 &&
          (maxLongitude - minLongitude).abs() < 0.002) {
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(points.first, 14),
        );
        return;
      }
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLatitude, minLongitude),
            northeast: LatLng(maxLatitude, maxLongitude),
          ),
          48,
        ),
      );
    } catch (_) {
      // The platform view can be disposed while an animation is in flight.
    }
  }

  void _handleCameraMove(CameraPosition position) {
    _pendingZoomLevel = position.zoom;
  }

  void _handleCameraIdle() {
    if (_zoomBucketFor(_pendingZoomLevel) == _zoomBucketFor(_zoomLevel)) {
      return;
    }
    setState(() {
      _zoomLevel = _pendingZoomLevel;
      _puckIcons = const {};
    });
    _refreshPuckIcons();
  }

  Future<void> _showFilters() async {
    final provider = _transactionProvider;
    if (provider == null) return;

    final mappedReferences = _ethiopiaLocations
        .map((location) => location.transactionReference)
        .toSet();
    final transactions = provider.allTransactions
        .where(
          (transaction) => mappedReferences.contains(transaction.reference),
        )
        .toList(growable: false);
    final bankIds = <int>{};
    final accountsByKey = <String, AccountSummary>{};
    final unmatchedBankIds = <int>{};
    final categoryIds = <int>{};
    for (final transaction in transactions) {
      final bankId = transaction.bankId;
      if (bankId != null) bankIds.add(bankId);
      final account = provider.accountSummaryForTransaction(transaction);
      if (account != null) {
        accountsByKey[_mapAccountKey(account)] = account;
      } else if (bankId != null) {
        unmatchedBankIds.add(bankId);
      }
      categoryIds.addAll(provider.categoryIdsForFiltering(transaction));
    }

    final bankLabels = <int, String>{};
    String bankLabel(int bankId) => bankLabels.putIfAbsent(
          bankId,
          () => context.l10nTextRead(provider.getBankShortName(bankId)),
        );
    final sortedBankIds = bankIds.toList(growable: true)
      ..sort(
        (left, right) => compareDisplayText(
          bankLabel(left),
          bankLabel(right),
        ),
      );
    final accounts = accountsByKey.values.toList(growable: true)
      ..sort(
        (left, right) => compareAccountDisplayFields(
          leftBankId: left.bankId,
          rightBankId: right.bankId,
          leftHolderName: left.accountHolderName,
          rightHolderName: right.accountHolderName,
          leftAccountNumber: left.accountNumber,
          rightAccountNumber: right.accountNumber,
          bankNameForId: bankLabel,
        ),
      );
    final categories = orderedCategoriesForFilter(
      categoryIds.map(provider.getCategoryById).whereType<Category>(),
    );

    final selected = await showModalBottomSheet<_SpendingMapFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _SpendingMapFilterSheet(
        initialFilters: _filters,
        bankIds: sortedBankIds,
        accounts: accounts,
        unmatchedBankIds: unmatchedBankIds,
        categories: categories,
        bankLabel: bankLabel,
      ),
    );
    if (!mounted || selected == null || selected == _filters) return;
    setState(() {
      _filters = selected;
      _puckIcons = const {};
    });
    await Future.wait([_refreshPuckIcons(), _fitVisibleLocations()]);
  }

  Future<void> _showMapOptions() async {
    final action = await showModalBottomSheet<_MapOptionsAction>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.cardColor(context),
      builder: (sheetContext) => _MapOptionsSheet(
        displayMode: _mapDisplayMode,
        canDelete: _locations.isNotEmpty,
        onRoadmap: () => Navigator.pop(
          sheetContext,
          _MapOptionsAction.roadmap,
        ),
        onSatellite: () => Navigator.pop(
          sheetContext,
          _MapOptionsAction.satellite,
        ),
        onDelete: () => Navigator.pop(
          sheetContext,
          _MapOptionsAction.deleteLocations,
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _MapOptionsAction.roadmap:
        await _setMapDisplayMode(_MapDisplayMode.roadmap);
      case _MapOptionsAction.satellite:
        await _setMapDisplayMode(_MapDisplayMode.satellite);
      case _MapOptionsAction.deleteLocations:
        await _clearLocations();
    }
  }

  Future<void> _setMapDisplayMode(_MapDisplayMode displayMode) async {
    if (_mapDisplayMode == displayMode) return;
    setState(() => _mapDisplayMode = displayMode);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _mapDisplayModePreferenceKey,
        displayMode.name,
      );
    } catch (error) {
      debugPrint('debug: Could not save Spending Map style: $error');
    }
  }

  Future<void> _clearLocations() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10nText('Delete saved locations?')),
        content: Text(
          dialogContext.l10nText(
            'This permanently removes all saved transaction locations for '
            'the active profile. Your transactions will not be deleted.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.l10nText('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
            child: Text(dialogContext.l10nText('Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.clearForActiveProfile();
    if (!mounted) return;
    _mapController = null;
    setState(() {
      _locations = const [];
      _puckIcons = const {};
      _puckGeneration += 1;
      _mapReady = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasEthiopiaLocations = _ethiopiaLocations.isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: switch ((_loading, _loadError, hasEthiopiaLocations)) {
        (true, _, _) => _MapStatusShell(
            onBack: () => Navigator.maybePop(context),
            onOptions: _showMapOptions,
            child: const CircularProgressIndicator(),
          ),
        (false, final Object error, _) => _MapStatusShell(
            onBack: () => Navigator.maybePop(context),
            onOptions: _showMapOptions,
            child: _ErrorState(
              message: error.toString(),
              onRetry: _loadLocations,
            ),
          ),
        (false, null, false) => _MapStatusShell(
            onBack: () => Navigator.maybePop(context),
            onOptions: _showMapOptions,
            child: const _EmptyMapState(),
          ),
        _ => _buildMap(context),
      },
    );
  }

  Widget _buildMap(BuildContext context) {
    final filtered = _filteredLocations;
    final zones = _buildZones(filtered);
    final ethiopiaLocations = _ethiopiaLocations;
    final initialCenter = ethiopiaLocations.isEmpty
        ? _ethiopiaCenter
        : _averageCenter(ethiopiaLocations);
    final mediaPadding = MediaQuery.paddingOf(context);

    return Stack(
      children: [
        Positioned.fill(
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: initialCenter,
              zoom: 10,
            ),
            mapType: _mapDisplayMode == _MapDisplayMode.satellite
                ? MapType.hybrid
                : MapType.normal,
            style: AppColors.isDark(context) &&
                    _mapDisplayMode == _MapDisplayMode.roadmap
                ? _darkRoadMapStyle
                : null,
            markers: _buildZoneMarkers(zones),
            cameraTargetBounds: CameraTargetBounds(_ethiopiaMapBounds),
            minMaxZoomPreference: const MinMaxZoomPreference(5, 20),
            padding: EdgeInsets.fromLTRB(
              12,
              mediaPadding.top + 76,
              12,
              mediaPadding.bottom + 68,
            ),
            compassEnabled: false,
            mapToolbarEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            buildingsEnabled: true,
            onMapCreated: (controller) {
              _mapController = controller;
              if (mounted) setState(() => _mapReady = true);
              _fitVisibleLocations();
            },
            onCameraMove: _handleCameraMove,
            onCameraIdle: _handleCameraIdle,
          ),
        ),
        if (!_mapReady)
          const Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: Color(0x33FFFFFF),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            minimum: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: _FloatingMapHeader(
              mappedCount: filtered.length,
              activeFilterCount: _filters.activeCount,
              onBack: () => Navigator.maybePop(context),
              onFilter: _showFilters,
              onOptions: _showMapOptions,
            ),
          ),
        ),
        Positioned(
          right: 14,
          bottom: mediaPadding.bottom + 16,
          child: _MapActionButton(
            icon: AppIcons.myLocationRounded,
            tooltip: context.l10nText('Go to current location'),
            onTap: _goToCurrentLocation,
            loading: _locatingUser,
          ),
        ),
      ],
    );
  }

  LatLng _averageCenter(List<TransactionLocation> locations) {
    final longitude = locations.fold<double>(
          0,
          (sum, location) => sum + location.longitude,
        ) /
        locations.length;
    final latitude = locations.fold<double>(
          0,
          (sum, location) => sum + location.latitude,
        ) /
        locations.length;
    return LatLng(latitude, longitude);
  }
}

class _FloatingMapHeader extends StatelessWidget {
  const _FloatingMapHeader({
    required this.mappedCount,
    required this.activeFilterCount,
    required this.onBack,
    this.onFilter,
    required this.onOptions,
  });

  final int mappedCount;
  final int activeFilterCount;
  final VoidCallback onBack;
  final VoidCallback? onFilter;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MapActionButton(
          icon: AppIcons.arrow_back_rounded,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onTap: onBack,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Align(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: _MapIdentityPill(
                mappedCount: mappedCount,
                onTap: onOptions,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        if (onFilter != null)
          _MapFilterActionButton(
            activeCount: activeFilterCount,
            onTap: onFilter!,
          )
        else
          const SizedBox(width: 44),
      ],
    );
  }
}

class _MapIdentityPill extends StatelessWidget {
  const _MapIdentityPill({
    required this.mappedCount,
    required this.onTap,
  });

  final int mappedCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.l10nText('Map options'),
      child: Material(
        color: AppColors.cardColor(context).withValues(alpha: 0.96),
        elevation: 5,
        shadowColor: AppColors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(7, 6, 14, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primaryLight,
                  ),
                  child: const Icon(
                    AppIcons.map_rounded,
                    color: AppColors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 9),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10nText('Spending Map'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        context.l10nText(
                          '$mappedCount '
                          '${mappedCount == 1 ? 'transaction' : 'transactions'}',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MapActionButton extends StatelessWidget {
  const _MapActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    const borderRadius = 10.0;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.cardColor(context).withValues(alpha: 0.96),
        elevation: 3,
        shadowColor: AppColors.black.withValues(alpha: 0.14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
          side: BorderSide(color: AppColors.borderColor(context)),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: SizedBox(
            width: 44,
            height: 44,
            child: loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Icon(
                    icon,
                    color: AppColors.textSecondary(context),
                    size: 22,
                  ),
          ),
        ),
      ),
    );
  }
}

class _MapFilterActionButton extends StatelessWidget {
  const _MapFilterActionButton({
    required this.activeCount,
    required this.onTap,
  });

  final int activeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isActive = activeCount > 0;
    const borderRadius = 10.0;
    return Tooltip(
      message: context.l10nText('Filter map'),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: isActive
                ? AppColors.primaryDark.withValues(alpha: 0.1)
                : AppColors.cardColor(context).withValues(alpha: 0.96),
            elevation: 3,
            shadowColor: AppColors.black.withValues(alpha: 0.14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(borderRadius),
              side: BorderSide(
                color: isActive
                    ? AppColors.primaryDark
                    : AppColors.borderColor(context),
              ),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(borderRadius),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  AppIcons.filter_list,
                  color: isActive
                      ? AppColors.primaryDark
                      : AppColors.textSecondary(context),
                  size: 22,
                ),
              ),
            ),
          ),
          if (isActive)
            Positioned(
              top: -3,
              right: -3,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: const BoxDecoration(
                  color: AppColors.primaryDark,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$activeCount',
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SpendingMapFilterSheet extends StatefulWidget {
  const _SpendingMapFilterSheet({
    required this.initialFilters,
    required this.bankIds,
    required this.accounts,
    required this.unmatchedBankIds,
    required this.categories,
    required this.bankLabel,
  });

  final _SpendingMapFilters initialFilters;
  final List<int> bankIds;
  final List<AccountSummary> accounts;
  final Set<int> unmatchedBankIds;
  final List<Category> categories;
  final String Function(int bankId) bankLabel;

  @override
  State<_SpendingMapFilterSheet> createState() =>
      _SpendingMapFilterSheetState();
}

class _SpendingMapFilterSheetState extends State<_SpendingMapFilterSheet> {
  late String? _selectedType;
  late int? _selectedBankId;
  late String? _selectedAccountKey;
  late Set<int> _selectedCategoryIds;
  late final TextEditingController _minAmountController;
  late final TextEditingController _maxAmountController;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _amountError;

  @override
  void initState() {
    super.initState();
    final filters = widget.initialFilters;
    _selectedType = filters.type;
    _selectedBankId = filters.bankId;
    _selectedAccountKey = filters.accountKey;
    _selectedCategoryIds = <int>{...filters.categoryIds};
    _minAmountController = TextEditingController(
      text: _formatAmount(filters.minAmount),
    );
    _maxAmountController = TextEditingController(
      text: _formatAmount(filters.maxAmount),
    );
    _startDate = filters.startDate;
    _endDate = filters.endDate;
  }

  @override
  void dispose() {
    _minAmountController.dispose();
    _maxAmountController.dispose();
    super.dispose();
  }

  List<AccountSummary> get _visibleAccounts => _selectedBankId == null
      ? widget.accounts
      : widget.accounts
          .where((account) => account.bankId == _selectedBankId)
          .toList(growable: false);

  List<int> get _visibleUnmatchedBankIds => widget.unmatchedBankIds
      .where(
        (bankId) => _selectedBankId == null || bankId == _selectedBankId,
      )
      .toList(growable: false)
    ..sort(
      (left, right) => compareDisplayText(
        widget.bankLabel(left),
        widget.bankLabel(right),
      ),
    );

  void _selectBank(int? bankId) {
    setState(() {
      _selectedBankId = bankId;
      if (_selectedAccountKey == null) return;
      final accountVisible = _visibleAccounts.any(
        (account) => _mapAccountKey(account) == _selectedAccountKey,
      );
      final otherVisible = _visibleUnmatchedBankIds.any(
        (candidate) => _mapOtherAccountKey(candidate) == _selectedAccountKey,
      );
      if (!accountVisible && !otherVisible) _selectedAccountKey = null;
    });
  }

  void _toggleCategory(int categoryId) {
    setState(() {
      if (!_selectedCategoryIds.add(categoryId)) {
        _selectedCategoryIds.remove(categoryId);
      }
    });
  }

  void _clearAll() {
    setState(() {
      _selectedType = null;
      _selectedBankId = null;
      _selectedAccountKey = null;
      _selectedCategoryIds.clear();
      _minAmountController.clear();
      _maxAmountController.clear();
      _startDate = null;
      _endDate = null;
      _amountError = null;
    });
  }

  void _apply() {
    final min = _parseAmount(_minAmountController.text);
    final max = _parseAmount(_maxAmountController.text);
    final minInvalid =
        _minAmountController.text.trim().isNotEmpty && min == null;
    final maxInvalid =
        _maxAmountController.text.trim().isNotEmpty && max == null;
    if (minInvalid || maxInvalid) {
      setState(() => _amountError = 'Enter a valid amount');
      return;
    }
    if (min != null && max != null && max < min) {
      setState(() => _amountError = 'Maximum must be at least minimum.');
      return;
    }

    Navigator.of(context).pop(
      _SpendingMapFilters(
        type: _selectedType,
        bankId: _selectedBankId,
        accountKey: _selectedAccountKey,
        categoryIds: Set<int>.unmodifiable(_selectedCategoryIds),
        minAmount: min,
        maxAmount: max,
        startDate: _startDate,
        endDate: _endDate,
      ),
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initialDate = (isStart ? _startDate : _endDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (pickerContext, child) {
        final dark = AppColors.isDark(pickerContext);
        return Theme(
          data: Theme.of(pickerContext).copyWith(
            colorScheme: dark
                ? const ColorScheme.dark(
                    primary: AppColors.primaryLight,
                    onPrimary: AppColors.white,
                    surface: AppColors.darkCard,
                    onSurface: AppColors.white,
                  )
                : const ColorScheme.light(
                    primary: AppColors.primaryDark,
                    onPrimary: AppColors.white,
                    surface: AppColors.white,
                    onSurface: AppColors.slate900,
                  ),
          ),
          child: child!,
        );
      },
    );
    if (!mounted || picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  String _formatDate(DateTime date) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return DateFormat.yMMMd(locale).format(date);
  }

  double? _parseAmount(String raw) {
    final normalized = raw.trim().replaceAll(',', '');
    return normalized.isEmpty ? null : double.tryParse(normalized);
  }

  String _formatAmount(double? amount) {
    if (amount == null) return '';
    if (amount == amount.roundToDouble()) return amount.toStringAsFixed(0);
    return amount
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String _accountLabel(AccountSummary account) {
    final holder = account.accountHolderName.trim();
    final identity = holder.isEmpty
        ? account.accountNumber
        : '$holder • ${account.accountNumber}';
    return _selectedBankId == null
        ? '${widget.bankLabel(account.bankId)} • $identity'
        : identity;
  }

  String _otherLabel(int bankId) {
    final other = context.l10nText('Other transactions');
    return _selectedBankId == null
        ? '${widget.bankLabel(bankId)} • $other'
        : other;
  }

  Widget _sectionLabel(String label) {
    return Text(
      context.l10nText(label),
      style: TextStyle(
        color: AppColors.textSecondary(context),
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.7,
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      label: Text(context.l10nText(label)),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primaryLight.withValues(alpha: 0.14),
      backgroundColor: AppColors.surfaceColor(context),
      side: BorderSide(
        color:
            selected ? AppColors.primaryLight : AppColors.borderColor(context),
      ),
      labelStyle: TextStyle(
        color:
            selected ? AppColors.primaryLight : AppColors.textPrimary(context),
        fontSize: 13,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    );
  }

  Widget _amountField(
    TextEditingController controller,
    String hint, {
    TextInputAction? textInputAction,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: textInputAction,
      onChanged: (_) {
        if (_amountError != null) setState(() => _amountError = null);
      },
      decoration: InputDecoration(
        hintText: context.l10nText(hint),
        prefixText: 'ETB ',
        isDense: true,
        filled: true,
        fillColor: AppColors.surfaceColor(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.borderColor(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.borderColor(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primaryLight),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.86,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.slate400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10nText('Filter Spending Map'),
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(
                    AppIcons.close,
                    color: AppColors.textSecondary(context),
                  ),
                  splashRadius: 20,
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                16 + viewInsets + bottomPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('TYPE'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _chip(
                        label: 'All',
                        selected: _selectedType == null,
                        onTap: () => setState(() => _selectedType = null),
                      ),
                      _chip(
                        label: 'Expense',
                        selected: _selectedType == 'DEBIT',
                        onTap: () => setState(() => _selectedType = 'DEBIT'),
                      ),
                      _chip(
                        label: 'Income',
                        selected: _selectedType == 'CREDIT',
                        onTap: () => setState(() => _selectedType = 'CREDIT'),
                      ),
                    ],
                  ),
                  if (widget.bankIds.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _sectionLabel('BANK'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chip(
                          label: 'All Banks',
                          selected: _selectedBankId == null,
                          onTap: () => _selectBank(null),
                        ),
                        for (final bankId in widget.bankIds)
                          _chip(
                            label: widget.bankLabel(bankId),
                            selected: _selectedBankId == bankId,
                            onTap: () => _selectBank(bankId),
                          ),
                      ],
                    ),
                  ],
                  if (widget.accounts.isNotEmpty ||
                      widget.unmatchedBankIds.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _sectionLabel('ACCOUNT'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chip(
                          label: 'All account activity',
                          selected: _selectedAccountKey == null,
                          onTap: () =>
                              setState(() => _selectedAccountKey = null),
                        ),
                        for (final account in _visibleAccounts)
                          _chip(
                            label: _accountLabel(account),
                            selected:
                                _selectedAccountKey == _mapAccountKey(account),
                            onTap: () => setState(
                              () =>
                                  _selectedAccountKey = _mapAccountKey(account),
                            ),
                          ),
                        for (final bankId in _visibleUnmatchedBankIds)
                          _chip(
                            label: _otherLabel(bankId),
                            selected: _selectedAccountKey ==
                                _mapOtherAccountKey(bankId),
                            onTap: () => setState(
                              () => _selectedAccountKey =
                                  _mapOtherAccountKey(bankId),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  _sectionLabel('CATEGORY'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      CategoryFilterChip(
                        label: 'All',
                        selected: _selectedCategoryIds.isEmpty,
                        onTap: () =>
                            setState(() => _selectedCategoryIds.clear()),
                      ),
                      CategoryFilterChip(
                        label: 'Uncategorized',
                        selected: _selectedCategoryIds.contains(
                          uncategorizedCategoryFilterId,
                        ),
                        onTap: () => _toggleCategory(
                          uncategorizedCategoryFilterId,
                        ),
                      ),
                      for (final category in widget.categories)
                        if (category.id != null)
                          CategoryFilterChip(
                            label: category.name,
                            flow: category.flow,
                            subtleFlowTint: isSelfCategoryFilter(category),
                            selected:
                                _selectedCategoryIds.contains(category.id),
                            onTap: () => _toggleCategory(category.id!),
                          ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel('AMOUNT RANGE'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _amountField(
                          _minAmountController,
                          'Min',
                          textInputAction: TextInputAction.next,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _amountField(
                          _maxAmountController,
                          'Max',
                          textInputAction: TextInputAction.done,
                        ),
                      ),
                    ],
                  ),
                  if (_amountError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      context.l10nText(_amountError!),
                      style: const TextStyle(
                        color: AppColors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _sectionLabel('DATE RANGE'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _SpendingMapDatePickerField(
                          hint: 'Start date',
                          value: _startDate == null
                              ? null
                              : _formatDate(_startDate!),
                          onTap: () => _pickDate(isStart: true),
                          onClear: _startDate == null
                              ? null
                              : () => setState(() => _startDate = null),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SpendingMapDatePickerField(
                          hint: 'End date',
                          value:
                              _endDate == null ? null : _formatDate(_endDate!),
                          onTap: () => _pickDate(isStart: false),
                          onClear: _endDate == null
                              ? null
                              : () => setState(() => _endDate = null),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _clearAll,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textSecondary(context),
                            side: BorderSide(
                              color: AppColors.borderColor(context),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            context.l10nText('Clear All'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _apply,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryDark,
                            foregroundColor: AppColors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            context.l10nText('Apply Filters'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpendingMapDatePickerField extends StatelessWidget {
  const _SpendingMapDatePickerField({
    required this.hint,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  final String hint;
  final String? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceColor(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderColor(context)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value ?? context.l10nText(hint),
                style: TextStyle(
                  color: value == null
                      ? AppColors.textTertiary(context)
                      : AppColors.textPrimary(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(
                  AppIcons.close,
                  size: 16,
                  color: AppColors.textTertiary(context),
                ),
              )
            else
              Icon(
                AppIcons.calendar_today_outlined,
                size: 16,
                color: AppColors.textTertiary(context),
              ),
          ],
        ),
      ),
    );
  }
}

class _MapStatusShell extends StatelessWidget {
  const _MapStatusShell({
    required this.onBack,
    required this.onOptions,
    required this.child,
  });

  final VoidCallback onBack;
  final VoidCallback onOptions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.background(context),
            ),
            child: CustomPaint(painter: _MapBackdropPainter(isDark: isDark)),
          ),
        ),
        Positioned(
          top: 10,
          left: 14,
          right: 14,
          child: SafeArea(
            bottom: false,
            child: _FloatingMapHeader(
              mappedCount: 0,
              activeFilterCount: 0,
              onBack: onBack,
              onOptions: onOptions,
            ),
          ),
        ),
        Positioned.fill(
          child: SafeArea(
            minimum: const EdgeInsets.fromLTRB(24, 92, 24, 24),
            child: Center(child: child),
          ),
        ),
      ],
    );
  }
}

class _MapBackdropPainter extends CustomPainter {
  const _MapBackdropPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final roadPaint = Paint()
      ..color = (isDark ? AppColors.white : AppColors.white).withValues(
        alpha: isDark ? 0.055 : 0.72,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(-30, size.height * 0.32)
      ..cubicTo(
        size.width * 0.22,
        size.height * 0.18,
        size.width * 0.36,
        size.height * 0.58,
        size.width * 0.62,
        size.height * 0.46,
      )
      ..cubicTo(
        size.width * 0.8,
        size.height * 0.38,
        size.width * 0.82,
        size.height * 0.68,
        size.width + 30,
        size.height * 0.62,
      );
    canvas.drawPath(path, roadPaint);

    final minorRoadPaint = Paint()
      ..color = roadPaint.color.withValues(alpha: isDark ? 0.04 : 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final minorPath = Path()
      ..moveTo(size.width * 0.08, size.height + 20)
      ..cubicTo(
        size.width * 0.3,
        size.height * 0.72,
        size.width * 0.45,
        size.height * 0.88,
        size.width * 0.52,
        -20,
      );
    canvas.drawPath(minorPath, minorRoadPaint);

    final pulsePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.primaryLight.withValues(alpha: 0.22),
          AppColors.primaryLight.withValues(alpha: 0),
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.77, size.height * 0.3),
          radius: 70,
        ),
      );
    canvas.drawCircle(
      Offset(size.width * 0.77, size.height * 0.3),
      70,
      pulsePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _MapBackdropPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

class _MapOptionsSheet extends StatelessWidget {
  const _MapOptionsSheet({
    required this.displayMode,
    required this.canDelete,
    required this.onRoadmap,
    required this.onSatellite,
    required this.onDelete,
  });

  final _MapDisplayMode displayMode;
  final bool canDelete;
  final VoidCallback onRoadmap;
  final VoidCallback onSatellite;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10nText('Your private spending map'),
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10nText(
              'Numbered transaction pucks are built on your device. Totals '
              'does not upload your transaction amounts or saved transaction '
              'coordinates.',
            ),
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            context.l10nText('MAP STYLE'),
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 4),
          _MapOptionRow(
            icon: AppIcons.map_rounded,
            title: context.l10nText('Default map'),
            subtitle: context.l10nText(
              'Google road map with places, roads, and transit',
            ),
            selected: displayMode == _MapDisplayMode.roadmap,
            onTap: onRoadmap,
          ),
          _MapOptionRow(
            icon: AppIcons.satelliteView,
            title: context.l10nText('Satellite'),
            subtitle: context.l10nText(
              'Satellite imagery with roads and place labels',
            ),
            selected: displayMode == _MapDisplayMode.satellite,
            onTap: onSatellite,
          ),
          Divider(color: AppColors.borderColor(context)),
          _MapOptionRow(
            icon: AppIcons.shield_check,
            title: context.l10nText('Stored locally'),
            subtitle: context.l10nText(
              'Saved transaction coordinates stay in the Totals database.',
            ),
          ),
          if (canDelete)
            _MapOptionRow(
              icon: AppIcons.delete_outline_rounded,
              title: context.l10nText('Delete saved locations'),
              subtitle: context.l10nText(
                'Keep transactions and permanently remove map coordinates',
              ),
              foregroundColor: AppColors.red,
              onTap: onDelete,
            ),
        ],
      ),
    );
  }
}

class _MapOptionRow extends StatelessWidget {
  const _MapOptionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.foregroundColor,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color? foregroundColor;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = foregroundColor ??
        (selected ? AppColors.primaryLight : AppColors.textPrimary(context));
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: foreground.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: foreground, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(color: foreground, fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: AppColors.textSecondary(context),
          fontSize: 11,
        ),
      ),
      trailing: selected
          ? const Icon(
              AppIcons.check_rounded,
              color: AppColors.primaryLight,
              size: 20,
            )
          : null,
    );
  }
}

class _EmptyMapState extends StatelessWidget {
  const _EmptyMapState();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primaryLight,
            ),
            child: const Icon(
              AppIcons.map_pin_rounded,
              color: AppColors.white,
              size: 34,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            context.l10nText('Your map is ready'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10nText(
              'New debit and credit transactions will appear here after '
              'Totals captures their location. Existing transactions are not '
              'backfilled.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(AppIcons.map_rounded, color: AppColors.red, size: 38),
          const SizedBox(height: 12),
          Text(
            context.l10nText('Could not load Spending Map'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onRetry,
            child: Text(context.l10nText('Try again')),
          ),
        ],
      ),
    );
  }
}
