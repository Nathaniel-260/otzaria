import 'package:equatable/equatable.dart';
import 'package:otzaria/text_book/paged/models/paginated_book.dart';

sealed class PagedLayoutState extends Equatable {
  const PagedLayoutState();

  @override
  List<Object?> get props => const [];
}

/// עוד לא התבקש עימוד.
class PagedLayoutIdle extends PagedLayoutState {
  const PagedLayoutIdle();
}

/// תוכן הספר טעון רק בחלקו. עימוד על תוכן חלקי היה מספר עמודים שגוי ומייצר
/// מפתח מטמון שלא יימצא שוב, ולכן ממתינים לתוכן המלא.
class PagedLayoutWaitingForContent extends PagedLayoutState {
  const PagedLayoutWaitingForContent();
}

/// העימוד רץ. [progress] הוא 0..1 לפי הסעיפים שעובדו.
class PagedLayoutRunning extends PagedLayoutState {
  final double progress;

  const PagedLayoutRunning(this.progress);

  @override
  List<Object?> get props => [progress];
}

class PagedLayoutReady extends PagedLayoutState {
  final PaginatedBook book;

  /// העימוד נטען מהמטמון ולא חושב מחדש. שימושי לאבחון ולטסטים.
  final bool fromCache;

  const PagedLayoutReady(this.book, {required this.fromCache});

  @override
  List<Object?> get props => [book, fromCache];
}
