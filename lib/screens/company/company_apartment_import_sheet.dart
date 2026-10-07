import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../widgets/app_form_field.dart';
import '../../widgets/form_sheet.dart';

/// Company Admin > Apartments > "Import Data (CSV)".
///
/// Bulk-adds an apartment's Towers, Floors, Flats and Residents from one CSV
/// (one row per flat). Same feature, rules and result as the website's
/// Apartments > Import Data (CSV) - both call the backend's
/// ApartmentDataImportService (POST /company/apartments/{id}/import).
///
/// Flow: download the demo CSV -> fill it in -> pick the apartment -> pick
/// the file -> "Validate only" (default, saves nothing) or import for real.
/// If any row is wrong NOTHING is saved and every problem is listed with its
/// CSV row number so the file can be fixed and uploaded again.
class ApartmentImportSheet extends StatefulWidget {
  /// Rows of GET /company/apartments (needs id, name, apartment_type).
  final List apartments;
  final int? initialApartmentId;

  /// Called after a REAL (not validate-only) import succeeds, so the
  /// apartments list can refresh its flat / resident / tower counts.
  final VoidCallback onImported;

  const ApartmentImportSheet({
    super.key,
    required this.apartments,
    required this.onImported,
    this.initialApartmentId,
  });

  @override
  State<ApartmentImportSheet> createState() => _ApartmentImportSheetState();
}

class _ApartmentImportSheetState extends State<ApartmentImportSheet> {
  int? _aptId;
  Uint8List? _bytes;
  String? _fileName;
  bool _validateOnly = true;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _report;

  @override
  void initState() {
    super.initState();
    _aptId = widget.initialApartmentId;
  }

  Map? get _selectedApartment {
    for (final a in widget.apartments) {
      if (a is Map && a['id'] == _aptId) return a;
    }
    return null;
  }

  Future<void> _openDemo(String type) async {
    final url = '${ApiService.baseUrl}/import-templates/apartment-data?type=$type';
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) setState(() => _error = 'Could not open the download link.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open the download link.');
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final f = result.files.single;
      if (f.bytes == null) {
        setState(() => _error = 'Could not read the selected file. Please try again.');
        return;
      }
      setState(() {
        _bytes = f.bytes;
        _fileName = f.name;
        _error = null;
        _report = null;
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _submit() async {
    if (_aptId == null) {
      setState(() => _error = 'Please choose the apartment to import into.');
      return;
    }
    if (_bytes == null) {
      setState(() => _error = 'Please choose a CSV file first.');
      return;
    }
    setState(() { _busy = true; _error = null; _report = null; });
    try {
      final res = await ApiService().uploadMultipartBytes(
        '/company/apartments/$_aptId/import',
        {'dry_run': _validateOnly ? '1' : '0'},
        bytes: _bytes!,
        filename: _fileName ?? 'import.csv',
      );
      final data = Map<String, dynamic>.from(res['data'] as Map);
      setState(() { _report = data; _busy = false; });
      if (data['ok'] == true && data['dry_run'] != true) widget.onImported();
    } on ApiValidationException catch (e) {
      setState(() { _busy = false; _error = e.message; });
    } catch (e) {
      setState(() { _busy = false; _error = e.toString().replaceAll('Exception: ', ''); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;
    final apt = _selectedApartment;
    final aptWithTower = apt == null ? null : apt['apartment_type'] != 'without_tower';

    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.upload_file, color: primary),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Import Apartment Data (CSV)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 8),
          Text(
            "Add an apartment's Towers, Floors, Flats and Residents from one CSV file - one row per flat. "
            'Download the demo file, fill in your data, then upload it here.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey[700], height: 1.35),
          ),
          const SizedBox(height: 14),
          FormErrorBanner(message: _error),

          // Step 1 - demo
          const Text('1. Download the demo CSV', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () => _openDemo('with_tower'),
              icon: const Icon(Icons.download, size: 18),
              label: const Text('With towers'),
            ),
            OutlinedButton.icon(
              onPressed: () => _openDemo('without_tower'),
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Without towers'),
            ),
          ]),
          const SizedBox(height: 14),

          // Step 2 - apartment
          const Text('2. Choose the apartment', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          AppFieldShell(
            accent: BrandingService.secondary,
            child: DropdownButtonFormField<int>(
              value: _aptId,
              isExpanded: true,
              items: widget.apartments
                  .whereType<Map>()
                  .map((a) => DropdownMenuItem<int>(
                        value: a['id'] as int,
                        child: Text(
                          '${a['name']} - ${a['apartment_type'] == 'without_tower' ? 'without towers' : 'with towers'}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: (v) => setState(() { _aptId = v; _report = null; }),
              decoration: appFieldDecoration(label: 'Apartment', icon: Icons.apartment, accent: BrandingService.secondary),
            ),
          ),
          if (aptWithTower != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                aptWithTower
                    ? 'This apartment has towers - use the "With towers" file (tower + floor + flat columns).'
                    : 'This apartment has no towers - use the "Without towers" file (leave tower out).',
                style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
              ),
            ),
          const SizedBox(height: 14),

          // Step 3 - file
          const Text('3. Upload the filled CSV', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickFile,
            icon: const Icon(Icons.attach_file, size: 18),
            label: Text(_fileName ?? 'Choose CSV file', overflow: TextOverflow.ellipsis),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
          ),
          CheckboxListTile(
            value: _validateOnly,
            onChanged: _busy ? null : (v) => setState(() => _validateOnly = v ?? true),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            title: const Text('Validate only - check the file and show what would happen, but save nothing',
                style: TextStyle(fontSize: 12.5)),
          ),

          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('How to fill the CSV', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            children: const [
              _HelpLine('tower', 'Only for apartments with towers, e.g. "Tower A" (created automatically). Leave it out otherwise.'),
              _HelpLine('floor', 'Ground Floor, Floor 1, Floor 2 ... (also G / 0 = Ground, 1 = Floor 1). Required for towers.'),
              _HelpLine('flat_number', 'Required, unique in the whole apartment, e.g. A-101.'),
              _HelpLine('resident_name', 'Only if the flat has a resident - leave all resident columns empty for a vacant flat.'),
              _HelpLine('resident_phone', 'Required for India apartments - digits only (format the column as Text in Excel).'),
              _HelpLine('resident_email', 'Required for apartments outside India.'),
              _HelpLine('occupancy_type', 'Owner or Tenant (default Owner).'),
              _HelpLine('move_in_date', 'YYYY-MM-DD or DD/MM/YYYY (default today).'),
              _HelpLine('', 'Same person owning several flats: repeat their name + phone/email on each row. '
                  'Existing towers/floors/flats are re-used, so uploading twice is safe. '
                  'If any row has a problem nothing is imported. Max 2000 rows / 2 MB.'),
            ],
          ),
          const SizedBox(height: 8),

          ElevatedButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(_validateOnly ? Icons.fact_check_outlined : Icons.upload),
            label: Text(_busy ? 'Please wait...' : (_validateOnly ? 'Validate CSV' : 'Import now')),
            style: ElevatedButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
          ),

          if (_report != null) _ReportView(report: _report!),
        ]),
      ),
    );
  }
}

