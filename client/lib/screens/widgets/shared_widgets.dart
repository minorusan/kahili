import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/kahili_theme.dart';

import 'web_copy_stub.dart' if (dart.library.js_interop) 'web_copy_impl.dart' as web_copy;

/// A SelectionArea wrapper that fixes Ctrl+C on Flutter web.
class CopyableSelectionArea extends StatefulWidget {
  final Widget child;
  const CopyableSelectionArea({super.key, required this.child});

  @override
  State<CopyableSelectionArea> createState() => _CopyableSelectionAreaState();
}

class _CopyableSelectionAreaState extends State<CopyableSelectionArea> {
  static String? selectedText;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _WebCopyHandler._register();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      onSelectionChanged: (content) {
        selectedText = content?.plainText;
      },
      child: widget.child,
    );
  }
}

class _WebCopyHandler {
  static bool _registered = false;

  static void _register() {
    if (_registered) return;
    _registered = true;
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  static bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.keyC) return false;

    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final meta = HardwareKeyboard.instance.isMetaPressed;
    if (!ctrl && !meta) return false;

    final text = _CopyableSelectionAreaState.selectedText;
    if (text != null && text.isNotEmpty) {
      web_copy.writeToClipboard(text);
      return true;
    }
    return false;
  }
}

Widget sectionHeader(String title) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: KahiliColors.textSecondary, letterSpacing: 0.3)),
  );
}

Widget darkCard({required Widget child}) {
  return Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: KahiliColors.surfaceLight,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: KahiliColors.border),
    ),
    child: child,
  );
}

Widget kahiliDivider() => const Divider(height: 1, color: KahiliColors.border);

Widget timelineRow(String label, String value, Color dotColor) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 12, color: KahiliColors.textTertiary))),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 13, color: KahiliColors.textPrimary, fontFamily: 'monospace')),
        ),
      ],
    ),
  );
}

Widget linkRow(BuildContext context, String url, IconData icon) {
  return InkWell(
    onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
    onLongPress: () => _copyToClipboard(context, url),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: KahiliColors.cyanMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(url, style: const TextStyle(fontSize: 12, color: KahiliColors.cyan, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _copyToClipboard(context, url),
            child: const Icon(Icons.copy_rounded, size: 14, color: KahiliColors.textTertiary),
          ),
        ],
      ),
    ),
  );
}

void _copyToClipboard(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
  );
}
