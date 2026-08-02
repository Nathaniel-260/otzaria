import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/services/indexing_preflight.dart';

void main() {
  group('IndexingPreflight.inspectPath', () {
    test('נתיב מקומי רגיל — בלי תקלות', () {
      expect(IndexingPreflight.inspectPath(r'C:\otzaria\index'), isEmpty);
    });

    test('נתיב UNC מזוהה ככונן רשת', () {
      final findings = IndexingPreflight.inspectPath(r'\\server\share\index');
      expect(
        findings.map((f) => f.issue),
        contains(IndexingPreflightIssue.indexPathOnNetworkDrive),
      );
    });

    test('תיקיית OneDrive מזוהה, כולל הווריאנט הארגוני', () {
      for (final path in [
        r'C:\Users\a\OneDrive\otzaria\index',
        r'C:\Users\a\OneDrive - Contoso\otzaria\index',
        r'C:\Users\a\Dropbox\otzaria\index',
      ]) {
        expect(
          IndexingPreflight.inspectPath(path).map((f) => f.issue),
          contains(IndexingPreflightIssue.indexPathInCloudSyncFolder),
          reason: '$path אמור להיות מזוהה כתיקיית סנכרון',
        );
      }
    });

    test('שם תיקייה שרק מכיל "Dropbox" אינו מסומן', () {
      // ההשוואה על רכיב נתיב שלם — אחרת ספרייה בשם "ספרי Dropbox" הייתה
      // מקפיצה אזהרה שקרית בכל אינדוקס.
      expect(
        IndexingPreflight.inspectPath(r'C:\ספרי Dropbox שלי\index'),
        isEmpty,
      );
    });

    test('תקלה חוסמת מובחנת מאזהרה', () {
      const blocking = IndexingPreflightFinding(
        IndexingPreflightIssue.indexPathNotWritable,
      );
      const warning = IndexingPreflightFinding(
        IndexingPreflightIssue.indexPathInCloudSyncFolder,
      );
      expect(blocking.isBlocking, isTrue);
      expect(warning.isBlocking, isFalse);
    });

    test('לכל תקלה יש כותרת והנחיה לא ריקות', () {
      for (final issue in IndexingPreflightIssue.values) {
        final finding = IndexingPreflightFinding(issue);
        expect(finding.title, isNotEmpty);
        expect(finding.suggestion, isNotEmpty);
      }
    });
  });
}
