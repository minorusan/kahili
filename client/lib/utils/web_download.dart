import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void downloadTextFile(String content, String filename) {
  final bytes = utf8.encode(content);
  final blob = html.Blob([bytes], 'text/markdown');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
