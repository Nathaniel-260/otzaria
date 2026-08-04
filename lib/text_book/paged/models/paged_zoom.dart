/// זום בתצוגת העמודים.
///
/// הזום מגדיל את העמוד **כולו** ולא את הגופן — האותיות מוטבעות בעמוד כמו
/// ב-PDF. לכן שינוי זום אינו מעמד מחדש ואינו מזיז טקסט בין עמודים.
library;

const double kDefaultPagedZoom = 1.0;
const double kMinPagedZoom = 0.5;
const double kMaxPagedZoom = 3.0;
const double kPagedZoomStep = 0.1;

/// חוסם את הזום לטווח המותר. מוחל גם על ערך שנטען מטאב שמור.
double clampPagedZoom(double zoom) {
  if (zoom.isNaN) return kDefaultPagedZoom;
  return zoom.clamp(kMinPagedZoom, kMaxPagedZoom);
}

/// הזום הבא בכיוון [direction] — 1 להגדלה, -1 להקטנה.
///
/// העיגול לעשירייה מונע צבירת שגיאות float אחרי כמה צעדים (1.1 + 0.1 אינו
/// 1.2 בדיוק), כדי שערכי הזום יישארו נקיים לתצוגה ולשמירה.
double steppedPagedZoom(double zoom, int direction) {
  final steps = (clampPagedZoom(zoom) / kPagedZoomStep).round() + direction;
  return clampPagedZoom(steps * kPagedZoomStep);
}
