import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/theme/cassandra_colors.dart';
import '../../../services/storage/storage_service.dart';
import '../../shared/image_crop_screen.dart';

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
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImageCropScreen(
          imageFile: pickedFile,
          outputSize: 768,
          outputPath: dest.path,
        ),
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

  String? _cachedSource;
  Future<Uint8List?>? _storageBytesFuture;

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

  Future<Uint8List?> _loadStorageBytes(String source) async {
    final cached = _bytesCache[source];
    if (cached != null) return cached;
    try {
      final bytes = await StorageService().readBytesByReference(source);
      if (bytes != null && bytes.isNotEmpty) {
        _bytesCache[source] = bytes;
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

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
    if (StorageService.isStorageReference(source)) {
      // Return instantly from cache if available.
      final cached = _bytesCache[source];
      if (cached != null) {
        _storageBytesFuture = Future.value(cached);
      } else {
        _storageBytesFuture = _loadStorageBytes(source);
      }
    } else {
      _storageBytesFuture = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = (widget.imagePathOrUrl ?? '').trim();
    if (source.isNotEmpty) {
      final dataBytes = _decodeDataImage(source);
      if (dataBytes != null) {
        return CircleAvatar(
          radius: widget.radius,
          backgroundImage: MemoryImage(dataBytes),
        );
      }
      if (StorageService.isStorageReference(source)) {
        return FutureBuilder<Uint8List?>(
          future: _storageBytesFuture,
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes != null && bytes.isNotEmpty) {
              return CircleAvatar(
                radius: widget.radius,
                backgroundImage: MemoryImage(bytes),
              );
            }
            return CircleAvatar(
              radius: widget.radius,
              backgroundColor: CassandraColors.primary,
              child: Icon(
                Icons.person,
                color: CassandraColors.onPrimary,
                size: widget.radius,
              ),
            );
          },
        );
      }
      if (source.startsWith('http://') || source.startsWith('https://')) {
        return CircleAvatar(
          radius: widget.radius,
          foregroundImage: NetworkImage(source),
          backgroundColor: CassandraColors.primary,
          child: Icon(
            Icons.person,
            color: CassandraColors.onPrimary,
            size: widget.radius,
          ),
        );
      }

      final file = File(source);
      if (file.existsSync()) {
        return CircleAvatar(
          radius: widget.radius,
          backgroundImage: FileImage(file),
        );
      }
    }

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
}
