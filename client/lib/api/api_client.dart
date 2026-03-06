import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import '../models/mother_issue.dart';
import '../models/sentry_issue.dart';
import '../models/api_models.dart';

class ApiClient {
  static String get _baseUrl {
    if (kIsWeb) return '';
    return 'http://192.168.0.11:3401';
  }

  // ── Status ───────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getStatus() async {
    final res = await http.get(Uri.parse('$_baseUrl/api/status'));
    if (res.statusCode != 200) {
      throw Exception('Failed to get status: ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Mother issues ─────────────────────────────────────────────────

  static Future<List<MotherIssue>> getMotherIssues() async {
    final res = await http.get(Uri.parse('$_baseUrl/api/kahu/mother-issues'));
    if (res.statusCode != 200) {
      throw Exception('Failed to load mother issues: ${res.statusCode}');
    }
    final List<dynamic> data = jsonDecode(res.body);
    return data
        .map((item) => MotherIssue.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static Future<MotherIssue> getMotherIssue(String id) async {
    final res = await http.get(Uri.parse('$_baseUrl/api/kahu/mother-issues/$id'));
    if (res.statusCode != 200) {
      throw Exception('Failed to load mother issue: ${res.statusCode}');
    }
    return MotherIssue.fromJson(jsonDecode(res.body));
  }

  static Future<MotherIssue> createManualMotherIssue(String issueId) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/kahu/mother-issues/manual'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'issueId': issueId}),
    );
    if (res.statusCode != 201) {
      throw Exception('Failed to create mother issue: ${res.statusCode} ${res.body}');
    }
    return MotherIssue.fromJson(jsonDecode(res.body));
  }

  // ── Investigation ─────────────────────────────────────────────────

  static Future<InvestigationStatus> getInvestigationStatus() async {
    final res = await http.get(Uri.parse('$_baseUrl/api/investigate'));
    if (res.statusCode != 200) {
      throw Exception('Failed to get investigation status: ${res.statusCode}');
    }
    return InvestigationStatus.fromJson(jsonDecode(res.body));
  }

  static Future<void> startInvestigation({
    required String motherIssueId,
    String? branch,
    String? additionalPrompt,
  }) async {
    final body = <String, dynamic>{'motherIssueId': motherIssueId};
    if (branch != null) body['branch'] = branch;
    if (additionalPrompt != null && additionalPrompt.isNotEmpty) {
      body['additionalPrompt'] = additionalPrompt;
    }
    final res = await http.post(
      Uri.parse('$_baseUrl/api/investigate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      final data = jsonDecode(res.body);
      throw Exception(data['error'] ?? 'Failed to start investigation');
    }
  }

  // ── Report ────────────────────────────────────────────────────────

  static Future<ReportResult> getReport(String motherIssueId) async {
    final res = await http.get(Uri.parse('$_baseUrl/api/report/$motherIssueId'));
    if (res.statusCode != 200) {
      throw Exception('Failed to get report: ${res.statusCode}');
    }
    return ReportResult.fromJson(jsonDecode(res.body));
  }

  // ── Reports status ──────────────────────────────────────────────

  static Future<Set<String>> getInvestigatedIssueIds() async {
    final res = await http.get(Uri.parse('$_baseUrl/api/reports/status'));
    if (res.statusCode != 200) {
      throw Exception('Failed to get reports status: ${res.statusCode}');
    }
    final data = jsonDecode(res.body);
    final List<dynamic> ids = data['investigated'] ?? [];
    return ids.cast<String>().toSet();
  }

  // ── Raw issues ──────────────────────────────────────────────────

  static Future<List<SentryIssue>> getIssues() async {
    final res = await http.get(Uri.parse('$_baseUrl/api/kahu/issues'));
    if (res.statusCode != 200) {
      throw Exception('Failed to load issues: ${res.statusCode}');
    }
    final List<dynamic> data = jsonDecode(res.body);
    return data
        .map((item) => SentryIssue.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static Future<Map<String, dynamic>> getIssueDetail(String id) async {
    final res = await http.get(Uri.parse('$_baseUrl/api/kahu/issues/$id'));
    if (res.statusCode != 200) {
      throw Exception('Failed to load issue detail: ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Rule generation ────────────────────────────────────────────

  static Future<RuleGenerationStatus> getRuleGenerationStatus() async {
    final res = await http.get(Uri.parse('$_baseUrl/api/generate-rule'));
    if (res.statusCode != 200) {
      throw Exception('Failed to get rule generation status: ${res.statusCode}');
    }
    return RuleGenerationStatus.fromJson(jsonDecode(res.body));
  }

  static Future<void> startRuleGeneration(String prompt) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/generate-rule'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'prompt': prompt}),
    );
    if (res.statusCode != 200) {
      final data = jsonDecode(res.body);
      throw Exception(data['error'] ?? 'Failed to start rule generation');
    }
  }

  // ── Rules ────────────────────────────────────────────────────────

  static Future<List<Map<String, String>>> getRules() async {
    final res = await http.get(Uri.parse('$_baseUrl/api/kahu/rules'));
    if (res.statusCode != 200) {
      throw Exception('Failed to load rules: ${res.statusCode}');
    }
    final List<dynamic> data = jsonDecode(res.body);
    return data.map((r) {
      final m = r as Map<String, dynamic>;
      return <String, String>{
        'name': m['name'] as String? ?? '',
        'description': m['description'] as String? ?? '',
        'logic': m['logic'] as String? ?? '',
      };
    }).toList();
  }

  static Future<void> regenerateRule({required String ruleName, required String prompt}) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/regenerate-rule'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'ruleName': ruleName, 'prompt': prompt}),
    );
    if (res.statusCode != 200) {
      final data = jsonDecode(res.body);
      throw Exception(data['error'] ?? 'Failed to regenerate rule');
    }
  }

  // ── Daily reports ──────────────────────────────────────────────────

  static Future<List<String>> getDailyReportDates() async {
    final res = await http.get(Uri.parse('$_baseUrl/api/daily-reports'));
    if (res.statusCode != 200) {
      throw Exception('Failed to load daily report dates: ${res.statusCode}');
    }
    final data = jsonDecode(res.body);
    return List<String>.from(data['dates'] ?? []);
  }

  static Future<String?> getDailyReport(String date) async {
    final res = await http.get(Uri.parse('$_baseUrl/api/daily-reports/$date'));
    if (res.statusCode != 200) {
      throw Exception('Failed to load daily report: ${res.statusCode}');
    }
    final data = jsonDecode(res.body);
    if (data['exists'] == true) return data['report'] as String;
    return null;
  }

  // ── Repo info ─────────────────────────────────────────────────────

  static Future<RepoInfo> getRepoInfo() async {
    final res = await http.get(Uri.parse('$_baseUrl/api/repo-info'));
    if (res.statusCode != 200) {
      throw Exception('Failed to get repo info: ${res.statusCode}');
    }
    return RepoInfo.fromJson(jsonDecode(res.body));
  }

  // ── Settings ────────────────────────────────────────────────────

  static Future<Map<String, String>> getSettings() async {
    final res = await http.get(Uri.parse('$_baseUrl/api/kahu-settings'));
    if (res.statusCode != 200) {
      throw Exception('Failed to get settings: ${res.statusCode}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data.map((k, v) => MapEntry(k, v?.toString() ?? ''));
  }

  static Future<Map<String, dynamic>> applySettings(Map<String, String> settings) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/kahu-settings'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(settings),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to apply settings: ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Help agent ──────────────────────────────────────────────────

  static Future<HelpAgentStatus> getHelpAgentStatus() async {
    final res = await http.get(Uri.parse('$_baseUrl/api/help-agent'));
    if (res.statusCode != 200) {
      throw Exception('Failed to get help agent status: ${res.statusCode}');
    }
    return HelpAgentStatus.fromJson(jsonDecode(res.body));
  }

  static Future<void> startHelpAgent(String question) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/help-agent'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'question': question}),
    );
    if (res.statusCode != 200) {
      final data = jsonDecode(res.body);
      throw Exception(data['error'] ?? 'Failed to start help agent');
    }
  }

  static Future<List<HelpQuestionSummary>> getHelpQuestions() async {
    final res = await http.get(Uri.parse('$_baseUrl/api/help-questions'));
    if (res.statusCode != 200) {
      throw Exception('Failed to load help questions: ${res.statusCode}');
    }
    final List<dynamic> data = jsonDecode(res.body);
    return data
        .map((item) => HelpQuestionSummary.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static Future<HelpQuestionDetail> getHelpQuestion(String id) async {
    final res = await http.get(Uri.parse('$_baseUrl/api/help-questions/$id'));
    if (res.statusCode != 200) {
      throw Exception('Failed to load help question: ${res.statusCode}');
    }
    return HelpQuestionDetail.fromJson(jsonDecode(res.body));
  }

  // ── Archive issues ──────────────────────────────────────────────────

  static Future<Map<String, dynamic>> archiveIssues({
    required List<String> issueIds,
    required Map<String, dynamic> archiveParams,
    String? comment,
  }) async {
    final body = <String, dynamic>{
      'issueIds': issueIds,
      'archiveParams': archiveParams,
    };
    if (comment != null && comment.isNotEmpty) body['comment'] = comment;
    final res = await http.post(
      Uri.parse('$_baseUrl/api/kahu/archive-issues'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode != 200 && res.statusCode != 207) {
      final data = jsonDecode(res.body);
      throw Exception(data['error'] ?? 'Failed to archive issues');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Develop agent ──────────────────────────────────────────────────

  static Future<DevelopAgentStatus> getDevelopAgentStatus() async {
    final res = await http.get(Uri.parse('$_baseUrl/api/develop-agent'));
    if (res.statusCode != 200) {
      throw Exception('Failed to get develop agent status: ${res.statusCode}');
    }
    return DevelopAgentStatus.fromJson(jsonDecode(res.body));
  }

  static Future<void> startDevelopAgent(String request) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/develop-agent'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'request': request}),
    );
    if (res.statusCode != 200) {
      final data = jsonDecode(res.body);
      throw Exception(data['error'] ?? 'Failed to start develop agent');
    }
  }

  static Future<List<DevelopRequestSummary>> getDevelopRequests() async {
    final res = await http.get(Uri.parse('$_baseUrl/api/develop-requests'));
    if (res.statusCode != 200) {
      throw Exception('Failed to load develop requests: ${res.statusCode}');
    }
    final List<dynamic> data = jsonDecode(res.body);
    return data
        .map((item) => DevelopRequestSummary.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static Future<DevelopRequestDetail> getDevelopRequest(String id) async {
    final res = await http.get(Uri.parse('$_baseUrl/api/develop-requests/$id'));
    if (res.statusCode != 200) {
      throw Exception('Failed to load develop request: ${res.statusCode}');
    }
    return DevelopRequestDetail.fromJson(jsonDecode(res.body));
  }

  // ── Prompts ──────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getPrompts() async {
    final res = await http.get(Uri.parse('$_baseUrl/api/prompts'));
    if (res.statusCode != 200) {
      throw Exception('Failed to load prompts: ${res.statusCode}');
    }
    final List<dynamic> data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  static Future<void> savePrompt(String name, String template) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/api/prompts/$name'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'template': template}),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to save prompt: ${res.statusCode}');
    }
  }
}
