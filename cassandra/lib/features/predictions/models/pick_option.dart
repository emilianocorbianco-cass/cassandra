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

  // Knockout — 90 minuti (risultato ai tempi regolamentari)
  homeReg, // "1 (90')"
  drawReg, // "X (90')"
  awayReg, // "2 (90')"
  // Knockout — supplementari
  homeEt, // "1 (120')"
  drawEt, // "X (120')" — pareggio anche dopo i supplementari → rigori
  awayEt, // "2 (120')"
  // Knockout — rigori
  homePen, // "1 (rig.)"
  awayPen, // "2 (rig.)"
}

extension PickOptionX on PickOption {
  bool get isNone => this == PickOption.none;

  bool get isSingle =>
      this == PickOption.home ||
      this == PickOption.draw ||
      this == PickOption.away;

  bool get isDouble =>
      this == PickOption.homeDraw ||
      this == PickOption.drawAway ||
      this == PickOption.homeAway;

  bool get isKnockout =>
      this == PickOption.homeReg ||
      this == PickOption.drawReg ||
      this == PickOption.awayReg ||
      this == PickOption.homeEt ||
      this == PickOption.drawEt ||
      this == PickOption.awayEt ||
      this == PickOption.homePen ||
      this == PickOption.awayPen;

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
      case PickOption.homeReg:
        return "1 (90')";
      case PickOption.drawReg:
        return "X (90')";
      case PickOption.awayReg:
        return "2 (90')";
      case PickOption.homeEt:
        return "1 (120')";
      case PickOption.drawEt:
        return "X (120')";
      case PickOption.awayEt:
        return "2 (120')";
      case PickOption.homePen:
        return '1 (rig.)';
      case PickOption.awayPen:
        return '2 (rig.)';
    }
  }
}
