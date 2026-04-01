import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/theme/cassandra_colors.dart';
import '../../../services/storage/storage_service.dart';
import '../../shared/image_crop_screen.dart';
import '../../shared/image_viewer_overlay.dart';

class GroupImageHelper {
  GroupImageHelper._();

  static Future<String?> pickAndSaveGroupImage(BuildContext context) async {
    // Capture navigator before async gap — context may become unmounted
    // after the native image picker returns (iOS lifecycle rebuild).
    final navigator = Navigator.of(context, rootNavigator: true);

    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
    );
    if (xFile == null) return null;

    final dir = await getApplicationDocumentsDirectory();
    final dest = File('${dir.path}/group_image.png');
    final pickedFile = File(xFile.path);

    final croppedPath = await navigator.push<String?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImageCropScreen(
          imageFile: pickedFile,
          outputSize: 512,
          outputPath: dest.path,
        ),
      ),
    );

    return croppedPath;
  }
}

class GroupImageDisplay extends StatefulWidget {
  final String? imagePath;
  final double radius;

  const GroupImageDisplay({
    super.key,
    required this.imagePath,
    this.radius = 28,
  });

  @override
  State<GroupImageDisplay> createState() => _GroupImageDisplayState();
}

class _GroupImageDisplayState extends State<GroupImageDisplay> {
  String? _cachedSource;
  ImageProvider<Object>? _resolvedImage;

  @override
  void initState() {
    super.initState();
    _loadImageIfNeeded();
  }

  @override
  void didUpdateWidget(covariant GroupImageDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadImageIfNeeded();
  }

  void _loadImageIfNeeded() {
    final source = (widget.imagePath ?? '').trim();
    if (source == _cachedSource) return;
    _cachedSource = source;

    if (source.isEmpty) {
      _resolvedImage = null;
      return;
    }

    final lower = source.toLowerCase();

    // data:image URI — decode sincrono
    if (lower.startsWith('data:image/')) {
      final comma = source.indexOf(',');
      if (comma > 0 && comma < source.length - 1) {
        final b64 = source.substring(comma + 1).trim();
        if (b64.isNotEmpty) {
          try {
            _resolvedImage = MemoryImage(base64Decode(b64));
            return;
          } catch (_) {}
        }
      }
      _resolvedImage = null;
      return;
    }

    // storage:// reference — fetch asincrono, setState quando arriva
    if (StorageService.isStorageReference(source)) {
      // Non resettare _resolvedImage qui: la vecchia immagine resta visibile
      // fino a quando arrivano i nuovi bytes (evita flash).
      StorageService().readBytesByReference(source).then((bytes) {
        if (!mounted) return;
        if ((widget.imagePath ?? '').trim() != source) return;
        setState(() {
          _resolvedImage = (bytes != null && bytes.isNotEmpty)
              ? MemoryImage(bytes)
              : null;
        });
      });
      return;
    }

    // URL HTTP
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      _resolvedImage = NetworkImage(source);
      return;
    }

    // File locale
    if (File(source).existsSync()) {
      _resolvedImage = FileImage(File(source));
      return;
    }

    _resolvedImage = null;
  }

  void _openFullScreen() {
    if (_resolvedImage == null) return;
    ImageViewerOverlay.show(
      context,
      imageProvider: _resolvedImage!,
      heroTag: 'group_image_${widget.imagePath}',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_resolvedImage != null) {
      return GestureDetector(
        onTap: _openFullScreen,
        child: Hero(
          tag: 'group_image_${widget.imagePath}',
          createRectTween: (begin, end) => RectTween(begin: begin, end: end),
          child: CircleAvatar(
            radius: widget.radius,
            backgroundImage: _resolvedImage,
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: CassandraColors.primary,
      child: Icon(Icons.groups, color: Colors.white, size: widget.radius),
    );
  }
}
