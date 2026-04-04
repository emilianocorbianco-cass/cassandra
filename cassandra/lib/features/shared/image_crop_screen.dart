import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../app/theme/cassandra_colors.dart';
import '../../l10n/app_localizations.dart';

class ImageCropScreen extends StatefulWidget {
  const ImageCropScreen({
    super.key,
    required this.imageFile,
    required this.outputSize,
    required this.outputPath,
  });

  final File imageFile;
  final double outputSize;
  final String outputPath;

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen>
    with SingleTickerProviderStateMixin {
  final _boundaryKey = GlobalKey();
  final _transformController = TransformationController();
  late final AnimationController _snapController;
  Animation<Matrix4>? _snapAnimation;
  bool _saving = false;
  bool _initialTransformSet = false;

  /// Original image pixel dimensions (null while loading).
  Size? _imagePixelSize;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
        if (_snapAnimation != null) {
          _transformController.value = _snapAnimation!.value;
        }
      });
    _loadImageDimensions();
  }

  @override
  void dispose() {
    _snapController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  Future<void> _loadImageDimensions() async {
    final bytes = await widget.imageFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size = Size(
      frame.image.width.toDouble(),
      frame.image.height.toDouble(),
    );
    frame.image.dispose();
    if (!mounted) return;
    setState(() => _imagePixelSize = size);
  }

  // ---- geometry helpers ----

  double _circleSize(BuildContext ctx) =>
      MediaQuery.sizeOf(ctx).shortestSide * 0.82;

  Rect _circleRect(BuildContext ctx) {
    final size = MediaQuery.sizeOf(ctx);
    final circle = _circleSize(ctx);
    final top = (size.height - circle) / 2 - 30;
    return Rect.fromLTWH((size.width - circle) / 2, top, circle, circle);
  }

  /// Image display size: scaled so its shorter side equals the screen's
  /// shortest side, preserving the original aspect ratio.
  Size _displaySize(BuildContext ctx) {
    final img = _imagePixelSize!;
    final screenShort = MediaQuery.sizeOf(ctx).shortestSide;
    final scale = screenShort / img.shortestSide;
    return Size(img.width * scale, img.height * scale);
  }

  /// Minimum InteractiveViewer scale: the image's shorter visual dimension
  /// must still equal the circle diameter.
  double _minScale(BuildContext ctx) {
    final display = _displaySize(ctx);
    final circle = _circleSize(ctx);
    return circle / display.shortestSide;
  }

  // ---- interaction ----

  void _onInteractionStart(ScaleStartDetails _) {
    _snapController.stop();
  }

  void _onInteractionEnd(ScaleEndDetails _) {
    final display = _displaySize(context);
    final rect = _circleRect(context);
    final matrix = _transformController.value.clone();

    final scale = matrix.getMaxScaleOnAxis();
    final tx = matrix[12];
    final ty = matrix[13];

    final imgW = display.width * scale;
    final imgH = display.height * scale;

    // Clamp translation so the image fully covers the circle.
    final clampedTx = tx.clamp(rect.right - imgW, rect.left).toDouble();
    final clampedTy = ty.clamp(rect.bottom - imgH, rect.top).toDouble();

    if ((clampedTx - tx).abs() < 0.5 && (clampedTy - ty).abs() < 0.5) return;

    final target = matrix.clone();
    target[12] = clampedTx;
    target[13] = clampedTy;

    _snapAnimation = Matrix4Tween(
      begin: _transformController.value,
      end: target,
    ).animate(
      CurvedAnimation(parent: _snapController, curve: Curves.easeOut),
    );
    _snapController.forward(from: 0);
  }

  // ---- save / capture ----

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      final rect = _circleRect(context);
      final dpr = MediaQuery.devicePixelRatioOf(context);

      final fullImage = await boundary.toImage(pixelRatio: dpr);

      final out = widget.outputSize;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.clipPath(Path()..addOval(Rect.fromLTWH(0, 0, out, out)));
      canvas.drawImageRect(
        fullImage,
        Rect.fromLTWH(
          rect.left * dpr,
          rect.top * dpr,
          rect.width * dpr,
          rect.height * dpr,
        ),
        Rect.fromLTWH(0, 0, out, out),
        Paint()..filterQuality = FilterQuality.high,
      );

      final picture = recorder.endRecording();
      final cropped = await picture.toImage(out.toInt(), out.toInt());
      final byteData = await cropped.toByteData(
        format: ui.ImageByteFormat.png,
      );

      fullImage.dispose();
      cropped.dispose();

      if (byteData == null) return;
      await File(widget.outputPath).writeAsBytes(
        byteData.buffer.asUint8List(),
      );

      if (!mounted) return;
      Navigator.of(context).pop(widget.outputPath);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final circleRect = _circleRect(context);

    // Show blank screen while decoding image dimensions.
    if (_imagePixelSize == null) {
      return const Scaffold(backgroundColor: Colors.black);
    }

    final display = _displaySize(context);

    // Centre the image on the circle before the first frame.
    if (!_initialTransformSet) {
      _initialTransformSet = true;
      _transformController.value = Matrix4.identity()
        ..setEntry(0, 3, circleRect.center.dx - display.width / 2)
        ..setEntry(1, 3, circleRect.center.dy - display.height / 2);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full-screen zoomable / pannable image
          Positioned.fill(
            child: RepaintBoundary(
              key: _boundaryKey,
              child: InteractiveViewer(
                transformationController: _transformController,
                constrained: false,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                minScale: _minScale(context),
                maxScale: 5,
                onInteractionStart: _onInteractionStart,
                onInteractionEnd: _onInteractionEnd,
                child: SizedBox(
                  width: display.width,
                  height: display.height,
                  child: Image.file(widget.imageFile, fit: BoxFit.fill),
                ),
              ),
            ),
          ),
          // Dark overlay with circular cutout
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _CircleHolePainter(circleRect: circleRect),
              ),
            ),
          ),
          // White circle border ring
          Positioned.fromRect(
            rect: circleRect,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.6),
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
          // Close button
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(context).pop(null),
            ),
          ),
          // Save button
          Positioned(
            left: 32,
            right: 32,
            bottom: MediaQuery.paddingOf(context).bottom + 24,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: CassandraColors.platinum,
                foregroundColor: CassandraColors.inkBlackV2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: CassandraColors.inkBlackV2,
                      ),
                    )
                  : Text(l10n.settingsSave),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleHolePainter extends CustomPainter {
  _CircleHolePainter({required this.circleRect});

  final Rect circleRect;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.7);
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, paint);
    canvas.drawOval(circleRect, Paint()..blendMode = BlendMode.clear);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CircleHolePainter oldDelegate) =>
      circleRect != oldDelegate.circleRect;
}
