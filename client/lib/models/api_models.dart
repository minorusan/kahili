class InvestigationStatus {
  final bool active;
  final String? motherIssueId;
  final String? status; // "running" | "completed" | "failed"
  final String? branch;
  final String? lastReport;
  final String? startedAt;
  final String? completedAt;

  InvestigationStatus({
    required this.active,
    this.motherIssueId,
    this.status,
    this.branch,
    this.lastReport,
    this.startedAt,
    this.completedAt,
  });

  factory InvestigationStatus.fromJson(Map<String, dynamic> json) {
    final inv = json['investigation'] as Map<String, dynamic>?;
    return InvestigationStatus(
      active: json['active'] == true,
      motherIssueId: inv?['motherIssueId'],
      status: inv?['status'],
      branch: inv?['branch'],
      lastReport: inv?['lastReport'],
      startedAt: inv?['startedAt'],
      completedAt: inv?['completedAt'],
    );
  }
}

class ReportResult {
  final bool exists;
  final String motherIssueId;
  final String? report;

  ReportResult({required this.exists, required this.motherIssueId, this.report});

  factory ReportResult.fromJson(Map<String, dynamic> json) {
    return ReportResult(
      exists: json['exists'] == true,
      motherIssueId: json['motherIssueId'] ?? '',
      report: json['report'],
    );
  }
}

class RepoInfo {
  final List<String> branches;
  final List<String> tags;

  RepoInfo({required this.branches, required this.tags});

  factory RepoInfo.fromJson(Map<String, dynamic> json) {
    return RepoInfo(
      branches: List<String>.from(json['branches'] ?? []),
      tags: List<String>.from(json['tags'] ?? []),
    );
  }
}

class RuleGenerationStatus {
  final bool active;
  final String? status; // "running" | "completed" | "failed" | "rejected"
  final String? prompt;
  final String? lastStatus;
  final String? startedAt;
  final String? completedAt;

  RuleGenerationStatus({
    required this.active,
    this.status,
    this.prompt,
    this.lastStatus,
    this.startedAt,
    this.completedAt,
  });

  factory RuleGenerationStatus.fromJson(Map<String, dynamic> json) {
    final gen = json['generation'] as Map<String, dynamic>?;
    return RuleGenerationStatus(
      active: json['active'] == true,
      status: gen?['status'],
      prompt: gen?['prompt'],
      lastStatus: gen?['lastStatus'],
      startedAt: gen?['startedAt'],
      completedAt: gen?['completedAt'],
    );
  }
}

class HelpAgentStatus {
  final bool active;
  final String? id;
  final String? question;
  final String? status; // "running" | "completed" | "failed"
  final String? statusText;
  final String? startedAt;
  final String? completedAt;

  HelpAgentStatus({
    required this.active,
    this.id,
    this.question,
    this.status,
    this.statusText,
    this.startedAt,
    this.completedAt,
  });

  factory HelpAgentStatus.fromJson(Map<String, dynamic> json) {
    final agent = json['agent'] as Map<String, dynamic>?;
    return HelpAgentStatus(
      active: json['active'] == true,
      id: agent?['id'],
      question: agent?['question'],
      status: agent?['status'],
      statusText: agent?['statusText'],
      startedAt: agent?['startedAt'],
      completedAt: agent?['completedAt'],
    );
  }
}

class HelpQuestionSummary {
  final String id;
  final String question;
  final String status;
  final String startedAt;
  final String? completedAt;

  HelpQuestionSummary({
    required this.id,
    required this.question,
    required this.status,
    required this.startedAt,
    this.completedAt,
  });

  factory HelpQuestionSummary.fromJson(Map<String, dynamic> json) {
    return HelpQuestionSummary(
      id: json['id'] ?? '',
      question: json['question'] ?? '',
      status: json['status'] ?? '',
      startedAt: json['startedAt'] ?? '',
      completedAt: json['completedAt'],
    );
  }
}

class HelpQuestionDetail {
  final String question;
  final String answer;
  final String status;
  final String startedAt;
  final String? completedAt;

  HelpQuestionDetail({
    required this.question,
    required this.answer,
    required this.status,
    required this.startedAt,
    this.completedAt,
  });

  factory HelpQuestionDetail.fromJson(Map<String, dynamic> json) {
    return HelpQuestionDetail(
      question: json['question'] ?? '',
      answer: json['answer'] ?? '',
      status: json['status'] ?? '',
      startedAt: json['startedAt'] ?? '',
      completedAt: json['completedAt'],
    );
  }
}