class _HelpLine extends StatelessWidget {
  final String column;
  final String text;
  const _HelpLine(this.column, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text.rich(TextSpan(children: [
          if (column.isNotEmpty)
            TextSpan(text: '$column  ', style: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'monospace', fontSize: 12)),
          TextSpan(text: text, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        ])),
      ),
    );
  }
}

class _ReportView extends StatelessWidget {
  final Map<String, dynamic> report;
  const _ReportView({required this.report});

  static const _labels = <String, String>{
    'towers_created': 'Towers',
    'floors_created': 'Floors',
    'flats_created': 'Flats',
    'flats_existing': 'Flats already existing',
    'flats_vacant': 'Vacant flats (no resident)',
    'residents_created': 'Residents',
    'extra_flats_linked': 'Extra flats linked to a resident',
    'residents_skipped': 'Residents already in flat (skipped)',
  };

  @override
  Widget build(BuildContext context) {
    final ok = report['ok'] == true;
    final dry = report['dry_run'] == true;
    final summary = Map<String, dynamic>.from((report['summary'] as Map?) ?? {});
    final errors = (report['errors'] as List?) ?? const [];
    final warnings = (report['warnings'] as List?) ?? const [];
    final errorCount = (report['error_count'] as num?)?.toInt() ?? errors.length;
    final color = ok ? Colors.green : Colors.red;
    final title = ok ? (dry ? 'Validation passed' : 'Import completed') : 'Import failed';
    final showSummary = ok || summary.values.any((v) => (v as num? ?? 0) > 0);

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(ok ? Icons.check_circle : Icons.cancel, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('$title - ${report['total_rows'] ?? 0} row(s)', style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 4),
        Text('${report['message'] ?? ''}', style: TextStyle(fontSize: 12.5, color: Colors.grey[800])),
        if (showSummary) ...[
          const SizedBox(height: 10),
          for (final e in _labels.entries)
            if (((summary[e.key] as num?) ?? 0) > 0 || e.key == 'flats_created' || e.key == 'residents_created')
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.5),
                child: Row(children: [
                  Expanded(child: Text(
                    (dry && (e.key == 'towers_created' || e.key == 'floors_created' || e.key == 'flats_created' || e.key == 'residents_created'))
                        ? '${e.value} to create'
                        : (e.key.endsWith('_created') ? '${e.value} created' : e.value),
                    style: const TextStyle(fontSize: 12.5),
                  )),
                  Text('${(summary[e.key] as num?) ?? 0}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                ]),
              ),
        ],
        for (final w in warnings)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text('$w', style: TextStyle(fontSize: 12, color: Colors.orange.shade800))),
        if (errors.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            '$errorCount problem(s) found${errorCount > errors.length ? ' (showing the first ${errors.length})' : ''}:',
            style: TextStyle(fontWeight: FontWeight.w700, color: Colors.red.shade700, fontSize: 13),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: errors.length,
              separatorBuilder: (_, __) => const Divider(height: 10),
              itemBuilder: (_, i) {
                final e = Map<String, dynamic>.from(errors[i] as Map);
                final row = (e['row'] as num?)?.toInt() ?? 0;
                final col = '${e['column'] ?? ''}';
                return Text.rich(TextSpan(children: [
                  TextSpan(text: row > 0 ? 'Row $row' : 'File', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                  if (col.isNotEmpty) TextSpan(text: '  [$col]', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  TextSpan(text: '  ${e['message'] ?? ''}', style: const TextStyle(fontSize: 12.5)),
                ]));
              },
            ),
          ),
        ],
      ]),
    );
  }
}
