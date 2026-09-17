import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';

/// Profile > Linked Devices (requirement sections 10 & 11) - the Company
/// app's copy of the same screen shipped in the resident/admin app.
///
/// Lists every trusted environment on the account - website/browser
/// records included, not just this app's - so a Company Admin can see
/// where their account is currently trusted and revoke any one of them.
///
/// Two things this screen is careful to make visible, because they are the
/// whole point of the verification model and would otherwise look like
/// bugs:
///
///  1. Email and Phone are shown as two SEPARATE status chips per entry.
///     They're independent within an environment, so "Email verified /
///     Phone not verified" on one device is a perfectly normal state.
///  2. The platform is shown prominently, because the SAME physical phone
///     legitimately appears twice - once as a Website/Browser record and
///     once as a Company App record - and those two never share
///     verification with each other.
///
/// Removing an entry revokes both login methods for that ONE environment
/// and nothing else; the next sign-in from it asks for verification again.
class LinkedDevicesScreen extends StatefulWidget {
  const LinkedDevicesScreen({super.key});

  @override
  State<LinkedDevicesScreen> createState() => _LinkedDevicesScreenState();
}

class _LinkedDevicesScreenState extends State<LinkedDevicesScreen> {
  List<Map<String, dynamic>> _devices = [];
  bool _loading = true;
  String? _error;
  int? _removingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService().get('/linked-devices');
      final list = (res['data'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() { _devices = list; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _remove(Map<String, dynamic> device) async {
    final isCurrent = device['is_current'] == true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Device'),
        content: Text(isCurrent
            // Removing the environment you're standing in is allowed (it's
            // a legitimate "stop trusting this handset" action) but it
            // does mean the next sign-in here asks for an OTP again, so
            // say so plainly rather than surprising them later.
            ? 'This is the device you are using right now. Remove it? You will be asked to verify again the next time you sign in from this app.'
            : 'Remove this device? Signing in from it again will require verification.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _removingId = device['id'] as int);
    try {
      final res = await ApiService().delete('/linked-devices/${device['id']}');
      if (!mounted) return;
      setState(() {
        _devices.removeWhere((d) => d['id'] == device['id']);
        _removingId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res['message']?.toString() ?? 'Device removed.'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _removingId = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceAll('Exception: ', '')),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Linked Devices'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _errorState()
                : _devices.isEmpty
                    ? _emptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        itemCount: _devices.length + 1,
                        itemBuilder: (_, i) => i == 0
                            ? _explainer()
                            : _deviceCard(_devices[i - 1], primary),
                      ),
      ),
    );
  }

  Widget _explainer() => const Padding(
        padding: EdgeInsets.only(bottom: 14),
        child: Text(
          'These are the browsers and app installations where your account is '
          'currently trusted. Email and phone sign-in are verified separately '
          'on each one, and the website and this app count as separate '
          'environments even on the same phone.',
          style: TextStyle(fontSize: 12.5, color: Colors.black54, height: 1.4),
        ),
      );

  Widget _deviceCard(Map<String, dynamic> d, Color primary) {
    final isApp     = d['platform'] == 'app';
    final isCurrent = d['is_current'] == true;
    final busy      = _removingId == d['id'];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isCurrent ? primary : Colors.black12, width: isCurrent ? 1.4 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(
              d['device_type'] == 'mobile'
                  ? Icons.smartphone
                  : d['device_type'] == 'tablet'
                      ? Icons.tablet_mac
                      : Icons.laptop_mac,
              color: Colors.black45,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(
                      d['device_name']?.toString() ?? 'Unknown device',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isCurrent) ...[
                    const SizedBox(width: 6),
                    _pill('This device', primary, filled: true),
                  ],
                ]),
                const SizedBox(height: 5),
                // The platform badge, front and centre - see the class doc
                // comment for why the same handset can appear twice.
                _pill(
                  d['platform_label']?.toString() ?? (isApp ? 'Company App' : 'Website / Browser'),
                  isApp ? Colors.indigo : Colors.blueGrey,
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    'ID ${d['device_ref'] ?? '—'}',
                    if (d['last_active_human'] != null) 'Last active ${d['last_active_human']}',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 11.5, color: Colors.black45),
                ),
              ]),
            ),
            busy
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _remove(d),
                  ),
          ]),
          const SizedBox(height: 10),
          // Two independent statuses, never collapsed into one "verified"
          // flag - that independence is the requirement's core rule.
          Wrap(spacing: 8, runSpacing: 6, children: [
            _statusChip(Icons.mail_outline, 'Email', d['email_verified'] == true),
            _statusChip(Icons.phone_iphone, 'Phone', d['phone_verified'] == true),
          ]),
        ]),
      ),
    );
  }

  Widget _statusChip(IconData icon, String label, bool verified) {
    final color = verified ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color.shade800),
        const SizedBox(width: 5),
        Text(
          verified ? '$label verified' : '$label not verified',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color.shade800),
        ),
      ]),
    );
  }

  Widget _pill(String text, Color color, {bool filled = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: filled ? color : color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: filled ? Colors.white : color,
          ),
        ),
      );

  Widget _emptyState() => ListView(
        padding: const EdgeInsets.all(32),
        children: const [
          SizedBox(height: 80),
          Icon(Icons.devices_other, size: 56, color: Colors.black26),
          SizedBox(height: 12),
          Text('No trusted devices recorded yet.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
        ],
      );

  Widget _errorState() => ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 80),
          const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 16),
          Center(child: OutlinedButton(onPressed: _load, child: const Text('Retry'))),
        ],
      );
}
