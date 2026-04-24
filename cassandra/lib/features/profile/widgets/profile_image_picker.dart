import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/theme/cassandra_colors.dart';
import '../../../services/storage/storage_service.dart';
import '../../shared/image_crop_screen.dart';
import '../../shared/image_viewer_overlay.dart';

class ProfileImageHelper {
  ProfileImageHelper._();

  static Future<String?> pickAndSaveProfileImage(BuildContext context) async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1536,
    );
    if (xFile == null) return null;

    final dir = await getApplicationDocumentsDirectory();
    final dest = File('${dir.path}/profile_image.png');
    final pickedFile = File(xFile.path);

    if (!context.mounted) return null;
    final croppedPath = await Navigator.of(context).push<String?>(
      PageRouteBuilder(
        fullscreenDialog: true,
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, __, ___) => ImageCropScreen(
          imageFile: pickedFile,
          outputSize: 768,
          outputPath: dest.path,
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );

    return croppedPath;
  }
}

class ProfileImageDisplay extends StatefulWidget {
  const ProfileImageDisplay({
    super.key,
    required this.imagePathOrUrl,
    this.radius = 24,
  });

  final String? imagePathOrUrl;
  final double radius;

  /// Pre-warm the cache for a given source (call during splash).
  /// Also pre-resolves the cache directory for instant disk reads later.
  static Future<void> preWarmCache(String? source) async {
    // Pre-resolve cache dir so disk reads are instant later.
    _ProfileImageDisplayState._cacheDir ??=
        await getApplicationDocumentsDirectory();

    final s = (source ?? '').trim();
    if (s.isEmpty ||
        _ProfileImageDisplayState._bytesCache.containsKey(s)) {
      return;
    }

    // Try disk cache first (instant if file exists).
    if (StorageService.isStorageReference(s)) {
      final diskBytes = await _ProfileImageDisplayState._loadFromDisk(s);
      if (diskBytes != null && diskBytes.isNotEmpty) {
        _ProfileImageDisplayState._bytesCache[s] = diskBytes;
        return;
      }
    }

    if (!StorageService.isStorageReference(s)) {
      return;
    }
    try {
      final bytes = await StorageService().readBytesByReference(s);
      if (bytes != null && bytes.isNotEmpty) {
        _ProfileImageDisplayState._bytesCache[s] = bytes;
        unawaited(_ProfileImageDisplayState._saveToDisk(s, bytes));
      }
    } catch (_) {}
  }

  @override
  State<ProfileImageDisplay> createState() => _ProfileImageDisplayState();
}

class _ProfileImageDisplayState extends State<ProfileImageDisplay> {
  /// Static in-memory cache so Storage images are instant after first load.
  static final Map<String, Uint8List> _bytesCache = {};

  static const _maxRetries = 3;

  /// Local disk cache directory, resolved once.
  static Directory? _cacheDir;

  String? _cachedSource;
  Future<Uint8List?>? _storageBytesFuture;
  int _retryCount = 0;

