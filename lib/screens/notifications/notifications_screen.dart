import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../services/language_service.dart';
import '../../widgets/empty_state.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List _items = [];
  int  _unread = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiService().get('/notifications');
      setState(() {
        _items  = res['data']['data'] ?? [];
        _unread = res['unread_count'] ?? 0;
        _loading = false;
      });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _markRead(int id) async {
    try {
      await ApiService().post('/notifications/$id/read', {});
      _load();
    } catch (_) {}
  }

  IconData _icon(String type) {
    switch (type) {
      case 'payment_due':       return Icons.warning_amber_rounded;
      case 'payment_received':  return Icons.check_circle_outline;
      case 'notice':            return Icons.campaign_outlined;
      case 'booking_update':    return Icons.calendar_today_outlined;
      case 'complaint_update':  return Icons.chat_bubble_outline;
      case 'visitor':           return Icons.badge_outlined;
      case 'plan_expiry':       return Icons.timer_outlined;
      case 'offer':             return Icons.local_offer_outlined;
      default:                   return Icons.notifications_outlined;
    }
  }

  Color _color(String type) {
    switch (type) {
      case 'payment_due':  return Colors.red;
      case 'payment_received': return Colors.green;
      case 'plan_expiry': return Colors.orange;
      case 'offer':       return Colors.green;
      default:             return BrandingService.primary;
    }
  }

  /// Turns the raw API timestamp (ISO 8601, e.g. "2026-07-20T14:32:00Z")
  /// into a friendly, human-readable time - "Just now" / "5m ago" / "2h ago"
  /// for anything recent, then falls back to a proper date once it's more
  /// than a day old, instead of dumping the raw ISO string on screen.
  String _formatTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final DateTime dt;
    try {
      dt = DateTime.parse(iso).toLocal();
    } catch (_) {
      return iso;
    }

    final now  = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inSeconds < 60) return LanguageService.t('just_now');
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24 && dt.day == now.day) return '${diff.inHours}h ago';

    final yesterday = now.subtract(const Duration(days: 1));
    if (dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day) {
      return '${LanguageService.t('yesterday')}, ${DateFormat('h:mm a').format(dt)}';
    }
    if (dt.year == now.year) return BrandingService.formatDateTimeShort(dt);
    return BrandingService.formatDateTime(dt);
  }

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: Row(children: [
          Text(LanguageService.t('notifications')),
          if (_unread > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.22),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('$_unread', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ],
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? EmptyState(icon: Icons.notifications_none_rounded, title: LanguageService.t('no_notifications_yet'), color: primary)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final n = _items[i];
                        final isRead = n['read_at'] != null;
                        final color  = _color(n['type']);

                        return Material(
                          color: isRead ? Colors.white : color.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () { if (!isRead) _markRead(n['id']); },
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: isRead ? Colors.black.withOpacity(0.05) : color.withOpacity(0.18)),
                                boxShadow: [
                                  BoxShadow(
                                    color: (isRead ? Colors.black : color).withOpacity(isRead ? 0.03 : 0.10),
                                    blurRadius: 10, offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Container(
                                  width: 44, height: 44,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(colors: [color, color.withOpacity(0.72)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                    borderRadius: BorderRadius.circular(13),
                                    boxShadow: [BoxShadow(color: color.withOpacity(0.32), blurRadius: 7, offset: const Offset(0, 3))],
                                  ),
                                  child: Icon(_icon(n['type']), color: Colors.white, size: 21),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Expanded(
                                        child: Text(n['title'] ?? '',
                                            style: TextStyle(
                                              fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                                              fontSize: 14.5,
                                              color: Colors.black87,
                                            )),
                                      ),
                                      if (!isRead) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          margin: const EdgeInsets.only(top: 3),
                                          width: 9, height: 9,
                                          decoration: BoxDecoration(color: BrandingService.accent, shape: BoxShape.circle),
                                        ),
                                      ],
                                    ]),
                                    const SizedBox(height: 4),
                                    Text(n['message'] ?? '',
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.3)),
                                    const SizedBox(height: 8),
                                    Row(children: [
                                      Icon(Icons.access_time_rounded, size: 12, color: Colors.grey.shade500),
                                      const SizedBox(width: 4),
                                      Text(_formatTime(n['created_at']),
                                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                                    ]),
                                  ]),
                                ),
                              ]),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
