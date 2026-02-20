import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/theme/cassandra_colors.dart';

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

class ProfileImageDisplay extends StatelessWidget {
  const ProfileImageDisplay({
    super.key,
    required this.imagePathOrUrl,
    this.radius = 24,
  });

  final String? imagePathOrUrl;
  final double radius;

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

  @override
  Widget build(BuildContext context) {
    final source = (imagePathOrUrl ?? '').trim();
    if (source.isNotEmpty) {
      final dataBytes = _decodeDataImage(source);
      if (dataBytes != null) {
        return CircleAvatar(
          radius: radius,
          backgroundImage: MemoryImage(dataBytes),
        );
      }
      if (source.startsWith('http://') || source.startsWith('https://')) {
        return CircleAvatar(
          radius: radius,
          foregroundImage: NetworkImage(source),
          backgroundColor: CassandraColors.primary,
          child: Icon(
            Icons.person,
            color: CassandraColors.onPrimary,
            size: radius,
          ),
        );
      }

      final file = File(source);
      if (file.existsSync()) {
        return CircleAvatar(radius: radius, backgroundImage: FileImage(file));
      }
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: CassandraColors.primary,
      child: Icon(Icons.person, color: CassandraColors.onPrimary, size: radius),
    );
  }
}
