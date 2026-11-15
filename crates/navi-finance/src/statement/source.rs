//! A statement file's bytes as text: UTF-8 (with or without a BOM), else
//! GB18030 (Alipay's CSV); an XLSX workbook (WeChat Pay) becomes CSV of its
//! first sheet. Sizes are bounded so a small file cannot expand without
//! limit.

use std::io::{Cursor, Read};

/// The largest statement file accepted.
pub const MAX_FILE_BYTES: usize = 20 * 1024 * 1024;
/// The most a workbook part may expand to.
const MAX_PART_BYTES: u64 = 16 * 1024 * 1024;

/// Why a file is not a readable statement.
#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum StatementError {
    #[error("the file is too large")]
    TooLarge,
    #[error("the file is empty")]
    Empty,
    #[error("the workbook cannot be read")]
    UnreadableWorkbook,
}

/// The text of a statement file.
pub fn decode(bytes: &[u8]) -> Result<String, StatementError> {
    if bytes.len() > MAX_FILE_BYTES {
        return Err(StatementError::TooLarge);
    }
    let text = if bytes.starts_with(b"PK\x03\x04") {
        workbook_csv(bytes)?
    } else {
        let bytes = bytes.strip_prefix(b"\xef\xbb\xbf").unwrap_or(bytes);
        match std::str::from_utf8(bytes) {
            Ok(text) => text.to_owned(),
            Err(_) => encoding_rs::GB18030.decode(bytes).0.into_owned(),
        }
    };
    if text.trim().is_empty() {
        return Err(StatementError::Empty);
    }
    Ok(text)
}

fn part(
    archive: &mut zip::ZipArchive<Cursor<&[u8]>>,
    name: &str,
) -> Result<Option<String>, StatementError> {
    let file = match archive.by_name(name) {
        Ok(file) => file,
        Err(zip::result::ZipError::FileNotFound) => return Ok(None),
        Err(_) => return Err(StatementError::UnreadableWorkbook),
    };
    if file.size() > MAX_PART_BYTES {
        return Err(StatementError::TooLarge);
    }
    let mut text = String::new();
    // The declared size can lie: stop reading past the ceiling.
    let read = file
        .take(MAX_PART_BYTES + 1)
        .read_to_string(&mut text)
        .map_err(|_| StatementError::UnreadableWorkbook)?;
    if read as u64 > MAX_PART_BYTES {
        return Err(StatementError::TooLarge);
    }
    Ok(Some(text))
}

/// The first worksheet of an XLSX workbook as RFC 4180 CSV.
fn workbook_csv(bytes: &[u8]) -> Result<String, StatementError> {
    let mut archive =
        zip::ZipArchive::new(Cursor::new(bytes)).map_err(|_| StatementError::UnreadableWorkbook)?;
    let shared = match part(&mut archive, "xl/sharedStrings.xml")? {
        Some(xml) => shared_strings(&xml)?,
        None => Vec::new(),
    };
    let sheet = part(&mut archive, "xl/worksheets/sheet1.xml")?
        .ok_or(StatementError::UnreadableWorkbook)?;
    let document =
        roxmltree::Document::parse(&sheet).map_err(|_| StatementError::UnreadableWorkbook)?;
    let mut out = String::new();
    for row in document
        .descendants()
        .filter(|n| n.has_tag_name_local("row"))
    {
        let mut values: Vec<(usize, String)> = Vec::new();
        let mut last: Option<usize> = None;
        for cell in row.children().filter(|n| n.has_tag_name_local("c")) {
            let column = match cell.attribute("r") {
                Some(reference) => column_of(reference)?,
                None => last.map_or(0, |c| c + 1),
            };
            let raw = cell_value(cell);
            let value = match cell.attribute("t") {
                Some("s") => raw
                    .parse::<usize>()
                    .ok()
                    .and_then(|i| shared.get(i).cloned())
                    .ok_or(StatementError::UnreadableWorkbook)?,
                Some("b") => if raw == "1" { "TRUE" } else { "FALSE" }.to_owned(),
                _ => raw,
            };
            values.push((column, value));
            last = Some(last.map_or(column, |l| l.max(column)));
        }
        let Some(width) = last else {
            continue;
        };
        let mut cells = vec![String::new(); width + 1];
        for (column, value) in values {
            cells[column] = escape(&value);
        }
        out.push_str(&cells.join(","));
        out.push('\n');
    }
    Ok(out)
}

trait LocalName {
    fn has_tag_name_local(&self, name: &str) -> bool;
}

