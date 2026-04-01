import 'package:flutter/material.dart';

/// Full-screen overlay that shows an image clipped in a circle with
/// tap-to-dismiss. Supports Hero animation when a [heroTag] is provided.
class ImageViewerOverlay extends StatelessWidget {
  const ImageViewerOverlay({
    super.key,
    required this.imageProvider,
    this.heroTag,
  });

  final ImageProvider imageProvider;
  final String? heroTag;

  /// Opens the overlay as a modal route with fade transition.
  static void show(
    BuildContext context, {
    required ImageProvider imageProvider,
    String? heroTag,
  }) {
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black87,
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, animation, secondaryAnimation) => ImageViewerOverlay(
          imageProvider: imageProvider,
          heroTag: heroTag,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final diameter = screenSize.width * 0.75;

    final circleImage = Center(
      child: ClipOval(
        child: SizedBox(
          width: diameter,
          height: diameter,
          child: Image(
            image: imageProvider,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );

    final imageWidget = heroTag != null
        ? Hero(
            tag: heroTag!,
            flightShuttleBuilder: (_, animation, direction, fromContext, toContext) {
              // Use the destination widget during flight for consistent look.
              return toContext.widget;
            },
            createRectTween: (begin, end) {
              // Linear path instead of the default curved materialRectArc.
              return RectTween(begin: begin, end: end);
            },
            child: circleImage,
          )
        : circleImage;

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: imageWidget),
      ),
    );
  }
}
