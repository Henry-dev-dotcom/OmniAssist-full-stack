import 'package:flutter_test/flutter_test.dart';
import 'package:omniassist/features/reviews/review_csv.dart';

void main() {
  group('parseCsv', () {
    test('quotes, doubled quotes, commas and newlines in cells, CRLF, BOM', () {
      final t = parseCsv(
        '﻿Title,Notes\r\n"Smith, 2020","said ""hi""\nthen left"\r\nJones,\n',
      );
      expect(t.headers, ['Title', 'Notes']);
      expect(t.rows, [
        ['Smith, 2020', 'said "hi"\nthen left'],
        ['Jones', ''],
      ]);
    });

    test('blank lines are skipped and a last line without newline counts', () {
      expect(parseCsv('a,b\n\n1,2').rows, [
        ['1', '2'],
      ]);
    });

    test('limits and broken input give line-numbered errors', () {
      expect(
        () => parseCsv('a\n"open\nstill open'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'm',
            contains('Line 2'),
          ),
        ),
      );
      expect(() => parseCsv(''), throwsFormatException);
      final wide = List.generate(csvMaxColumns + 1, (i) => 'c$i').join(',');
      expect(() => parseCsv(wide), throwsFormatException);
      final tall = 'a\n${List.filled(csvMaxRows + 1, 'x').join('\n')}';
      expect(() => parseCsv(tall), throwsFormatException);
      expect(
        () => parseCsv('a\n${'x' * (csvMaxCell + 1)}'),
        throwsFormatException,
      );
    });
  });

  group('planImport', () {
    final stages = {'Screening': 's1', 'Full Text': 's2'};

    test('guesses columns and builds rows', () {
      final t = parseCsv(
        'Citation,DOI,Decision,Tags,Stage,URL\n'
        'Smith 2020,10.1/x,Include,rct; adults ,full text,https://doi.org/10.1/x\n',
      );
      final mapping = guessMapping(t.headers);
      expect(mapping['title'], 0);
      expect(mapping['source_identifier'], 1);
      final [row] = planImport(t, mapping, stages, 's1');
      expect(row.errors, isEmpty);
      expect(row.data, {
        'title': 'Smith 2020',
        'stage_id': 's2',
        'source_identifier': '10.1/x',
        'decision': 'include',
        'reviewer': null,
        'tags': ['rct', 'adults'],
        'notes': null,
        'external_url': 'https://doi.org/10.1/x',
      });
    });

    test('every bad row is reported with its line, nothing is dropped', () {
      final t = parseCsv(
        'title,decision,stage,url\n'
        ',,,\n'
        'Ok,perhaps,,\n'
        'Ok,,Nowhere,javascript:alert(1)\n'
        'Good,,,\n',
      );
      final rows = planImport(t, guessMapping(t.headers), stages, 's1');
      expect(rows.map((r) => r.line), [2, 3, 4, 5]);
      expect(rows[0].errors, ['Title is empty.']);
      expect(rows[1].errors.single, contains('include, exclude or maybe'));
      expect(rows[2].errors, hasLength(2));
      expect(rows[3].errors, isEmpty);
      expect(rows[3].data['stage_id'], 's1');
    });
  });

  test('export quotes cells and defuses formulas', () {
    expect(
      encodeCsv([
        ['id', 'title'],
        ['1', 'A, "B"'],
        ['2', '=HYPERLINK("x")'],
        ['3', null],
      ]),
      'id,title\r\n1,"A, ""B"""\r\n2,"\'=HYPERLINK(""x"")"\r\n3,\r\n',
    );
    // Round trip keeps content.
    final back = parseCsv(
      encodeCsv([
        ['t'],
        ['line1\nline2'],
      ]),
    );
    expect(back.rows.single.single, 'line1\nline2');
  });
}
