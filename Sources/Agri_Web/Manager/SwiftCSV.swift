//
//  SwiftCSV.swift
//  Agri_Web
//
//  Created by Silas Pham on 30/6/26.
//

import Vapor

extension String {
    internal var firstLine: String {
        var current = startIndex
        while current < endIndex && self[current].isNewline == false {
            current = self.index(after: current)
        }
        return String(self[..<current])
    }
}

extension Character {
    internal var isNewline: Bool {
        return self == "\n"
            || self == "\r\n"
            || self == "\r"
    }
}

public enum CSVDelimiter: Equatable, ExpressibleByUnicodeScalarLiteral, Sendable {

    public typealias UnicodeScalarLiteralType = Character

    case comma, semicolon, tab
    case character(Character)

    public init(unicodeScalarLiteral: Character) {
        self.init(rawValue: unicodeScalarLiteral)
    }

    init(rawValue: Character) {
        switch rawValue {
        case ",":  self = .comma
        case ";":  self = .semicolon
        case "\t": self = .tab
        default:   self = .character(rawValue)
        }
    }

    public var rawValue: Character {
        switch self {
        case .comma: return ","
        case .semicolon: return ";"
        case .tab: return "\t"
        case .character(let character): return character
        }
    }
}

extension CSVDelimiter {
    static let recognized: [CSVDelimiter] = [.comma, .tab, .semicolon]

    /// - Returns: Delimiter between cells based on the first line in the CSV. Falls back to `.comma`.
    public static func guessed(string: String) -> CSVDelimiter {
        let recognizedDelimiterCharacters = CSVDelimiter.recognized.map(\.rawValue)

        // Trim newline and spaces, but keep tabs (as delimiters)
        var trimmedCharacters = CharacterSet.whitespacesAndNewlines
        trimmedCharacters.remove("\t")
        let line = string.trimmingCharacters(in: trimmedCharacters).firstLine

        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            switch character {
            case "\"":
                // When encountering an open quote, skip to the closing counterpart.
                // If none is found, skip to end of line.

                // 1) Advance one character to skip the quote
                index = line.index(after: index)

                // 2) Look for the closing quote and move current position after it
                if index < line.endIndex,
                   let closingQuoteInddex = line[index...].firstIndex(of: character) {
                    index = line.index(after: closingQuoteInddex)
                } else {
                    index = line.endIndex
                }
            case _ where recognizedDelimiterCharacters.contains(character):
                return CSVDelimiter(rawValue: character)
            default:
                index = line.index(after: index)
            }
        }

        // Fallback value
        return .comma
    }
}

public struct Named: CSVView {

    public typealias Row = [String : String]
    public typealias Columns = [String : [String]]

    public var rows: [Row]
    public var columns: Columns?

    public init(header: [String], text: String, delimiter: CSVDelimiter, loadColumns: Bool = false, rowLimit: Int? = nil) throws {

        self.rows = try {
            var rows: [Row] = []
            try Parser.enumerateAsDict(header: header, content: text, delimiter: delimiter, rowLimit: rowLimit) { dict in
                rows.append(dict)
            }
            return rows
        }()

        self.columns = {
            guard loadColumns else { return nil }
            var columns: Columns = [:]
            for field in header {
                columns[field] = rows.map { $0[field] ?? "" }
            }
            return columns
        }()
    }

    public func serialize(header: [String], delimiter: CSVDelimiter) -> String {
        let rowsOrderingCellsByHeader = rows.map { row in
            header.map { cellID in row[cellID]! }
        }

        return Serializer.serialize(header: header, rows: rowsOrderingCellsByHeader, delimiter: delimiter)
    }

}

extension CSV {
    /// Parse the file and call a block on each row, passing it in as a list of fields.
    /// - Parameters limitTo: Maximum absolute line number in the content, *not* maximum amount of rows.
    @available(*, deprecated, message: "Use enumerateAsArray(startAt:rowLimit:_:) instead")
    public func enumerateAsArray(limitTo maxRow: Int? = nil, startAt: Int = 0, _ rowCallback: @escaping ([String]) -> ()) throws {

        try Parser.enumerateAsArray(text: self.text, delimiter: self.delimiter, startAt: startAt, rowLimit: maxRow.map { $0 - startAt }, rowCallback: rowCallback)
    }

