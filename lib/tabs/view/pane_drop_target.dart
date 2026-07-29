import 'package:flutter/material.dart';
import 'package:otzaria/tabs/models/pane_tree.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/view/pane_drop_geometry.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// מטען הגרירה של טאב אל תוך אזור הקריאה.
@immutable
class PaneDragData {
  /// הטאב הנגרר.
  final OpenedTab tab;

  /// נתיב החלונית שממנה נגרר, כשהגרירה התחילה בתוך אותו טאב מפוצל.
  /// `null` כשהמקור הוא טאב אחר בשורת הכרטיסיות.
  final PanePath? sourcePath;

  const PaneDragData({required this.tab, this.sourcePath});
}

/// עוטף חלונית קריאה ומקבל טאבים שנגררים אליה, עם חיווי חי של המקום
/// שאליו החלונית תיכנס — מרכז להחלפה, או אחד מארבעת הקצוות לפיצול.
class PaneDropTarget extends StatefulWidget {
  /// נתיב החלונית בעץ הפיצולים של הטאב.
  final PanePath path;

  /// החלונית שהיעד עוטף — נדרש כדי לזהות גרירה של הטאב שמכיל אותה.
  final OpenedTab pane;

  /// תוכן החלונית.
  final Widget child;

  /// נקרא כשהמשתמש משחרר טאב מעל החלונית.
  final void Function(
    PaneDragData data,
    PanePath path,
    PaneDropPosition position,
  )
  onDrop;

  const PaneDropTarget({
    super.key,
    required this.path,
    required this.pane,
    required this.child,
    required this.onDrop,
  });

  @override
  State<PaneDropTarget> createState() => _PaneDropTargetState();
}

class _PaneDropTargetState extends State<PaneDropTarget> {
  PaneDropPosition? _position;

  /// גרירה שלא תשנה דבר אינה מציגה חיווי: חלונית אל עצמה, או טאב שהחלונית
  /// הזו כבר בתוכו — חיווי כזה מבטיח פיצול שה-bloc דוחה בשקט.
  bool _accepts(PaneDragData data) {
    final source = data.sourcePath;
    if (source != null) return !_samePath(source, widget.path);
    return pathOfPane(data.tab, widget.pane) == null;
  }

  static bool _samePath(PanePath a, PanePath b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _updatePosition(Offset globalOffset) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final next = dropPositionFor(
      localPosition: box.globalToLocal(globalOffset),
      size: box.size,
      textDirection: Directionality.of(context),
    );
    if (next != _position) setState(() => _position = next);
  }

  @override
  Widget build(BuildContext context) {
    return DragTarget<PaneDragData>(
      onWillAcceptWithDetails: (details) {
        if (!_accepts(details.data)) return false;
        _updatePosition(details.offset);
        return true;
      },
      onMove: (details) {
        if (_accepts(details.data)) _updatePosition(details.offset);
      },
      onLeave: (_) => setState(() => _position = null),
      onAcceptWithDetails: (details) {
        final position = _position;
        setState(() => _position = null);
        if (position != null) {
          widget.onDrop(details.data, widget.path, position);
        }
      },
      builder: (context, candidate, rejected) {
        return Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (_position != null)
              Positioned.fill(
                child: IgnorePointer(child: _DropPreview(position: _position!)),
              ),
          ],
        );
      },
    );
  }
}

/// המלבן המונפש שמסמן את החלק שהחלונית הנגררת תתפוס.
class _DropPreview extends StatelessWidget {
  final PaneDropPosition position;

  const _DropPreview({required this.position});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final rect = previewRectFor(
          position: position,
          size: constraints.biggest,
          textDirection: Directionality.of(context),
        );

        return Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: rect.height,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppSurfaces.paneDropPreview(colorScheme),
                  border: Border.all(
                    color: AppSurfaces.paneDropPreviewBorder(colorScheme),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
