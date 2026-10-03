import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint, setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/_redesign/screens/todays_transactions_page.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/_redesign/widgets/category_filter_chip.dart';
import 'package:totals/_redesign/widgets/place_name_editor_sheet.dart';
import 'package:totals/_redesign/widgets/saved_location_editor_sheet.dart';
import 'package:totals/l10n/app_localizations.dart';
import 'package:totals/models/category.dart';
import 'package:totals/models/saved_location.dart';
import 'package:totals/models/summary_models.dart';
import 'package:totals/models/transaction_location.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/repositories/saved_location_repository.dart';
import 'package:totals/repositories/transaction_location_repository.dart';
import 'package:totals/services/offline_place_gazetteer.dart';
import 'package:totals/utils/account_sort.dart';
import 'package:totals/utils/category_filter_utils.dart';
import 'package:totals/utils/spending_map_clustering.dart';
import 'package:totals/utils/spending_map_metrics.dart';
import 'package:url_launcher/url_launcher.dart';

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
const _puckIconSourceSize = 160.0;
const _placeLabelIconSourceWidth = 460.0;
const _placeLabelIconSourceHeight = 170.0;
const _placeLabelCenterX = _placeLabelIconSourceWidth / 2;
const _puckIconScale = 54 / 160;
const _puckMarkerAnchor = Offset(0.5, 0.5);
const _placeLabelMarkerAnchor = Offset(0.5, 1);
const _savedLocationMarkerAnchor = Offset(0.5, 104 / 170);

enum _MapDisplayMode { roadmap, satellite }

enum _MapOptionsAction {
  roadmap,
  satellite,
  openOvertureAttribution,
  openAddisCadastreSource,
  deleteLocations,
}

class _SpendingMapFilters {
  const _SpendingMapFilters({
    this.puckMetric = SpendingMapPuckMetric.transactionCount,
    this.type,
    this.bankId,
    this.accountKey,
    this.categoryIds = const <int>{},
    this.minAmount,
    this.maxAmount,
    this.startDate,
    this.endDate,
  });

  final SpendingMapPuckMetric puckMetric;
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
      other.puckMetric == puckMetric &&
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
        puckMetric,
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

class _SpendingZone {
  const _SpendingZone({
    required this.id,
    required this.name,
    required this.puckPlaceLabel,
    required this.center,
    required this.transactionCount,
    required this.netAmount,
    required this.transactionReferences,
    required this.savedLocationIds,
    required this.customPlaceName,
  });

  final String id;
  final String name;
  final String puckPlaceLabel;
  final LatLng center;
  final int transactionCount;
  final double netAmount;
  final List<String> transactionReferences;
  final List<String> savedLocationIds;
  final String? customPlaceName;

  bool get isSavedLocationCluster =>
      transactionCount == 0 && savedLocationIds.length > 1;

  List<String> get membershipKeys => <String>[
        ...transactionReferences.map(
          (reference) => 'transaction:$reference',
        ),
        ...savedLocationIds.map((id) => 'saved:$id'),
      ];
}

class _SpendingMapClusterMember {
  const _SpendingMapClusterMember.transaction(
    TransactionLocation this.transactionLocation,
  ) : savedLocation = null;

  const _SpendingMapClusterMember.saved(
    SavedLocation this.savedLocation,
  ) : transactionLocation = null;

  final TransactionLocation? transactionLocation;
  final SavedLocation? savedLocation;

  double get latitude =>
      transactionLocation?.latitude ?? savedLocation!.latitude;
  double get longitude =>
      transactionLocation?.longitude ?? savedLocation!.longitude;
  String get stableKey => transactionLocation != null
      ? 'transaction:${transactionLocation!.transactionReference}'
      : 'saved:${savedLocation!.id}';
}

class _ZoneAccumulator {
  double netAmount = 0;
  int count = 0;
  final Set<String> transactionReferences = <String>{};
  final List<TransactionLocation> locations = <TransactionLocation>[];

