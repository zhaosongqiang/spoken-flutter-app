import 'package:flutter_test/flutter_test.dart';
import 'package:ielts_speaking/core/models.dart';

void main() {
  test('parses nullable backend fields without throwing', () {
    final detail = AssessmentDetail.fromJson(<String, dynamic>{
      'id': 33,
      'recordId': 26,
      'questionId': 60,
      'part': 1,
      'seqNo': 1,
      'questionPrompt': 'Do you like science?',
      'questionAudioUrl': null,
      'audioPath': null,
      'transcription': null,
      'overallScore': 7,
      'pronunciationScore': null,
    });

    expect(detail.id, 33);
    expect(detail.overallScore, 7.0);
    expect(detail.pronunciationScore, isNull);
    expect(detail.audioPath, isEmpty);
  });

  test('flattens library tests', () {
    final library = SpokenLibrary.fromJson(<String, dynamic>{
      'totalBooks': 1,
      'totalTests': 1,
      'books': [
        {
          'bookId': 14,
          'type': 2,
          'bookName': '5–8 月',
          'tests': [
            {'id': 60, 'bookId': 14, 'type': 2, 'name': 'Science', 'part': 1}
          ],
        }
      ],
    });

    expect(library.tests.single.name, 'Science');
    expect(library.tests.single.part, 1);
  });

  test('parses the nested record details contract', () {
    final details = RecordDetails.fromJson(<String, dynamic>{
      'record': {
        'id': 28,
        'testId': 60,
        'bookName': '5-8月',
        'testName': 'Science',
        'createAt': '2026-08-13T19:41:00',
      },
      'details': [
        {
          'id': 45,
          'recordId': 28,
          'questionId': 573,
          'part': 1,
          'seqNo': 1,
          'questionPrompt': 'Do you like science?',
          'overallScore': 6,
          'fluencyCoherenceScore': 6,
          'lexicalResourceScore': 6,
          'wordCnt': 27,
        }
      ],
    });

    expect(details.record.id, 28);
    expect(details.record.testName, 'Science');
    expect(details.details.single.fluencyScore, 6);
    expect(details.details.single.lexicalScore, 6);
    expect(details.details.single.wordCount, 27);
  });
}
