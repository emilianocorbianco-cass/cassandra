import 'dart:ui';

import 'package:flutter/material.dart';

/// A reusable Liquid Glass card widget.
///
/// Renders a frosted-glass surface using [BackdropFilter] + an asymmetric
/// specular border (bright top-left, dim bottom-right) to simulate a light
/// source coming from the top-left — matching Apple visionOS aesthetics.
///
/// Usage:
/// ```dart
/// GlassCard(
///   borderRadius: 16,
///   padding: EdgeInsets.all(12),
///   child: MyContent(),
/// )
/// ```
///
/// Note: [BackdropFilter] requires a non-opaque background **behind** this
/// widget. Wrap the ancestor Scaffold in a gradient `DecoratedBox` so the
/// blur effect is visible.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = 16.0,
    this.padding = const EdgeInsets.all(12),
    this.margin,
    this.fillOpacity = 0.70,
    this.blur = 12.0,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  /// Opacity of the white fill (0.0 → fully transparent, 1.0 → opaque).
  /// Typical range: 0.60–0.80 for a "frosted" look.
  final double fillOpacity;

  /// Blur radius for the BackdropFilter (sigmaX == sigmaY).
  /// Higher values look better but cost more GPU.
  final double blur;

  @override
  Widget build(BuildContext context) {
    // The shadow lives OUTSIDE the ClipRRect so it isn't clipped away.
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 20,
            spreadRadius: -2,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 5,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              // Semi-transparent white fill — picks up ambient color from blur
              color: Colors.white.withValues(alpha: fillOpacity),
              // Specular border: bright top-left, dim bottom-right
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.88),
                  width: 1.0,
                ),
                left: BorderSide(
                  color: Colors.white.withValues(alpha: 0.65),
                  width: 1.0,
                ),
                right: BorderSide(
                  color: Colors.white.withValues(alpha: 0.20),
                  width: 0.5,
                ),
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 0.5,
                ),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
