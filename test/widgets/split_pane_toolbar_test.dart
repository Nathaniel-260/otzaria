import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/navigation/responsive_action_bar.dart';

/// צמצום סרגל הפעולות בחלונית של טאב מפוצל: רוחב המסך אינו רוחב החלונית,
/// ולכן מספר הכפתורים קבוע ונמוך — והחיפוש עולה לראש כדי לא ליפול לתפריט.
void main() {
  ActionButtonData action(String tooltip) => ActionButtonData.simple(
    icon: FluentIcons.search_24_regular,
    tooltip: tooltip,
    onPressed: () {},
    compact: false,
  );

  List<String?> tooltipsOf(List<ActionButtonData> actions) =>
      actions.map((a) => a.tooltip).toList();

  test('בתצוגה מפוצלת החיפוש עולה לראש הסרגל', () {
    final actions = [
      action('פתח ספר במהדורה מודפסת'),
      action('מפרשים'),
      action('הסתר ניקוד'),
      action('חיפוש'),
      action('הגדל את גודל הטקסט'),
    ];

    final result = promoteSearchInSplitPane(actions, true);

    expect(tooltipsOf(result).first, 'חיפוש');
    expect(tooltipsOf(result), hasLength(actions.length));
    expect(
      tooltipsOf(result),
      containsAll(tooltipsOf(actions)),
      reason: 'אף פעולה לא נעלמה',
    );
  });

  test('בתצוגה רגילה הסדר אינו משתנה כלל', () {
    final actions = [action('מפרשים'), action('חיפוש')];

    expect(promoteSearchInSplitPane(actions, false), same(actions));
  });

  test('סרגל בלי חיפוש אינו משתנה', () {
    final actions = [action('מפרשים'), action('הדפסה')];

    expect(promoteSearchInSplitPane(actions, true), same(actions));
  });

  test('חיפוש שכבר ראשון אינו מזיז דבר', () {
    final actions = [action('חיפוש'), action('מפרשים')];

    expect(promoteSearchInSplitPane(actions, true), same(actions));
  });

  test('תקרת הכפתורים בחלונית נמוכה מזו של מסך מלא', () {
    expect(kSplitPaneMaxToolbarButtons, 3);
    expect(
      kSplitPaneMaxToolbarButtons,
      lessThan(maxToolbarButtonsForWidth(1600)),
      reason: 'אחרת אין צמצום בפועל בחלונית צרה',
    );
  });
}
