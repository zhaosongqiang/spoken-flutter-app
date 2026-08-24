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
      'suggestedScore': 82.5,
      'pronAccuracy': null,
    });

    expect(detail.id, 33);
    expect(detail.suggestedScore, 82.5);
    expect(detail.pronAccuracy, isNull);
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
          'suggestedScore': 81,
          'pronAccuracy': 90,
          'pronFluency': 0.87,
          'pronunciationWords': [
            {'word': 'science', 'pronAccuracy': 92, 'matchTag': 0}
          ],
        }
      ],
    });

    expect(details.record.id, 28);
    expect(details.record.testName, 'Science');
    expect(details.details.single.suggestedScore, 81);
    expect(details.details.single.pronAccuracy, 90);
    expect(details.details.single.pronFluency, 0.87);
    expect(details.details.single.pronunciationWords, isA<List<dynamic>>());
  });

  test('parses Qwen bands and flat Tencent words independently', () {
    final evaluation = AiEvaluation.fromJson(<String, dynamic>{
      'overallBand': 6.5,
      'pronunciationBand': 6,
      'fluencyCoherenceBand': 6.5,
      'lexicalResourceBand': 7,
      'grammarBand': 6,
      'suggestedScore': 82.5,
      'pronAccuracy': 91,
      'pronFluency': 0.88,
      'words': [
        {
          'word': 'science',
          'pronAccuracy': 92,
          'pronFluency': 0.9,
          'matchTag': 0,
        }
      ],
    });

    expect(evaluation.overallBand, 6.5);
    expect(evaluation.suggestedScore, 82.5);
    expect(evaluation.pronFluency, 0.88);
    expect(evaluation.words, isA<List<dynamic>>());
  });
}
