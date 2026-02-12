import 'dart:io';

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
    final path = imagePath;
    if (path != null && File(path).existsSync()) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: FileImage(File(path)),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: CassandraColors.primary,
      child: Icon(Icons.groups, color: Colors.white, size: radius),
    );
  }
}