  void add(TransactionLocation location) {
    netAmount += spendingMapNetContribution(
      transactionType: location.transactionType,
      amount: location.amount,
    );
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

class _PuckMotion {
  const _PuckMotion({
    required this.markerId,
    required this.puckIcon,
    required this.placeLabelIcon,
    required this.from,
    required this.to,
    required this.fromAlpha,
    required this.toAlpha,
    required this.zIndex,
  });

  final String markerId;
  final BitmapDescriptor puckIcon;
  final BitmapDescriptor placeLabelIcon;
  final LatLng from;
  final LatLng to;
  final double fromAlpha;
  final double toAlpha;
  final int zIndex;

  LatLng positionAt(double progress) {
    return LatLng(
      from.latitude + ((to.latitude - from.latitude) * progress),
      from.longitude + ((to.longitude - from.longitude) * progress),
    );
  }

  double alphaAt(double progress) {
    return fromAlpha + ((toAlpha - fromAlpha) * progress);
  }
}

String _spendingZoneId(List<String> sortedReferences) {
  var hash = 0xcbf29ce484222325;
  for (final reference in sortedReferences) {
    for (final codeUnit in reference.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
    }
    hash ^= 0xff;
    hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
  }
  return '${sortedReferences.length}-${hash.toRadixString(16)}';
}

class SpendingMapPage extends StatefulWidget {
  const SpendingMapPage({
    super.key,
    this.transactionLocationRepository,
    this.savedLocationRepository,
  });

  final TransactionLocationRepository? transactionLocationRepository;
  final SavedLocationRepository? savedLocationRepository;

  @override
  State<SpendingMapPage> createState() => _SpendingMapPageState();
}

class _SpendingMapPageState extends State<SpendingMapPage>
    with SingleTickerProviderStateMixin {
  static const _puckTransitionDuration = Duration(milliseconds: 240);

  late final TransactionLocationRepository _repository;
  late final SavedLocationRepository _savedLocationRepository;

  TransactionProvider? _transactionProvider;
  OfflinePlaceGazetteer? _offlineGazetteer;
  List<TransactionLocation> _locations = const [];
  List<SavedLocation> _savedLocations = const [];
  _SpendingMapFilters _filters = const _SpendingMapFilters();
  List<_SpendingZone> _displayedZones = const [];
  Map<String, BitmapDescriptor> _puckIcons = const {};
  Map<String, BitmapDescriptor> _placeLabelIcons = const {};
  Map<String, BitmapDescriptor> _savedLocationIcons = const {};
  final Map<String, BitmapDescriptor> _puckIconCache = {};
  final Map<String, BitmapDescriptor> _placeLabelIconCache = {};
  List<_PuckMotion> _puckMotions = const [];
  List<_SpendingZone>? _puckTransitionTargetZones;
  Map<String, BitmapDescriptor> _puckTransitionTargetIcons = const {};
  Map<String, BitmapDescriptor> _puckTransitionTargetPlaceLabelIcons = const {};
  late final AnimationController _puckTransitionController;
  int _puckGeneration = 0;
  double _zoomLevel = 10;
  double _pendingZoomLevel = 10;
  bool _cameraMoving = false;
  GoogleMapController? _mapController;
  bool _loading = true;
  bool _mapReady = false;
  bool _locatingUser = false;
  String? _openingZoneId;
  String? _editingZoneId;
  String? _editingSavedLocationId;
  String _languageCode = 'en';
  _MapDisplayMode _mapDisplayMode = _MapDisplayMode.roadmap;
  Object? _loadError;

  List<TransactionLocation> get _ethiopiaLocations => _locations
      .where(
        (location) => _ethiopiaMapBounds.contains(
          LatLng(location.latitude, location.longitude),
        ),
      )
      .toList(growable: false);

  List<SavedLocation> get _ethiopiaSavedLocations => _savedLocations
      .where(
        (location) => _ethiopiaMapBounds.contains(
          LatLng(location.latitude, location.longitude),
        ),
      )
      .toList(growable: false);

  Set<String> get _assignedSavedLocationIds => _locations
      .map((location) => location.savedLocationId)
      .whereType<String>()
      .toSet();

  List<SavedLocation> get _unassignedSavedLocations {
    final assignedIds = _assignedSavedLocationIds;
    return _ethiopiaSavedLocations
        .where((location) => !assignedIds.contains(location.id))
        .toList(growable: false);
  }

  List<TransactionLocation> get _filteredLocations {
    final locationFiltered = _ethiopiaLocations
        .where(_filters.matchesLocation)
        .toList(growable: false);
    final provider = _transactionProvider;
    if (provider == null) {
      return locationFiltered;
    }

    final transactionsByReference = {
      for (final transaction in provider.allTransactions)
        transaction.reference: transaction,
    };
    return locationFiltered.where((location) {
      final transaction =
          transactionsByReference[location.transactionReference];
      if (transaction != null && provider.isExcludedFromTotals(transaction)) {
        return false;
      }
      if (!_filters.hasTransactionFilters) return true;
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
    _repository =
        widget.transactionLocationRepository ?? TransactionLocationRepository();
    _savedLocationRepository =
        widget.savedLocationRepository ?? SavedLocationRepository();
    _puckTransitionController = AnimationController(
      vsync: this,
      duration: _puckTransitionDuration,
    )
      ..addListener(_handlePuckTransitionTick)
      ..addStatusListener(_handlePuckTransitionStatus);
    _loadLocations();
  }

  @override
  void dispose() {
    _puckGeneration += 1;
    _puckTransitionController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _languageCode = Localizations.localeOf(context).languageCode;
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
      OfflinePlaceGazetteer? offlineGazetteer = _offlineGazetteer;
      if (offlineGazetteer == null) {
        try {
          offlineGazetteer = await OfflinePlaceGazetteer.loadEthiopianCities();
        } catch (error) {
          debugPrint('Could not load the offline city gazetteer: $error');
        }
      }
      final locations = await _repository.getTransactionLocations();
      final savedLocations = await _savedLocationRepository.getSavedLocations();
      if (!mounted) return;
      setState(() {
        _offlineGazetteer = offlineGazetteer;
        _locations = locations;
        _savedLocations = savedLocations;
        _mapDisplayMode = displayMode;
        _loading = false;
      });
      await _refreshPuckIcons();
      await _refreshSavedLocationIcons();
      await _fitVisibleLocations();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  List<_SpendingZone> _buildZones(
    List<TransactionLocation> locations, {
    required double zoom,
  }) {
    final clusterMembers = <_SpendingMapClusterMember>[
      ...locations.map(_SpendingMapClusterMember.transaction),
      ..._unassignedSavedLocations.map(_SpendingMapClusterMember.saved),
    ];
    if (clusterMembers.isEmpty) return const [];
    final averageLatitude = clusterMembers.fold<double>(
          0,
          (sum, member) => sum + member.latitude,
        ) /
        clusterMembers.length;
    final clusters = clusterSpendingMapLocations<_SpendingMapClusterMember>(
      locations: clusterMembers,
      latitudeOf: (member) => member.latitude,
      longitudeOf: (member) => member.longitude,
      stableKeyOf: (member) => member.stableKey,
      radiusMeters: spendingMapGroupingRadiusMeters(
        zoom: zoom,
        latitude: averageLatitude,
      ),
    );

    final zones = <_SpendingZone>[];
    for (final cluster in clusters) {
      final bucket = _ZoneAccumulator();
      for (final member in cluster.members) {
        final transactionLocation = member.transactionLocation;
        if (transactionLocation != null) bucket.add(transactionLocation);
      }
      final savedLocationIds = cluster.members
          .map((member) => member.savedLocation?.id)
          .whereType<String>()
          .toList(growable: true)
        ..sort();
      // Keep a lone empty saved place as a draggable pin. Multiple empty
      // saved places use the same animated puck lifecycle as transactions.
      if (!spendingMapClusterUsesPuck(
        transactionCount: bucket.count,
        savedLocationCount: savedLocationIds.length,
      )) {
        continue;
      }

      final center = LatLng(cluster.latitude, cluster.longitude);
      final references = bucket.transactionReferences.toList(growable: true)
        ..sort();
      final membershipKeys = <String>[
        ...references.map((reference) => 'transaction:$reference'),
        ...savedLocationIds.map((id) => 'saved:$id'),
      ]..sort();
      final customPlaceName = bucket.customPlaceName;
      final placeSummary = summarizeSpendingMapPlaceNames(
            cluster.members.map((member) {
              final savedLocation = member.savedLocation;
              if (savedLocation != null) return savedLocation.name;
              final transactionLocation = member.transactionLocation!;
              return transactionLocation.placeName ??
                  _approximatePlaceName(
                    LatLng(
                      transactionLocation.latitude,
                      transactionLocation.longitude,
                    ),
                  );
            }),
            customNames: cluster.members
                .map((member) =>
                    member.savedLocation?.name ??
                    member.transactionLocation?.placeName)
                .whereType<String>(),
          ) ??
          SpendingMapPlaceSummary(
            mainName: _approximatePlaceName(center),
            otherNameCount: 0,
          );
      zones.add(_SpendingZone(
        id: _spendingZoneId(membershipKeys),
        name: placeSummary.mainName,
        puckPlaceLabel: placeSummary.label,
        center: center,
        transactionCount: bucket.count,
        netAmount: bucket.netAmount,
        transactionReferences: List<String>.unmodifiable(references),
        savedLocationIds: List<String>.unmodifiable(savedLocationIds),
        customPlaceName: customPlaceName,
      ));
    }

    zones.sort((first, second) {
      final countComparison =
          second.transactionCount.compareTo(first.transactionCount);
      return countComparison != 0
          ? countComparison
          : first.id.compareTo(second.id);
    });
    return zones;
  }

  String _approximatePlaceName(LatLng point) {
    return ethiopiaPlaceNameForCoordinates(
      latitude: point.latitude,
      longitude: point.longitude,
      languageCode: _languageCode,
      gazetteer: _offlineGazetteer,
    );
  }

  Set<Marker> _buildZoneMarkers() {
    if (_puckMotions.isNotEmpty) {
      final progress = Curves.easeInOutCubic.transform(
        _puckTransitionController.value,
      );
      return _puckMotions.expand((motion) {
        final position = motion.positionAt(progress);
        final alpha = motion.alphaAt(progress).clamp(0.0, 1.0).toDouble();
        return <Marker>[
          Marker(
            markerId: MarkerId('zone-label-${motion.markerId}'),
            position: position,
            alpha: alpha,
            anchor: _placeLabelMarkerAnchor,
            icon: motion.placeLabelIcon,
            consumeTapEvents: true,
            zIndexInt: motion.zIndex,
          ),
          Marker(
            markerId: MarkerId('zone-puck-${motion.markerId}'),
            position: position,
            alpha: alpha,
            anchor: _puckMarkerAnchor,
            icon: motion.puckIcon,
            consumeTapEvents: true,
            zIndexInt: motion.zIndex + 2,
          ),
        ];
      }).toSet();
    }

    return _displayedZones
        .take(50)
        .where(
          (zone) =>
              _puckIcons[zone.id] != null && _placeLabelIcons[zone.id] != null,
        )
        .expand((zone) {
      return <Marker>[
        Marker(
          markerId: MarkerId('zone-label-${zone.id}'),
          position: zone.center,
          anchor: _placeLabelMarkerAnchor,
          icon: _placeLabelIcons[zone.id]!,
          consumeTapEvents: true,
          zIndexInt: 1,
          onTap: zone.isSavedLocationCluster
              ? () => _zoomIntoSavedLocationCluster(zone)
              : () => _editZonePlaceName(zone),
        ),
        Marker(
          markerId: MarkerId('zone-puck-${zone.id}'),
          position: zone.center,
          anchor: _puckMarkerAnchor,
          icon: _puckIcons[zone.id]!,
          consumeTapEvents: true,
          zIndexInt: 3,
          infoWindow: InfoWindow(
            title: zone.name,
            snippet: zone.isSavedLocationCluster
                ? '${zone.savedLocationIds.length} saved locations'
                : '${zone.transactionCount} transactions',
          ),
          onTap: zone.isSavedLocationCluster
              ? () => _zoomIntoSavedLocationCluster(zone)
              : () => _openZone(zone),
        ),
      ];
    }).toSet();
  }

  Set<Marker> _buildSavedLocationMarkers() {
    final targetZones = _puckTransitionTargetZones;
    final transitionProgress = targetZones == null
        ? 1.0
        : Curves.easeInOutCubic.transform(
            _puckTransitionController.value,
          );
    final markers = <Marker>{};

    for (final location in _unassignedSavedLocations) {
      final icon = _savedLocationIcons[location.id];
      if (icon == null) continue;
      final savedPosition = LatLng(location.latitude, location.longitude);
      final currentZone = _zoneContainingSavedLocation(
        _displayedZones,
        location.id,
      );
      final targetZone = targetZones == null
          ? null
          : _zoneContainingSavedLocation(targetZones, location.id);

      LatLng markerPosition = savedPosition;
      var alpha = 1.0;
      if (targetZones == null) {
        if (currentZone != null) continue;
      } else if (currentZone != null && targetZone != null) {
        continue;
      } else if (currentZone == null && targetZone != null) {
        markerPosition = _interpolateMapPosition(
          savedPosition,
          targetZone.center,
          transitionProgress,
        );
        alpha = 1 - transitionProgress;
      } else if (currentZone != null && targetZone == null) {
        markerPosition = _interpolateMapPosition(
          currentZone.center,
          savedPosition,
          transitionProgress,
        );
        alpha = transitionProgress;
      }

      markers.add(
        Marker(
          markerId: MarkerId('saved-location-${location.id}'),
          position: markerPosition,
          alpha: alpha.clamp(0.0, 1.0),
          anchor: _savedLocationMarkerAnchor,
          icon: icon,
          consumeTapEvents: true,
          draggable: targetZones == null,
          zIndexInt: 2,
          infoWindow: InfoWindow(
            title: location.name,
            snippet: 'Saved location • drag to move',
          ),
          onTap:
              targetZones == null ? () => _editSavedLocation(location) : null,
          onDragEnd: targetZones == null
              ? (position) => _moveSavedLocation(location, position)
              : null,
        ),
      );
    }
    return markers;
  }

  _SpendingZone? _zoneContainingSavedLocation(
    Iterable<_SpendingZone> zones,
    String savedLocationId,
  ) {
    for (final zone in zones) {
      if (zone.savedLocationIds.contains(savedLocationId)) return zone;
    }
    return null;
  }

  LatLng _interpolateMapPosition(
    LatLng from,
    LatLng to,
    double progress,
  ) {
    return LatLng(
      from.latitude + ((to.latitude - from.latitude) * progress),
      from.longitude + ((to.longitude - from.longitude) * progress),
    );
  }

  String _puckLabel(_SpendingZone zone) {
    if (zone.isSavedLocationCluster) {
      return NumberFormat.compact(locale: 'en').format(
        zone.savedLocationIds.length,
      );
    }
    return switch (_filters.puckMetric) {
      SpendingMapPuckMetric.transactionCount =>
        NumberFormat.compact(locale: 'en').format(zone.transactionCount),
      SpendingMapPuckMetric.netAmount =>
        formatSpendingMapNetPuckLabel(zone.netAmount),
    };
  }

  Future<
      ({
        Map<String, BitmapDescriptor> puckIcons,
        Map<String, BitmapDescriptor> placeLabelIcons,
      })> _loadPuckIcons(
    List<_SpendingZone> zones,
  ) async {
    final puckLabelsByZone = <String, String>{
      for (final zone in zones) zone.id: _puckLabel(zone),
    };
    final missingPuckLabels = puckLabelsByZone.values
        .where((label) => !_puckIconCache.containsKey(label))
        .toSet();
    final generatedPuckEntries = await Future.wait(
      missingPuckLabels.map((label) async {
        return MapEntry(label, await _createPuckIcon(label: label));
      }),
    );
    _puckIconCache.addEntries(generatedPuckEntries);
    final puckIcons = <String, BitmapDescriptor>{
      for (final entry in puckLabelsByZone.entries)
        entry.key: _puckIconCache[entry.value]!,
    };

    final placeLabelsByZone = <String, String>{
      for (final zone in zones) zone.id: zone.puckPlaceLabel,
    };
    final missingPlaceLabels = placeLabelsByZone.values
        .where((label) => !_placeLabelIconCache.containsKey(label))
        .toSet();
    final generatedPlaceLabelEntries = await Future.wait(
      missingPlaceLabels.map((label) async {
        return MapEntry(
          label,
          await _createPlaceLabelIcon(placeLabel: label),
        );
      }),
    );
    _placeLabelIconCache.addEntries(generatedPlaceLabelEntries);
    final placeLabelIcons = <String, BitmapDescriptor>{
      for (final entry in placeLabelsByZone.entries)
        entry.key: _placeLabelIconCache[entry.value]!,
    };

    const maximumCachedIcons = 128;
    final activePuckLabels = puckLabelsByZone.values.toSet();
    while (_puckIconCache.length > maximumCachedIcons) {
      final staleLabel = _puckIconCache.keys.firstWhere(
        (label) => !activePuckLabels.contains(label),
      );
      _puckIconCache.remove(staleLabel);
    }
    final activePlaceLabels = <String>{
      ...placeLabelsByZone.values,
      ..._savedLocations.map((location) => location.name),
    };
    while (_placeLabelIconCache.length > maximumCachedIcons) {
      final staleLabel = _placeLabelIconCache.keys.firstWhere(
        (label) => !activePlaceLabels.contains(label),
      );
      _placeLabelIconCache.remove(staleLabel);
    }

    return (
      puckIcons: puckIcons,
      placeLabelIcons: placeLabelIcons,
    );
  }

  Future<void> _refreshSavedLocationIcons() async {
    final names = _savedLocations.map((location) => location.name).toSet();
    final missingNames =
        names.where((name) => !_placeLabelIconCache.containsKey(name)).toSet();
    final generatedEntries = await Future.wait(
      missingNames.map((name) async {
        return MapEntry(
          name,
          await _createPlaceLabelIcon(placeLabel: name),
        );
      }),
    );
    _placeLabelIconCache.addEntries(generatedEntries);
    if (!mounted) return;
    setState(() {
      _savedLocationIcons = <String, BitmapDescriptor>{
        for (final location in _savedLocations)
          location.id: _placeLabelIconCache[location.name]!,
      };
    });
  }

  Future<void> _refreshPuckIcons({
    double? zoom,
    bool animate = false,
  }) async {
    final generation = ++_puckGeneration;
    final targetZoom = zoom ?? _zoomLevel;
    final animatePucks =
        animate && MediaQuery.maybeOf(context)?.disableAnimations != true;
    final zones = _buildZones(
      _filteredLocations,
      zoom: targetZoom,
    ).take(50).toList(growable: false);
    final icons = await _loadPuckIcons(zones);
    if (!mounted || generation != _puckGeneration) return;
    if (animate &&
        (_cameraMoving || (_pendingZoomLevel - targetZoom).abs() > 0.05)) {
      return;
    }

    final hasVisibleClusterMembers =
        _displayedZones.isNotEmpty || _unassignedSavedLocations.isNotEmpty;
    final shouldAnimate = animatePucks &&
        hasVisibleClusterMembers &&
        _zoneMembershipChanged(_displayedZones, zones);
    if (shouldAnimate) {
      setState(() => _zoomLevel = targetZoom);
      _startPuckTransition(
        zones,
        icons.puckIcons,
        icons.placeLabelIcons,
      );
      return;
    }

    _puckTransitionController.stop();
    setState(() {
      _zoomLevel = targetZoom;
      _displayedZones = zones;
      _puckIcons = icons.puckIcons;
      _placeLabelIcons = icons.placeLabelIcons;
      _puckMotions = const [];
      _puckTransitionTargetZones = null;
      _puckTransitionTargetIcons = const {};
      _puckTransitionTargetPlaceLabelIcons = const {};
    });
  }

  bool _zoneMembershipChanged(
    List<_SpendingZone> current,
    List<_SpendingZone> next,
  ) {
    if (current.length != next.length) return true;
    final currentIds = current.map((zone) => zone.id).toSet();
    final nextIds = next.map((zone) => zone.id).toSet();
    return !setEquals(currentIds, nextIds);
  }

  _SpendingZone? _relatedZone(
    _SpendingZone zone,
    Map<String, _SpendingZone> zonesByMember,
  ) {
    final overlapByZone = <String, int>{};
    final relatedById = <String, _SpendingZone>{};
    for (final memberKey in zone.membershipKeys) {
      final related = zonesByMember[memberKey];
      if (related == null) continue;
      relatedById[related.id] = related;
      overlapByZone.update(
        related.id,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    if (overlapByZone.isEmpty) return null;
    final bestId = overlapByZone.entries.reduce((best, candidate) {
      if (candidate.value != best.value) {
        return candidate.value > best.value ? candidate : best;
      }
      return candidate.key.compareTo(best.key) < 0 ? candidate : best;
    }).key;
    return relatedById[bestId];
  }

  void _startPuckTransition(
    List<_SpendingZone> targetZones,
    Map<String, BitmapDescriptor> targetIcons,
    Map<String, BitmapDescriptor> targetPlaceLabelIcons,
  ) {
    _puckTransitionController.stop();
    final currentById = {
      for (final zone in _displayedZones) zone.id: zone,
    };
    final targetById = {
      for (final zone in targetZones) zone.id: zone,
    };
    final currentByMember = <String, _SpendingZone>{
      for (final zone in _displayedZones)
        for (final memberKey in zone.membershipKeys) memberKey: zone,
    };
    final targetByMember = <String, _SpendingZone>{
      for (final zone in targetZones)
        for (final memberKey in zone.membershipKeys) memberKey: zone,
    };
    final motions = <_PuckMotion>[];

    for (final target in targetZones) {
      final current = currentById[target.id];
      if (current == null) continue;
      final icon = targetIcons[target.id];
      final placeLabelIcon = targetPlaceLabelIcons[target.id];
      if (icon == null || placeLabelIcon == null) continue;
      motions.add(
        _PuckMotion(
          markerId: target.id,
          puckIcon: icon,
          placeLabelIcon: placeLabelIcon,
          from: current.center,
          to: target.center,
          fromAlpha: 1,
          toAlpha: 1,
          zIndex: 2,
        ),
      );
    }

    for (final current in _displayedZones) {
      if (targetById.containsKey(current.id)) continue;
      final icon = _puckIcons[current.id];
      final placeLabelIcon = _placeLabelIcons[current.id];
      if (icon == null || placeLabelIcon == null) continue;
      final related = _relatedZone(current, targetByMember);
      motions.add(
        _PuckMotion(
          markerId: current.id,
          puckIcon: icon,
          placeLabelIcon: placeLabelIcon,
          from: current.center,
          to: related?.center ?? current.center,
          fromAlpha: 1,
          toAlpha: 0,
          zIndex: 1,
        ),
      );
    }

    for (final target in targetZones) {
      if (currentById.containsKey(target.id)) continue;
      final icon = targetIcons[target.id];
      final placeLabelIcon = targetPlaceLabelIcons[target.id];
      if (icon == null || placeLabelIcon == null) continue;
      final related = _relatedZone(target, currentByMember);
      motions.add(
        _PuckMotion(
          markerId: target.id,
          puckIcon: icon,
          placeLabelIcon: placeLabelIcon,
          from: related?.center ?? target.center,
          to: target.center,
          fromAlpha: 0,
          toAlpha: 1,
          zIndex: 2,
        ),
      );
    }

    if (motions.isEmpty) {
      setState(() {
        _displayedZones = targetZones;
        _puckIcons = targetIcons;
        _placeLabelIcons = targetPlaceLabelIcons;
      });
      return;
    }

    _puckTransitionController.value = 0;
    setState(() {
      _puckMotions = List<_PuckMotion>.unmodifiable(motions);
      _puckTransitionTargetZones = targetZones;
      _puckTransitionTargetIcons = targetIcons;
      _puckTransitionTargetPlaceLabelIcons = targetPlaceLabelIcons;
    });
    _puckTransitionController.forward();
  }

  void _handlePuckTransitionTick() {
    if (mounted && _puckMotions.isNotEmpty) setState(() {});
  }

  void _handlePuckTransitionStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _finishPuckTransition();
  }

  void _finishPuckTransition() {
    final targetZones = _puckTransitionTargetZones;
    if (targetZones == null) return;
    final targetIcons = _puckTransitionTargetIcons;
    final targetPlaceLabelIcons = _puckTransitionTargetPlaceLabelIcons;
    _puckTransitionController.stop();
    setState(() {
      _displayedZones = targetZones;
      _puckIcons = targetIcons;
      _placeLabelIcons = targetPlaceLabelIcons;
      _puckMotions = const [];
      _puckTransitionTargetZones = null;
      _puckTransitionTargetIcons = const {};
      _puckTransitionTargetPlaceLabelIcons = const {};
    });
  }

  Future<BitmapDescriptor> _createPuckIcon({required String label}) async {
    const center = Offset(
      _puckIconSourceSize / 2,
      _puckIconSourceSize / 2,
    );
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
          _puckIconSourceSize.toInt(),
          _puckIconSourceSize.toInt(),
        );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final data = bytes?.buffer.asUint8List() ?? Uint8List(0);
    return BitmapDescriptor.bytes(data, width: 54, height: 54);
  }

  Future<BitmapDescriptor> _createPlaceLabelIcon({
    required String placeLabel,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final placeTextPainter = TextPainter(
      text: TextSpan(
        text: placeLabel,
        style: const TextStyle(
          color: AppColors.white,
          fontSize: 40,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 330);
    final placePillWidth = math.max(150.0, placeTextPainter.width + 44);
    final placePillRect = Rect.fromCenter(
      center: const Offset(_placeLabelCenterX, 45),
      width: placePillWidth,
      height: 68,
    );
    final placePillPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          placePillRect,
          const Radius.circular(26),
        ),
      );
    final pointerPath = Path()
      ..moveTo(_placeLabelCenterX - 12, placePillRect.bottom - 5)
      ..lineTo(_placeLabelCenterX, 104)
      ..lineTo(_placeLabelCenterX + 12, placePillRect.bottom - 5)
      ..close();
    final placeLabelPath = Path.combine(
      PathOperation.union,
      placePillPath,
      pointerPath,
    );
    canvas.drawShadow(placeLabelPath, AppColors.black, 7, true);
    canvas.drawPath(
      placeLabelPath,
      Paint()..color = AppColors.slate900.withValues(alpha: 0.94),
    );
    canvas.drawPath(
      placeLabelPath,
      Paint()
        ..color = AppColors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    placeTextPainter.paint(
      canvas,
      Offset(
        _placeLabelCenterX - (placeTextPainter.width / 2),
        placePillRect.center.dy - (placeTextPainter.height / 2),
      ),
    );

    final image = await recorder.endRecording().toImage(
          _placeLabelIconSourceWidth.toInt(),
          _placeLabelIconSourceHeight.toInt(),
        );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final data = bytes?.buffer.asUint8List() ?? Uint8List(0);
    return BitmapDescriptor.bytes(
      data,
      width: _placeLabelIconSourceWidth * _puckIconScale,
      height: _placeLabelIconSourceHeight * _puckIconScale,
    );
  }

  Future<String> _savePlaceName(
    _SpendingZone zone,
    String? placeName,
  ) async {
    final normalizedName = await _savePlaceNameForTransactionReferences(
      zone.transactionReferences.toSet(),
      placeName,
    );
    return normalizedName ?? _approximatePlaceName(zone.center);
  }

  Future<String?> _savePlaceNameForTransactionReferences(
    Set<String> references,
    String? placeName,
  ) async {
    final normalizedName = normalizeTransactionPlaceName(placeName);
    await _repository.setPlaceNameForTransactionReferences(
      references,
      normalizedName,
    );
    if (!mounted) return normalizedName;

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
    await _reloadMapLocationData();
    return normalizedName;
  }

  Future<void> _editZonePlaceName(_SpendingZone zone) async {
    if (_editingZoneId != null) return;
    _editingZoneId = zone.id;
    try {
      if (!mounted) return;
      final result = await showPlaceNameEditorSheet(
        context: context,
        initialValue: zone.customPlaceName,
      );
      if (!mounted || result == null) return;
      await _savePlaceName(zone, result.value);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${context.l10nTextRead('Could not update place name')}: $error',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      _editingZoneId = null;
    }
  }

  SavedLocation? _savedLocationNear(LatLng point) {
    SavedLocation? nearest;
    var nearestDistance = double.infinity;
    for (final location in _savedLocations) {
      final distance = spendingMapDistanceMeters(
        firstLatitude: point.latitude,
        firstLongitude: point.longitude,
        secondLatitude: location.latitude,
        secondLongitude: location.longitude,
      );
      if (distance <= spendingMapSameLocationRadiusMeters &&
          distance < nearestDistance) {
        nearest = location;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  Future<void> _createSavedLocationAt(LatLng point) async {
    if (_editingSavedLocationId != null) return;
    await HapticFeedback.mediumImpact();
    if (!mounted) return;
    final nearbyLocation = _savedLocationNear(point);
    if (nearbyLocation != null) {
      if (mounted) {
        _showLocationMessage(
          'A saved location already exists within 50 metres.',
        );
      }
      await _editSavedLocation(nearbyLocation);
      return;
    }

    _editingSavedLocationId = 'new';
    try {
      final result = await showSavedLocationEditorSheet(
        context: context,
        approximateName: _approximatePlaceName(point),
      );
      if (!mounted ||
          result == null ||
          result.action != SavedLocationEditorAction.save) {
        return;
      }
      final created = await _savedLocationRepository.createLocation(
        name: result.name!,
        latitude: point.latitude,
        longitude: point.longitude,
      );
      if (!mounted) return;
      setState(() {
        _savedLocations = <SavedLocation>[..._savedLocations, created]..sort(
            (first, second) => first.name.toLowerCase().compareTo(
                  second.name.toLowerCase(),
                ),
          );
      });
      await _refreshPuckIcons();
      await _refreshSavedLocationIcons();
      await HapticFeedback.selectionClick();
    } catch (error) {
      if (!mounted) return;
      _showLocationMessage('Could not save this location: $error');
    } finally {
      _editingSavedLocationId = null;
    }
  }

  Future<void> _editSavedLocation(SavedLocation location) async {
    if (_editingSavedLocationId != null) return;
    _editingSavedLocationId = location.id;
    try {
      final result = await showSavedLocationEditorSheet(
        context: context,
        approximateName: _approximatePlaceName(
          LatLng(location.latitude, location.longitude),
        ),
        initialName: location.name,
        allowDelete: true,
      );
      if (!mounted || result == null) return;
      if (result.action == SavedLocationEditorAction.delete) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(dialogContext.l10nText('Delete saved location?')),
            content: Text(
              dialogContext.l10nText(
                'Transactions already assigned here will keep their current coordinates and name.',
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
        await _savedLocationRepository.deleteLocation(location.id);
      } else {
        await _savedLocationRepository.updateLocation(
          location,
          name: result.name,
        );
      }
      await _reloadMapLocationData();
    } catch (error) {
      if (!mounted) return;
      _showLocationMessage('Could not update this location: $error');
    } finally {
      _editingSavedLocationId = null;
    }
  }

  Future<void> _moveSavedLocation(
    SavedLocation location,
    LatLng position,
  ) async {
    if (!_ethiopiaMapBounds.contains(position)) {
      await _reloadMapLocationData();
      return;
    }
    try {
      await _savedLocationRepository.updateLocation(
        location,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      await _reloadMapLocationData();
      await HapticFeedback.selectionClick();
    } catch (error) {
      if (!mounted) return;
      _showLocationMessage('Could not move this location: $error');
      await _reloadMapLocationData();
    }
  }

  List<TransactionLocationGroupEntry> _locationGroupEntriesForZone(
    _SpendingZone zone,
  ) {
    final references = zone.transactionReferences.toSet();
    final entriesByReference = <String, TransactionLocationGroupEntry>{};
    for (final location in _locations) {
      if (!references.contains(location.transactionReference)) continue;
      entriesByReference[location.transactionReference] =
          TransactionLocationGroupEntry(
        transactionReference: location.transactionReference,
        fallbackName: _approximatePlaceName(
          LatLng(location.latitude, location.longitude),
        ),
        customName: location.placeName,
      );
    }
    return zone.transactionReferences
        .map((reference) => entriesByReference[reference])
        .whereType<TransactionLocationGroupEntry>()
        .toList(growable: false);
  }

  Future<void> _zoomIntoSavedLocationCluster(_SpendingZone zone) async {
    final controller = _mapController;
    if (controller == null) return;
    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          zone.center,
          math.min(_zoomLevel + 2.5, 20.0),
        ),
      );
    } catch (_) {
      // The platform view can be disposed while an animation is in flight.
    }
  }

  Future<void> _openZone(_SpendingZone zone) async {
    if (_openingZoneId != null) return;
    _openingZoneId = zone.id;
    try {
      if (!mounted) return;
      final transactionLabel = context.l10nTextRead(
        zone.transactionCount == 1 ? 'transaction' : 'transactions',
      );
      final locationGroupEntries = _locationGroupEntriesForZone(zone);
      final hasMultipleLocationNames = locationGroupEntries
              .map((entry) => entry.displayName.trim().toLowerCase())
              .toSet()
              .length >
          1;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TodaysTransactionsPage(
            transactionReferences: Set<String>.unmodifiable(
              zone.transactionReferences,
            ),
            title: hasMultipleLocationNames
                ? context.l10nTextRead('Locations')
                : zone.name,
            subtitle: '${zone.transactionCount} $transactionLabel',
            editableTitleValue:
                hasMultipleLocationNames ? null : zone.customPlaceName,
            onTitleChanged: hasMultipleLocationNames
                ? null
                : (placeName) => _savePlaceName(zone, placeName),
            locationGroupEntries: hasMultipleLocationNames
                ? locationGroupEntries
                : const <TransactionLocationGroupEntry>[],
            onLocationGroupNameChanged: hasMultipleLocationNames
                ? _savePlaceNameForTransactionReferences
                : null,
          ),
        ),
      );
      await _reloadMapLocationData();
    } finally {
      _openingZoneId = null;
    }
  }

  Future<void> _reloadMapLocationData() async {
    try {
      final locations = await _repository.getTransactionLocations();
      final savedLocations = await _savedLocationRepository.getSavedLocations();
      if (!mounted) return;
      setState(() {
        _locations = locations;
        _savedLocations = savedLocations;
      });
      await _refreshPuckIcons();
      await _refreshSavedLocationIcons();
    } catch (error) {
      debugPrint('Could not refresh spending map locations: $error');
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
    final points = <LatLng>[
      ...filtered.map(
        (location) => LatLng(location.latitude, location.longitude),
      ),
      ..._ethiopiaSavedLocations.map(
        (location) => LatLng(location.latitude, location.longitude),
      ),
    ];
    if (points.isEmpty) {
      try {
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(_ethiopiaCenter, 5.5),
        );
      } catch (_) {
        // The platform view can be disposed while an animation is in flight.
      }
      return;
    }
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
    _cameraMoving = true;
    if (_puckTransitionTargetZones != null) _finishPuckTransition();
  }

  void _handleCameraIdle() {
    _cameraMoving = false;
    if ((_pendingZoomLevel - _zoomLevel).abs() <= 0.01) return;
    unawaited(
      _refreshPuckIcons(
        zoom: _pendingZoomLevel,
        animate: true,
      ),
    );
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
    setState(() => _filters = selected);
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
        canDelete: _locations.isNotEmpty || _savedLocations.isNotEmpty,
        onRoadmap: () => Navigator.pop(
          sheetContext,
          _MapOptionsAction.roadmap,
        ),
        onSatellite: () => Navigator.pop(
          sheetContext,
          _MapOptionsAction.satellite,
        ),
        onOpenOvertureAttribution: () => Navigator.pop(
          sheetContext,
          _MapOptionsAction.openOvertureAttribution,
        ),
        onOpenAddisCadastreSource: () => Navigator.pop(
          sheetContext,
          _MapOptionsAction.openAddisCadastreSource,
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
      case _MapOptionsAction.openOvertureAttribution:
        await _openGazetteerSource(
          'overture_divisions',
          Uri.parse('https://docs.overturemaps.org/attribution/'),
        );
      case _MapOptionsAction.openAddisCadastreSource:
        await _openGazetteerSource(
          'addis_cadastre',
          Uri.parse('https://eland.addiscadaster.gov.et/maps'),
        );
      case _MapOptionsAction.deleteLocations:
        await _clearLocations();
    }
  }

  Future<void> _openGazetteerSource(
    String sourceId,
    Uri fallbackUri,
  ) async {
    final uri =
        _offlineGazetteer?.sourceById(sourceId)?.licenseUrl ?? fallbackUri;
    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) {
        _showLocationMessage(
          'Could not open the map data source information.',
        );
      }
    } catch (_) {
      if (mounted) {
        _showLocationMessage(
          'Could not open the map data source information.',
        );
      }
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
            'This permanently removes all saved places and transaction map '
            'coordinates for the active profile. Your transactions will not '
            'be deleted.',
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
    await _savedLocationRepository.clearForActiveProfile();
    if (!mounted) return;
    _puckTransitionController.stop();
    setState(() {
      _locations = const [];
      _savedLocations = const [];
      _displayedZones = const [];
      _puckIcons = const {};
      _placeLabelIcons = const {};
      _savedLocationIcons = const {};
      _puckMotions = const [];
      _puckTransitionTargetZones = null;
      _puckTransitionTargetIcons = const {};
      _puckTransitionTargetPlaceLabelIcons = const {};
      _puckGeneration += 1;
    });
    try {
      await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_ethiopiaCenter, 5.5),
      );
    } catch (_) {
      // The map can be disposed while the reset animation is in flight.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: switch ((_loading, _loadError)) {
        (true, _) => _MapStatusShell(
            onBack: () => Navigator.maybePop(context),
            onOptions: _showMapOptions,
            child: const CircularProgressIndicator(),
          ),
        (false, final Object error) => _MapStatusShell(
            onBack: () => Navigator.maybePop(context),
            onOptions: _showMapOptions,
            child: _ErrorState(
              message: error.toString(),
              onRetry: _loadLocations,
            ),
          ),
        _ => _buildMap(context),
      },
    );
  }

  Widget _buildMap(BuildContext context) {
    final filtered = _filteredLocations;
    final ethiopiaLocations = _ethiopiaLocations;
    final ethiopiaSavedLocations = _ethiopiaSavedLocations;
    final initialCenter = ethiopiaLocations.isNotEmpty
        ? _averageCenter(ethiopiaLocations)
        : ethiopiaSavedLocations.isNotEmpty
            ? _averageSavedLocationCenter(ethiopiaSavedLocations)
            : _ethiopiaCenter;
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
            markers: <Marker>{
              ..._buildZoneMarkers(),
              ..._buildSavedLocationMarkers(),
            },
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
            onLongPress: _createSavedLocationAt,
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
          left: 14,
          bottom: mediaPadding.bottom + 16,
          child: const _MapLongPressHint(),
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

  LatLng _averageSavedLocationCenter(List<SavedLocation> locations) {
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
  late SpendingMapPuckMetric _selectedPuckMetric;
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
    _selectedPuckMetric = filters.puckMetric;
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
        puckMetric: _selectedPuckMetric,
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
    final flowTintedCategoryIds =
        categoryFilterIdsWithFlowTint(widget.categories);

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
                  _sectionLabel('PUCK LABELS'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _chip(
                        label: 'Transaction count',
                        selected: _selectedPuckMetric ==
                            SpendingMapPuckMetric.transactionCount,
                        onTap: () => setState(
                          () => _selectedPuckMetric =
                              SpendingMapPuckMetric.transactionCount,
                        ),
                      ),
                      _chip(
                        label: 'Net amount',
                        selected: _selectedPuckMetric ==
                            SpendingMapPuckMetric.netAmount,
                        onTap: () => setState(
                          () => _selectedPuckMetric =
                              SpendingMapPuckMetric.netAmount,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10nText(
                      'Net amount shows credits minus debits for each puck.',
                    ),
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 20),
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
                            subtleFlowTint:
                                flowTintedCategoryIds.contains(category.id),
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
    required this.onOpenOvertureAttribution,
    required this.onOpenAddisCadastreSource,
    required this.onDelete,
  });

  final _MapDisplayMode displayMode;
  final bool canDelete;
  final VoidCallback onRoadmap;
  final VoidCallback onSatellite;
  final VoidCallback onOpenOvertureAttribution;
  final VoidCallback onOpenAddisCadastreSource;
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
              'Transaction pucks are built on your device. Totals does not '
              'send your financial data anywhere to make Spending Map work, '
              'and it does not attach transaction details to Google map '
              'requests.',
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
              'Saved coordinates stay in Totals. Addis subcity and supported '
              'Ethiopian city names come from a bundled offline asset.',
            ),
          ),
          _MapDataAttribution(
            onOpenOverture: onOpenOvertureAttribution,
            onOpenAddisCadastre: onOpenAddisCadastreSource,
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

class _MapDataAttribution extends StatelessWidget {
  const _MapDataAttribution({
    required this.onOpenOverture,
    required this.onOpenAddisCadastre,
  });

  final VoidCallback onOpenOverture;
  final VoidCallback onOpenAddisCadastre;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10nText('OFFLINE PLACE DATA'),
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 2),
          Wrap(
            spacing: 8,
            runSpacing: 2,
            children: [
              _MapAttributionLink(
                label: '© OpenStreetMap contributors · Overture Maps · '
                    'ODbL/CDLA',
                onTap: onOpenOverture,
              ),
              _MapAttributionLink(
                label: 'Addis Ababa Cadaster · public WFS',
                onTap: onOpenAddisCadastre,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MapAttributionLink extends StatelessWidget {
  const _MapAttributionLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.textSecondary(context),
            ),
          ),
        ),
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

class _MapLongPressHint extends StatelessWidget {
  const _MapLongPressHint();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width - 86,
        ),
        padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
        decoration: BoxDecoration(
          color: AppColors.cardColor(context).withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.borderColor(context)),
          boxShadow: [
            BoxShadow(
              color: AppColors.black.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                AppIcons.add_rounded,
                color: AppColors.primaryLight,
                size: 17,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                context.l10nText('Press and hold the map to save a location'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
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
