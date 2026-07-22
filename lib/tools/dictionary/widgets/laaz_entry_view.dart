import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/widgets/misc/link_preview_styles.dart';
import 'package:otzaria/widgets/smart_text/smart_text.dart';

/// הפריסה המלאה של קבוצת ערכי לעז (אותו תעתיק ופירוש ממקורות שונים),
/// לדיאלוג שנפתח מתפריט ההקשר: ערך, לטינית, פירוש, מקורות, הערה ואנגלית.
class LaazEntryGroupView extends StatelessWidget {
  const LaazEntryGroupView({super.key, required this.group});

  final List<LaazDictionaryEntry> group;

  @override
  Widget build(BuildContext context) {
    final entry = group.first;
    final lemmas = <String>{for (final e in group) e.lemma}.join(', ');
    final references = <String>{
      for (final e in group)
        if (e.sourceReference.isNotEmpty) e.sourceReference,
    }.join(', ');
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final secondaryStyle = textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$lemmas — ${entry.laazHebrew}',
          style: textTheme.bodyLarge,
        ),
        if (entry.laazLatin.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            entry.laazLatin,
            textDirection: TextDirection.ltr,
            style: textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        if (entry.meaning.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            entry.meaning,
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
        if (references.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('רש"י $references', style: secondaryStyle),
        ],
        if (entry.note != null) ...[
          const SizedBox(height: 8),
          Text(entry.note!, style: secondaryStyle),
        ],
        if (entry.english != null) ...[
          const SizedBox(height: 8),
          Text(
            entry.english!,
            textDirection: TextDirection.ltr,
            style: secondaryStyle,
          ),
        ],
      ],
    );
  }
}

/// תוכן חלונית הריחוף ללעזי רש"י: שם הלעז ופירושו בלבד, לכל קבוצת התאמה,
/// בעיצוב המשותף של חלוניות התצוגה המקדימה ([LinkPreviewStyles]).
class LaazHoverPreviewContent extends StatelessWidget {
  const LaazHoverPreviewContent({super.key, required this.groups});

  final List<List<LaazDictionaryEntry>> groups;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settings) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < groups.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _buildGroup(context, settings, groups[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGroup(
    BuildContext context,
    SettingsState settings,
    List<LaazDictionaryEntry> group,
  ) {
    final entry = group.first;
    final name = entry.laazHebrew.isNotEmpty ? entry.laazHebrew : entry.lemma;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: LinkPreviewStyles.title(context, settings, compact: true),
        ),
        if (entry.meaning.isNotEmpty) ...[
          LinkPreviewStyles.divider(compact: true),
          SmartTextWidget(
            text: entry.meaning,
            settings: LinkPreviewStyles.content(settings),
          ),
        ],
      ],
    );
  }
}
