import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../services/branding_service.dart';
import '../../widgets/ams_dialog.dart';
import '../../widgets/app_form_field.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/empty_state.dart';
import '../../utils/type_helpers.dart';
import '../../services/language_service.dart';
import '../../services/drawer_state.dart';

class AdminReportsFinancialScreen extends StatefulWidget {
  const AdminReportsFinancialScreen({super.key});
  @override
  State<AdminReportsFinancialScreen> createState() => _State();
}

class _State extends State<AdminReportsFinancialScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  final _now = DateTime.now();
  late int _month, _year;

  // 'month' (existing behaviour) or 'all_time' (since inception).
  String _periodMode = 'month';
  int? _residentId;
  String? _residentName;
  int? _flatId;
  String? _flatNumber;

  // Pending-dues pagination, used only when the API returns summary_only.
  int _pendingPage = 1;
  List _pendingItems = [];

  @override
  void initState() {
    super.initState();
    _month = _now.month; _year = _now.year;
    _load();
  }

  bool get _hasFilter => _residentId != null || _flatId != null;

  String _buildQuery({int page = 1}) {
    final params = <String, String>{'period': _periodMode, 'page': '$page'};
    if (_periodMode == 'month') { params['month'] = '$_month'; params['year'] = '$_year'; }
    if (_residentId != null) params['resident_id'] = '$_residentId';
    if (_flatId != null) params['flat_id'] = '$_flatId';
    return params.entries.map((e) => '${e.key}=${e.value}').join('&');
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; _pendingPage = 1; _pendingItems = []; });
    try {
      final res = await ApiService().get('/admin/reports/financial?${_buildQuery()}');
      final data = (res['data'] as Map?)?.cast<String,dynamic>();
      setState(() {
        _data = data;
        _pendingItems = (data?['pending_bills'] as List? ?? []);
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString().replaceAll('Exception: ',''); _loading = false; });
    }
  }

  Future<void> _loadMorePending() async {
    if (_data?['summary_only'] != true) return;
    final total = (_data?['pending_total'] as num?)?.toInt() ?? 0;
    if (_pendingItems.length >= total) return;
    setState(() => _loadingMore = true);
    try {
      final res = await ApiService().get('/admin/reports/financial?${_buildQuery(page: _pendingPage + 1)}');
      final data = (res['data'] as Map?)?.cast<String,dynamic>();
      setState(() {
        _pendingPage += 1;
        _pendingItems = [..._pendingItems, ...(data?['pending_bills'] as List? ?? [])];
        _loadingMore = false;
      });
    } catch (e) {
      setState(() => _loadingMore = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _pickFilter() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.home_outlined), title: Text(LanguageService.t('search_by_flat')), onTap: () => Navigator.pop(ctx, 'flat')),
          ListTile(leading: const Icon(Icons.person_outline), title: Text(LanguageService.t('search_by_resident')), onTap: () => Navigator.pop(ctx, 'resident')),
          if (_hasFilter)
            ListTile(leading: const Icon(Icons.clear), title: Text(LanguageService.t('clear_filter')), onTap: () => Navigator.pop(ctx, 'clear')),
        ]),
      ),
    );
    if (choice == null) return;
    if (choice == 'clear') {
      setState(() { _residentId = null; _residentName = null; _flatId = null; _flatNumber = null; });
      _load();
      return;
    }
    if (choice == 'flat') {
      final picked = await _searchPicker(endpoint: '/admin/flats', labelKey: 'flat_number', title: LanguageService.t('select_flat'));
      if (picked != null) {
        setState(() { _flatId = picked['id'] as int; _flatNumber = picked['flat_number']?.toString(); _residentId = null; _residentName = null; });
        _load();
      }
    } else {
      final picked = await _searchPicker(endpoint: '/admin/residents', labelKey: 'name', title: LanguageService.t('select_resident_2'));
      if (picked != null) {
        setState(() { _residentId = picked['id'] as int; _residentName = picked['name']?.toString(); _flatId = null; _flatNumber = null; });
        _load();
      }
    }
  }

  Future<Map<String, dynamic>?> _searchPicker({required String endpoint, required String labelKey, required String title}) async {
    // /admin/flats returns a full plain list; /admin/residents is paginated
    // (20/page) but supports ?search= - so residents are searched live
    // server-side instead of trying to page through everything client-side.
    final paginated = endpoint == '/admin/residents';

    List<Map<String, dynamic>> flatAll = [];
    if (!paginated) {
      try {
        final res = await ApiService().get(endpoint);
        flatAll = ((res['data'] as List?) ?? []).cast<Map<String, dynamic>>();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
        return null;
      }
    }
    if (!mounted) return null;

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        var query = '';
        List<Map<String, dynamic>> results = paginated ? [] : flatAll;
        bool searching = false;
        Timer? debounce;
        return StatefulBuilder(builder: (ctx, setSt) {
          Future<void> runSearch(String q) async {
            if (!paginated) {
              setSt(() => results = flatAll.where((f) => (f[labelKey]?.toString() ?? '').toLowerCase().contains(q.toLowerCase())).toList());
              return;
            }
            setSt(() => searching = true);
            try {
              final res = await ApiService().get('$endpoint?search=${Uri.encodeQueryComponent(q)}');
              final page = (res['data'] as Map?)?.cast<String, dynamic>();
              setSt(() {
                results = ((page?['data'] as List?) ?? []).cast<Map<String, dynamic>>();
                searching = false;
              });
            } catch (_) {
              setSt(() => searching = false);
            }
          }
          if (paginated && query.isEmpty && results.isEmpty && !searching) {
            // First open: show the first page (most recently added residents).
            runSearch('');
          }
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            content: SizedBox(width: double.maxFinite, height: 400, child: Column(children: [
              AppFieldShell(
                accent: BrandingService.primary,
                child: TextField(
                  decoration: appFieldDecoration(label: '', hint: 'Search…', icon: Icons.search, accent: BrandingService.primary),
                  onChanged: (v) {
                    query = v;
                    debounce?.cancel();
                    debounce = Timer(const Duration(milliseconds: 350), () => runSearch(v));
                  },
                ),
              ),
              const SizedBox(height: 10),
              if (searching) LinearProgressIndicator(color: BrandingService.primary, minHeight: 2),
              Expanded(child: ListView.builder(
                itemCount: results.length,
                itemBuilder: (ctx, i) => ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  title: Text(results[i][labelKey]?.toString() ?? '—'),
                  onTap: () => Navigator.pop(ctx, results[i]),
                ),
              )),
            ])),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(LanguageService.t('cancel')))],
          );
        });
      },
    );
  }

  Future<void> _editOpeningBalance() async {
    final result = await AmsDialog.promptText(
      context,
      title: LanguageService.t('set_opening_balance'),
      message: LanguageService.t('if_you_re_starting_to_use_this_app_partway_th'),
      label: LanguageService.t('opening_balance'),
      icon: Icons.account_balance_wallet_outlined,
      initialValue: (_data?['opening_balance'] ?? 0).toString(),
      confirmText: LanguageService.t('save'),
      cancelText: LanguageService.t('cancel'),
      maxLines: 1,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
    );
    if (result == null || result.isEmpty) return;
    final value = double.tryParse(result);
    if (value == null || value < 0) return;
    try {
      await ApiService().post('/admin/reports/opening-balance', {'opening_balance': value});
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = BrandingService.primary;
    final sym     = BrandingService.currencySymbol;
    final months  = ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(LanguageService.t('financial_report')),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      drawer: const AppDrawer(),
      onDrawerChanged: DrawerVisibility.onChanged,
      body: Column(children: [
        // Period selector
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(children: [
            Row(children: [
              Expanded(child: SegmentedButton<String>(
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: primary,
                  selectedForegroundColor: Colors.white,
                  side: BorderSide(color: primary.withOpacity(0.3)),
                ),
                segments: [
                  ButtonSegment(value: 'month', label: Text(LanguageService.t('this_month')), icon: Icon(Icons.calendar_month, size: 16)),
                  ButtonSegment(value: 'all_time', label: Text(LanguageService.t('all_time')), icon: Icon(Icons.all_inclusive, size: 16)),
                ],
                selected: {_periodMode},
                onSelectionChanged: (s) { setState(() => _periodMode = s.first); _load(); },
              )),
            ]),
            if (_periodMode == 'month') ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: AppFieldShell(accent: primary, child: DropdownButtonFormField<int>(
                  value: _month,
                  decoration: appFieldDecoration(label: LanguageService.t('month'), icon: Icons.calendar_today_rounded, accent: primary),
                  items: List.generate(12, (i) => DropdownMenuItem(value: i+1, child: Text(months[i+1]))),
                  onChanged: (v) { setState(() => _month = v!); _load(); },
                ))),
                const SizedBox(width: 12),
                Expanded(child: AppFieldShell(accent: primary, child: DropdownButtonFormField<int>(
                  value: _year,
                  decoration: appFieldDecoration(label: LanguageService.t('year'), icon: Icons.event_outlined, accent: primary),
                  items: List.generate(5, (i) => DropdownMenuItem(value: _now.year - 2 + i, child: Text('${_now.year - 2 + i}'))),
                  onChanged: (v) { setState(() => _year = v!); _load(); },
                ))),
              ]),
            ],
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: ActionChip(
                avatar: Icon(_hasFilter ? Icons.filter_alt : Icons.filter_alt_outlined, size: 18, color: _hasFilter ? Colors.white : primary),
                label: Text(
                  _flatId != null ? 'Flat: ${_flatNumber ?? _flatId}' : (_residentId != null ? 'Resident: ${_residentName ?? _residentId}' : 'Search Flat / Resident'),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _hasFilter ? Colors.white : null),
                ),
                backgroundColor: _hasFilter ? primary : null,
                onPressed: _pickFilter,
              )),
              if (_hasFilter) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: LanguageService.t('clear_filter_2'),
                  onPressed: () { setState(() { _residentId = null; _residentName = null; _flatId = null; _flatNumber = null; }); _load(); },
                ),
              ],
            ]),
          ]),
        ),
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(icon: const Icon(Icons.refresh), label: Text(LanguageService.t('retry')), onPressed: _load),
                ]))
              : _data == null
                  ? Center(child: Text(LanguageService.t('no_data_2'), style: TextStyle(color: Colors.grey)))
                  : Builder(builder: (context) {
                      final summaryOnly = _data!['summary_only'] == true;
                      final hasFilter = _data!['has_filter'] == true;
                      final headerTitle = _periodMode == 'all_time'
                          ? 'All Time Report'
                          : '${months[_month]} $_year Report';
                      final billed     = ((_data!['total_billed'] as num?) ?? 0).toDouble();
                      final collected  = ((_data!['total_collected'] as num?) ?? 0).toDouble();
                      final outstanding= ((_data!['total_outstanding'] as num?) ?? 0).toDouble();
                      final expenses   = ((_data!['total_expenses'] as num?) ?? 0).toDouble();
                      final otherIncome= ((_data!['total_other_income'] as num?) ?? 0).toDouble();
                      final collectionRate = (collected + outstanding) > 0 ? (collected / (collected + outstanding) * 100) : 0.0;
                      return RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(padding: const EdgeInsets.all(16), children: [
                        Row(children: [
                          Expanded(child: Text(headerTitle,
                              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: 0.1))),
                          if (hasFilter)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: primary.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                              child: Text(LanguageService.t('filtered'), style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.w700)),
                            ),
                        ]),
                        if (summaryOnly) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: Colors.blue.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                            child: Row(children: [
                              const Icon(Icons.info_outline, size: 16, color: Colors.blueGrey),
                              const SizedBox(width: 8),
                              Expanded(child: Text(
                                LanguageService.t('condensed_all_time_summary_search_a_flat_or'),
                                style: TextStyle(fontSize: 11.5, color: Colors.blueGrey.shade700),
                              )),
                            ]),
                          ),
                        ],
                        const SizedBox(height: 14),
                        // Hero: fund balance
                        if (!hasFilter) ...[
                          _FundBalanceHero(
                            sym: sym,
                            primary: primary,
                            balance: ((_data!['fund_balance'] as num?) ?? 0).toDouble(),
                            opening: ((_data!['opening_balance'] as num?) ?? 0).toDouble(),
                            fmt: _fmt,
                            onEdit: _editOpeningBalance,
                          ),
                          const SizedBox(height: 12),
                          _VisibilityCard(
                            value: toBool(_data!['resident_financial_visibility'], defaultValue: true),
                            onChanged: (v) async {
                              try {
                                await ApiService().post('/admin/reports/opening-balance', {
                                  'opening_balance': _data!['opening_balance'],
                                  'resident_financial_visibility': v,
                                });
                                _load();
                              } catch (e) {
                                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red));
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                        ],
                        // Summary — donut + key figures (hidden in condensed all-time summary)
                        if (!summaryOnly) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(LanguageService.t('collection_overview'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.grey.shade800)),
                              const SizedBox(height: 14),
                              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                                _DonutChart(
                                  size: 108,
                                  strokeWidth: 14,
                                  segments: [
                                    _DonutSegment(collected, const Color(0xFF22A55A)),
                                    _DonutSegment(outstanding, const Color(0xFFF0932B)),
                                  ],
                                  centerLabel: '${collectionRate.toStringAsFixed(0)}%',
                                  centerSubLabel: 'collected',
                                ),
                                const SizedBox(width: 18),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  _LegendRow(color: const Color(0xFF2563EB), label: LanguageService.t('billed'), value: '$sym${_fmt(billed)}'),
                                  const SizedBox(height: 10),
                                  _LegendRow(color: const Color(0xFF22A55A), label: LanguageService.t('collected'), value: '$sym${_fmt(collected)}'),
                                  const SizedBox(height: 10),
                                  _LegendRow(color: const Color(0xFFF0932B), label: LanguageService.t('outstanding'), value: '$sym${_fmt(outstanding)}'),
                                  if (!hasFilter && otherIncome > 0) ...[
                                    const SizedBox(height: 10),
                                    _LegendRow(color: const Color(0xFF16A085), label: LanguageService.t('other_income'), value: '$sym${_fmt(otherIncome)}'),
                                  ],
                                  if (!hasFilter) ...[
                                    const SizedBox(height: 10),
                                    _LegendRow(color: const Color(0xFFE84C3D), label: LanguageService.t('expenses'), value: '$sym${_fmt(expenses)}'),
                                  ],
                                ])),
                              ]),
                            ]),
                          ),
                          const SizedBox(height: 14),
                          Row(children: [
                            Expanded(child: _StatCard('Bills Raised', '${_data!['total_bills'] ?? 0}', primary, Icons.receipt_long_rounded)),
                            const SizedBox(width: 10),
                            Expanded(child: _StatCard('Bills Paid', '${_data!['paid_bills'] ?? 0}', const Color(0xFF16A085), Icons.task_alt_rounded)),
                          ]),
                        if (((_data!['one_time_collected'] as num?) ?? 0) > 0 ||
                            ((_data!['one_time_pending'] as num?) ?? 0) > 0) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
                            child: Row(children: [
                              const Icon(Icons.bolt_rounded, size: 15, color: Colors.indigo),
                              const SizedBox(width: 6),
                              Expanded(child: Text(
                                'incl. $sym${_fmt(_data!['one_time_collected'])} one-time collected'
                                '${((_data!['one_time_pending'] as num?) ?? 0) > 0 ? " · $sym${_fmt(_data!['one_time_pending'])} one-time pending" : ""}',
                                style: TextStyle(fontSize: 11, color: Colors.indigo.shade700, fontWeight: FontWeight.w600),
                              )),
                            ]),
                          ),
                        ],
                        const SizedBox(height: 20),
                        // Collection breakdown
                        if ((_data!['by_method'] as Map?)?.isNotEmpty == true) ...[
                          _SectionHeader(icon: Icons.pie_chart_rounded, color: Colors.teal, title: LanguageService.t('by_payment_method')),
                          const SizedBox(height: 10),
                          _MethodBreakdownCard(byMethod: (_data!['by_method'] as Map), sym: sym, fmt: _fmt),
                        ],
                        const SizedBox(height: 8),
                        ], // end if (!summaryOnly) grid + by_method + income
                        const SizedBox(height: 8),
                        if (!summaryOnly) ...[
                          _SectionHeader(icon: Icons.arrow_downward_rounded, color: Colors.green, title: LanguageService.t('income_payments_received')),
                          const SizedBox(height: 10),
                          _DetailSection(
                            sym: sym,
                            title: LanguageService.t('income_payments_received'), color: Colors.green,
                            icon: Icons.arrow_downward_rounded,
                            items: (_data!['payments'] as List? ?? []),
                            emptyText: 'No payments in this period.',
                            hideHeader: true,
                            rowBuilder: (item, sym) => _DetailRow(
                              title: item['resident'] ?? '—',
                              subtitle: '${item['type'] == 'one_time' ? LanguageService.t('one_time') : LanguageService.t('maintenance')} · ${item['bill_number'] ?? ''}'
                                  '${item['flat'] != null ? ' · Flat ${item['flat']}' : ''}'
                                  ' · ${(item['method'] ?? '').toString().toUpperCase()} · ${item['paid_at'] ?? ''}',
                              amount: '$sym${_fmt(item['amount'])}',
                              amountColor: Colors.green,
                              isOneTime: item['type'] == 'one_time',
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        // Pending / Outstanding — always shown per the "gross amount in
                        // hand, outstanding, pending" ask, paginated when summaryOnly.
                        _SectionHeader(icon: Icons.hourglass_top_rounded, color: Colors.orange, title: LanguageService.t('pending_outstanding')),
                        const SizedBox(height: 10),
                        if (summaryOnly)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Total Pending: $sym${_fmt(_data!['total_outstanding'])}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                        _DetailSection(
                          sym: sym,
                          title: LanguageService.t('pending_outstanding'), color: Colors.orange,
                          icon: Icons.hourglass_top_rounded,
                          items: _pendingItems,
                          emptyText: 'No pending dues.',
                          initiallyExpanded: summaryOnly,
                          hideHeader: true,
                          countOverride: summaryOnly ? (_data!['pending_total'] as num?)?.toInt() : null,
                          rowBuilder: (item, sym) => _DetailRow(
                            title: item['resident'] ?? '—',
                            subtitle: '${item['type'] == 'one_time' ? LanguageService.t('one_time') : LanguageService.t('maintenance')} · ${item['bill_number'] ?? ''}'
                                ' · Flat ${item['flat'] ?? '—'} · Due ${item['due_date'] != null ? BrandingService.formatDateString(item['due_date'].toString()) : ''}'
                                '${item['rejected'] == true ? ' (claim rejected)' : ''}'
                                '${(item['description'] != null && item['description'].toString().trim().isNotEmpty) ? '\n${item['description']}' : ''}',
                            amount: '$sym${_fmt(item['outstanding'])}',
                            amountColor: Colors.orange,
                            isOneTime: item['type'] == 'one_time',
                          ),
                        ),
                        if (summaryOnly && _pendingItems.length < ((_data!['pending_total'] as num?)?.toInt() ?? 0)) ...[
                          const SizedBox(height: 8),
                          Center(child: _loadingMore
                              ? const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())
                              : OutlinedButton.icon(
                                  icon: const Icon(Icons.expand_more),
                                  label: Text('Load more (${_pendingItems.length} of ${_data!['pending_total']})'),
                                  onPressed: _loadMorePending,
                                )),
                        ],
                        if (!hasFilter && !summaryOnly) ...[
                        const SizedBox(height: 16),
                        _SectionHeader(icon: Icons.arrow_downward_rounded, color: const Color(0xFF16A085), title: LanguageService.t('other_income')),
                        const SizedBox(height: 10),
                        _DetailSection(
                          sym: sym,
                          title: LanguageService.t('other_income'), color: const Color(0xFF16A085),
                          icon: Icons.arrow_downward_rounded,
                          items: (_data!['other_income_items'] as List? ?? []),
                          emptyText: 'No other income in this period.',
                          hideHeader: true,
                          rowBuilder: (item, sym) => _DetailRow(
                            title: item['title'] ?? '—',
                            subtitle: '${item['category'] ?? '—'} · ${item['payer'] ?? '—'} · ${item['date'] != null ? BrandingService.formatDateString(item['date'].toString()) : ''}',
                            amount: '$sym${_fmt(item['amount'])}',
                            amountColor: const Color(0xFF16A085),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _SectionHeader(icon: Icons.arrow_upward_rounded, color: Colors.red, title: LanguageService.t('expenses')),
                        const SizedBox(height: 10),
                        _DetailSection(
                          sym: sym,
                          title: LanguageService.t('expenses'), color: Colors.red,
                          icon: Icons.arrow_upward_rounded,
                          items: (_data!['expense_items'] as List? ?? []),
                          emptyText: 'No expenses in this period.',
                          hideHeader: true,
                          rowBuilder: (item, sym) => _DetailRow(
                            title: item['title'] ?? '—',
                            subtitle: '${item['category'] ?? '—'} · ${item['vendor'] ?? '—'} · ${item['date'] != null ? BrandingService.formatDateString(item['date'].toString()) : ''}',
                            amount: '$sym${_fmt(item['amount'])}',
                            amountColor: Colors.red,
                          ),
                        ),
                        ],
                      ]),
                    );
                    })),
      ]),
    );
  }

  String _fmt(dynamic v) {
    if (v == null) return '0';
    final d = double.tryParse(v.toString()) ?? 0;
    if (d >= 100000) return '${(d/100000).toStringAsFixed(1)}L';
    if (d >= 1000)   return '${(d/1000).toStringAsFixed(1)}K';
    return d.toStringAsFixed(0);
  }
}
class _FundBalanceHero extends StatelessWidget {
  final String sym;
  final Color primary;
  final double balance, opening;
  final String Function(dynamic) fmt;
  final VoidCallback onEdit;
  const _FundBalanceHero({
    required this.sym, required this.primary, required this.balance,
    required this.opening, required this.fmt, required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final positive = balance >= 0;
    final gradient = positive
        ? [const Color(0xFF1E3A8A), const Color(0xFF2563EB)]
        : [const Color(0xFF7F1D1D), const Color(0xFFDC2626)];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [BoxShadow(color: gradient[1].withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Stack(children: [
        Positioned(
          right: -18, top: -30,
          child: Icon(Icons.account_balance_wallet_rounded, size: 130, color: Colors.white.withOpacity(0.08)),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(LanguageService.t('current_fund_balance'),
                style: TextStyle(fontSize: 12.5, color: Colors.white.withOpacity(0.85), fontWeight: FontWeight.w600)),
            const Spacer(),
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onEdit,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
                child: const Icon(Icons.edit_outlined, size: 15, color: Colors.white),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text('$sym${fmt(balance)}',
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.2)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.14), borderRadius: BorderRadius.circular(20)),
            child: Text('Opening balance: $sym${fmt(opening)}',
                style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.w600)),
          ),
        ]),
      ]),
    );
  }
}

