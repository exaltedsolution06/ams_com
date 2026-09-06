import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../services/language_service.dart';
import '../../utils/rule_blocks.dart';

/// Apartment Admin: edit the "Rules" page shown to residents.
///
/// Line-based rich text editor (bold / italic / color per line) plus a
/// mic button per line for speech-to-text dictation - built without a
/// third-party rich-text package (see lib/utils/rule_blocks.dart for why).
/// Speech recognition reuses the same `speech_to_text` package/pattern
/// already wired up for voice commands elsewhere in the app - 100%
/// on-device/browser-native, no extra API key or dependency.
class AdminRulesScreen extends StatefulWidget {
  const AdminRulesScreen({super.key});
  @override
  State<AdminRulesScreen> createState() => _AdminRulesScreenState();
}

class _AdminRulesScreenState extends State<AdminRulesScreen> {
  final List<RuleBlock> _blocks = [];
  final List<TextEditingController> _controllers = [];
  final List<FocusNode> _focusNodes = [];

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _lastUpdatedLabel;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().get('/rules');
      final data = (res['data'] as Map?)?.cast<String, dynamic>();
      final html = data?['content'] as String? ?? '';
      final updatedAt = data?['updated_at'] as String?;
      _setBlocks(decodeHtmlToRuleBlocks(html));
      setState(() {
        _lastUpdatedLabel = updatedAt?.split('T').first;
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  void _setBlocks(List<RuleBlock> blocks) {
    for (final c in _controllers) { c.dispose(); }
    for (final f in _focusNodes) { f.dispose(); }
    _controllers.clear();
    _focusNodes.clear();
    _blocks..clear()..addAll(blocks);
    for (final b in _blocks) {
      _controllers.add(TextEditingController(text: b.text));
      _focusNodes.add(FocusNode());
    }
  }

  void _addLine({int? afterIndex}) {
    final insertAt = afterIndex == null ? _blocks.length : afterIndex + 1;
    setState(() {
      _blocks.insert(insertAt, RuleBlock());
      _controllers.insert(insertAt, TextEditingController());
      _focusNodes.insert(insertAt, FocusNode());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (insertAt < _focusNodes.length) _focusNodes[insertAt].requestFocus();
    });
  }

  void _removeLine(int index) {
    if (_blocks.length == 1) {
      // Keep at least one (empty) line instead of leaving nothing to edit.
      setState(() { _controllers[0].clear(); _blocks[0] = RuleBlock(); });
      return;
    }
    setState(() {
      _blocks.removeAt(index);
      _controllers.removeAt(index).dispose();
      _focusNodes.removeAt(index).dispose();
    });
  }

  void _moveLine(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final block = _blocks.removeAt(oldIndex);
      final ctrl = _controllers.removeAt(oldIndex);
      final focus = _focusNodes.removeAt(oldIndex);
      _blocks.insert(newIndex, block);
      _controllers.insert(newIndex, ctrl);
      _focusNodes.insert(newIndex, focus);
    });
  }

  Future<void> _save() async {
    for (var i = 0; i < _blocks.length; i++) {
      _blocks[i].text = _controllers[i].text;
    }
    final html = encodeRuleBlocksToHtml(_blocks);
    setState(() => _saving = true);
    try {
      await ApiService().put('/admin/rules', {'content': html});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageService.t('rules_updated')), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Color _colorFromHex(String hex) {
    final h = hex.replaceFirst('#', '');
    final full = h.length == 6 ? 'FF$h' : h;
    return Color(int.parse(full, radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(LanguageService.t('rules')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load),
        ],
      ),
      floatingActionButton: _loading || _error != null
          ? null
          : FloatingActionButton.extended(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving...' : 'Save Rules'),
              backgroundColor: BrandingService.primary,
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(icon: const Icon(Icons.refresh), label: Text(LanguageService.t('retry')), onPressed: _load),
                    ]),
                  ),
                )
              : Column(children: [
                  Container(
                    width: double.infinity,
                    color: BrandingService.primary.withOpacity(0.06),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(children: [
                      Icon(Icons.info_outline, size: 16, color: BrandingService.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _lastUpdatedLabel != null
                              ? 'Residents see this exactly as shown below · last updated $_lastUpdatedLabel'
                              : 'Residents will see this exactly as shown below.',
                          style: TextStyle(fontSize: 12, color: BrandingService.primary),
                        ),
                      ),
                    ]),
                  ),
                  Expanded(
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                      itemCount: _blocks.length,
                      onReorder: _moveLine,
                      itemBuilder: (_, i) => _RuleLineCard(
                        key: ValueKey('rule_line_$i${_controllers[i].hashCode}'),
                        index: i,
                        block: _blocks[i],
                        controller: _controllers[i],
                        focusNode: _focusNodes[i],
                        colorFromHex: _colorFromHex,
                        onChanged: () => setState(() {}),
                        onAddBelow: () => _addLine(afterIndex: i),
                        onDelete: () => _removeLine(i),
                      ),
                    ),
                  ),
                ]),
    );
  }
}

class _RuleLineCard extends StatefulWidget {
  final int index;
  final RuleBlock block;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Color Function(String hex) colorFromHex;
  final VoidCallback onChanged;
  final VoidCallback onAddBelow;
  final VoidCallback onDelete;

  const _RuleLineCard({
    super.key,
    required this.index,
    required this.block,
    required this.controller,
    required this.focusNode,
    required this.colorFromHex,
    required this.onChanged,
    required this.onAddBelow,
    required this.onDelete,
  });

