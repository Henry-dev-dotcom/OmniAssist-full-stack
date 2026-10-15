/// CSV import and export for review items (Spec 4.8, Task 30). Pure code: no I/O.
library;

// Limits the spec left open (decision 0003).
const csvMaxBytes = 5 * 1000 * 1000;
const csvMaxRows = 5000;
const csvMaxColumns = 50;
const csvMaxCell = 10000;

class CsvTable {
  const CsvTable(this.headers, this.rows);
  final List<String> headers;
  final List<List<String>> rows;
}

/// RFC 4180: quoted fields, doubled quotes, commas and newlines inside quotes, CRLF or LF.
/// Throws [FormatException] with a line number for an unterminated quote or a limit.
CsvTable parseCsv(String input) {
  final text = input.startsWith('﻿') ? input.substring(1) : input;
  final records = <List<String>>[];
  var field = StringBuffer();
  var record = <String>[];
  var inQuotes = false;
  var line = 1, quoteLine = 1;

  void endField() {
    if (field.length > csvMaxCell) {
      throw FormatException(
        'Line $line: a cell is longer than $csvMaxCell characters.',
      );
    }
    record.add(field.toString());
    field = StringBuffer();
  }

  void endRecord() {
    endField();
    if (!(record.length == 1 && record.first.isEmpty)) records.add(record);
    if (records.length > csvMaxRows + 1) {
      throw const FormatException('The file has more than $csvMaxRows rows.');
    }
    record = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        if (c == '\n') line++;
        field.write(c);
      }
    } else if (c == '"' && field.isEmpty) {
      inQuotes = true;
      quoteLine = line;
    } else if (c == ',') {
      endField();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      endRecord();
      line++;
    } else {
      field.write(c);
    }
  }
  if (inQuotes) {
    throw FormatException('Line $quoteLine: a quoted cell is never closed.');
  }
  if (field.isNotEmpty || record.isNotEmpty) endRecord();
  if (records.isEmpty) throw const FormatException('The file is empty.');
  final headers = [for (final h in records.first) h.trim()];
  if (headers.length > csvMaxColumns) {
    throw const FormatException(
      'The file has more than $csvMaxColumns columns.',
    );
  }
  return CsvTable(headers, records.skip(1).toList());
}

/// Fields a column can be mapped to. Only [title] is required.
const importFields = <String, String>{
  'title': 'Title or citation',
  'source_identifier': 'Source ID (DOI, PMID…)',
  'decision': 'Decision',
  'reviewer': 'Reviewer',
  'tags': 'Tags (separated by ;)',
  'notes': 'Notes',
  'external_url': 'Link',
  'stage': 'Stage name',
};

const _aliases = <String, List<String>>{
  'title': ['title', 'citation', 'reference', 'study'],
  'source_identifier': [
    'source_identifier',
    'source id',
    'id',
    'doi',
    'pmid',
    'source',
  ],
  'decision': ['decision'],
  'reviewer': ['reviewer'],
  'tags': ['tags', 'tag', 'keywords'],
  'notes': ['notes', 'note', 'comments', 'abstract'],
  'external_url': ['external_url', 'url', 'link'],
  'stage': ['stage'],
};

/// Best guess of field to column index from header names; the user can change it.
Map<String, int?> guessMapping(List<String> headers) {
  final lower = [for (final h in headers) h.toLowerCase().trim()];
  return {
    for (final f in importFields.keys)
      f: () {
        for (final a in _aliases[f]!) {
          final i = lower.indexOf(a);
          if (i >= 0) return i;
        }
        return null;
      }(),
  };
}

class ImportRow {
  ImportRow(this.line, this.data, this.errors);
  final int line; // 1-based line in the file, header is line 1
  final Map<String, Object?> data;
  final List<String> errors;
}

/// Validates every row before anything is written (Spec 4.8). [stages] maps stage names
/// (case-insensitive) to ids; rows without a stage go to [defaultStageId].
List<ImportRow> planImport(
  CsvTable table,
  Map<String, int?> mapping,
  Map<String, String> stages,
  String defaultStageId,
) {
  final byName = {for (final e in stages.entries) e.key.toLowerCase(): e.value};
  String cell(List<String> row, String field) {
    final i = mapping[field];
    return i == null || i >= row.length ? '' : row[i].trim();
  }

  return [
    for (final (n, row) in table.rows.indexed)
      () {
        final errors = <String>[];
        final title = cell(row, 'title');
        if (title.isEmpty) errors.add('Title is empty.');
        if (title.length > 1000) {
          errors.add('Title is longer than 1000 characters.');
        }
        final decision = cell(row, 'decision').toLowerCase();
        if (decision.isNotEmpty &&
            !{'include', 'exclude', 'maybe'}.contains(decision)) {
          errors.add('Decision must be include, exclude or maybe.');
        }
        final tags = [
          for (final t in cell(row, 'tags').split(';'))
            if (t.trim().isNotEmpty) t.trim(),
        ];
        if (tags.length > 50) errors.add('More than 50 tags.');
        if (tags.any((t) => t.length > 60)) {
          errors.add('A tag is longer than 60 characters.');
        }
        final url = cell(row, 'external_url');
        final uri = Uri.tryParse(url);
        if (url.isNotEmpty &&
            (uri == null ||
                !{'http', 'https'}.contains(uri.scheme) ||
                uri.host.isEmpty)) {
          errors.add('Link must start with http:// or https://.');
        }
        final stageName = cell(row, 'stage');
        final stageId = stageName.isEmpty
            ? defaultStageId
            : byName[stageName.toLowerCase()];
        if (stageId == null) errors.add('Unknown stage "$stageName".');
        for (final (f, max) in const [
          ('source_identifier', 500),
          ('reviewer', 120),
          ('notes', 20000),
        ]) {
          if (cell(row, f).length > max) {
            errors.add('${importFields[f]} is too long.');
          }
        }
        String? opt(String f) => cell(row, f).isEmpty ? null : cell(row, f);
        return ImportRow(n + 2, {
          'title': title,
          'stage_id': stageId,
          'source_identifier': opt('source_identifier'),
          'decision': decision.isEmpty ? null : decision,
          'reviewer': opt('reviewer'),
          'tags': tags,
          'notes': opt('notes'),
          'external_url': url.isEmpty ? null : url,
        }, errors);
      }(),
  ];
}

const exportColumns = [
  'id',
  'review_id',
  'stage',
  'stage_id',
  'title',
  'source_identifier',
  'decision',
  'reviewer',
  'tags',
  'notes',
  'external_url',
  'updated_at',
];

/// Quotes when needed, and defuses spreadsheet formulas (=, +, -, @) with a leading '.
String csvCell(Object? v) {
  var s = v == null ? '' : '$v';
  if (s.isNotEmpty && '=+-@\t\r'.contains(s[0])) s = "'$s";
  if (s.contains(RegExp(r'[",\r\n]'))) s = '"${s.replaceAll('"', '""')}"';
  return s;
}

String encodeCsv(List<List<Object?>> rows) =>
    '${rows.map((r) => r.map(csvCell).join(',')).join('\r\n')}\r\n';
