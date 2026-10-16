export type CsvPreview = { headers: string[]; rows: string[][]; errors: string[] };

export function previewCsv(source: string): CsvPreview {
  if (new TextEncoder().encode(source).length > 1_000_000) return { headers: [], rows: [], errors: ["CSV file exceeds the 1 MB limit."] };
  const records: string[][] = [];
  let row: string[] = [], cell = "", quoted = false;
  for (let i = 0; i < source.length; i++) {
    const char = source[i];
    if (quoted) {
      if (char === '"' && source[i + 1] === '"') { cell += '"'; i++; }
      else if (char === '"') quoted = false;
      else cell += char;
    } else if (char === '"' && cell.length === 0) quoted = true;
    else if (char === ",") { row.push(cell); cell = ""; }
    else if (char === "\n" || char === "\r") {
      if (char === "\r" && source[i + 1] === "\n") i++;
      row.push(cell); cell = "";
      if (row.some((value) => value.trim())) records.push(row);
      row = [];
    } else cell += char;
    if (cell.length > 20_000) return { headers: [], rows: [], errors: ["A CSV cell exceeds the 20,000 character limit."] };
  }
  if (quoted) return { headers: [], rows: [], errors: ["CSV contains an unclosed quoted field."] };
  if (cell || row.length) { row.push(cell); if (row.some((value) => value.trim())) records.push(row); }
  if (!records.length) return { headers: [], rows: [], errors: ["CSV has no header row."] };
  const headers = records.shift()!.map((header) => header.trim());
  const errors: string[] = [];
  if (headers.length > 50) errors.push("CSV has more than 50 columns.");
  if (new Set(headers.map((h) => h.toLowerCase())).size !== headers.length) errors.push("CSV headers must be unique.");
  if (records.length > 100) errors.push("CSV has more than 100 data rows (the server mutation batch limit).");
  records.forEach((values, index) => {
    if (values.length !== headers.length) errors.push(`Row ${index + 2}: expected ${headers.length} columns, found ${values.length}.`);
    else if (headers.findIndex((h) => h.toLowerCase() === "title") >= 0 && !values[headers.findIndex((h) => h.toLowerCase() === "title")].trim()) errors.push(`Row ${index + 2}: title is required.`);
    else { const sourceIndex = headers.findIndex((h) => ["source_identifier", "doi", "id"].includes(h.toLowerCase())); if (sourceIndex >= 0 && values[sourceIndex].length > 500) errors.push(`Row ${index + 2}: source identifier exceeds 500 characters.`); }
  });
  return { headers, rows: records, errors };
}
