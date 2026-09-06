import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/branding_service.dart';
import '../../services/language_service.dart';
import '../../widgets/empty_state.dart';

class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({super.key});
  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final List<Map> _messages = [];
  final _scrollCtrl = ScrollController();
  final _inputCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  int? _myUserId;
  int _lastId = 0;
  Timer? _pollTimer;
  bool _sending = false;
  bool _uploading = false;
  bool _showEmoji = false;
  bool _attachmentsEnabled = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scrollCtrl.dispose();
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final user = await AuthService().getUser();
    _myUserId = user?['id'] as int?;
    _attachmentsEnabled = user?['chat_attachments_enabled'] == true;
    await _loadInitial();
    // Simple polling every 5 seconds for a "live" feel without websocket infra.
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
  }

  Future<void> _loadInitial() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().get('/chat/messages');
      final list = List<Map>.from(res['data'] ?? []);
      setState(() {
        // Full reload (initial load AND manual refresh both call this) —
        // clear first so refreshing doesn't duplicate every message
        // already in the list.
        _messages
          ..clear()
          ..addAll(list);
        if (list.isNotEmpty) _lastId = list.last['id'] as int;
        _loading = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  Future<void> _poll() async {
    if (_lastId == 0) return;
    try {
      final res = await ApiService().get('/chat/messages?after_id=$_lastId');
      final list = List<Map>.from(res['data'] ?? []);
      if (list.isNotEmpty && mounted) {
        setState(() {
          _addMessages(list);
        });
        _scrollToBottom();
      }
    } catch (_) {
      // Silent fail on background poll - don't disrupt the UI with errors.
    }
  }

  /// Adds a message only if its id isn't already in the list. Needed
  /// because the background poll (every 5s) and an in-flight send/upload
  /// can race: if a poll request was already sent using the OLD _lastId
  /// right as you send a new message, that poll's response can come back
  /// containing the very message you just added locally — causing a
  /// visible duplicate until the next full reload. Guarding on id fixes
  /// this regardless of which call "wins" the race.
  void _addMessage(Map msg) {
    final id = msg['id'];
    if (id != null && _messages.any((m) => m['id'] == id)) return;
    _messages.add(msg);
    if (id is int) _lastId = id;
  }

  void _addMessages(List<Map> list) {
    for (final m in list) {
      _addMessage(m);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _inputCtrl.clear();
    try {
      final res = await ApiService().post('/chat/messages', {'message': text});
      final msg = (res['data'] as Map);
      setState(() {
        _addMessage(msg);
      });
      _scrollToBottom();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSendPhoto(ImageSource source) async {
    if (!_attachmentsEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(LanguageService.t('photo_sharing_isn_t_enabled_for_your_apartmen')),
      ));
      return;
    }
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 90);
    if (picked == null) return;

    setState(() => _uploading = true);
    try {
      final res = await ApiService().uploadMultipart(
        '/chat/attachment',
        {},
        filePath: picked.path,
        fileField: 'file',
      );
      final msg = (res['data'] as Map);
      setState(() {
        _addMessage(msg);
      });
      _scrollToBottom();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(LanguageService.t('take_photo')),
            onTap: () { Navigator.pop(ctx); _pickAndSendPhoto(ImageSource.camera); },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(LanguageService.t('choose_from_gallery')),
            onTap: () { Navigator.pop(ctx); _pickAndSendPhoto(ImageSource.gallery); },
          ),
          if (!_attachmentsEnabled)
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                LanguageService.t('photo_sharing_isn_t_enabled_for_your_apartmen_2'),
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
        ]),
      ),
    );
  }

  void _openImage(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
      ),
    );
  }

  void _toggleEmoji() {
    if (_showEmoji) {
      setState(() => _showEmoji = false);
    } else {
      FocusScope.of(context).unfocus();
      setState(() => _showEmoji = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;
    return Scaffold(
      appBar: AppBar(
        title: Text(LanguageService.t('community_chat')),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadInitial)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 12),
                    ElevatedButton(onPressed: _loadInitial, child: Text(LanguageService.t('retry'))),
                  ]),
                )
              : Column(children: [
                  Expanded(
                    child: _messages.isEmpty
                        ? EmptyState(icon: Icons.chat_bubble_outline, title: LanguageService.t('no_messages_yet_say_hello_to_your_community'), color: BrandingService.primary)
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.all(14),
                            itemCount: _messages.length,
                            itemBuilder: (_, i) {
                              final m = _messages[i];
                              final isMine = m['user_id'] == _myUserId;
                              final isAdmin = (m['user']?['role']) == 'apartment_admin';
                              final showHeader = i == 0 || _messages[i - 1]['user_id'] != m['user_id'];
                              final type = m['type'] as String? ?? 'text';
                              final attachmentUrl = m['attachment_url'] as String?;
                              return Align(
                                alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: type == 'image'
                                      ? const EdgeInsets.all(5)
                                      : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                  decoration: BoxDecoration(
                                    color: isMine ? primary : (isAdmin ? Colors.amber.shade50 : Colors.grey.shade100),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    if (showHeader && !isMine)
                                      Padding(
                                        padding: EdgeInsets.only(bottom: 3, left: type == 'image' ? 6 : 0, top: type == 'image' ? 4 : 0),
                                        child: Row(children: [
                                          Text(m['user']?['name'] ?? '',
                                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5,
                                                  color: isAdmin ? Colors.amber.shade800 : Colors.blueGrey)),
                                          if (isAdmin) ...[
                                            const SizedBox(width: 5),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                              decoration: BoxDecoration(color: Colors.amber.shade700, borderRadius: BorderRadius.circular(6)),
                                              child: Text(LanguageService.t('admin'), style: TextStyle(color: Colors.white, fontSize: 9)),
                                            ),
                                          ],
                                        ]),
                                      ),
                                    if (type == 'image' && attachmentUrl != null)
                                      GestureDetector(
                                        onTap: () => _openImage(attachmentUrl),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(10),
                                          child: Image.network(attachmentUrl, fit: BoxFit.cover,
                                              width: 200, height: 200,
                                              errorBuilder: (_, __, ___) => Container(
                                                width: 200, height: 140, color: Colors.grey.shade300,
                                                child: const Icon(Icons.broken_image_outlined, color: Colors.grey))),
                                        ),
                                      )
                                    else if (type == 'file' && attachmentUrl != null)
                                      InkWell(
                                        onTap: () {}, // file preview/download can be wired to url_launcher later
                                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                                          Icon(Icons.insert_drive_file_outlined, size: 20, color: isMine ? Colors.white : Colors.black54),
                                          const SizedBox(width: 6),
                                          Flexible(child: Text(m['attachment_name'] ?? 'File',
                                              style: TextStyle(color: isMine ? Colors.white : Colors.black87, fontSize: 13, decoration: TextDecoration.underline))),
                                        ]),
                                      ),
                                    if ((m['message'] as String?)?.isNotEmpty == true)
                                      Padding(
                                        padding: EdgeInsets.only(top: type != 'text' ? 6 : 0, left: type == 'image' ? 6 : 0, right: type == 'image' ? 6 : 0),
                                        child: Text(m['message'],
                                            style: TextStyle(color: isMine ? Colors.white : Colors.black87, fontSize: 14)),
                                      ),
                                  ]),
                                ),
                              );
                            },
                          ),
                  ),
                  if (_uploading) const LinearProgressIndicator(minHeight: 2),
                  SafeArea(
                    top: false,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(6, 8, 10, 8),
                      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, -2))]),
                      child: Row(children: [
                        IconButton(
                          icon: Icon(_showEmoji ? Icons.keyboard_alt_outlined : Icons.emoji_emotions_outlined, color: Colors.grey[600]),
                          onPressed: _toggleEmoji,
                        ),
                        IconButton(
                          icon: Icon(Icons.attach_file_rounded, color: _attachmentsEnabled ? Colors.grey[600] : Colors.grey[350]),
                          onPressed: _uploading ? null : _showAttachmentOptions,
                        ),
                        Expanded(
                          child: TextField(
                            controller: _inputCtrl,
                            decoration: InputDecoration(hintText: LanguageService.t('message_the_community'), isDense: true),
                            minLines: 1, maxLines: 4,
                            onTap: () { if (_showEmoji) setState(() => _showEmoji = false); },
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        const SizedBox(width: 6),
                        CircleAvatar(
                          backgroundColor: primary,
                          child: _sending
                              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : IconButton(icon: const Icon(Icons.send, color: Colors.white, size: 18), onPressed: _send),
                        ),
                      ]),
                    ),
                  ),
                  Offstage(
                    offstage: !_showEmoji,
                    child: SizedBox(
                      height: 280,
                      child: EmojiPicker(
                        textEditingController: _inputCtrl,
                        onEmojiSelected: (category, emoji) {},
                        config: const Config(height: 280),
                      ),
                    ),
                  ),
                ]),
    );
  }
}
