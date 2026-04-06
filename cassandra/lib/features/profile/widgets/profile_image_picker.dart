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
  static Future<void> preWarmCache(String? source) async {
    final s = (source ?? '').trim();
    if (s.isEmpty ||
        _ProfileImageDisplayState._bytesCache.containsKey(s)) {
      return;
    }
    if (!StorageService.isStorageReference(s)) {
      return;
    }
    try {
      final bytes = await StorageService().readBytesByReference(s);
      if (bytes != null && bytes.isNotEmpty) {
        _ProfileImageDisplayState._bytesCache[s] = bytes;
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

  Future<Uint8List?> _loadStorageBytesWithRetry(String source) async {
    final cached = _bytesCache[source];
    if (cached != null) return cached;
    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        final bytes = await StorageService().readBytesByReference(source);
        if (bytes != null && bytes.isNotEmpty) {
          _bytesCache[source] = bytes;
          return bytes;
        }
      } catch (_) {}
      if (attempt < _maxRetries) {
        await Future<void>.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }
    // Fallback: resolve download URL and fetch via HTTP.
    _downloadUrl ??= await StorageService().getDownloadUrl(source);
    return null;
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
