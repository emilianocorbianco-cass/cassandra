import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/theme/cassandra_colors.dart';
import '../../../services/storage/storage_service.dart';

class ProfileImageHelper {
  ProfileImageHelper._();

  static Future<String?> pickAndSaveProfileImage() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 768,
    );
    if (xFile == null) return null;

    final dir = await getApplicationDocumentsDirectory();
    final dest = File('${dir.path}/profile_image.jpg');
    final bytes = await xFile.readAsBytes();
    await dest.writeAsBytes(bytes);
    return dest.path;
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

  @override
  State<ProfileImageDisplay> createState() => _ProfileImageDisplayState();
}

class _ProfileImageDisplayState extends State<ProfileImageDisplay> {
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

  Future<Uint8List?> _loadStorageBytes(String source) {
    try {
      return StorageService().readBytesByReference(source);
    } catch (_) {
      return Future<Uint8List?>.value(null);
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
      _storageBytesFuture = _loadStorageBytes(source);
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