impl LocalName for roxmltree::Node<'_, '_> {
    fn has_tag_name_local(&self, name: &str) -> bool {
        self.is_element() && self.tag_name().name() == name
    }
}

fn texts(node: roxmltree::Node<'_, '_>) -> String {
    node.descendants()
        .filter(|n| n.has_tag_name_local("t"))
        .filter_map(|n| n.text())
        .collect()
}

fn shared_strings(xml: &str) -> Result<Vec<String>, StatementError> {
    let document =
        roxmltree::Document::parse(xml).map_err(|_| StatementError::UnreadableWorkbook)?;
    Ok(document
        .descendants()
        .filter(|n| n.has_tag_name_local("si"))
        .map(texts)
        .collect())
}

fn cell_value(cell: roxmltree::Node<'_, '_>) -> String {
    if cell.attribute("t") == Some("inlineStr") {
        return texts(cell);
    }
    cell.children()
        .find(|n| n.has_tag_name_local("v"))
        .and_then(|n| n.text())
        .unwrap_or_default()
        .to_owned()
}

/// `C7` → 2. Columns past `XFD` (Excel's last) are refused.
fn column_of(reference: &str) -> Result<usize, StatementError> {
    let letters: Vec<u8> = reference
        .bytes()
        .take_while(u8::is_ascii_uppercase)
        .collect();
    if letters.is_empty() || letters.len() > 3 {
        return Err(StatementError::UnreadableWorkbook);
    }
    let value = letters.iter().fold(0_usize, |value, letter| {
        value * 26 + usize::from(letter - b'A' + 1)
    });
    if value > 16_384 {
        return Err(StatementError::UnreadableWorkbook);
    }
    Ok(value - 1)
}

fn escape(value: &str) -> String {
    if value.contains([',', '"', '\r', '\n']) {
        format!("\"{}\"", value.replace('"', "\"\""))
    } else {
        value.to_owned()
    }
}

#[cfg(test)]
mod tests {
    use std::io::Write;

    use zip::write::SimpleFileOptions;

    use super::*;

    fn workbook(shared: &str, sheet: &str) -> Vec<u8> {
        let mut out = Vec::new();
        {
            let mut zip = zip::ZipWriter::new(Cursor::new(&mut out));
            let options = SimpleFileOptions::default();
            zip.start_file("xl/sharedStrings.xml", options).unwrap();
            zip.write_all(shared.as_bytes()).unwrap();
            zip.start_file("xl/worksheets/sheet1.xml", options).unwrap();
            zip.write_all(sheet.as_bytes()).unwrap();
            zip.finish().unwrap();
        }
        out
    }

    #[test]
    fn a_workbook_becomes_csv_of_its_first_sheet() {
        let shared = r#"<sst xmlns="x"><si><t>交易时间</t></si><si><t>金额(元)</t></si><si><r><t>纸巾,</t></r><r><t>家庭装</t></r></si></sst>"#;
        let sheet = r#"<worksheet xmlns="x"><sheetData>
            <row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1" t="s"><v>1</v></c></row>
            <row r="2"><c r="A2" t="inlineStr"><is><t>2026-07-16 12:00:00</t></is></c><c r="B2" t="s"><v>2</v></c><c r="C2"><v>31.5</v></c></row>
            <row r="3"/>
        </sheetData></worksheet>"#;
        let text = decode(&workbook(shared, sheet)).unwrap();
        assert_eq!(
            text,
            "交易时间,,金额(元)\n2026-07-16 12:00:00,\"纸巾,家庭装\",31.5\n"
        );
        let broken = workbook(
            shared,
            r#"<worksheet><row><c r="A1" t="s"><v>9</v></c></row></worksheet>"#,
        );
        assert_eq!(decode(&broken), Err(StatementError::UnreadableWorkbook));
        assert_eq!(
            decode(b"PK\x03\x04junk"),
            Err(StatementError::UnreadableWorkbook)
        );
    }

    #[test]
    fn text_is_utf8_or_gb18030_and_never_empty() {
        let (gbk, _, _) = encoding_rs::GB18030.encode("交易时间,金额\n");
        assert_eq!(decode(&gbk).unwrap(), "交易时间,金额\n");
        assert_eq!(decode("\u{feff}a,b".as_bytes()).unwrap(), "a,b");
        assert_eq!(decode(b"  \n"), Err(StatementError::Empty));
        assert_eq!(
            decode(&vec![b'a'; MAX_FILE_BYTES + 1]),
            Err(StatementError::TooLarge)
        );
        assert_eq!(column_of("AA10"), Ok(26));
        assert!(column_of("10").is_err() && column_of("XFE1").is_err());
    }
}
