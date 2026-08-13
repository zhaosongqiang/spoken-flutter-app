typedef JsonMap = Map<String, dynamic>;

JsonMap asJsonMap(Object? value) =>
    value is Map<String, dynamic> ? value : <String, dynamic>{};

List<JsonMap> asJsonMapList(Object? value) => value is List
    ? value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList()
    : <JsonMap>[];

int asInt(Object? value, [int fallback = 0]) => value is num
    ? value.toInt()
    : int.tryParse(value?.toString() ?? '') ?? fallback;

double? asNullableDouble(Object? value) =>
    value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');

String asString(Object? value, [String fallback = '']) =>
    value?.toString() ?? fallback;

class AccountBootstrap {
  const AccountBootstrap({required this.accountStatus, required this.newUser});

  factory AccountBootstrap.fromJson(JsonMap json) => AccountBootstrap(
        accountStatus: asString(json['accountStatus'], 'trial'),
        newUser: json['newUser'] == true,
      );

  final String accountStatus;
  final bool newUser;
}

class TestItem {
  const TestItem({
    required this.id,
    required this.bookId,
    required this.type,
    required this.bookName,
    required this.name,
    required this.part,
    required this.seqNo,
    required this.testNo,
    required this.displayName,
  });

  factory TestItem.fromJson(JsonMap json) => TestItem(
        id: asInt(json['id']),
        bookId: asInt(json['bookId']),
        type: asInt(json['type']),
        bookName: asString(json['bookName']),
        name: asString(json['name']),
        part: json['part'] == null ? null : asInt(json['part']),
        seqNo: asInt(json['seqNo']),
        testNo: json['testNo'] == null ? null : asInt(json['testNo']),
        displayName: asString(json['displayName']),
      );

  JsonMap toJson() => <String, dynamic>{
        'id': id,
        'bookId': bookId,
        'type': type,
        'bookName': bookName,
        'name': name,
        'part': part,
        'seqNo': seqNo,
        'testNo': testNo,
        'displayName': displayName,
      };

  final int id;
  final int bookId;
  final int type;
  final String bookName;
  final String name;
  final int? part;
  final int seqNo;
  final int? testNo;
  final String displayName;
}

class BookGroup {
  const BookGroup({
    required this.bookId,
    required this.type,
    required this.bookName,
    required this.tests,
  });

  factory BookGroup.fromJson(JsonMap json) => BookGroup(
        bookId: asInt(json['bookId']),
        type: asInt(json['type']),
        bookName: asString(json['bookName']),
        tests: asJsonMapList(json['tests']).map(TestItem.fromJson).toList(),
      );

  final int bookId;
  final int type;
  final String bookName;
  final List<TestItem> tests;
}

class SpokenLibrary {
  const SpokenLibrary({
    required this.totalBooks,
    required this.totalTests,
    required this.books,
  });

  factory SpokenLibrary.fromJson(JsonMap json) => SpokenLibrary(
        totalBooks: asInt(json['totalBooks']),
        totalTests: asInt(json['totalTests']),
        books: asJsonMapList(json['books']).map(BookGroup.fromJson).toList(),
      );

  final int totalBooks;
  final int totalTests;
  final List<BookGroup> books;

  List<TestItem> get tests => [for (final book in books) ...book.tests];
}

class QuestionItem {
  const QuestionItem({
    required this.id,
    required this.testId,
    required this.part,
    required this.seqNo,
    required this.questionText,
    required this.audioUrl,
    required this.taskType,
  });

  factory QuestionItem.fromJson(JsonMap json) => QuestionItem(
        id: asInt(json['id']),
        testId: asInt(json['testId']),
        part: asInt(json['part'], 1),
        seqNo: asInt(json['seqNo']),
        questionText: asString(json['questionText']),
        audioUrl: asString(json['audioUrl']),
        taskType: asString(json['taskType']),
      );

  final int id;
  final int testId;
  final int part;
  final int seqNo;
  final String questionText;
  final String audioUrl;
  final String taskType;
}