class _VisibilityCard extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _VisibilityCard({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3))],
    ),
    child: Material(
      // SwitchListTile paints its background/ink splashes on the nearest
      // Material ancestor - without this, the outer Container's own
      // DecoratedBox (needed for the white rounded card + shadow look)
      // intercepts that paint and Flutter throws "background color or ink
      // splashes may be invisible" at runtime.
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: SwitchListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.blueGrey.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.visibility_outlined, color: Colors.blueGrey, size: 20),
        ),
        title: Text(LanguageService.t('resident_financial_visibility'), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
        subtitle: Text(LanguageService.t('let_residents_see_fund_balance_expenses_and_p'), style: const TextStyle(fontSize: 11.5)),
        value: value,
        onChanged: onChanged,
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  const _SectionHeader({required this.icon, required this.color, required this.title});

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(9)),
      child: Icon(icon, size: 16, color: color),
    ),
    const SizedBox(width: 8),
    Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
  ]);
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label, value;
  const _LegendRow({required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 8),
    Expanded(child: Text(label, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, fontWeight: FontWeight.w600))),
    Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
  ]);
}

class _DonutSegment {
  final double value;
  final Color color;
  const _DonutSegment(this.value, this.color);
}

/// Lightweight donut chart built with CustomPainter — no external chart
/// package required. Renders each segment proportionally to its value with
/// a soft rounded-cap stroke, and a label in the centre.
class _DonutChart extends StatelessWidget {
  final double size, strokeWidth;
  final List<_DonutSegment> segments;
  final String centerLabel, centerSubLabel;
  const _DonutChart({
    required this.size, required this.strokeWidth, required this.segments,
    required this.centerLabel, required this.centerSubLabel,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size, height: size,
    child: Stack(alignment: Alignment.center, children: [
      CustomPaint(size: Size(size, size), painter: _DonutPainter(segments, strokeWidth)),
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text(centerLabel, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        Text(centerSubLabel, style: TextStyle(fontSize: 9.5, color: Colors.grey.shade600)),
      ]),
    ]),
  );
}

