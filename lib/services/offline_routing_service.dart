import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

class OfflineRouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final int visitedNodes;
  final int routeNodes;
  final int routeEdges;

  const OfflineRouteResult({
    required this.points,
    required this.distanceMeters,
    required this.visitedNodes,
    required this.routeNodes,
    required this.routeEdges,
  });

  double get distanceKm => distanceMeters / 1000.0;
}

class _RoutingNode {
  final int id;
  final double latitude;
  final double longitude;

  const _RoutingNode({
    required this.id,
    required this.latitude,
    required this.longitude,
  });
}

class _RoutingEdge {
  final int id;
  final int from;
  final int to;
  final double distanceMeters;
  final bool forward;
  final int roadId;
  final String geometry;

  const _RoutingEdge({
    required this.id,
    required this.from,
    required this.to,
    required this.distanceMeters,
    required this.forward,
    required this.roadId,
    required this.geometry,
  });
}

class _GraphState {
  final Map<int, _RoutingNode> nodes = {};
  final Map<int, List<_RoutingEdge>> outgoing = {};

  void addNode(_RoutingNode node) {
    nodes[node.id] = node;
    outgoing.putIfAbsent(node.id, () => <_RoutingEdge>[]);
  }

  void addEdge(_RoutingEdge edge) {
    outgoing.putIfAbsent(edge.from, () => <_RoutingEdge>[]);
    outgoing[edge.from]!.add(edge);
  }

  void clear() {
    nodes.clear();
    outgoing.clear();
  }
}

class _BinaryReader {
  final ByteData data;
  int offset = 0;

  _BinaryReader(Uint8List bytes)
      : data = ByteData.sublistView(bytes);

  int get remaining => data.lengthInBytes - offset;

  void require(int bytes) {
    if (remaining < bytes) {
      throw FormatException(
        'Unexpected end of routing tile. '
            'Needed $bytes bytes, remaining $remaining.',
      );
    }
  }

  int readUint8() {
    require(1);
    final value = data.getUint8(offset);
    offset += 1;
    return value;
  }

  int readUint32() {
    require(4);
    final value = data.getUint32(
      offset,
      Endian.little,
    );
    offset += 4;
    return value;
  }

  int readInt32() {
    require(4);
    final value = data.getInt32(
      offset,
      Endian.little,
    );
    offset += 4;
    return value;
  }

  int readUint64() {
    require(8);
    final value = data.getUint64(
      offset,
      Endian.little,
    );
    offset += 8;
    return value;
  }

  String readUtf8(int length) {
    require(length);

    final bytes = data.buffer.asUint8List(
      data.offsetInBytes + offset,
      length,
    );

    offset += length;

    return String.fromCharCodes(bytes);
  }

  Uint8List readBytes(int length) {
    require(length);

    final bytes = data.buffer.asUint8List(
      data.offsetInBytes + offset,
      length,
    );

    offset += length;

    return bytes;
  }
}

class _PriorityQueueItem {
  final int nodeId;
  final double fScore;
  final double gScore;

  const _PriorityQueueItem({
    required this.nodeId,
    required this.fScore,
    required this.gScore,
  });
}

class _MinHeap {
  final List<_PriorityQueueItem> _items = [];

  bool get isEmpty => _items.isEmpty;

  void add(_PriorityQueueItem item) {
    _items.add(item);

    int index = _items.length - 1;

    while (index > 0) {
      final parent = (index - 1) ~/ 2;

      if (_items[parent].fScore <= item.fScore) {
        break;
      }

      _items[index] = _items[parent];
      index = parent;
    }

    _items[index] = item;
  }

