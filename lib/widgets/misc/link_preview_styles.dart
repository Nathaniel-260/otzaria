import 'package:flutter/material.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';

/// מקור יחיד לעיצוב הטקסט בתוכן חלוניות התצוגה המקדימה — קישורים, הערות
/// מוטמעות ולעזי רש"י. שינוי כאן משנה את כל החלוניות יחד.
abstract final class LinkPreviewStyles {
  /// סגנון כותרת החלונית (כתובת היעד / שם הלעז). [compact] — חלונית ריחוף.
  static TextStyle title(
    BuildContext context,
    SettingsState settings, {
    bool compact = false,
  }) {
    return TextStyle(
      fontSize: compact ? 11 : settings.commentatorsFontSize - 2,
      fontWeight: FontWeight.bold,
      fontFamily: settings.commentatorsFontFamily,
      color: Theme.of(context).colorScheme.primary,
    );
  }

  /// הקו המפריד בין כותרת החלונית לתוכנה.
  static Divider divider({bool compact = false}) =>
      Divider(height: compact ? 8 : 16);

  /// הגדרות רינדור תוכן החלונית, לפי הגדרות תצוגת המפרשים.
  static RenderSettings content(
    SettingsState settings, {
    bool removeNikud = false,
    bool removePunctuation = false,
  }) {
    return RenderSettings(
      removeNikud: removeNikud,
      removePunctuation: removePunctuation,
      removeTeamim: !settings.showTeamim,
      replaceHolyNames: settings.replaceHolyNames,
      fontSize: settings.commentatorsFontSize,
      fontFamily: settings.commentatorsFontFamily,
      fontWeight: settings.commentatorsFontBold ? FontWeight.bold : null,
      lineHeight: settings.lineHeight,
      justifyText: true,
    );
  }
}