class _DonutPainter extends CustomPainter {
  final List<_DonutSegment> segments;
  final double strokeWidth;
  _DonutPainter(this.segments, this.strokeWidth);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final total = segments.fold<double>(0, (a, b) => a + b.value);

    final track = Paint()
      ..color = Colors.grey.withOpacity(0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    if (total <= 0) return;

    double start = -math.pi / 2;
    for (final seg in segments) {
      if (seg.value <= 0) continue;
      final sweep = (seg.value / total) * 2 * math.pi;
      final paint = Paint()
        ..color = seg.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), start, sweep * 0.985, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.segments != segments || oldDelegate.strokeWidth != strokeWidth;
}

/// Horizontal proportional bars for the "by payment method" breakdown —
/// gives an at-a-glance visual comparison instead of a plain list.
class _MethodBreakdownCard extends StatelessWidget {
  final Map byMethod;
  final String sym;
  final String Function(dynamic) fmt;
  const _MethodBreakdownCard({required this.byMethod, required this.sym, required this.fmt});

  static const _palette = [
    Color(0xFF16A085), Color(0xFF2563EB), Color(0xFFE8A010),
    Color(0xFF8E44AD), Color(0xFFE84C3D), Color(0xFF34495E),
  ];

  static const _icons = {
    'cash': Icons.payments_outlined,
    'card': Icons.credit_card_outlined,
    'upi': Icons.qr_code_scanner_rounded,
    'bank_transfer': Icons.account_balance_outlined,
    'cheque': Icons.receipt_long_outlined,
    'online': Icons.language_rounded,
    'wallet': Icons.account_balance_wallet_outlined,
  };

