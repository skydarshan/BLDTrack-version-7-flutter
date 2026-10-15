import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_helpers.dart';
import '../../../core/theme/app_theme.dart';
import '../../app/app_services.dart';
import '../../pms/widgets/media_widgets.dart';
import '../../pms/widgets/pms_widgets.dart';

Future<void> shareDmrDownload(
  BuildContext context, {
  required Future<List<int>> Function() load,
  required String filename,
  required String label,
}) async {
  try {
    final bytes = await load();
    final dir = await getTemporaryDirectory();
    final safe = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File('${dir.path}/$safe');
    await file.writeAsBytes(bytes, flush: true);
    if (!context.mounted) return;
    await Share.shareXFiles([XFile(file.path)], text: label);
  } on ApiException catch (e) {
    if (context.mounted) showPmsSnack(context, e.message, error: true);
  } catch (_) {
    if (context.mounted) showPmsSnack(context, 'Download failed', error: true);
  }
}

Future<void> showDocSubmissionSheet(
  BuildContext context, {
  required String recordId,
  required bool imprest,
  String? existingDate,
  String? existingRemarks,
}) async {
  var date = DateTime.tryParse(existingDate ?? '');
  final remarks = TextEditingController(text: existingRemarks ?? '');
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: StatefulBuilder(
          builder: (context, setSheet) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Document submission',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    const Text('Enter the HO submission date, audit remarks, or both.'),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: date ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setSheet(() => date = picked);
                      },
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                      label: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          date == null ? 'Submission date' : formatDate(date!.toIso8601String()),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: remarks,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Remarks for audit'),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () async {
                        if (date == null && remarks.text.trim().isEmpty) {
                          showPmsSnack(
                            context,
                            'Enter a submission date or audit remarks',
                            error: true,
                          );
                          return;
                        }
                        final entry = <String, dynamic>{
                          'id': recordId,
                          if (date != null) 'date_of_doc_submission_to_ho': date!.toIso8601String(),
                          if (remarks.text.trim().isNotEmpty) 'remarks_for_audit': remarks.text.trim(),
                        };
                        try {
                          final api = context.read<AppServices>().dmr;
                          if (imprest) {
                            await api.imprestDocSubmission({'entries': [entry]});
                          } else {
                            await api.docSubmission({'entries': [entry]});
                          }
                          if (sheetContext.mounted) Navigator.pop(sheetContext, true);
                        } on ApiException catch (e) {
                          if (context.mounted) showPmsSnack(context, e.message, error: true);
                        }
                      },
                      child: const Text('Save submission'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );
  remarks.dispose();
  if (saved == true && context.mounted) {
    showPmsSnack(context, 'Document submission saved');
  }
}

