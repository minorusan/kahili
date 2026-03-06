import 'mother_issue.dart';

class SentryIssue {
  final String id;
  final String shortId;
  final String title;
  final String level;
  final String count;
  final int userCount;
  final String firstSeen;
  final String lastSeen;
  final String platform;
  final String permalink;
  final List<StackFrame>? stackFrames;
  final String? errorType;
  final String? errorValue;

  SentryIssue({
    required this.id,
    required this.shortId,
    required this.title,
    required this.level,
    required this.count,
    required this.userCount,
    required this.firstSeen,
    required this.lastSeen,
    required this.platform,
    required this.permalink,
    this.stackFrames,
    this.errorType,
    this.errorValue,
  });

  factory SentryIssue.fromJson(Map<String, dynamic> json) {
    List<StackFrame>? frames;
    if (json['stackTrace'] != null) {
      final rawFrames = json['stackTrace']['frames'] as List<dynamic>?;
      if (rawFrames != null) {
        frames = rawFrames
            .map((f) => StackFrame.fromJson(f as Map<String, dynamic>))
            .toList();
      }
    }

    return SentryIssue(
      id: json['id'] ?? '',
      shortId: json['shortId'] ?? '',
      title: json['title'] ?? '',
      level: json['level'] ?? '',
      count: (json['count'] ?? '0').toString(),
      userCount: json['userCount'] is int
          ? json['userCount']
          : int.tryParse(json['userCount']?.toString() ?? '0') ?? 0,
      firstSeen: json['firstSeen'] ?? '',
      lastSeen: json['lastSeen'] ?? '',
      platform: json['platform'] ?? '',
      permalink: json['permalink'] ?? '',
      stackFrames: frames,
      errorType: json['errorType'] as String?,
      errorValue: json['errorValue'] as String?,
    );
  }
}