  @override
  Widget build(BuildContext context) {
    double _num(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;
    final entries = byMethod.entries.toList()
      ..sort((a, b) => _num(b.value).compareTo(_num(a.value)));
    final total = entries.fold<double>(0, (a, e) => a + _num(e.value));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(children: [
        for (int i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          Builder(builder: (_) {
            final e = entries[i];
            final key = e.key.toString();
            final val = _num(e.value);
            final pct = total > 0 ? val / total : 0.0;
            final color = _palette[i % _palette.length];
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(_icons[key] ?? Icons.payment_outlined, size: 15, color: color),
                const SizedBox(width: 7),
                Expanded(child: Text(key.replaceAll('_', ' ').toUpperCase(),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                Text('$sym${fmt(val)}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color)),
                const SizedBox(width: 6),
                Text('${(pct * 100).toStringAsFixed(0)}%', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: pct.clamp(0.0, 1.0).toDouble(),
                  minHeight: 7,
                  backgroundColor: color.withOpacity(0.1),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ]);
          }),
        ],
      ]),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title, sym, emptyText;
  final Color color;
  final IconData icon;
  final List items;
  final Widget Function(Map item, String sym) rowBuilder;
  final bool initiallyExpanded;
  final int? countOverride;
  final bool hideHeader;
  const _DetailSection({
    required this.title, required this.sym, required this.color, required this.icon,
    required this.items, required this.emptyText, required this.rowBuilder,
    this.initiallyExpanded = false, this.countOverride, this.hideHeader = false,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          leading: hideHeader
              ? null
              : Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(9)),
                  child: Icon(icon, size: 16, color: color),
                ),
          title: hideHeader
              ? Text('${countOverride ?? items.length} record(s)', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600))
              : Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          subtitle: hideHeader ? null : Text('${countOverride ?? items.length} record(s)', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          children: items.isEmpty
              ? [Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: EmptyState(icon: icon, title: emptyText, color: color),
                )]
              : items.map((raw) => rowBuilder((raw as Map).cast<String, dynamic>(), sym)).toList(),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String title, subtitle, amount;
  final Color amountColor;
  final bool isOneTime;
  const _DetailRow({
    required this.title, required this.subtitle, required this.amount, required this.amountColor,
    this.isOneTime = false,
  });
  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    title: Row(children: [
      Flexible(child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
      if (isOneTime) ...[
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.blue.withOpacity(0.3))),
          child: Text(LanguageService.t('one_time'), style: TextStyle(fontSize: 9, color: Colors.blue, fontWeight: FontWeight.w600)),
        ),
      ],
    ]),
    subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
    trailing: Text(amount, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: amountColor)),
  );
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final Color color;
  final IconData icon;
  const _StatCard(this.label, this.value, this.color, [this.icon = Icons.insights_rounded]);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3))],
    ),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(11)),
        child: Icon(icon, size: 18, color: color),
      ),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
      ])),
    ]),
  );
}
