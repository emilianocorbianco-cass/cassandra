enum PickOption {
  none,

  // Singole (1 / X / 2)
  home, // "1"
  draw, // "X"
  away, // "2"

  // Doppie chance (1X / X2 / 12)
  homeDraw, // "1X"
  drawAway, // "X2"
  homeAway, // "12"
}

extension PickOptionX on PickOption {
  bool get isNone => this == PickOption.none;

  bool get isSingle =>
      this == PickOption.home || this == PickOption.draw || this == PickOption.away;

  bool get isDouble =>
      this == PickOption.homeDraw ||
      this == PickOption.drawAway ||
      this == PickOption.homeAway;

  String get label {
    switch (this) {
      case PickOption.none:
        return '-';
      case PickOption.home:
        return '1';
      case PickOption.draw:
        return 'X';
      case PickOption.away:
        return '2';
      case PickOption.homeDraw:
        return '1X';
      case PickOption.drawAway:
        return 'X2';
      case PickOption.homeAway:
        return '12';
    }
  }
}