Future<bool> showCreditNoteSheet(
  BuildContext context, {
  required String roNumber,
  required String vendorId,
  required String siteId,
}) async {
  final number = TextEditingController();
  final amount = TextEditingController();
  var date = DateTime.now();
  PendingFile? document;
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: StatefulBuilder(
          builder: (context, setSheet) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Add credit note',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: number,
                      decoration: const InputDecoration(labelText: 'Credit note number *'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setSheet(() => date = picked);
                      },
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                      label: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(formatDate(date.toIso8601String())),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Amount *'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final files = await pickPmsFiles(allowMultiple: false);
                        if (files.isEmpty) return;
                        setSheet(() => document = files.first);
                      },
                      icon: const Icon(Icons.attach_file),
                      label: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(document?.filename ?? 'Attach document *'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () async {
                        final value = num.tryParse(amount.text.trim());
                        if (number.text.trim().isEmpty) {
                          showPmsSnack(context, 'Credit note number is required', error: true);
                          return;
                        }
                        if (value == null || value <= 0) {
                          showPmsSnack(context, 'Amount must be greater than 0', error: true);
                          return;
                        }
                        if (document == null) {
                          showPmsSnack(context, 'Attach the credit note document', error: true);
                          return;
                        }
                        try {
                          await context.read<AppServices>().dmr.createCreditNote(
                            {
                              'creditNoteNumber': number.text.trim(),
                              'creditNoteDate': date.toIso8601String(),
                              'creditNoteAmount': value,
                              'ro_number': roNumber,
                              'vendorId': vendorId,
                              'site': siteId,
                            },
                            document: document!.toEntry(),
                          );
                          if (sheetContext.mounted) Navigator.pop(sheetContext, true);
                        } on ApiException catch (e) {
                          if (context.mounted) showPmsSnack(context, e.message, error: true);
                        }
                      },
                      child: const Text('Save credit note'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );
  number.dispose();
  amount.dispose();
  return saved == true;
}

class DebitNoteCreateScreen extends StatefulWidget {
  const DebitNoteCreateScreen({
    super.key,
    required this.orderId,
    required this.roNumber,
    required this.siteId,
    required this.vendorId,
  });

  final String orderId;
  final String roNumber;
  final String siteId;
  final String vendorId;

  @override
  State<DebitNoteCreateScreen> createState() => _DebitNoteCreateScreenState();
}

class _DebitNoteCreateScreenState extends State<DebitNoteCreateScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  final _remarks = TextEditingController();
  List<Map<String, dynamic>> _entries = [];
  final _selected = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await context.read<AppServices>().dmr.debitInvoiceEntries({
        'ro_number': widget.roNumber,
      });
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Map<String, dynamic> _itemPayload(Map<String, dynamic> line) {
    final rejected = asNum(line['rejected_qty']) ?? 0;
    final rate = asNum(line['rate']) ?? 0;
    final gstPct = asNum(line['gst']) ?? asNum(line['gst_percentage']) ?? 0;
    final amount = asNum(line['amount']) ?? (rejected * rate);
    final gst = asNum(line['gst_amount']) ?? (amount * gstPct / 100);
    final uom = line['uom'];
    return {
      'item_id': mongoId(line['item_id']) ?? '',
      'item_name': line['item_name']?.toString() ?? itemLabel(line, fallback: ''),
      'uom': uom is String ? uom : labelOf(uom, fallback: ''),
      'po_qty': asNum(line['po_qty']) ?? 0,
      'received_qty': asNum(line['received_qty']) ?? 0,
      'accepted_qty': asNum(line['accepted_qty']) ?? 0,
      'invoice_qty': asNum(line['invoice_qty']) ?? 0,
      'rate': rate,
      'rejected_qty': rejected,
      'invoice_rate': asNum(line['invoice_rate']) ?? rate,
      'debit_reason': line['remark']?.toString() ?? '',
      'amount': amount,
      'gst': gst,
      'gst_percentage': gstPct,
    };
  }

  Future<void> _save() async {
    if (_selected.isEmpty) {
      showPmsSnack(context, 'Select at least one invoice entry', error: true);
      return;
    }
    final chosen = _entries.where((e) => _selected.contains(idOf(e))).toList();
    final items = <Map<String, dynamic>>[];
    final invoices = <String>[];
    var totalAmount = 0.0;
    var totalGst = 0.0;
    for (final entry in chosen) {
      final invoice = entry['invoice_number']?.toString().trim() ?? '';
      if (invoice.isNotEmpty) invoices.add(invoice);
      final raw = entry['dmr_items'] ?? entry['items'];
      if (raw is! List) continue;
      for (final line in raw) {
        if (line is! Map) continue;
        final mapped = _itemPayload(Map<String, dynamic>.from(line));
        items.add(mapped);
        totalAmount += (mapped['amount'] as num).toDouble();
        totalGst += (mapped['gst'] as num).toDouble();
      }
    }
    setState(() => _saving = true);
    final api = context.read<AppServices>().dmr;
    try {
      final next = await api.nextDebitNumber({
        'site_id': widget.siteId,
      });
      final number = next['next_debit_note_number']?.toString().trim() ?? '';
      if (number.isEmpty) {
        throw ApiException(message: 'Debit note number is missing');
      }
      await api.createDebitNote({
        'debitNoteNumber': number,
        'ro_number': widget.roNumber,
        'dmr_orderID': widget.orderId,
        'vendorId': widget.vendorId,
        'site': widget.siteId,
        'dmrEntries': _selected.toList(),
        'InvoiceNumber': invoices,
        'items': items,
        'additionalDebits': const [],
        'totalAmount': totalAmount,
        'totalGST': totalGst,
        'grandTotal': totalAmount + totalGst,
        'remarks': _remarks.text.trim(),
        'status': 'raised',
      });
      if (!mounted) return;
      await showSavedConfirmation(context, 'Debit note raised');
      if (mounted) context.pop(true);
    } on ApiException catch (e) {
      if (mounted) showPmsSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Raise debit note')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Padding(
                  padding: AppTheme.formPadding,
                  child: ErrorBanner(message: _error!, onRetry: _load),
                )
              : ListView(
                  padding: AppTheme.formPadding,
                  children: [
                    Text('RO: ${widget.roNumber}'),
                    const SizedBox(height: 12),
                    if (_entries.isEmpty)
                      const Text('No invoice entries are available for a debit note.')
                    else
                      for (final entry in _entries)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _selected.contains(idOf(entry)),
                          title: Text(entry['invoice_number']?.toString() ?? entry['dmr_no']?.toString() ?? 'Entry'),
                          subtitle: Text(formatDate(entry['invoice_date'] ?? entry['createdAt'])),
                          onChanged: (checked) {
                            final id = idOf(entry);
                            if (id == null) return;
                            setState(() {
                              if (checked == true) {
                                _selected.add(id);
                              } else {
                                _selected.remove(id);
                              }
                            });
                          },
                        ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _remarks,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Remarks'),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _saving || _entries.isEmpty ? null : _save,
                      child: Text(_saving ? 'Saving…' : 'Raise debit note'),
                    ),
                  ],
                ),
    );
  }
}