class SpokenQuestions {
  const SpokenQuestions({required this.test, required this.questions});

  factory SpokenQuestions.fromJson(JsonMap json) => SpokenQuestions(
        test: json['test'] is Map
            ? TestItem.fromJson(Map<String, dynamic>.from(json['test'] as Map))
            : null,
        questions: asJsonMapList(json['questions'])
            .map(QuestionItem.fromJson)
            .toList(),
      );

  final TestItem? test;
  final List<QuestionItem> questions;
}

class AssessmentResult {
  const AssessmentResult({
    required this.recordId,
    required this.detailId,
    required this.audioPath,
    required this.score,
    required this.transcription,
  });

  factory AssessmentResult.fromJson(JsonMap json) => AssessmentResult(
        recordId: asInt(json['recordId']),
        detailId: asInt(json['detailId']),
        audioPath: asString(json['audioPath']),
        score: asNullableDouble(json['score']) ?? 0,
        transcription: asString(json['transcription']),
      );

  final int recordId;
  final int detailId;
  final String audioPath;
  final double score;
  final String transcription;
}

class AssessmentRecord {
  const AssessmentRecord({
    required this.id,
    required this.testId,
    required this.bookName,
    required this.testName,
    required this.createAt,
  });

  factory AssessmentRecord.fromJson(JsonMap json) => AssessmentRecord(
        id: asInt(json['id']),
        testId: asInt(json['testId']),
        bookName: asString(json['bookName']),
        testName: asString(json['testName']),
        createAt:
            DateTime.tryParse(asString(json['createAt'])) ?? DateTime(1970),
      );

  final int id;
  final int testId;
  final String bookName;
  final String testName;
  final DateTime createAt;
}

class RecordPage {
  const RecordPage({
    required this.records,
    required this.hasMore,
    required this.nextCursorId,
  });

  factory RecordPage.fromJson(JsonMap json) => RecordPage(
        records: asJsonMapList(json['records'])
            .map(AssessmentRecord.fromJson)
            .toList(),
        hasMore: json['hasMore'] == true,
        nextCursorId:
            json['nextCursorId'] == null ? null : asInt(json['nextCursorId']),
      );

  final List<AssessmentRecord> records;
  final bool hasMore;
  final int? nextCursorId;
}

class AssessmentDetail {
  const AssessmentDetail({
    required this.id,
    required this.recordId,
    required this.questionId,
    required this.part,
    required this.seqNo,
    required this.questionPrompt,
    required this.questionAudioUrl,
    required this.audioPath,
    required this.transcription,
    required this.overallScore,
    required this.pronunciationScore,
    required this.fluencyScore,
    required this.lexicalScore,
    required this.grammarScore,
    required this.sentencesPronunciation,
    required this.relevance,
    required this.speed,
    required this.wordCount,
  });

  factory AssessmentDetail.fromJson(JsonMap json) => AssessmentDetail(
        id: asInt(json['id']),
        recordId: asInt(json['recordId']),
        questionId: asInt(json['questionId']),
        part: asInt(json['part'], 1),
        seqNo: asInt(json['seqNo']),
        questionPrompt: asString(json['questionPrompt']),
        questionAudioUrl: asString(json['questionAudioUrl']),
        audioPath: asString(json['audioPath']),
        transcription: asString(json['transcription']),
        overallScore: asNullableDouble(json['overallScore']),
        pronunciationScore: asNullableDouble(json['pronunciationScore']),
        fluencyScore: asNullableDouble(json['fluencyCoherenceScore']),
        lexicalScore: asNullableDouble(json['lexicalResourceScore']),
        grammarScore: asNullableDouble(json['grammarScore']),
        sentencesPronunciation: json['sentencesPronunciation'],
        relevance: json['relevance'] == null ? null : asInt(json['relevance']),
        speed: json['speed'] == null ? null : asInt(json['speed']),
        wordCount: json['wordCnt'] == null ? null : asInt(json['wordCnt']),
      );

