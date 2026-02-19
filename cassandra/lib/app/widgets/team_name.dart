import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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

  bool _isSvgUrl(String value) {
    final lower = value.toLowerCase().trim();
    if (lower.endsWith('.svg')) return true;
    final queryIndex = lower.indexOf('?');
    if (queryIndex > 0) {
      return lower.substring(0, queryIndex).endsWith('.svg');
    }
    return false;
  }

  String _normalizeLogoUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('http://')) {
      return 'https://${trimmed.substring('http://'.length)}';
    }
    return trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = style ?? DefaultTextStyle.of(context).style;
    final fontSize = effectiveStyle.fontSize ?? 14.0;
    // Altezza logo ≈ altezza lettera maiuscola (circa 70-75% del fontSize)
    final logoSize = fontSize * logoScale;

    final normalized = name.trim().toLowerCase();
    final isJuventus = normalized == 'juventus';
    final rawUrl = logoUrl;
    if (!isJuventus && (rawUrl == null || rawUrl.isEmpty)) {
      return Text(name, style: effectiveStyle, textAlign: textAlign);
    }
    final url = rawUrl == null ? null : _normalizeLogoUrl(rawUrl);

    final logoWidget = isJuventus
        ? SvgPicture.asset(
            'assets/logos/juventus_mark.svg',
            width: logoSize,
            height: logoSize,
            fit: BoxFit.contain,
          )
        : _isSvgUrl(url!)
        ? SvgPicture.network(
            url,
            width: logoSize,
            height: logoSize,
            fit: BoxFit.contain,
            placeholderBuilder: (_) =>
                SizedBox(width: logoSize, height: logoSize),
          )
        : Image.network(
            url,
            width: logoSize,
            height: logoSize,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) =>
                SizedBox(width: logoSize, height: logoSize),
          );

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
      child: logoWidget,
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
