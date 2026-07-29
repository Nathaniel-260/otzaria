import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pane_tree.dart';
import 'package:otzaria/tabs/models/tab.dart';

abstract class TabsEvent extends Equatable {
  const TabsEvent();

  @override
  List<Object?> get props => [];
}

class AddTab extends TabsEvent {
  final OpenedTab tab;
  // אם true – הטאב נכנס סמוך לטאב הנוכחי (cross-reference מתוך ספר פתוח).
  // אחרת – נוסף בסוף רשימת הטאבים, כברירת מחדל לפתיחת ספר חדש.
  final bool insertAdjacent;

  const AddTab(this.tab, {this.insertAdjacent = false});

  @override
  List<Object?> get props => [tab, insertAdjacent];
}

class OpenOrFocusTab extends TabsEvent {
  final OpenedTab tab;
  final String? targetTitle;
  final bool insertAdjacent;

  /// כשטאב קיים מאותר ועושים לו focus - האם להעביר אליו את המיקום (index/page)
  /// של הטאב הנכנס. משמש סימניות והיסטוריה - שם המשתמש בוחר מיקום ספציפי ולא
  /// רק את הספר, ולכן רוצים שהטאב הקיים ייגלל לאותו מיקום.
  final bool navigateToPositionIfReused;

  const OpenOrFocusTab(
    this.tab, {
    this.targetTitle,
    this.insertAdjacent = false,
    this.navigateToPositionIfReused = false,
  });

  @override
  List<Object?> get props => [
    tab,
    targetTitle,
    insertAdjacent,
    navigateToPositionIfReused,
  ];
}

/// החלפת טאב קיים בטאב אחר באותו מיקום — סיום רזולוציה של ResolvingTab.
class ReplaceTab extends TabsEvent {
  final OpenedTab oldTab;
  final OpenedTab newTab;

  const ReplaceTab({required this.oldTab, required this.newTab});

  @override
  List<Object?> get props => [oldTab, newTab];
}

class ReplaceAllTabs extends TabsEvent {
  final List<OpenedTab> tabs;
  final int currentTabIndex;

  const ReplaceAllTabs(this.tabs, this.currentTabIndex);

  @override
  List<Object?> get props => [tabs, currentTabIndex];
}

class SaveTabs extends TabsEvent {
  const SaveTabs();

  @override
  List<Object?> get props => [];
}

class RemoveTab extends TabsEvent {
  final OpenedTab tab;

  const RemoveTab(this.tab);

  @override
  List<Object?> get props => [tab];
}

/// סגירת קבוצת כרטיסיות בפעולה אחת (בחירה מרובה בשורת הכרטיסיות).
class RemoveTabs extends TabsEvent {
  final List<OpenedTab> tabs;

  const RemoveTabs(this.tabs);

  @override
  List<Object?> get props => [tabs];
}

/// צירוף/הסרה של כרטיסיה מהבחירה המרובה (Ctrl/Cmd+לחיצה).
class ToggleTabSelection extends TabsEvent {
  final OpenedTab tab;

  const ToggleTabSelection(this.tab);

  @override
  List<Object?> get props => [tab];
}

/// בחירת טווח מהכרטיסיה הפעילה עד [tab] (Shift+לחיצה).
class SelectTabRange extends TabsEvent {
  final OpenedTab tab;

  const SelectTabRange(this.tab);

  @override
  List<Object?> get props => [tab];
}

class ClearTabSelection extends TabsEvent {
  const ClearTabSelection();
}

class CloseCurrentTab extends TabsEvent {
  const CloseCurrentTab();

  @override
  List<Object?> get props => [];
}

class RestoreLastClosedTab extends TabsEvent {
  const RestoreLastClosedTab();

  @override
  List<Object?> get props => [];
}

class SetCurrentTab extends TabsEvent {
  final int index;

  const SetCurrentTab(this.index);

  @override
  List<Object?> get props => [index];
}

class CloseAllTabs extends TabsEvent {}

class CloseOtherTabs extends TabsEvent {
  final OpenedTab keepTab;

  const CloseOtherTabs(this.keepTab);

