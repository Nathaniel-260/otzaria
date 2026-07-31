import 'package:flutter/widgets.dart';

/// מעביר את רצועת הכרטיסיות של חלונית אל הסרגל העליון של המסך שבתוכה.
///
/// כך הרצועה תופסת את מקום הכותרת במקום להוסיף שורה: הכרטיסייה המוצגת היא
/// הכותרת, ומספר שורות הרהיטים בטאב מפוצל אינו גדל.
class PaneTabsScope extends InheritedWidget {
  /// הרצועה שתוצג במקום הכותרת. `null` כשהמסך אינו חלונית בטאב מפוצל, או
  /// כשהוא מוסתר מאחורי כרטיסייה אחרת.
  final Widget? strip;

  const PaneTabsScope({super.key, required this.strip, required super.child});

  static Widget? stripOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PaneTabsScope>()?.strip;

  @override
  bool updateShouldNotify(PaneTabsScope oldWidget) =>
      !identical(oldWidget.strip, strip);
}
