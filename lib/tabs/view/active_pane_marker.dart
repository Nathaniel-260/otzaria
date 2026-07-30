import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/tab.dart';

/// מסמן את החלונית שנלחצה כחלונית הפעילה של הטאב.
///
/// [HitTestBehavior.translucent] כדי שהתוכן עצמו יקבל את הלחיצה כרגיל — הסימון
/// הוא תופעת לוואי של הלחיצה ולא במקומה.
class ActivePaneMarker extends StatelessWidget {
  /// החלונית שהמסמן עוטף.
  final OpenedTab pane;

  /// בטאב שאינו מפוצל יש חלונית אחת, ואין מה לסמן.
  final bool enabled;

  final Widget child;

  const ActivePaneMarker({
    super.key,
    required this.pane,
    required this.enabled,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => context.read<TabsBloc>().add(SetActivePane(pane)),
      child: child,
    );
  }
}
