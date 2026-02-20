import 'package:flutter/material.dart';
import '../theme/cassandra_colors.dart';

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

  static const Map<String, String> _bundledLogosByTeam = {
    'atalanta': 'assets/logos/atalanta.png',
    'bologna': 'assets/logos/bologna.png',
    'cagliari': 'assets/logos/cagliari.png',
    'como': 'assets/logos/como.png',
    'cremonese': 'assets/logos/cremonese.png',
    'fiorentina': 'assets/logos/fiorentina.png',
    'genoa': 'assets/logos/genoa.png',
    'inter': 'assets/logos/inter.png',
    'juventus': 'assets/logos/juventus.png',
    'lazio': 'assets/logos/lazio.png',
    'lecce': 'assets/logos/lecce.png',
    'milan': 'assets/logos/milan.png',
    'ac milan': 'assets/logos/milan.png',
    'napoli': 'assets/logos/napoli.png',
    'parma': 'assets/logos/parma.png',
    'pisa': 'assets/logos/pisa.png',
    'roma': 'assets/logos/roma.png',
    'as roma': 'assets/logos/roma.png',
    'sassuolo': 'assets/logos/sassuolo.png',
    'torino': 'assets/logos/torino.png',
    'udinese': 'assets/logos/udinese.png',
    'verona': 'assets/logos/verona.png',
  };

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
    if (trimmed.isEmpty) return trimmed;
    if (trimmed.startsWith('assets/')) return trimmed;
    if (trimmed.startsWith('/assets/')) return trimmed.substring(1);
    if (trimmed.startsWith('//')) return 'https:$trimmed';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    if (trimmed.contains('://')) return trimmed;
    if (trimmed.contains('.') && trimmed.contains('/')) {
      return 'https://$trimmed';
    }
    return trimmed;
  }

  String _teamKey(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }

  String? _bundledLogoForTeamName(String teamName) {
    final key = _teamKey(teamName);
    if (key.isEmpty) return null;
    final direct = _bundledLogosByTeam[key];
    if (direct != null) return direct;
    for (final entry in _aliasesByTeam.entries) {
      final teamAsset = _bundledLogosByTeam[entry.key];
      if (teamAsset == null) continue;
      final aliases = entry.value;
      final matches = aliases.any((alias) => key.contains(alias));
      if (matches) return teamAsset;
    }
    return null;
  }

  static const Map<String, List<String>> _aliasesByTeam = {
    'atalanta': ['atalanta'],
    'bologna': ['bologna'],
    'cagliari': ['cagliari'],
    'como': ['como'],
    'cremonese': ['cremonese'],
    'fiorentina': ['fiorentina'],
    'genoa': ['genoa'],
    'inter': ['inter', 'internazionale'],
    'juventus': ['juventus'],
    'lazio': ['lazio'],
    'lecce': ['lecce'],
    'milan': ['milan'],
    'napoli': ['napoli'],
    'parma': ['parma'],
    'pisa': ['pisa'],
    'roma': ['roma'],
    'sassuolo': ['sassuolo'],
    'torino': ['torino'],
    'udinese': ['udinese'],
    'verona': ['verona', 'hellas'],
  };

  String _svgToPngUrl(String value) {
    final trimmed = value.trim();
    final match = RegExp(
      r'^(.*)\.svg(\?.*)?$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (match == null) return trimmed;
    final base = match.group(1) ?? trimmed;
    final query = match.group(2) ?? '';
    return '$base.png$query';
  }

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = (style ?? DefaultTextStyle.of(context).style)
        .copyWith(color: style?.color ?? CassandraColors.slate);
    final fontSize = effectiveStyle.fontSize ?? 14.0;
    // Altezza logo ≈ altezza lettera maiuscola (circa 70-75% del fontSize)
    final logoSize = fontSize * logoScale;

    final bundledAsset = _bundledLogoForTeamName(name);
    final rawUrl = logoUrl;
    if (bundledAsset == null && (rawUrl == null || rawUrl.isEmpty)) {
      return Text(name, style: effectiveStyle, textAlign: textAlign);
    }
    final url = rawUrl == null ? null : _normalizeLogoUrl(rawUrl);

    final logoWidget = bundledAsset != null
        ? Image.asset(
            bundledAsset,
            width: logoSize,
            height: logoSize,
            fit: BoxFit.contain,
          )
        : url != null && url.startsWith('assets/')
        ? Image.asset(
            url,
            width: logoSize,
            height: logoSize,
            fit: BoxFit.contain,
          )
        : _isSvgUrl(url!)
        ? Image.network(
            _svgToPngUrl(url),
            width: logoSize,
            height: logoSize,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) =>
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
      children: reversed ? [text, gap, logoWidget] : [logoWidget, gap, text],
    );
  }
}
