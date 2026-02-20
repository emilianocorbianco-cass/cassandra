import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/theme/cassandra_colors.dart';

class GroupImageHelper {
  GroupImageHelper._();

  static Future<String?> pickAndSaveGroupImage() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
    );
    if (xFile == null) return null;

    final dir = await getApplicationDocumentsDirectory();
    final dest = File('${dir.path}/group_image.jpg');
    final bytes = await xFile.readAsBytes();
    await dest.writeAsBytes(bytes);
    return dest.path;
  }
}

class GroupImageDisplay extends StatelessWidget {
  final String? imagePath;
  final double radius;

  const GroupImageDisplay({
    super.key,
    required this.imagePath,
    this.radius = 28,
  });

  @override
  Widget build(BuildContext context) {
    final source = (imagePath ?? '').trim();
    if (source.isNotEmpty) {
      final lower = source.toLowerCase();
      if (lower.startsWith('data:image/')) {
        final comma = source.indexOf(',');
        if (comma > 0 && comma < source.length - 1) {
          final b64 = source.substring(comma + 1).trim();
          if (b64.isNotEmpty) {
            try {
              final bytes = base64Decode(b64);
              return CircleAvatar(
                radius: radius,
                backgroundImage: MemoryImage(Uint8List.fromList(bytes)),
              );
            } catch (_) {
              // ignore malformed data URI
            }
          }
        }
      }

      if (source.startsWith('http://') || source.startsWith('https://')) {
        return CircleAvatar(
          radius: radius,
          backgroundImage: NetworkImage(source),
        );
      }

      if (File(source).existsSync()) {
        return CircleAvatar(
          radius: radius,
          backgroundImage: FileImage(File(source)),
        );
      }
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: CassandraColors.primary,
      child: Icon(Icons.groups, color: Colors.white, size: radius),
    );
  }
}
