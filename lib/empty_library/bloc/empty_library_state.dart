import 'package:equatable/equatable.dart';

abstract class EmptyLibraryState extends Equatable {
  final bool isLoading;
  final String? selectedPath;
  final String? errorMessage;
  final List<String>? zipFiles;
  // non-null = כפתור ההורדה מושבת + הסיבה מוצגת למשתמש
  final String? downloadDisabledReason;

  const EmptyLibraryState({
    this.isLoading = false,
    this.selectedPath,
    this.errorMessage,
    this.zipFiles,
    this.downloadDisabledReason,
  });

  @override
  List<Object?> get props => [
    isLoading,
    selectedPath,
    errorMessage,
    zipFiles,
    downloadDisabledReason,
  ];
}

class EmptyLibraryInitial extends EmptyLibraryState {
  const EmptyLibraryInitial({super.downloadDisabledReason});
}

class EmptyLibraryLoading extends EmptyLibraryState {
  const EmptyLibraryLoading({
    super.selectedPath,
  }) : super(isLoading: true);
}

class EmptyLibraryDirectorySelected extends EmptyLibraryState {
  const EmptyLibraryDirectorySelected({
    required String selectedPath,
  }) : super(selectedPath: selectedPath);
}

class EmptyLibraryError extends EmptyLibraryState {
  const EmptyLibraryError({
    super.errorMessage,
    super.selectedPath,
    super.zipFiles,
    super.downloadDisabledReason,
  });
}

class EmptyLibraryZipExtracted extends EmptyLibraryState {
  final String extractedFileName;

  const EmptyLibraryZipExtracted({
    required String selectedPath,
    required this.extractedFileName,
  }) : super(selectedPath: selectedPath);

  @override
  List<Object?> get props => [
    ...super.props,
    extractedFileName,
  ];
}

class EmptyLibraryExtracting extends EmptyLibraryState {
  final double progress;
  final String message;

  /// הפעולה ניתנת לעצירה ([CancelLibraryImportRequested]) בשלב הזה.
  final bool cancellable;

  const EmptyLibraryExtracting({
    required String selectedPath,
    required this.progress,
    required this.message,
    this.cancellable = false,
  }) : super(selectedPath: selectedPath, isLoading: true);

  @override
  List<Object?> get props => [
    ...super.props,
    progress,
    message,
    cancellable,
  ];
}

class EmptyLibraryDownloading extends EmptyLibraryState {
  final double progress;
  final String message;

  const EmptyLibraryDownloading({
    required this.progress,
    required this.message,
  }) : super(isLoading: true);

  @override
  List<Object?> get props => [
    ...super.props,
    progress,
    message,
  ];
}
