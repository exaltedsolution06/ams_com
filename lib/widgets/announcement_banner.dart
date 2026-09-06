import 'package:flutter/material.dart';
import '../services/announcement_service.dart';
import '../services/auth_service.dart';

/// Mobile counterpart of the web's dashboard announcement box. Drop this
/// near the top of a dashboard screen's body. Fetches active
/// announcements, hides any already dismissed this "session" (see
/// AuthService.getDismissedAnnouncementIds — cleared on logout), and lets
/// the user close each one with an X, which hides it for the rest of this
/// login (persists across app restarts, resets on next login).
class AnnouncementBanner extends StatefulWidget {
  const AnnouncementBanner({super.key});

  @override
  State<AnnouncementBanner> createState() => _AnnouncementBannerState();
}

class _AnnouncementBannerState extends State<AnnouncementBanner> {
  List<AnnouncementItem> _items = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final active = await AnnouncementService.fetchActive();
    final dismissed = await AuthService().getDismissedAnnouncementIds();
    if (!mounted) return;
    setState(() {
      _items = active.where((a) => !dismissed.contains(a.id)).toList();
      _loaded = true;
    });
  }

  Future<void> _dismiss(AnnouncementItem item) async {
    setState(() => _items.remove(item));
    await AuthService().dismissAnnouncement(item.id);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in _items) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.campaign_rounded, color: Color(0xFF1D4ED8), size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.message,
                    style: const TextStyle(fontSize: 13.5, color: Color(0xFF1E293B), height: 1.35),
                  ),
                ),
                InkWell(
                  onTap: () => _dismiss(item),
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded, size: 18, color: Color(0xFF64748B)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
