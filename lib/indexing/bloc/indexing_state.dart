import 'package:equatable/equatable.dart';
import 'package:otzaria/indexing/models/indexing_failure.dart';

sealed class IndexingState extends Equatable {
  final int? booksProcessed;
  final int? totalBooks;
  final bool isCreatingIndex;

  const IndexingState({
    this.booksProcessed,
    this.totalBooks,
    this.isCreatingIndex = false,
  });

  @override
  List<Object?> get props => [booksProcessed, totalBooks, isCreatingIndex];
}

class IndexingInitial extends IndexingState {}

class IndexingInProgress extends IndexingState {
  const IndexingInProgress({
    super.booksProcessed,
    super.totalBooks,
    super.isCreatingIndex,
  });
}

/// הריצה הגיעה לסופה. [failures] אינה בהכרח ריקה — ספרים בודדים יכולים
/// להיכשל בלי לעצור את הריצה, וזה בדיוק המידע שהיה נזרק ל-debugPrint.
class IndexingComplete extends IndexingState {
  final List<IndexingFailure> failures;

  /// מספר הכשלים בפועל; גדול מ-[failures] כשהאיסוף נחתך בתקרה.
  final int failureCount;

  const IndexingComplete({this.failures = const [], int? failureCount})
    : failureCount = failureCount ?? 0;

  /// האם כל הספרים אכן נכנסו לאינדקס.
  bool get isClean => failureCount == 0;

  @override
  List<Object?> get props => [...super.props, failures, failureCount];
}

/// הריצה נעצרה לפני סיומה מסיבה שאינה בקשת המשתמש — [message] מסביר למה.
class IndexingStopped extends IndexingState {
  final IndexingStopReason reason;
  final String message;
  final List<IndexingFailure> failures;
  final int failureCount;

  const IndexingStopped({
    required this.reason,
    required this.message,
    this.failures = const [],
    int? failureCount,
    super.booksProcessed,
    super.totalBooks,
  }) : failureCount = failureCount ?? 0;

  @override
  List<Object?> get props => [
    ...super.props,
    reason,
    message,
    failures,
    failureCount,
  ];
}

class IndexingError extends IndexingState {
  final String error;

  const IndexingError(this.error, {super.booksProcessed, super.totalBooks});

  @override
  List<Object?> get props => [error, booksProcessed, totalBooks];
}
