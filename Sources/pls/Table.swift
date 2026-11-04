/// Rows as aligned columns: every column but the last is padded to its widest cell, columns are two spaces apart,
/// and trailing spaces are trimmed.
func table(_ rows: [[String]], indent: String = "") -> [String] {
    let columns = rows.map(\.count).max() ?? 0
    let widths = (0..<max(columns - 1, 0)).map { column in
        rows.map { column < $0.count ? $0[column].count : 0 }.max() ?? 0
    }
    return rows.map { row in
        let cells = row.enumerated()
            .map { column, cell in column < widths.count ? cell.padded(to: widths[column]) : cell }
        return indent + cells.joined(separator: "  ").replacing(/\s+$/, with: "")
    }
}
