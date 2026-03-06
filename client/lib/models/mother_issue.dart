class MotherIssueMetrics {
  final int totalOccurrences;
  final int affectedUsers;
  final String firstSeen;
  final String lastSeen;

  MotherIssueMetrics({
    required this.totalOccurrences,
    required this.affectedUsers,
    required this.firstSeen,
    required this.lastSeen,
  });

  factory MotherIssueMetrics.fromJson(Map<String, dynamic> json) {
    return MotherIssueMetrics(
      totalOccurrences: json['totalOccurrences'] ?? 0,
      affectedUsers: json['affectedUsers'] ?? 0,
      firstSeen: json['firstSeen'] ?? '',
      lastSeen: json['lastSeen'] ?? '',
    );
  }
}

class StackFrame {
  final String filename;
  final String function;
  final int lineno;
  final bool inApp;

  StackFrame({
    required this.filename,
    required this.function,
    required this.lineno,
    required this.inApp,
  });

  factory StackFrame.fromJson(Map<String, dynamic> json) {
    return StackFrame(
      filename: json['filename'] ?? '',
      function: json['function'] ?? '',
      lineno: json['lineno'] ?? 0,
      inApp: json['inApp'] ?? false,
    );
  }
}

class MotherIssue {
  final String id;
  final String groupingKey;
  final String ruleName;
  final String title;
  final String errorType;
  final String level;
  final MotherIssueMetrics metrics;
  final List<String> childIssueIds;
  final List<String> childStatuses;
  final List<String> sentryLinks;
  final List<String> smartlookUrls;
  final List<StackFrame>? stackFrames;
  final String? firstSeenRelease;
  final bool allChildrenArchived;
  final String createdAt;
  final String updatedAt;

  MotherIssue({
    required this.id,
    required this.groupingKey,
    required this.ruleName,
    required this.title,
    required this.errorType,
    required this.level,
    required this.metrics,
    required this.childIssueIds,
    required this.childStatuses,
    required this.sentryLinks,
    required this.smartlookUrls,
    this.stackFrames,
    this.firstSeenRelease,
    required this.allChildrenArchived,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MotherIssue.fromJson(Map<String, dynamic> json) {
    List<StackFrame>? frames;
    if (json['stackTrace'] != null) {
      final rawFrames = json['stackTrace']['frames'] as List<dynamic>?;
      if (rawFrames != null) {
        frames = rawFrames
            .map((f) => StackFrame.fromJson(f as Map<String, dynamic>))
            .toList();
      }
    }

    return MotherIssue(
      id: json['id'] ?? '',
      groupingKey: json['groupingKey'] ?? '',
      ruleName: json['ruleName'] ?? '',
      title: json['title'] ?? '',
      errorType: json['errorType'] ?? '',
      level: json['level'] ?? '',
      metrics: MotherIssueMetrics.fromJson(json['metrics'] ?? {}),
      childIssueIds: List<String>.from(json['childIssueIds'] ?? []),
      childStatuses: List<String>.from(json['childStatuses'] ?? []),
      sentryLinks: List<String>.from(json['sentryLinks'] ?? []),
      smartlookUrls: List<String>.from(json['smartlookUrls'] ?? []),
      stackFrames: frames,
      firstSeenRelease: json['firstSeenRelease'],
      allChildrenArchived: json['allChildrenArchived'] == true,
      createdAt: json['createdAt'] ?? '',
      updatedAt: json['updatedAt'] ?? '',
    );
  }
}
