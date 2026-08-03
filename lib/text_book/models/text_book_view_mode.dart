/// מצב התצוגה של קורא הטקסט.
///
/// מקור האמת היחיד לשאלה "איזו תצוגה פעילה". שדות בוליאניים נפרדים לכל תצוגה
/// היו מאפשרים שילובים לא-חוקיים (שתי תצוגות דולקות יחד), ולכן ה-state מחזיק
/// את ה-enum ומספק getters נגזרים.
enum TextBookViewMode {
  /// מפרשים בחלונית בצד.
  split,

  /// מפרשים מתחת לטקסט.
  combined,

  /// צורת הדף — פריסת מפרשים סביב הטקסט.
  pageShape,
}

extension TextBookViewModeX on TextBookViewMode {
  /// השם שמוצג למשתמש בבורר התצוגה.
  String get displayName => switch (this) {
    TextBookViewMode.split => 'מפרשים בצד',
    TextBookViewMode.combined => 'מפרשים מתחת',
    TextBookViewMode.pageShape => 'צורת הדף',
  };

  /// המזהה שנשמר בהעדפות וב-JSON של הטאב. שינוי ערך כאן פוסל העדפות שמורות.
  String get storageKey => name;

  /// ממיר מזהה שמור בחזרה ל-enum, או [fallback] אם אינו מוכר.
  static TextBookViewMode fromStorageKey(
    String? key, {
    TextBookViewMode fallback = TextBookViewMode.combined,
  }) {
    for (final mode in TextBookViewMode.values) {
      if (mode.storageKey == key) return mode;
    }
    return fallback;
  }
}
