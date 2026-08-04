import 'package:flutter/material.dart';

/// מילימטר אחד בפיקסלים לוגיים, לפי 96dpi — אותה המרה שדפדפנים עושים ל-`mm`.
/// כל המידות מוגדרות במ"מ כדי שעמוד A4 על המסך יתאים לעמוד A4 מודפס.
const double kMmToLogicalPx = 96 / 25.4;

/// גדלי נייר מוכנים.
enum PagePaperSize {
  a4(widthMm: 210, heightMm: 297, label: 'A4'),
  letter(widthMm: 215.9, heightMm: 279.4, label: 'Letter');

  const PagePaperSize({
    required this.widthMm,
    required this.heightMm,
    required this.label,
  });

  final double widthMm;
  final double heightMm;
  final String label;

  double get widthPx => widthMm * kMmToLogicalPx;
  double get heightPx => heightMm * kMmToLogicalPx;
}

/// גאומטריה של עמוד פיזי בתצוגת העמודים.
///
/// כל המידות בפיקסלים לוגיים. [columnWidth] הוא הרוחב שהעימוד מודד בו **וגם**
/// הרוחב שהתצוגה מציירת בו — חובה להעביר אותו כ-`SizedBox(width:)` מפורש ולא
/// להסתמך על `Expanded`, אחרת המדידה והציור מתפצלים ושורה נחתכת בתחתית העמוד.
@immutable
class PageGeometry {
  final double width;
  final double height;
  final EdgeInsets margins;

  /// מספר הטורים בעמוד — 1 או 2.
  final int columns;

  /// המרווח בין הטורים (רק כשיש יותר מטור אחד).
  final double columnGap;

  /// הגובה השמור בתחתית העמוד למספר העמוד.
  final double headerHeight;

  /// המרווח האנכי בין סעיף לסעיף.
  final double sectionGap;

  const PageGeometry({
    required this.width,
    required this.height,
    required this.margins,
    required this.columns,
    required this.columnGap,
    required this.headerHeight,
    required this.sectionGap,
  }) : assert(columns == 1 || columns == 2, 'נתמכים טור אחד או שניים');

  /// עמוד לפי גודל נייר מוכן, עם שוליים ומרווחים במילימטרים.
  factory PageGeometry.paper(
    PagePaperSize paper, {
    int columns = 2,
    double marginMm = 18,
    double columnGapMm = 7,
    double headerMm = 8,
    double sectionGapMm = 1.5,
  }) {
    final margin = marginMm * kMmToLogicalPx;
    return PageGeometry(
      width: paper.widthPx,
      height: paper.heightPx,
      margins: EdgeInsets.all(margin),
      columns: columns,
      columnGap: columnGapMm * kMmToLogicalPx,
      headerHeight: headerMm * kMmToLogicalPx,
      sectionGap: sectionGapMm * kMmToLogicalPx,
    );
  }

  /// הרוחב הפנוי לטקסט אחרי השוליים.
  double get contentWidth => width - margins.horizontal;

  /// הגובה הפנוי לטקסט אחרי השוליים ואזור מספר העמוד.
  double get contentHeight => height - margins.vertical - headerHeight;

  /// רוחב טור בודד — היחידה שהמדידה והציור חייבים לחלוק.
  double get columnWidth {
    final result = (contentWidth - columnGap * (columns - 1)) / columns;
    // שוליים או מרווח גדולים מהעמוד נותנים רוחב שלילי, והמדידה הייתה נכשלת
    // מאוחר יותר בלי לומר למה.
    assert(result > 0, 'השוליים והמרווח גדולים מרוחב העמוד');
    return result;
  }

  /// כמה טקסט נכנס בעמוד שלם: כל הטורים יחד.
  double get totalColumnHeight => contentHeight * columns;

  /// אותה גאומטריה בטור אחד — לשימוש במסך צר, שבו העמוד שומר על גודלו
  /// ורק מפסיק להתפצל.
  PageGeometry get singleColumn => columns == 1 ? this : copyWith(columns: 1);

  PageGeometry copyWith({
    double? width,
    double? height,
    EdgeInsets? margins,
    int? columns,
    double? columnGap,
    double? headerHeight,
    double? sectionGap,
  }) {
    return PageGeometry(
      width: width ?? this.width,
      height: height ?? this.height,
      margins: margins ?? this.margins,
      columns: columns ?? this.columns,
      columnGap: columnGap ?? this.columnGap,
      headerHeight: headerHeight ?? this.headerHeight,
      sectionGap: sectionGap ?? this.sectionGap,
    );
  }

  /// מפתח יציב למטמון העימוד. מעוגל למאית פיקסל — חישובי מ"מ מייצרים שברים
  /// ארוכים, ושינוי ברמת ה-1e-12 אינו משנה שבירת שורות.
  String get cacheKey {
    String n(double v) => v.toStringAsFixed(2);
    return 'w${n(width)},h${n(height)},'
        'm${n(margins.left)}/${n(margins.top)}/'
        '${n(margins.right)}/${n(margins.bottom)},'
        'c$columns,g${n(columnGap)},f${n(headerHeight)},s${n(sectionGap)}';
  }

  @override
  bool operator ==(Object other) =>
      other is PageGeometry &&
      other.width == width &&
      other.height == height &&
      other.margins == margins &&
      other.columns == columns &&
      other.columnGap == columnGap &&
      other.headerHeight == headerHeight &&
      other.sectionGap == sectionGap;

  @override
  int get hashCode => Object.hash(
    width,
    height,
    margins,
    columns,
    columnGap,
    headerHeight,
    sectionGap,
  );

  @override
  String toString() => 'PageGeometry($cacheKey)';
}
