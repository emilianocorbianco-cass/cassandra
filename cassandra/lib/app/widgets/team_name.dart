import 'package:flutter/material.dart';

class TeamName extends StatelessWidget {
  const TeamName({
    super.key,
    required this.name,
    this.logoUrl,
    this.style,
    this.textAlign,
    this.reversed = false,
    this.logoScale = 1.0,
  });

  final String name;
  final String? logoUrl;
  final TextStyle? style;
  final TextAlign? textAlign;
  final double logoScale;

  /// Se true, mostra testo-logo (allineamento destra) anziché logo-testo.
  final bool reversed;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = style ?? DefaultTextStyle.of(context).style;
    final fontSize = effectiveStyle.fontSize ?? 14.0;
    // Altezza logo ≈ altezza lettera maiuscola (circa 70-75% del fontSize)
    final logoSize = fontSize * logoScale;

    final url = logoUrl;
    if (url == null || url.isEmpty) {
      return Text(name, style: effectiveStyle, textAlign: textAlign);
    }

    final logo = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.6),
            blurRadius: 1.5,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: Image.network(
        url,
        width: logoSize,
        height: logoSize,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) =>
            SizedBox(width: logoSize, height: logoSize),
      ),
    );

    final text = Flexible(
      child: Text(
        name,
        style: effectiveStyle,
        textAlign: textAlign,
        overflow: TextOverflow.ellipsis,
      ),
    );

    final gap = SizedBox(width: fontSize * 0.35);

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: reversed
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: reversed ? [text, gap, logo] : [logo, gap, text],
    );
  }
}
