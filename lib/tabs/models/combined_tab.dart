import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/utils/file/hive_utils.dart';

/// ציר הפיצול בין שתי החלוניות של [CombinedTab].
enum SplitAxis {
  /// זו לצד זו — ב-RTL החלונית הראשונה יושבת בימין.
  horizontal,

  /// זו מעל זו — החלונית הראשונה למעלה.
  vertical;

  static SplitAxis fromId(String? id) =>
      id == vertical.name ? vertical : horizontal;
}

/// צומת פיצול בעץ החלוניות של טאב: מציג שתי חלוניות עם מפריד ניתן לגרירה.
///
/// כל חלונית היא עצמה [OpenedTab] — ולכן יכולה להיות [CombinedTab] נוספת.
/// קינון כזה נותן כל פריסה אפשרית (רבעים, חצי + שני רבעים וכו').
///
/// סגירת הטאב סוגרת את כל החלוניות שתחתיו.
class CombinedTab extends OpenedTab {
  /// החלונית הראשונה — ימנית ב-[SplitAxis.horizontal], עליונה ב-[SplitAxis.vertical].
  final OpenedTab rightTab;

  /// החלונית השנייה — שמאלית ב-[SplitAxis.horizontal], תחתונה ב-[SplitAxis.vertical].
  final OpenedTab leftTab;

  /// ציר הפיצול בין שתי החלוניות.
  final SplitAxis axis;

  /// חלקה של החלונית הראשונה מהמקום הפנוי (0.0-1.0).
  ///
  /// משתנה במקום (mutable) בכוונה: גרירת המפריד לא אמורה ליצור צומת חדש,
  /// שהיה מחליף את מפתח הטאב ומאתחל מחדש את תוכן החלוניות.
  double splitRatio;

  CombinedTab({
    required this.rightTab,
    required this.leftTab,
    this.axis = SplitAxis.horizontal,
    this.splitRatio = 0.5,
    bool isPinned = false,
  }) : super(
         buildTitle(rightTab, leftTab),
         isPinned: isPinned,
       );

  /// החלונית הראשונה בסדר התצוגה (ימין/למעלה).
  OpenedTab get first => rightTab;

  /// החלונית השנייה בסדר התצוגה (שמאל/למטה).
  OpenedTab get second => leftTab;

  /// כותרת המורכבת משמות כל חלוניות העלה, ולא משמות הצמתים המקוננים —
  /// בלעדיה קינון היה מייצר "משולב: משולב: א | ב | ג".
  static String buildTitle(OpenedTab first, OpenedTab second) {
    final names = <String>[];
    void collect(OpenedTab tab) {
      if (tab is CombinedTab) {
        collect(tab.rightTab);
        collect(tab.leftTab);
      } else {
        names.add(tab.title);
      }
    }

    collect(first);
    collect(second);
    return 'משולב: ${names.join(' | ')}';
  }

  /// יוצרת עותק עם חלוניות ו/או ציר מוחלפים, תוך שמירת [splitRatio] והצמדה.
  CombinedTab copyWith({
    OpenedTab? rightTab,
    OpenedTab? leftTab,
    SplitAxis? axis,
    double? splitRatio,
    bool? isPinned,
  }) {
    return CombinedTab(
      rightTab: rightTab ?? this.rightTab,
      leftTab: leftTab ?? this.leftTab,
      axis: axis ?? this.axis,
      splitRatio: splitRatio ?? this.splitRatio,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  /// משחררת את הטאב ואת כל החלוניות שתחתיו.
  @override
  void dispose() {
    rightTab.dispose();
    leftTab.dispose();
    super.dispose();
  }

  factory CombinedTab.fromJson(Map<String, dynamic> json) {
    OpenedTab decodeTab(Map<String, dynamic> map) {
      if (map['type'] == 'PdfCommentatorsTab') {
        return PdfCommentatorsTab.fromJson(map);
      }
      if (map['type'] == 'CommentatorsTab') {
        return CommentatorsTab.fromJson(map);
      }
      return OpenedTab.fromJson(map);
    }

    return CombinedTab(
      rightTab: decodeTab(castMap(json['rightTab'])),
      leftTab: decodeTab(castMap(json['leftTab'])),
      axis: SplitAxis.fromId(json['axis'] as String?),
      splitRatio: (json['splitRatio'] as num?)?.toDouble() ?? 0.5,
      isPinned: json['isPinned'] ?? false,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'rightTab': rightTab.toJson(),
      'leftTab': leftTab.toJson(),
      'axis': axis.name,
      'splitRatio': splitRatio,
      'isPinned': isPinned,
      'type': 'CombinedTab',
    };
  }
}