  Uint8List? _decodeDataImage(String source) {
    final lower = source.toLowerCase();
    if (!lower.startsWith('data:image/')) return null;
    final comma = source.indexOf(',');
    if (comma <= 0 || comma >= source.length - 1) return null;
    final b64 = source.substring(comma + 1).trim();
    if (b64.isEmpty) return null;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  /// Deterministic local filename from a storage reference.
  /// Uses a simple character-based hash that is stable across app sessions
  /// (unlike Dart's String.hashCode which is randomized per isolate).
  static String _localFileName(String source) {
    var h = 0x811c9dc5; // FNV-1a 32-bit offset basis
    for (var i = 0; i < source.length; i++) {
      h ^= source.codeUnitAt(i);
      h = (h * 0x01000193) & 0xFFFFFFFF; // FNV prime, 32-bit mask
    }
    return 'profile_${h.toRadixString(16)}.png';
  }

  /// Try to load from local disk cache (instant, no network).
  static Future<Uint8List?> _loadFromDisk(String source) async {
    try {
      _cacheDir ??= await getApplicationDocumentsDirectory();
      final file = File('${_cacheDir!.path}/${_localFileName(source)}');
      if (file.existsSync()) return file.readAsBytes();
    } catch (_) {}
    return null;
  }

  /// Persist bytes to local disk cache.
  static Future<void> _saveToDisk(String source, Uint8List bytes) async {
    try {
      _cacheDir ??= await getApplicationDocumentsDirectory();
      final file = File('${_cacheDir!.path}/${_localFileName(source)}');
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {}
  }

  Future<Uint8List?> _loadStorageBytesWithRetry(String source) async {
    // 1. In-memory cache
    final memCached = _bytesCache[source];
    if (memCached != null) return memCached;

    // 2. Local disk cache (instant, no network)
    final diskCached = await _loadFromDisk(source);
    if (diskCached != null && diskCached.isNotEmpty) {
      _bytesCache[source] = diskCached;
      // Refresh from network in background (update local cache silently).
      _refreshFromNetworkInBackground(source);
      return diskCached;
    }

    // 3. Single fast attempt + parallel download-URL resolution.
    //    Start resolving the download URL immediately so it's ready as a
    //    fallback if the direct Storage fetch fails or is slow.
    final urlFuture = StorageService().getDownloadUrl(source);

    try {
      final bytes = await StorageService()
          .readBytesByReference(source)
          .timeout(const Duration(seconds: 8));
      if (bytes != null && bytes.isNotEmpty) {
        _bytesCache[source] = bytes;
        unawaited(_saveToDisk(source, bytes));
        return bytes;
      }
    } catch (_) {}

    // Direct fetch failed — use the download URL resolved in parallel.
    _downloadUrl ??= await urlFuture.timeout(
      const Duration(seconds: 8),
      onTimeout: () => null,
    );
    return null;
  }

  /// Silently refresh from network and update local cache.
  void _refreshFromNetworkInBackground(String source) {
    StorageService().readBytesByReference(source).then((bytes) {
      if (bytes != null && bytes.isNotEmpty) {
        _bytesCache[source] = bytes;
        unawaited(_saveToDisk(source, bytes));
      }
    }).catchError((_) {});
  }

  /// HTTP download URL fallback when direct Storage fetch fails.
  String? _downloadUrl;

  @override
  void initState() {
    super.initState();
    _refreshStorageFutureIfNeeded();
  }

  @override
  void didUpdateWidget(covariant ProfileImageDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshStorageFutureIfNeeded();
  }

  void _refreshStorageFutureIfNeeded() {
    final source = (widget.imagePathOrUrl ?? '').trim();
    if (source == _cachedSource) return;
    _cachedSource = source;
    _retryCount = 0;
    if (StorageService.isStorageReference(source)) {
      final cached = _bytesCache[source];
      if (cached != null) {
        _storageBytesFuture = Future.value(cached);
      } else {
        _storageBytesFuture = _loadStorageBytesWithRetry(source);
      }
    } else {
      _storageBytesFuture = null;
    }
  }

  void _retryLoad() {
    final source = (widget.imagePathOrUrl ?? '').trim();
    if (source.isEmpty || !StorageService.isStorageReference(source)) return;
    if (_retryCount >= _maxRetries) return;
    _retryCount++;
    setState(() {
      _storageBytesFuture = _loadStorageBytesWithRetry(source);
    });
  }

  Widget _tappable(ImageProvider image, Widget avatar) {
    final tag = 'profile_image_${widget.imagePathOrUrl}';
    return GestureDetector(
      onTap: () => ImageViewerOverlay.show(
        context,
        imageProvider: image,
        heroTag: tag,
      ),
      child: Hero(
        tag: tag,
        createRectTween: (begin, end) => RectTween(begin: begin, end: end),
        child: avatar,
      ),
    );
  }

  Widget _placeholder() {
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: CassandraColors.primary,
      child: Icon(
        Icons.person,
        color: CassandraColors.onPrimary,
        size: widget.radius,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final source = (widget.imagePathOrUrl ?? '').trim();
    if (source.isNotEmpty) {
      final dataBytes = _decodeDataImage(source);
      if (dataBytes != null) {
        final img = MemoryImage(dataBytes);
        return _tappable(
          img,
          CircleAvatar(
            radius: widget.radius,
            backgroundImage: img,
          ),
        );
      }
      if (StorageService.isStorageReference(source)) {
        return FutureBuilder<Uint8List?>(
          future: _storageBytesFuture,
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes != null && bytes.isNotEmpty) {
              final img = MemoryImage(bytes);
              return _tappable(
                img,
                CircleAvatar(
                  radius: widget.radius,
                  backgroundImage: img,
                ),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return CircleAvatar(
                radius: widget.radius,
                backgroundColor: CassandraColors.charcoal,
                child: SizedBox(
                  width: widget.radius * 0.6,
                  height: widget.radius * 0.6,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: CassandraColors.brightSnow,
                  ),
                ),
              );
            }
            // Direct Storage fetch failed — try HTTP download URL fallback.
            if (_downloadUrl != null && _downloadUrl!.isNotEmpty) {
              final img = NetworkImage(_downloadUrl!);
              return _tappable(
                img,
                CircleAvatar(
                  radius: widget.radius,
                  foregroundImage: img,
                  backgroundColor: CassandraColors.primary,
                  child: Icon(
                    Icons.person,
                    color: CassandraColors.onPrimary,
                    size: widget.radius,
                  ),
                ),
              );
            }
            // All failed: show placeholder, tap to retry
            return GestureDetector(
              onTap: _retryLoad,
              child: _placeholder(),
            );
          },
        );
      }
      if (source.startsWith('http://') || source.startsWith('https://')) {
        final img = NetworkImage(source);
        return _tappable(
          img,
          CircleAvatar(
            radius: widget.radius,
            foregroundImage: img,
            backgroundColor: CassandraColors.primary,
            child: Icon(
              Icons.person,
              color: CassandraColors.onPrimary,
              size: widget.radius,
            ),
          ),
        );
      }

      final file = File(source);
      if (file.existsSync()) {
        final img = FileImage(file);
        return _tappable(
          img,
          CircleAvatar(
            radius: widget.radius,
            backgroundImage: img,
          ),
        );
      }
    }

    return _placeholder();
  }
}