    /// Parse the CSV contents row by row from `start` for `rowLimit` amount of rows, or until the end of the input.
    /// - Parameters:
    ///   - startAt: Skip lines before this. Default value is `0` to start at the beginning.
    ///   - rowLimit: Amount of rows to consume, beginning to count at `startAt`. Default value is `nil` to consume
    ///     the whole input string.
    ///   - rowCallback: Array of each row's columnar values, in order.
    public func enumerateAsArray(startAt: Int = 0, rowLimit: Int? = nil, _ rowCallback: @escaping ([String]) -> ()) throws {

        try Parser.enumerateAsArray(text: self.text, delimiter: self.delimiter, startAt: startAt, rowLimit: rowLimit, rowCallback: rowCallback)
    }

    public func enumerateAsDict(_ block: @escaping ([String : String]) -> ()) throws {

        try Parser.enumerateAsDict(header: self.header, content: self.text, delimiter: self.delimiter, block: block)
    }
}

enum Parser {

    static func array(text: String, delimiter: CSVDelimiter, startAt offset: Int = 0, rowLimit: Int? = nil) throws -> [[String]] {

        var rows = [[String]]()

        try enumerateAsArray(text: text, delimiter: delimiter, startAt: offset, rowLimit: rowLimit) { row in
            rows.append(row)
        }

        return rows
    }

    /// Parse `text` and provide each row to `rowCallback` as an array of field values, one for each column per
    /// line of text, separated by `delimiter`.
    ///
    /// - Parameters:
    ///   - text: Text to parse.
    ///   - delimiter: Character to split row and header fields by (default is ',')
    ///   - offset: Skip lines before this. Default value is `0` to start at the beginning.
    ///   - rowLimit: Amount of rows to consume, beginning to count at `startAt`. Default value is `nil` to consume
    ///     the whole input string.
    ///   - rowCallback: Callback invoked for every parsed row between `startAt` and `limitTo` in `text`.
    /// - Throws: `CSVParseError`
    static func enumerateAsArray(text: String,
                                 delimiter: CSVDelimiter,
                                 startAt offset: Int = 0,
                                 rowLimit: Int? = nil,
                                 rowCallback: @escaping ([String]) -> ()) throws {
        let maxRowIndex = rowLimit.flatMap { $0 < 0 ? nil : offset + $0 }

        var currentIndex = text.startIndex
        let endIndex = text.endIndex

        var fields = [String]()
        let delimiter = delimiter.rawValue
        var field = ""

        var rowIndex = 0

        func finishRow() {
            defer {
                rowIndex += 1
                fields = []
                field = ""
            }

            guard rowIndex >= offset else { return }
            fields.append(String(field))
            rowCallback(fields)
        }

        var state: ParsingState = ParsingState(
            delimiter: delimiter,
            finishRow: finishRow,
            appendChar: {
                guard rowIndex >= offset else { return }
                field.append($0)
            },
            finishField: {
                guard rowIndex >= offset else { return }
                fields.append(field)
                field = ""
            })

        func limitReached(_ rowNumber: Int) -> Bool {
            guard let maxRowIndex = maxRowIndex else { return false }
            return rowNumber >= maxRowIndex
        }

        while currentIndex < endIndex,
              !limitReached(rowIndex) {
            let char = text[currentIndex]

            try state.change(char)

            currentIndex = text.index(after: currentIndex)
        }

        // Append remainder of the cache, unless we're past the limit already.
        if !limitReached(rowIndex) {
            if !field.isEmpty {
                fields.append(field)
            }

            if !fields.isEmpty {
                rowCallback(fields)
            }
        }
    }

    static func enumerateAsDict(header: [String], content: String, delimiter: CSVDelimiter, rowLimit: Int? = nil, block: @escaping ([String : String]) -> ()) throws {

        let enumeratedHeader = header.enumerated()

        // Start after the header
        try enumerateAsArray(text: content, delimiter: delimiter, startAt: 1, rowLimit: rowLimit) { fields in
            var dict = [String: String]()
            for (index, head) in enumeratedHeader {
                dict[head] = index < fields.count ? fields[index] : ""
            }
            block(dict)
        }
    }
}