  _PriorityQueueItem removeMin() {
    if (_items.isEmpty) {
      throw StateError('Priority queue is empty.');
    }

    final result = _items.first;
    final last = _items.removeLast();

    if (_items.isNotEmpty) {
      int index = 0;

      while (true) {
        final left = index * 2 + 1;
        final right = left + 1;

        if (left >= _items.length) {
          break;
        }

        int smallest = left;

        if (right < _items.length &&
            _items[right].fScore < _items[left].fScore) {
          smallest = right;
        }

        if (_items[smallest].fScore >= last.fScore) {
          break;
        }

        _items[index] = _items[smallest];
        index = smallest;
      }

      _items[index] = last;
    }

    return result;
  }
}

class OfflineRoutingService {
  static const String _assetDirectory =
      'assets/offline_routing/routing_tiles_v4';

  static const double _tileSize = 0.10;

  static const int _version = 4;

  static const double _coordinateScale = 100000.0;

  static const double _earthRadius = 6371000.0;

  static const int _initialMarginTiles = 2;

  static const int _maximumMarginTiles = 5;

  static final Map<String, Uint8List> _tileCache =
  <String, Uint8List>{};

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    if (kIsWeb) {
      debugPrint(
        'OFFLINE ROUTING V4: Web is not supported.',
      );
      return;
    }

    _initialized = true;