  @override
  List<Object?> get props => [keepTab];
}

class CloneTab extends TabsEvent {
  final OpenedTab tab;

  const CloneTab(this.tab);

  @override
  List<Object?> get props => [tab];
}

class MoveTab extends TabsEvent {
  final OpenedTab tab;
  final int newIndex;

  const MoveTab(this.tab, this.newIndex);

  @override
  List<Object?> get props => [tab, newIndex];
}

class NavigateToNextTab extends TabsEvent {}

class NavigateToPreviousTab extends TabsEvent {}

class LoadTabs extends TabsEvent {}

/// ממפה נתיבי קבצים של הטאבים הפתוחים מתיקיית ספרייה ישנה לחדשה, אחרי
/// העברת מיקום הספרייה, כדי שספרי PDF/DOCX פתוחים ייטענו מהמיקום החדש.
///
/// [completer] מאפשר להמתין לסיום ה-handler (עדכון הזיכרון + שמירה ל-Hive)
/// לפני שממשיכים לרענון, כדי שלא ייווצר race שבו שמירת הטאבים בעת ה-dispose
/// תדרוס את המיפוי עם הנתיב הישן. מוחרג מ-props (לא משפיע על שוויון האירוע).
class RemapBookPaths extends TabsEvent {
  final String fromDir;
  final String toDir;
  final Completer<void>? completer;

  const RemapBookPaths(this.fromDir, this.toDir, {this.completer});

  @override
  List<Object?> get props => [fromDir, toDir];
}

class TogglePinTab extends TabsEvent {
  final OpenedTab tab;

  const TogglePinTab(this.tab);

  @override
  List<Object?> get props => [tab];
}

class EnableSideBySideMode extends TabsEvent {
  final OpenedTab rightTab;
  final OpenedTab leftTab;

  /// ציר הפיצול בין שני הטאבים.
  final SplitAxis axis;

  const EnableSideBySideMode({
    required this.rightTab,
    required this.leftTab,
    this.axis = SplitAxis.horizontal,
  });

  @override
  List<Object?> get props => [rightTab, leftTab, axis];
}

class DisableSideBySideMode extends TabsEvent {
  final int tabIndex;
  const DisableSideBySideMode(this.tabIndex);

  @override
  List<Object?> get props => [tabIndex];
}

class UpdateSplitRatio extends TabsEvent {
  final double ratio;

  /// נתיב צומת הפיצול בטאב הנוכחי. ריק = צומת השורש.
  final PanePath path;

  const UpdateSplitRatio(this.ratio, {this.path = const []});

  @override
  List<Object?> get props => [ratio, path];
}

class SwapSideBySideTabs extends TabsEvent {
  /// נתיב צומת הפיצול שצדדיו יוחלפו. ריק = צומת השורש.
  final PanePath path;

  /// הטאב שבו הצומת. `null` = הטאב הפעיל.
  final int? tabIndex;

  const SwapSideBySideTabs({this.path = const [], this.tabIndex});

  @override
  List<Object?> get props => [path, tabIndex];
}

/// הפלת טאב על חלונית בטאב הנוכחי — פיצול, החלפה או הזזה פנימית.
///
/// [sourcePath] מסומן כשהטאב הנגרר הוא חלונית באותו טאב; אחרת הטאב מגיע
/// משורת הכרטיסיות ומוסר ממנה.
class DropTabOnPane extends TabsEvent {
  final OpenedTab tab;
  final PanePath targetPath;
  final PaneDropPosition position;
  final PanePath? sourcePath;

  const DropTabOnPane({
    required this.tab,
    required this.targetPath,
    required this.position,
    this.sourcePath,
  });

  @override
  List<Object?> get props => [tab, targetPath, position, sourcePath];
}

/// סגירת חלונית בודדת בתוך טאב מפוצל. סגירת החלונית האחרונה סוגרת את הטאב.
class ClosePane extends TabsEvent {
  final PanePath path;

  /// הטאב שבו החלונית. `null` = הטאב הפעיל.
  final int? tabIndex;

  const ClosePane(this.path, {this.tabIndex});

  @override
  List<Object?> get props => [path, tabIndex];
}
