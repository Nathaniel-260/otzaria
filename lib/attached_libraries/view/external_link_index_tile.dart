import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/attached_libraries/external_link_work_status.dart';
import 'package:otzaria/attached_libraries/models/attached_library.dart';
import 'package:otzaria/attached_libraries/repository/external_link_repository.dart';
import 'package:otzaria/settings/l10n/settings_text.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// האם [libraries] כוללת מסד תקין שיש לו אינדקס קישורים חיצוניים.
bool hasExternalLinkLibrary(List<AttachedLibrary> libraries) => libraries.any(
  (library) =>
      library.isOk &&
      library.capabilities.contains(AttachedLibraryCapability.externalLinks),
);

/// אישור לפני עצירת הבנייה; ההתקדמות נשמרת.
Future<bool> confirmLinkIndexStop(BuildContext context) async =>
    await showWarningDialog(
      context: context,
      title: context.settingsText('עצירת בניית האינדקס'),
      content: context.settingsText(
        'ההתקדמות נשמרת ואפשר להמשיך אחר כך מאותה נקודה. עד שהאינדקס יושלם המפרשים של המסד לא יוצגו על הספרים הרשמיים. לעצור?',
      ),
      confirmText: context.settingsText('עצור'),
      cancelText: context.settingsText('ביטול'),
    ) ??
    false;

/// אישור לפני בנייה מחדש, שמוחקת את ההתקדמות השמורה.
Future<bool> confirmLinkIndexRebuild(BuildContext context) async =>
    await showWarningDialog(
      context: context,
      title: context.settingsText('בנייה מחדש של האינדקס'),
      content: context.settingsText(
        'בנייה מחדש מוחקת את ההתקדמות ומתחילה מההתחלה (כמה דקות במסד גדול). להמשיך?',
      ),
      confirmText: context.settingsText('בנה מחדש'),
      cancelText: context.settingsText('ביטול'),
    ) ??
    false;

/// שורת "אינדקס קישורים" בהגדרות הספרייה: התקדמות הבנייה, עצירה, ובנייה
/// מחדש אחרי בנייה שנקטעה.
class ExternalLinkIndexTile extends StatelessWidget {
  const ExternalLinkIndexTile({super.key, this.links});

  /// ברירת המחדל: [ExternalLinkRepository.instance].
  final ExternalLinkRepository? links;

  @override
  Widget build(BuildContext context) {
    final repository = links ?? ExternalLinkRepository.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([
        repository.buildProgress,
        repository.buildingSlugs,
        repository.incompleteSlugs,
      ]),
      builder: (context, _) {
        final progress = repository.buildProgress.value;
        final isBuilding =
            progress.isNotEmpty || repository.buildingSlugs.value.isNotEmpty;
        final incomplete = repository.incompleteSlugs.value;
        final (:done, :total) = sumLinkBuildProgress(progress);
        final subtitle = isBuilding
            ? context.settingsText(
                'התקדמות האינדקס: {processed}/{total}',
                args: {
                  'processed': formatLinkCount(done),
                  'total': formatLinkCount(total),
                },
              )
            : incomplete.isNotEmpty
            ? context.settingsText('אינדקס הקישורים לא הושלם')
            : context.settingsText('האינדקס מעודכן');
        return SettingsActionTile.text(
          icon: FluentIcons.table_24_regular,
          title: context.settingsText('אינדקס קישורים'),
          subtitle: subtitle,
          actions: [
            if (isBuilding)
              ActionButton.neutral(
                text: context.settingsText('עצור'),
                onPressed: () async {
                  if (await confirmLinkIndexStop(context)) {
                    repository.cancelBuild();
                  }
                },
              )
            else if (incomplete.isNotEmpty) ...[
              ActionButton.recommended(
                text: context.settingsText('המשך בנייה'),
                onPressed: () {
                  for (final slug in incomplete) {
                    repository.requestResume(slug);
                  }
                },
              ),
              ActionButton.neutral(
                text: context.settingsText('בנה מחדש'),
                onPressed: () async {
                  if (!await confirmLinkIndexRebuild(context)) return;
                  for (final slug in incomplete) {
                    repository.requestRebuild(slug);
                  }
                },
              ),
            ],
          ],
        );
      },
    );
  }
}