  final int id;
  final int recordId;
  final int questionId;
  final int part;
  final int seqNo;
  final String questionPrompt;
  final String questionAudioUrl;
  final String audioPath;
  final String transcription;
  final double? overallScore;
  final double? pronunciationScore;
  final double? fluencyScore;
  final double? lexicalScore;
  final double? grammarScore;
  final Object? sentencesPronunciation;
  final int? relevance;
  final int? speed;
  final int? wordCount;
}

class RecordDetails {
  const RecordDetails({required this.record, required this.details});

  factory RecordDetails.fromJson(JsonMap json) => RecordDetails(
        record: AssessmentRecord.fromJson(asJsonMap(json['record'])),
        details: asJsonMapList(json['details'])
            .map(AssessmentDetail.fromJson)
            .toList(),
      );

  final AssessmentRecord record;
  final List<AssessmentDetail> details;
}

class AiEvaluation {
  const AiEvaluation({
    required this.overallScore,
    required this.pronunciationScore,
    required this.fluencyScore,
    required this.lexicalScore,
    required this.grammarScore,
    required this.sentencesPronunciation,
    required this.relevance,
    required this.speed,
    required this.wordCount,
    required this.overallSummary,
    required this.fluencySummary,
    required this.fluencyStrengths,
    required this.fluencyImprovements,
    required this.grammarSummary,
    required this.grammarStructures,
    required this.grammarCorrections,
    required this.lexicalSummary,
    required this.lexicalImprovements,
    required this.lexicalStrongExpressions,
    required this.pronunciationSummary,
    required this.improvedAnswerText,
    required this.improvedAnswerFeedback,
  });

  factory AiEvaluation.fromJson(JsonMap json) => AiEvaluation(
        overallScore: asNullableDouble(json['overallScore']),
        pronunciationScore: asNullableDouble(json['pronunciationScore']),
        fluencyScore: asNullableDouble(json['fluencyCoherenceScore']),
        lexicalScore: asNullableDouble(json['lexicalResourceScore']),
        grammarScore: asNullableDouble(json['grammarScore']),
        sentencesPronunciation: json['sentencesPronunciation'],
        relevance: json['relevance'] == null ? null : asInt(json['relevance']),
        speed: json['speed'] == null ? null : asInt(json['speed']),
        wordCount: json['wordCnt'] == null ? null : asInt(json['wordCnt']),
        overallSummary: asString(json['overallSummary']),
        fluencySummary: asString(json['fcSummary']),
        fluencyStrengths: asString(json['fcStrengths']),
        fluencyImprovements: asString(json['fcImprovements']),
        grammarSummary: asString(json['grammarSummary']),
        grammarStructures: json['grammarStructuresUsed'],
        grammarCorrections: json['grammarCorrections'],
        lexicalSummary: asString(json['lexicalSummary']),
        lexicalImprovements: json['lexicalImprovements'],
        lexicalStrongExpressions: json['lexicalStrongExpressions'],
        pronunciationSummary: asString(json['pronunciationSummary']),
        improvedAnswerText: asString(json['improvedAnswerText']),
        improvedAnswerFeedback: asString(json['improvedAnswerFeedback']),
      );

  final double? overallScore;
  final double? pronunciationScore;
  final double? fluencyScore;
  final double? lexicalScore;
  final double? grammarScore;
  final Object? sentencesPronunciation;
  final int? relevance;
  final int? speed;
  final int? wordCount;
  final String overallSummary;
  final String fluencySummary;
  final String fluencyStrengths;
  final String fluencyImprovements;
  final String grammarSummary;
  final Object? grammarStructures;
  final Object? grammarCorrections;
  final String lexicalSummary;
  final Object? lexicalImprovements;
  final Object? lexicalStrongExpressions;
  final String pronunciationSummary;
  final String improvedAnswerText;
  final String improvedAnswerFeedback;
}