enum Serializer {

    static let newline = "\n"

    static func serialize(header: [String], rows: [[String]], delimiter: CSVDelimiter) -> String {
        let head = serializeRow(row: header, delimiter: delimiter) + newline

        let content = rows.map { row in
            serializeRow(row: row, delimiter: delimiter)
        }.joined(separator: newline)

        return head + content
    }


    static func serializeRow(row: [String], delimiter: CSVDelimiter) -> String {
        let separator = String(delimiter.rawValue)

        let content = row.map { cell in
            cell.enquoted(whenContaining: separator)
        }.joined(separator: separator)

        return content
    }

}

fileprivate extension String {

    static let quote = "\""

    func enquoted(whenContaining separator: String) -> String {
        // If value contains a delimiter or quotes, double any embedded quotes and surround with quotes.
        // For more information, see https://www.rfc-editor.org/rfc/rfc4180.html
        if self.contains(separator) || self.contains(Self.quote) {
            return Self.quote + self.replacingOccurrences(of: Self.quote, with: Self.quote + Self.quote) + Self.quote
        } else {
            return self
        }
    }

}

public enum CSVParseError: Error {
    case generic(message: String)
    case quotation(message: String)
}

/// State machine of parsing CSV contents character by character.
struct ParsingState {

    private(set) var atStart = true
    private(set) var parsingField = false
    private(set) var parsingQuotes = false
    private(set) var innerQuotes = false

    let delimiter: Character
    let finishRow: () -> Void
    let appendChar: (Character) -> Void
    let finishField: () -> Void

    init(delimiter: Character,
         finishRow: @escaping () -> Void,
         appendChar: @escaping (Character) -> Void,
         finishField: @escaping () -> Void) {

        self.delimiter = delimiter
        self.finishRow = finishRow
        self.appendChar = appendChar
        self.finishField = finishField
    }

    /// - Throws: `CSVParseError`
    mutating func change(_ char: Character) throws {
        if atStart {
            if char == "\"" {
                atStart = false
                parsingQuotes = true
            } else if char == delimiter {
                finishField()
            } else if char.isNewline {
                finishRow()
            } else if char.isWhitespace {
              // ignore whitespaces between fields
            } else {
                parsingField = true
                atStart = false
                appendChar(char)
            }
        } else if parsingField {
            if innerQuotes {
                if char == "\"" {
                    appendChar(char)
                    innerQuotes = false
                } else {
                    throw CSVParseError.quotation(message: "Can't have non-quote here: \(char)")
                }
            } else {
                if char == "\"" {
                    innerQuotes = true
                } else if char == delimiter {
                    atStart = true
                    parsingField = false
                    innerQuotes = false
                    finishField()
                } else if char.isNewline {
                    atStart = true
                    parsingField = false
                    innerQuotes = false
                    finishRow()
                } else {
                    appendChar(char)
                }
            }
        } else if parsingQuotes {
            if innerQuotes {
                if char == "\"" {
                    appendChar(char)
                    innerQuotes = false
                } else if char == delimiter {
                    atStart = true
                    parsingField = false
                    innerQuotes = false
                    finishField()
                } else if char.isNewline {
                    atStart = true
                    parsingQuotes = false
                    innerQuotes = false
                    finishRow()
                } else if char.isWhitespace {
                  // ignore whitespaces between fields
                } else {
                    throw CSVParseError.quotation(message: "Can't have non-quote here: \(char)")
                }
            } else {
                if char == "\"" {
                    innerQuotes = true
                } else {
                    appendChar(char)
                }
            }
        } else {
            throw CSVParseError.generic(message: "me_irl")
        }
    }
}

public struct Enumerated: CSVView {

    public struct Column: Equatable {
        public let header: String
        public let rows: [String]
    }

    public typealias Row = [String]
    public typealias Columns = [Column]

    public private(set) var rows: [Row]
    public private(set) var columns: Columns?

