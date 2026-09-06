import 'package:flutter/material.dart';
import '../services/auth_service.dart';

import '../services/language_service.dart';
/// Horizontal "All My Flats / Flat A / Flat B" chip selector.
/// Renders nothing (zero height) when the resident has 0 or 1 flats,
/// so it's safe to drop into any screen unconditionally.
class FlatFilterBar extends StatefulWidget {
  final int? selectedFlatId; // null = merged / all flats
  final ValueChanged<int?> onChanged;

  const FlatFilterBar({super.key, required this.selectedFlatId, required this.onChanged});

  @override
  State<FlatFilterBar> createState() => _FlatFilterBarState();
}

class _FlatFilterBarState extends State<FlatFilterBar> {
  List<Map<String, dynamic>> _flats = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = await AuthService().getUser();
    final flats = (user?['flats'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (mounted) setState(() { _flats = flats; _loaded = true; });
  }

  String _label(Map<String, dynamic> f) {
    final number = f['flat_number']?.toString() ?? '';
    final tower = f['tower'];
    return tower != null ? '$number ($tower)' : number;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _flats.length <= 1) return const SizedBox.shrink();

    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(LanguageService.t('all_my_flats')),
              selected: widget.selectedFlatId == null,
              onSelected: (_) => widget.onChanged(null),
            ),
          ),
          for (final f in _flats)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(_label(f)),
                selected: widget.selectedFlatId == f['id'],
                onSelected: (_) => widget.onChanged(f['id'] as int),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small badge used inline on list rows (bills/complaints/visitors) to show
/// which flat that row belongs to, for residents with more than one flat.
class FlatTag extends StatelessWidget {
  final String? flatNumber;
  const FlatTag({super.key, this.flatNumber});

  @override
  Widget build(BuildContext context) {
    if (flatNumber == null || flatNumber!.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(flatNumber!, style: const TextStyle(fontSize: 11, color: Colors.black87)),
    );
  }
}