  @override
  State<_RuleLineCard> createState() => _RuleLineCardState();
}

class _RuleLineCardState extends State<_RuleLineCard> {
  void _pickColor() async {
    final chosen = await showModalBottomSheet<String?>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(LanguageService.t('text_color'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 14),
            Wrap(spacing: 14, runSpacing: 14, children: [
              for (final hex in ruleBlockColorPalette)
                InkWell(
                  onTap: () => Navigator.pop(ctx, hex),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.colorFromHex(hex),
                      border: Border.all(
                        color: widget.block.colorHex == hex ? Colors.black : Colors.black12,
                        width: widget.block.colorHex == hex ? 2.5 : 1,
                      ),
                    ),
                  ),
                ),
              InkWell(
                onTap: () => Navigator.pop(ctx, ''), // '' sentinel = clear
                customBorder: const CircleBorder(),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black26),
                  ),
                  child: const Icon(Icons.close, size: 18, color: Colors.black45),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
    if (chosen == null) return;
    setState(() => widget.block.colorHex = chosen.isEmpty ? null : chosen);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.block;
    final textColor = b.colorHex != null ? widget.colorFromHex(b.colorHex!) : Colors.black87;

    return Card(
      key: ValueKey('card_${widget.index}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ReorderableDragStartListener(
            index: widget.index,
            child: const Padding(
              padding: EdgeInsets.only(top: 14, right: 4),
              child: Icon(Icons.drag_indicator, color: Colors.black26, size: 20),
            ),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                minLines: 1,
                maxLines: 4,
                style: TextStyle(
                  fontSize: 14.5,
                  color: textColor,
                  fontWeight: b.bold ? FontWeight.bold : FontWeight.normal,
                  fontStyle: b.italic ? FontStyle.italic : FontStyle.normal,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: LanguageService.t('type_a_rule'),
                ),
                onChanged: (_) => widget.onChanged(),
              ),
              Row(children: [
                _ToggleIcon(
                  icon: Icons.format_bold,
                  active: b.bold,
                  onTap: () { setState(() => b.bold = !b.bold); widget.onChanged(); },
                ),
                _ToggleIcon(
                  icon: Icons.format_italic,
                  active: b.italic,
                  onTap: () { setState(() => b.italic = !b.italic); widget.onChanged(); },
                ),
                _ToggleIcon(
                  icon: Icons.palette_outlined,
                  active: b.colorHex != null,
                  activeColor: b.colorHex != null ? widget.colorFromHex(b.colorHex!) : null,
                  onTap: _pickColor,
                ),
                _MicButton(
                  controller: widget.controller,
                  onResult: widget.onChanged,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 20, color: Colors.grey),
                  tooltip: LanguageService.t('add_line_below'),
                  onPressed: widget.onAddBelow,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                  tooltip: LanguageService.t('delete_line'),
                  onPressed: widget.onDelete,
                  visualDensity: VisualDensity.compact,
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _ToggleIcon extends StatelessWidget {
  final IconData icon;
  final bool active;
  final Color? activeColor;
  final VoidCallback onTap;
  const _ToggleIcon({required this.icon, required this.active, required this.onTap, this.activeColor});

  @override
  Widget build(BuildContext context) {
    final color = active ? (activeColor ?? BrandingService.primary) : Colors.grey[500];
    return IconButton(
      icon: Icon(icon, size: 19, color: color),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: active ? (activeColor ?? BrandingService.primary).withOpacity(0.12) : null,
      ),
    );
  }
}

/// Small per-line mic button: tap to dictate straight into this line's
/// TextField (appends to whatever's already there). Uses the same
/// speech_to_text engine as the global voice command button, but simpler -
/// no command parsing, it just types out what it hears.
class _MicButton extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onResult;
  const _MicButton({required this.controller, required this.onResult});

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _listening = false;
  bool _busy = false;

  Future<void> _toggle() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    if (_busy) return;
    _busy = true;
    try {
      final ready = await _speech
          .initialize(onStatus: (status) {
            if (status == 'notListening' || status == 'done') {
              if (mounted) setState(() => _listening = false);
            }
          }, onError: (_) {
            if (mounted) setState(() => _listening = false);
          })
          .timeout(const Duration(seconds: 10), onTimeout: () => false);
      if (!ready) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(LanguageService.t('speech_recognition_is_not_available_on_this'))),
          );
        }
        return;
      }
      // Base text captured at listen-start, so live partial results replace
      // only what was spoken this session rather than piling up duplicates.
      final base = widget.controller.text;
      final needsSpace = base.isNotEmpty && !base.endsWith(' ');
      setState(() => _listening = true);
      await _speech.listen(
        onResult: (result) {
          final heard = result.recognizedWords;
          final combined = heard.isEmpty ? base : '$base${needsSpace ? ' ' : ''}$heard';
          widget.controller.value = TextEditingValue(
            text: combined,
            selection: TextSelection.collapsed(offset: combined.length),
          );
          widget.onResult();
          if (result.finalResult && mounted) setState(() => _listening = false);
        },
        listenOptions: stt.SpeechListenOptions(partialResults: true, cancelOnError: true),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _listening = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LanguageService.t('couldnt_start_the_microphone_please_try_again'))),
        );
      }
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        _listening ? Icons.mic : Icons.mic_none_rounded,
        size: 19,
        color: _listening ? Colors.red : Colors.grey[500],
      ),
      tooltip: _listening ? 'Stop dictation' : 'Speak to type',
      onPressed: _toggle,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: _listening ? Colors.red.withOpacity(0.10) : null,
      ),
    );
  }
}