    public init(header: [String], text: String, delimiter: CSVDelimiter, loadColumns: Bool = false, rowLimit: Int? = nil) throws {

        self.rows = try {
            var rows: [Row] = []
            try Parser.enumerateAsArray(text: text, delimiter: delimiter, startAt: 1, rowLimit: rowLimit) { fields in
                rows.append(fields)
            }

            // Fill in gaps at the end of rows that are too short.
            return makingRectangular(rows: rows)
        }()

        self.columns = {
            guard loadColumns else { return nil }
            return header.enumerated().map { (index: Int, header: String) -> Column in
                return Column(
                    header: header,
                    rows: rows.map { $0[safe: index] ?? "" })
            }
        }()
    }

    public func serialize(header: [String], delimiter: CSVDelimiter) -> String {
        return Serializer.serialize(header: header, rows: rows, delimiter: delimiter)
    }

}

extension Collection {
    subscript (safe index: Self.Index) -> Self.Iterator.Element? {
        return index < endIndex ? self[index] : nil
    }
}

fileprivate func makingRectangular(rows: [[String]]) -> [[String]] {
    let cellsPerRow = rows.map { $0.count }.max() ?? 0
    return rows.map { row -> [String] in
        let missingCellCount = cellsPerRow - row.count
        let appendix = Array(repeating: "", count: missingCellCount)
        return row + appendix
    }
}
// MARK: - CSVView
fileprivate let byteOrderMark = "\u{FEFF}"

public protocol CSVView {
    associatedtype Row
    associatedtype Columns

    var rows: [Row] { get }

    /// Is `nil` if `loadColumns` was set to `false`.
    var columns: Columns? { get }

    init(header: [String], text: String, delimiter: CSVDelimiter, loadColumns: Bool, rowLimit: Int?) throws

    func serialize(header: [String], delimiter: CSVDelimiter) -> String
}

/// CSV variant for which unique column names are assumed.
///
/// Example:
///
///     let csv = NamedCSV(...)
///     let allIDs = csv.columns["id"]
///     let firstEntry = csv.rows[0]
///     let fullName = firstEntry["firstName"] + " " + firstEntry["lastName"]
///
public typealias NamedCSV = CSV<Named>

/// CSV variant that exposes columns and rows as arrays.
/// Example:
///
///     let csv = EnumeratedCSV(...)
///     let allIds = csv.columns.filter { $0.header == "id" }.rows
///
public typealias EnumeratedCSV = CSV<Enumerated>

/// For convenience, there's `EnumeratedCSV` to access fields in rows by their column index,
/// and `NamedCSV` to access fields by their column names as defined in a header row.
open class CSV<DataView : CSVView>  {

    public let header: [String]

    /// Unparsed contents.
    public let text: String

    /// Used delimiter to parse `text` and to serialize the data again.
    public let delimiter: CSVDelimiter

    /// Underlying data representation of the CSV contents.
    public let content: DataView

    public var rows: [DataView.Row] {
        return content.rows
    }

    /// Is `nil` if `loadColumns` was set to `false` during initialization.
    public var columns: DataView.Columns? {
        return content.columns
    }

    /// Load CSV data from a string.
    ///
    /// - Parameters:
    ///   - string: CSV contents to parse.
    ///   - delimiter: Character used to separate cells from one another in rows.
    ///   - loadColumns: Whether to populate the `columns` dictionary (default is `true`)
    ///   - rowLimit: Amount of rows to parse (default is `nil`).
    /// - Throws: `CSVParseError` when parsing `string` fails.
    public init(string: String, delimiter: CSVDelimiter, loadColumns: Bool = true, rowLimit: Int? = nil) throws {
        if string.hasPrefix(byteOrderMark) {
            let trimmedString = string.dropFirst()
            self.text = String(trimmedString)
        } else {
            self.text = string
        }
        self.delimiter = delimiter
        self.header = try Parser.array(text: self.text, delimiter: delimiter, rowLimit: 1).first ?? []
        self.content = try DataView(header: header, text: self.text, delimiter: delimiter, loadColumns: loadColumns, rowLimit: rowLimit)
    }

    /// Load CSV data from a string and guess its delimiter from `CSV.recognizedDelimiters`, falling back to `.comma`.
    ///
    /// - parameter string: CSV contents to parse.
    /// - parameter loadColumns: Whether to populate the `columns` dictionary (default is `true`)
    /// - throws: `CSVParseError` when parsing `string` fails.
    public convenience init(string: String, loadColumns: Bool = true) throws {
        let delimiter = CSVDelimiter.guessed(string: string)
        try self.init(string: string, delimiter: delimiter, loadColumns: loadColumns)
    }

