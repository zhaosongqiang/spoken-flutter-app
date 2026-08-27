import 'package:flutter_test/flutter_test.dart';
import 'package:ielts_speaking/core/models.dart';

void main() {
  test('parses pronunciation words from the assessment response', () {
    final result = AssessmentResult.fromJson(<String, dynamic>{
      'recordId': 28,
      'detailId': 81,
      'audioPath': '/audio/81.wav',
      'score': 92,
      'transcription': 'Hello world.',
      'words': [
        {'word': 'Hello', 'overall': 96, 'pause': false},
      ],
    });

    expect(result.words.single['word'], 'Hello');
    expect(result.words.single['overall'], 96);
  });

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
      'words': null,
      'aiPronunciationAudioUrl': null,
    });

    expect(detail.id, 33);
    expect(detail.suggestedScore, 82.5);
    expect(detail.words, isEmpty);
    expect(detail.audioPath, isEmpty);
    expect(detail.aiPronunciationAudioUrl, isEmpty);
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
          'aiPronunciationAudioUrl': 'https://example.com/ai-pronunciation.mp3',
          'words': [
            {'word': 'science', 'overall': 92, 'pause': false}
          ],
        }
      ],
    });

    expect(details.record.id, 28);
    expect(details.record.testName, 'Science');
    expect(details.details.single.suggestedScore, 81);
    expect(details.details.single.words.single['word'], 'science');
    expect(details.details.single.words.single['overall'], 92);
    expect(
      details.details.single.aiPronunciationAudioUrl,
      'https://example.com/ai-pronunciation.mp3',
    );
  });

  test('parses the AI evaluation content independently from words', () {
    final evaluation = AiEvaluation.fromJson(<String, dynamic>{
      'overallSummary': '回答切题',
      'pronunciationSummary': '发音清晰',
      'fcSummary': '表达流畅',
    });

    expect(evaluation.overallSummary, '回答切题');
    expect(evaluation.pronunciationSummary, '发音清晰');
    expect(evaluation.fluencySummary, '表达流畅');
  });
}
