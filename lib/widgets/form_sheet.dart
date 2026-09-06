import 'package:flutter/material.dart';
import 'app_form_field.dart';

import '../services/language_service.dart';
/// Standard header row for every add/edit bottom-sheet form: icon in a
/// soft colored circle, a title, and — critically — a close (✕) button
/// on the right so the sheet can always be dismissed without submitting.
///
/// Usage:
///   FormSheetHeader(
///     icon: Icons.cell_tower_outlined,
///     title: isEdit ? 'Edit Tower' : 'Add Tower',
///     accent: BrandingService.primary,
///     onClose: () => Navigator.pop(ctx),
///   ),
class FormSheetHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color accent;
  final VoidCallback onClose;

  const FormSheetHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.accent,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: accent.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: LanguageService.t('close'),
          onPressed: onClose,
        ),
      ]),
      // Guarantees breathing room before the first field/banner below,
      // regardless of what each screen puts next - previously every call
      // site had to remember to add its own SizedBox(height: 16) here,
      // and a couple (admin_notices_screen.dart, admin_residents_screen.dart)
      // didn't, so their first field's label ended up crowding the header title.
      const SizedBox(height: 16),
    ]);
  }
}

/// Multi-select grid for "additional flats" (or any other secondary
/// flat/unit picker): rounded, tappable chip-tiles with a check icon,
/// used in place of a plain CheckboxListTile column so the selected
/// state reads clearly and the whole row is tappable (not just the tiny
/// checkbox hit-area).
///
/// Usage (inside a StatefulBuilder(builder: (ctx, setS) => ...)):
///   AdditionalFlatsSelector(
///     flats: _flats,
///     excludeId: selectedFlatId,
///     selectedIds: additionalFlatIds,
///     accent: BrandingService.secondary,
///     emptyLabel: LanguageService.t('no_other_vacant_flats_available'),
///     onToggle: (id) => setS(() =>
///         additionalFlatIds.contains(id) ? additionalFlatIds.remove(id) : additionalFlatIds.add(id)),
///   ),
class AdditionalFlatsSelector extends StatelessWidget {
  final List flats;
  final String? excludeId;
  final Set<String> selectedIds;
  final Color accent;
  final String emptyLabel;
  final ValueChanged<String> onToggle;

  const AdditionalFlatsSelector({
    super.key,
    required this.flats,
    required this.excludeId,
    required this.selectedIds,
    required this.accent,
    required this.emptyLabel,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final options = flats.where((f) => f['id'].toString() != excludeId).toList();

    if (options.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Text(emptyLabel, style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 190),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map<Widget>((f) {
            final id = f['id'].toString();
            final selected = selectedIds.contains(id);
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onToggle(id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: selected ? accent.withOpacity(0.10) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: selected ? accent : Colors.grey.shade300, width: selected ? 1.4 : 1),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(selected ? Icons.check_circle : Icons.circle_outlined,
                      size: 17, color: selected ? accent : Colors.grey[400]),
                  const SizedBox(width: 7),
                  Text(
                    'Flat ${f['flat_number']}${f['ownership_change'] == true ? ' (Ownership Change)' : ''}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? accent : Colors.grey[800],
                    ),
                  ),
                ]),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// A form field, styled exactly like the other text/dropdown fields
/// (icon chip, rounded border, accent focus color), that opens the
/// native time picker on tap instead of asking for manual "HH:mm" entry.
///
/// Usage (inside a StatefulBuilder(builder: (ctx, setS) => ...)):
///   TimeOfDay openTime = TimeOfDay(hour: 6, minute: 0);
///   ...
///   TimeFieldPicker(
///     label: LanguageService.t('open'),
///     icon: Icons.access_time,
///     accent: BrandingService.secondary,
///     time: openTime,
///     onChanged: (t) => setS(() => openTime = t),
///   ),
class TimeFieldPicker extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accent;
  final TimeOfDay time;
  final ValueChanged<TimeOfDay> onChanged;

  const TimeFieldPicker({
    super.key,
    required this.label,
    required this.icon,
    required this.accent,
    required this.time,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppFieldShell(
      accent: accent,
      child: TextField(
        readOnly: true,
        controller: TextEditingController(text: time.format(context)),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        decoration: appFieldDecoration(
          label: label,
          icon: icon,
          accent: accent,
          suffix: Icon(Icons.arrow_drop_down, color: Colors.grey[500]),
        ),
        onTap: () async {
          final picked = await showTimePicker(
            context: context,
            initialTime: time,
            builder: (ctx, child) => Theme(
              data: Theme.of(ctx).copyWith(
                colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: accent),
              ),
              child: child!,
            ),
          );
          if (picked != null) onChanged(picked);
        },
      ),
    );
  }
}

/// Parses a 24-hour "HH:mm" string (as stored/returned by the API) into
/// a [TimeOfDay]. Falls back to [fallback] if the string is missing or
/// malformed.
TimeOfDay parseTimeOfDay(String? value, {TimeOfDay fallback = const TimeOfDay(hour: 6, minute: 0)}) {
  if (value == null || !value.contains(':')) return fallback;
  final parts = value.split(':');
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts.length > 1 ? parts[1] : '');
  if (h == null || m == null) return fallback;
  return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
}

/// Formats a [TimeOfDay] back into the 24-hour "HH:mm" string the API
/// expects (independent of the user's locale/12-hour display format).
String formatTimeOfDay24(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Inline error banner shown INSIDE a form (as opposed to a SnackBar,
/// which renders behind/under a modal bottom sheet and is easy to miss).
/// Renders nothing when [message] is null/empty, so it's safe to place
/// unconditionally near the top of a form and just update the string.
///
/// Usage (inside a StatefulBuilder(builder: (ctx, setS) => ...)):
///   String? formError;
///   ...
///   FormErrorBanner(message: formError),
///   ...
///   onPressed: () async {
///     setS(() => formError = null);
///     if (name.isEmpty) { setS(() => formError = 'Name is required'); return; }
///     try {
///       ...
///     } catch (e) {
///       setS(() => formError = e.toString().replaceAll('Exception: ', ''));
///     }
///   }
class FormErrorBanner extends StatelessWidget {
  final String? message;
  const FormErrorBanner({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    if (message == null || message!.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.error_outline, color: Colors.red.shade600, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(message!, style: TextStyle(color: Colors.red.shade700, fontSize: 13, height: 1.3))),
        ]),
      ),
    );
  }
}