    /// Turn the CSV data into NSData using a given encoding
    func dataUsingEncoding(_ encoding: String.Encoding) -> Data? {
        return serialized.data(using: encoding)
    }

    /// Serialized form of the CSV data; depending on the View used, this may
    /// perform additional normalizations.
    open var serialized: String {
        return self.content.serialize(header: self.header, delimiter: self.delimiter)
    }
}

extension CSV: CustomStringConvertible {
    public var description: String {
        return self.serialized
    }
}

extension CSV {
    /// Load a CSV file from `url`.
    ///
    /// - Parameters:
    ///   - url: URL of the file (will be passed to `String(contentsOfURL:encoding:)` to load)
    ///   - delimiter: Character used to separate separate cells from one another in rows.
    ///   - encoding: Character encoding to read file (default is `.utf8`)
    ///   - loadColumns: Whether to populate the columns dictionary (default is `true`)
    /// - Throws: `CSVParseError` when parsing the contents of `url` fails, or file loading errors.
    convenience init(url: URL, delimiter: CSVDelimiter, encoding: String.Encoding = .utf8, loadColumns: Bool = true) throws {
        let contents = try String(contentsOf: url, encoding: encoding)
        try self.init(string: contents, delimiter: delimiter, loadColumns: loadColumns)
    }

    /// Load a CSV file from `url` and guess its delimiter from `CSV.recognizedDelimiters`, falling back to `.comma`.
    ///
    /// - Parameters:
    ///   - url: URL of the file (will be passed to `String(contentsOfURL:encoding:)` to load)
    ///   - encoding: Character encoding to read file (default is `.utf8`)
    ///   - loadColumns: Whether to populate the columns dictionary (default is `true`)
    /// - Throws: `CSVParseError` when parsing the contents of `url` fails, or file loading errors.
    convenience init(url: URL, encoding: String.Encoding = .utf8, loadColumns: Bool = true) throws {
        let contents = try String(contentsOf: url, encoding: encoding)
        try self.init(string: contents, loadColumns: loadColumns)
    }
}

extension CSV {
    /// Load a CSV file as a named resource from `bundle`.
    ///
    /// - Parameters:
    ///   - name: Name of the file resource inside `bundle`.
    ///   - ext: File extension of the resource; use `nil` to load the first file matching the name (default is `nil`)
    ///   - bundle: `Bundle` to use for resource lookup (default is `.main`)
    ///   - delimiter: Character used to separate separate cells from one another in rows.
    ///   - encoding: encoding used to read file (default is `.utf8`)
    ///   - loadColumns: Whether to populate the columns dictionary (default is `true`)
    /// - Throws: `CSVParseError` when parsing the contents of the resource fails, or file loading errors.
    /// - Returns: `nil` if the resource could not be found
    convenience init?(name: String, extension ext: String? = nil, bundle: Bundle = .main, delimiter: CSVDelimiter, encoding: String.Encoding = .utf8, loadColumns: Bool = true) throws {
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            return nil
        }
        try self.init(url: url, delimiter: delimiter, encoding: encoding, loadColumns: loadColumns)
    }

    /// Load a CSV file as a named resource from `bundle` and guess its delimiter from `CSV.recognizedDelimiters`, falling back to `.comma`.
    ///
    /// - Parameters:
    ///   - name: Name of the file resource inside `bundle`.
    ///   - ext: File extension of the resource; use `nil` to load the first file matching the name (default is `nil`)
    ///   - bundle: `Bundle` to use for resource lookup (default is `.main`)
    ///   - encoding: encoding used to read file (default is `.utf8`)
    ///   - loadColumns: Whether to populate the columns dictionary (default is `true`)
    /// - Throws: `CSVParseError` when parsing the contents of the resource fails, or file loading errors.
    /// - Returns: `nil` if the resource could not be found
   convenience init?(name: String, extension ext: String? = nil, bundle: Bundle = .main, encoding: String.Encoding = .utf8, loadColumns: Bool = true) throws {
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            return nil
        }
        try self.init(url: url, encoding: encoding, loadColumns: loadColumns)
    }
}