    debugPrint(
      'OFFLINE ROUTING V4 INITIALIZED',
    );
  }

  // ==========================================================
  // PUBLIC ROUTE METHOD
  // ==========================================================

  Future<OfflineRouteResult?> findRoute({
    required LatLng start,
    required LatLng destination,
    double? maximumSearchDistanceKm,
  }) async {
    if (kIsWeb) {
      debugPrint(
        'OFFLINE ROUTING V4: Web unsupported.',
      );
      return null;
    }

    await initialize();

    debugPrint(
      '==================================================',
    );
    debugPrint(
      'OFFLINE ROUTING V4',
    );
    debugPrint(
      'START: ${start.latitude}, ${start.longitude}',
    );
    debugPrint(
      'DESTINATION: '
          '${destination.latitude}, ${destination.longitude}',
    );
    debugPrint(
      '==================================================',
    );

    for (
    int marginTiles = _initialMarginTiles;
    marginTiles <= _maximumMarginTiles;
    marginTiles++
    ) {
      final result = await _findRouteWithMargin(
        start: start,
        destination: destination,
        marginTiles: marginTiles,
        maximumSearchDistanceKm:
        maximumSearchDistanceKm,
      );

      if (result != null) {
        debugPrint(
          'OFFLINE ROUTING V4: ROUTE FOUND',
        );

        debugPrint(
          'DISTANCE: '
              '${result.distanceKm.toStringAsFixed(3)} km',
        );

        debugPrint(
          'ROUTE NODES: ${result.routeNodes}',
        );

        debugPrint(
          'ROUTE EDGES: ${result.routeEdges}',
        );

        debugPrint(
          'GEOMETRY POINTS: ${result.points.length}',
        );

        return result;
      }

      debugPrint(
        'OFFLINE ROUTING V4: '
            'No route with margin $marginTiles tiles.',
      );
    }

    debugPrint(
      'OFFLINE ROUTING V4: NO ROUTE FOUND',
    );

    return null;
  }

  // ==========================================================
  // ROUTE WITH MARGIN
  // ==========================================================

  Future<OfflineRouteResult?> _findRouteWithMargin({
    required LatLng start,
    required LatLng destination,
    required int marginTiles,
    double? maximumSearchDistanceKm,
  }) async {
    final graph = _GraphState();

    final tiles = _calculateTiles(
      start: start,
      destination: destination,
      marginTiles: marginTiles,
    );

    debugPrint(
      'OFFLINE ROUTING V4: '
          'Loading ${tiles.length} tiles '
          '(margin=$marginTiles)',
    );

    int loadedTiles = 0;
    int missingTiles = 0;

    for (final tile in tiles) {
      final loaded = await _loadTileIntoGraph(
        tileLat: tile.$1,
        tileLon: tile.$2,
        graph: graph,
      );

      if (loaded) {
        loadedTiles++;
      } else {
        missingTiles++;
      }
    }

    debugPrint(
      'OFFLINE ROUTING V4: '
          'Tiles loaded=$loadedTiles '
          'missing=$missingTiles',
    );

    debugPrint(
      'OFFLINE ROUTING V4: '
          'Nodes=${graph.nodes.length} '
          'Edges=${_edgeCount(graph)}',
    );

    if (graph.nodes.isEmpty) {
      return null;
    }

    final nearestStart = _findNearestNode(
      graph.nodes,
      start,
    );

    final nearestDestination = _findNearestNode(
      graph.nodes,
      destination,
    );

    if (nearestStart == null ||
        nearestDestination == null) {
      return null;
    }

    debugPrint(
      'START NODE: ${nearestStart.node.id} '
          'DISTANCE: '
          '${nearestStart.distanceMeters.toStringAsFixed(2)} m',
    );

    debugPrint(
      'DESTINATION NODE: '
          '${nearestDestination.node.id} '
          'DISTANCE: '
          '${nearestDestination.distanceMeters.toStringAsFixed(2)} m',
    );

    if (maximumSearchDistanceKm != null) {
      final directDistance = _distanceMeters(
        start.latitude,
        start.longitude,
        destination.latitude,
        destination.longitude,
      );

      if (directDistance >
          maximumSearchDistanceKm * 1000.0) {
        debugPrint(
          'OFFLINE ROUTING V4: '
              'Requested route exceeds maximum distance.',
        );

        return null;
      }
    }

    final astarResult = _runAStar(
      graph: graph,
      startId: nearestStart.node.id,
      destinationId: nearestDestination.node.id,
    );

    if (astarResult == null) {
      return null;
    }

    final edgePath = astarResult.edgePath;

    final distanceMeters = edgePath.fold<double>(
      0.0,
          (sum, edge) => sum + edge.distanceMeters,
    );

    final geometry = _buildGeometry(
      edgePath,
    );

    if (geometry.isEmpty) {
      debugPrint(
        'OFFLINE ROUTING V4: '
            'Route found but geometry is empty.',
      );

      return null;
    }

    // Add exact GPS start and destination points.
    final finalGeometry = <LatLng>[
      start,
      ...geometry,
      destination,
    ];

    return OfflineRouteResult(
      points: _removeDuplicatePoints(
        finalGeometry,
      ),
      distanceMeters: distanceMeters,
      visitedNodes: astarResult.visitedNodes,
      routeNodes: astarResult.nodePath.length,
      routeEdges: edgePath.length,
    );
  }

  // ==========================================================
  // TILE CALCULATION
  // ==========================================================

  List<(int, int)> _calculateTiles({
    required LatLng start,
    required LatLng destination,
    required int marginTiles,
  }) {
    final minLat = math.min(
      start.latitude,
      destination.latitude,
    ) -
        marginTiles * _tileSize;

    final maxLat = math.max(
      start.latitude,
      destination.latitude,
    ) +
        marginTiles * _tileSize;

    final minLon = math.min(
      start.longitude,
      destination.longitude,
    ) -
        marginTiles * _tileSize;

    final maxLon = math.max(
      start.longitude,
      destination.longitude,
    ) +
        marginTiles * _tileSize;

    final minTileLat = _tileIndex(minLat);
    final maxTileLat = _tileIndex(maxLat);

    final minTileLon = _tileIndex(minLon);
    final maxTileLon = _tileIndex(maxLon);

    final result = <(int, int)>[];

    for (
    int lat = minTileLat;
    lat <= maxTileLat;
    lat++
    ) {
      for (
      int lon = minTileLon;
      lon <= maxTileLon;
      lon++
      ) {
        result.add((lat, lon));
      }
    }

    return result;
  }

  int _tileIndex(double coordinate) {
    return (coordinate / _tileSize).floor();
  }

  // ==========================================================
  // TILE LOADING
  // ==========================================================

  Future<bool> _loadTileIntoGraph({
    required int tileLat,
    required int tileLon,
    required _GraphState graph,
  }) async {
    final filename =
        '$_assetDirectory/'
        'tile_${tileLat}_${tileLon}.bin';

    try {
      Uint8List? bytes = _tileCache[filename];

      if (bytes == null) {
        final ByteData data =
        await rootBundle.load(filename);

        bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );

        _tileCache[filename] = bytes;
      }

      _decodeTile(
        bytes,
        graph,
        filename,
      );

      return true;
    } catch (e) {
      debugPrint(
        'OFFLINE ROUTING V4: '
            'Tile not found/unreadable: $filename',
      );

      return false;
    }
  }

  // ==========================================================
  // TILE DECODER
  // ==========================================================

  void _decodeTile(
      Uint8List bytes,
      _GraphState graph,
      String filename,
      ) {
    final reader = _BinaryReader(bytes);

    final magicBytes = reader.readBytes(4);

    final magic = String.fromCharCodes(
      magicBytes,
    );

    if (magic != 'FWRT') {
      throw FormatException(
        'Invalid routing tile magic in $filename',
      );
    }

    final version = reader.readUint32();

    if (version != _version) {
      throw FormatException(
        'Unsupported routing tile version: $version',
      );
    }

    // Tile coordinates.
    reader.readInt32();
    reader.readInt32();

    final nodeCount = reader.readUint32();
    final edgeCount = reader.readUint32();

    // --------------------------------------------------------
    // NODES
    // --------------------------------------------------------

    for (
    int i = 0;
    i < nodeCount;
    i++
    ) {
      final nodeId = reader.readUint32();

      final latitudeRaw = reader.readInt32();

      final longitudeRaw = reader.readInt32();

      final node = _RoutingNode(
        id: nodeId,
        latitude:
        latitudeRaw / _coordinateScale,
        longitude:
        longitudeRaw / _coordinateScale,
      );

      graph.addNode(node);
    }

    // --------------------------------------------------------
    // EDGES
    // --------------------------------------------------------

    for (
    int i = 0;
    i < edgeCount;
    i++
    ) {
      final edgeId = reader.readUint32();

      final fromNode = reader.readUint32();

      final toNode = reader.readUint32();

      final distanceMm = reader.readUint64();

      final forward = reader.readUint8();

      final roadId = reader.readUint32();

      final geometryLength = reader.readUint32();

      final geometry =
      reader.readUtf8(
        geometryLength,
      );

      if (!graph.nodes.containsKey(fromNode) ||
          !graph.nodes.containsKey(toNode)) {
        continue;
      }

      final edge = _RoutingEdge(
        id: edgeId,
        from: fromNode,
        to: toNode,
        distanceMeters:
        distanceMm / 1000.0,
        forward: forward == 1,
        roadId: roadId,
        geometry: geometry,
      );

      graph.addEdge(edge);
    }
  }

  // ==========================================================
  // NEAREST NODE
  // ==========================================================

  _NearestNode? _findNearestNode(
      Map<int, _RoutingNode> nodes,
      LatLng position,
      ) {
    _RoutingNode? best;
    double bestDistance = double.infinity;

    for (final node in nodes.values) {
      final distance = _distanceMeters(
        position.latitude,
        position.longitude,
        node.latitude,
        node.longitude,
      );

      if (distance < bestDistance) {
        bestDistance = distance;
        best = node;
      }
    }

    if (best == null) {
      return null;
    }

    return _NearestNode(
      node: best,
      distanceMeters: bestDistance,
    );
  }

  // ==========================================================
  // A*
  // ==========================================================

  _AStarResult? _runAStar({
    required _GraphState graph,
    required int startId,
    required int destinationId,
  }) {
    debugPrint(
      'OFFLINE ROUTING V4: Running A*',
    );

    final openSet = _MinHeap();

    final gScore = <int, double>{
      startId: 0.0,
    };

    final cameFromNode = <int, int>{};

    final cameFromEdge = <int, _RoutingEdge>{};

    final destination =
    graph.nodes[destinationId];

    if (destination == null) {
      return null;
    }

    final start =
    graph.nodes[startId];

    if (start == null) {
      return null;
    }

    openSet.add(
      _PriorityQueueItem(
        nodeId: startId,
        fScore: _distanceMeters(
          start.latitude,
          start.longitude,
          destination.latitude,
          destination.longitude,
        ),
        gScore: 0.0,
      ),
    );

    int visitedNodes = 0;

    while (!openSet.isEmpty) {
      final currentItem =
      openSet.removeMin();

      final currentId =
          currentItem.nodeId;

      final currentBest =
      gScore[currentId];

      if (currentBest == null) {
        continue;
      }

      if (currentItem.gScore >
          currentBest + 0.000001) {
        continue;
      }

      visitedNodes++;

      if (currentId == destinationId) {
        final reconstructed =
        _reconstructPath(
          startId: startId,
          destinationId: destinationId,
          cameFromNode: cameFromNode,
          cameFromEdge: cameFromEdge,
        );

        if (reconstructed == null) {
          return null;
        }

        debugPrint(
          'OFFLINE ROUTING V4: '
              'Destination reached.',
        );

        debugPrint(
          'A* visited: $visitedNodes',
        );

        return _AStarResult(
          nodePath: reconstructed.nodePath,
          edgePath: reconstructed.edgePath,
          visitedNodes: visitedNodes,
        );
      }

      final outgoing =
          graph.outgoing[currentId] ??
              const <_RoutingEdge>[];

      for (final edge in outgoing) {
        final neighbor = edge.to;

        if (!graph.nodes.containsKey(
          neighbor,
        )) {
          continue;
        }

        final tentativeG =
            currentBest +
                edge.distanceMeters;

        final previousG =
        gScore[neighbor];

        if (previousG != null &&
            tentativeG >= previousG) {
          continue;
        }

        gScore[neighbor] = tentativeG;

        cameFromNode[neighbor] =
            currentId;

        cameFromEdge[neighbor] =
            edge;

        final neighborNode =
        graph.nodes[neighbor]!;

        final heuristic =
        _distanceMeters(
          neighborNode.latitude,
          neighborNode.longitude,
          destination.latitude,
          destination.longitude,
        );

        openSet.add(
          _PriorityQueueItem(
            nodeId: neighbor,
            fScore:
            tentativeG + heuristic,
            gScore: tentativeG,
          ),
        );
      }
    }

    debugPrint(
      'OFFLINE ROUTING V4: '
          'A* could not reach destination.',
    );

    debugPrint(
      'A* visited: $visitedNodes',
    );

    return null;
  }

  // ==========================================================
  // PATH RECONSTRUCTION
  // ==========================================================

  _PathResult? _reconstructPath({
    required int startId,
    required int destinationId,
    required Map<int, int> cameFromNode,
    required Map<int, _RoutingEdge> cameFromEdge,
  }) {
    final nodePath = <int>[];
    final edgePath = <_RoutingEdge>[];

    int current = destinationId;

    nodePath.add(current);

    while (current != startId) {
      final previous =
      cameFromNode[current];

      final edge =
      cameFromEdge[current];

      if (previous == null ||
          edge == null) {
        return null;
      }

      edgePath.add(edge);

      current = previous;

      nodePath.add(current);
    }

    final reversedNodes = nodePath.reversed.toList();
    final reversedEdges = edgePath.reversed.toList();

    return _PathResult(
      nodePath: reversedNodes,
      edgePath: reversedEdges,
    );
  }

  // ==========================================================
  // GEOMETRY
  // ==========================================================

  List<LatLng> _buildGeometry(
      List<_RoutingEdge> edges,
      ) {
    final points = <LatLng>[];

    for (final edge in edges) {
      final geometry =
      _decodeGeometry(
        edge.geometry,
      );

      if (geometry.isEmpty) {
        continue;
      }

      if (points.isEmpty) {
        points.addAll(geometry);
        continue;
      }

      final first = geometry.first;

      final last = points.last;

      if (_samePoint(
        first,
        last,
      )) {
        points.addAll(
          geometry.skip(1),
        );
      } else {
        points.addAll(geometry);
      }
    }

    return _removeDuplicatePoints(
      points,
    );
  }

  List<LatLng> _decodeGeometry(
      String text,
      ) {
    final result = <LatLng>[];

    final pairs = text.split(';');

    for (final pair in pairs) {
      final trimmed = pair.trim();

      if (trimmed.isEmpty) {
        continue;
      }

      final parts = trimmed.split(',');

      if (parts.length != 2) {
        continue;
      }

      final latitude =
      double.tryParse(
        parts[0],
      );

      final longitude =
      double.tryParse(
        parts[1],
      );

      if (latitude == null ||
          longitude == null) {
        continue;
      }

      result.add(
        LatLng(
          latitude,
          longitude,
        ),
      );
    }

    return result;
  }

  List<LatLng> _removeDuplicatePoints(
      List<LatLng> points,
      ) {
    if (points.length < 2) {
      return points;
    }

    final result = <LatLng>[
      points.first,
    ];

    for (int i = 1; i < points.length; i++) {
      final previous =
          result.last;

      final current =
      points[i];

      if (!_samePoint(
        previous,
        current,
      )) {
        result.add(current);
      }
    }

    return result;
  }

  bool _samePoint(
      LatLng a,
      LatLng b,
      ) {
    return (a.latitude - b.latitude).abs() <
        0.0000001 &&
        (a.longitude - b.longitude).abs() <
            0.0000001;
  }

  // ==========================================================
  // DISTANCE
  // ==========================================================

  double _distanceMeters(
      double lat1,
      double lon1,
      double lat2,
      double lon2,
      ) {
    final phi1 =
        lat1 * math.pi / 180.0;

    final phi2 =
        lat2 * math.pi / 180.0;

    final dPhi =
        (lat2 - lat1) *
            math.pi /
            180.0;

    final dLambda =
        (lon2 - lon1) *
            math.pi /
            180.0;

    final a =
        math.sin(dPhi / 2) *
            math.sin(dPhi / 2) +
            math.cos(phi1) *
                math.cos(phi2) *
                math.sin(dLambda / 2) *
                math.sin(dLambda / 2);

    final c = 2 *
        math.atan2(
          math.sqrt(a),
          math.sqrt(
            math.max(
              0.0,
              1.0 - a,
            ),
          ),
        );

    return _earthRadius * c;
  }

  int _edgeCount(
      _GraphState graph,
      ) {
    return graph.outgoing.values.fold<int>(
      0,
          (sum, edges) => sum + edges.length,
    );
  }

  // ==========================================================
  // CACHE
  // ==========================================================

  void clearTileCache() {
    _tileCache.clear();

    debugPrint(
      'OFFLINE ROUTING V4: Tile cache cleared.',
    );
  }

  int get cachedTileCount =>
      _tileCache.length;
}

// ============================================================
// SUPPORT CLASSES
// ============================================================

class _NearestNode {
  final _RoutingNode node;
  final double distanceMeters;

  const _NearestNode({
    required this.node,
    required this.distanceMeters,
  });
}

class _AStarResult {
  final List<int> nodePath;
  final List<_RoutingEdge> edgePath;
  final int visitedNodes;

  const _AStarResult({
    required this.nodePath,
    required this.edgePath,
    required this.visitedNodes,
  });
}

class _PathResult {
  final List<int> nodePath;
  final List<_RoutingEdge> edgePath;

  const _PathResult({
    required this.nodePath,
    required this.edgePath,
  });
}