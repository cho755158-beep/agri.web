//
//  GSManager.swift
//  Agri_Web
//
//  Created by Silas Pham on 30/6/26.
//

import Vapor

// MARK: - Google Sheets content models
struct GSBatchUpdateRequest: Content {
    var requests: [GSRequestItem]
}

struct GSRequestItem: Content {
    var duplicateSheet: GSDuplicateSheet?
    var insertDimension: GSInsertDimension?
    var copyPaste: GSCopyPaste?
    var updateCells: GSUpdateCells?
}

struct GSDuplicateSheet: Content {
    var sourceSheetId: Int
    var newSheetName: String
}

struct GSInsertDimension: Content {
    var range: GSDimensionRange
    var inheritFromBefore: Bool
}

struct GSDimensionRange: Content {
    var sheetId: Int
    var dimension: String
    var startIndex: Int
    var endIndex: Int
}

struct GSCopyPaste: Content {
    var source: GSGridRange
    var destination: GSGridRange
    var pasteType: String
}

struct GSGridRange: Content {
    var sheetId: Int
    var startRowIndex: Int?
    var endRowIndex: Int?
}

struct GSUpdateCells: Content {
    var rows: [GSRowData]
    var fields: String
    var start: GSGridCoordinate
}

struct GSRowData: Content {
    var values: [GSCellData]
}

struct GSCellData: Content {
    var userEnteredValue: GSCellValue
}

struct GSCellValue: Content {
    var formulaValue: String?
    var stringValue: String?
}

struct GSGridCoordinate: Content {
    var sheetId: Int
    var rowIndex: Int
    var columnIndex: Int
}

struct GSValuesResponse: Content {
    let values: [[String]]?
}

struct GSSheetsResponse: Content {
    struct Sheet: Content {
        struct Properties: Content {
            let sheetId: Int
            let title: String
        }
        let properties: Properties
    }
    let sheets: [Sheet]
}

struct GSBatchUpdateResponse: Content {
    struct Reply: Content {
        struct DuplicateSheet: Content {
            struct Properties: Content {
                let sheetId: Int
                let title: String
            }
            let properties: Properties
        }
        let duplicateSheet: DuplicateSheet?
    }
    let replies: [Reply]?
}

class GSManager {
    let req: Request
    
    init(req: Request) {
        self.req = req
    }
    let apiKey = "AIzaSyClCz_Vt5e_dZOCjNMAm-alY7rwDtNiL68"
    let baseURL = "https://sheets.googleapis.com/v4/spreadsheets"

    // MARK: - Cell helpers
    private func rowNumber(from cell: String) -> Int? {
        Int(cell.filter(\.isNumber))
    }

    private func columnLetter(from cell: String) -> String {
        cell.filter { $0.isLetter }
    }

    private func columnName(from index: Int) -> String {
        var index = index
        var result = ""
        repeat {
            result = String(UnicodeScalar(65 + index % 26)!) + result
            index = index / 26 - 1
        } while index >= 0
        return result
    }

    private func columnIndex(from cell: String) -> Int {
        let letters = cell.filter { $0.isLetter }.uppercased()
        return letters.reduce(0) { $0 * 26 + Int($1.asciiValue! - 64) } - 1
    }

    // MARK: - Cache
    var cachedTabIDs: [String: Int] = [:]

    // MARK: - Dataset markers
    private let markers: [String: [String: String]] = [
        "AI": [
            "vnd_out": "<<VND_OUT>>",
            "usd_out": "<<USD_OUT>>",
            "tcv": "<<TCV>>"
        ],
        "AE": [
            "401002": "<<401002>>",
            "421201": "<<421201>>",
            "421202": "<<421202>>",
            "421203": "<<421203>>",
            "421202_usd": "<<421202_USD>>",
            "403101": "<<403101>>"
        ]
    ]

    // MARK: - Marker search
    // Mark changes to the original MacOS App
    func findMarkerCell(marker: String, sheetID: String, sheetName: String) async throws -> String {
        
        //Change
        let token = try await req.tokenManager.getValidAccessToken(req: req)
        
        var customAllowed = CharacterSet.urlPathAllowed
        customAllowed.remove(charactersIn: "/")
        
        guard let range = sheetName.addingPercentEncoding(withAllowedCharacters: customAllowed) else {
            // Change
            throw Abort(.badRequest, reason: "Invalid sheet name encoding")
        }
        // Change
        let uri = URI(string: "\(baseURL)/\(sheetID)/values/\(range)")

        // Change
        let response = try await req.client.get(uri) { clientReq in
            clientReq.headers.bearerAuthorization = .init(token: token)
        }
        
        // Change
        let data = try response.content.decode(GSValuesResponse.self)
        guard let rows = data.values else { throw Abort(.notFound, reason: "No values found") }

        for (rowIndex, row) in rows.enumerated() {
            for (columnIndex, value) in row.enumerated() where value == marker {
                let column = columnName(from: columnIndex)
                return "\(column)\(rowIndex + 1)"
            }
        }
        
        // Change
        throw Abort(.notFound, reason: "MarkerNotFound")
    }

    // MARK: - Get Sheet Tab ID
    func getSheetTabId(sheetID: String, sheetName: String) async throws -> Int {

        if let cached = cachedTabIDs[sheetName] { return cached }
        
        let token = try await req.tokenManager.getValidAccessToken(req: req)

        let uri = URI(string: "\(baseURL)/\(sheetID)")
        let response = try await req.client.get(uri) { clientReq in
            clientReq.headers.bearerAuthorization = .init(token: token)
        }
        let data = try response.content.decode(GSSheetsResponse.self)
        
        guard let tab = data.sheets.first(where: { $0.properties.title == sheetName }) else {
            throw Abort(.notFound, reason: "Tab not found")
        }
        
        cachedTabIDs[sheetName] = tab.properties.sheetId
        return tab.properties.sheetId
    }

    // MARK: - Duplicate Template
    func duplicateTemplate(template: Int, newSheetName: String, sheetID: String) async throws -> Int {
        let token = try await req.tokenManager.getValidAccessToken(req: req)

        let uri = URI(string: "\(baseURL)/\(sheetID):batchUpdate")
        
        let body = GSBatchUpdateRequest(requests: [GSRequestItem(duplicateSheet: GSDuplicateSheet(sourceSheetId: template, newSheetName: newSheetName))])
        
        let response = try await req.client.post(uri) { clientReq in
            clientReq.headers.bearerAuthorization = .init(token: token)
            try clientReq.content.encode(body)
        }
        
        if response.status != .ok {
            if response.status == .badRequest {
                return try await getSheetTabId(sheetID: sheetID, sheetName: newSheetName)
            }
            throw Abort(response.status)
        }

        let result = try response.content.decode(GSBatchUpdateResponse.self)
        guard let newSheetID = result.replies?.first?.duplicateSheet?.properties.sheetId else {
            throw Abort(.internalServerError)
        }
        
        cachedTabIDs[newSheetName] = newSheetID
        return newSheetID
    }

    // MARK: - Insert Rows
    func insertRows(count: Int, after templateRow: Int, sheetID: String, sheetName: String) async throws {
        guard count > 0 else { return }

        let tabID = try await getSheetTabId(sheetID: sheetID, sheetName: sheetName)
        let uri = URI(string: "\(baseURL)/\(sheetID):batchUpdate")
        
        let token = try await req.tokenManager.getValidAccessToken(req: req)
        
        let body = GSBatchUpdateRequest(requests: [
            GSRequestItem(insertDimension: GSInsertDimension(range: GSDimensionRange(sheetId: tabID, dimension: "ROWS", startIndex: templateRow, endIndex: templateRow + count), inheritFromBefore: true)),
            GSRequestItem(copyPaste: GSCopyPaste(source: GSGridRange(sheetId: tabID, startRowIndex: templateRow - 1, endRowIndex: templateRow), destination: GSGridRange(sheetId: tabID, startRowIndex: templateRow, endRowIndex: templateRow + count), pasteType: "PASTE_FORMAT"))
        ])

        let response = try await req.client.post(uri) { clientReq in
            clientReq.headers.bearerAuthorization = .init(token: token)
            try clientReq.content.encode(body)
        }
        
        guard response.status == .ok else {
            throw Abort(response.status)
        }
        
        req.logger.info("Insert formatted rows success.")
    }

    // MARK: - Populate Template
    func populateDynamicTemplate(
        _ values: [[String]],
        sheetID: String,
        template: String,
        dataset: String,
        sheetName: String
    ) async {
        
        guard !values.isEmpty else { return }
        guard let marker = markers[template]?[dataset] else { return }

        let markerCell: String
        do {
            markerCell = try await findMarkerCell(marker: marker, sheetID: sheetID, sheetName: sheetName)
        } catch {
            req.logger.warning("Marker not found: \(marker)")
            return
        }

        guard let markerRow = rowNumber(from: markerCell) else { return }
        let colIndex = columnIndex(from: markerCell)
        
        let tabID: Int
        do {
            tabID = try await getSheetTabId(sheetID: sheetID, sheetName: sheetName)
        } catch {
            req.logger.error("Failed to get Tab ID: \(error)")
            return
        }
        
        let insertedRowsCount = max(0, values.count - 1)
        
        // Map raw strings into the target format expected by updateCells
        let googleRowData: [GSRowData] = values.map { row in
            let cellValues = row.map { rawValue -> GSCellData in
                if rawValue.hasPrefix("=") {
                    // It's an actual formula (e.g., "=SUM(A1:A10)")
                    return GSCellData(userEnteredValue: GSCellValue(formulaValue: rawValue, stringValue: nil))
                } else if Double(rawValue.replacingOccurrences(of: ",", with: "")) != nil || rawValue.contains("$") {
                    // It's a formatted number/currency string (e.g., "1,250.00" or "$500")
                    // Passing it as a formulaValue forces Google to parse it like a manual paste!
                    return GSCellData(userEnteredValue: GSCellValue(formulaValue: "=\(rawValue)", stringValue: nil))
                } else {
                    // Standard plain text words
                    return GSCellData(userEnteredValue: GSCellValue(formulaValue: nil, stringValue: rawValue))
                }
            }
            return GSRowData(values: cellValues)
        }
        
        var batchRequests: [GSRequestItem] = []
        
        if insertedRowsCount > 0 {
            // Action A: Open up row space directly under the marker row
            batchRequests.append(GSRequestItem(insertDimension: GSInsertDimension(
                            range: GSDimensionRange(sheetId: tabID, dimension: "ROWS", startIndex: markerRow, endIndex: markerRow + insertedRowsCount),
                            inheritFromBefore: true
                        )))
            
            // Action B: Clone style metadata properties from the marker container row downwards
            batchRequests.append(GSRequestItem(copyPaste: GSCopyPaste(
                            source: GSGridRange(sheetId: tabID, startRowIndex: markerRow - 1, endRowIndex: markerRow),
                            destination: GSGridRange(sheetId: tabID, startRowIndex: markerRow, endRowIndex: markerRow + insertedRowsCount),
                            pasteType: "PASTE_FORMAT"
                        )))
        }
        
        batchRequests.append(GSRequestItem(updateCells: GSUpdateCells(
                    rows: googleRowData,
                    fields: "userEnteredValue",
                    start: GSGridCoordinate(sheetId: tabID, rowIndex: markerRow - 1, columnIndex: colIndex)
                )))
        
        do {
            let token = try await req.tokenManager.getValidAccessToken(req: req)
            let uri = URI(string: "\(baseURL)/\(sheetID):batchUpdate")
            let data = GSBatchUpdateRequest(requests: batchRequests)
            
            let response = try await req.client.post(uri) { clientReq in
                clientReq.headers.bearerAuthorization = .init(token: token)
                try clientReq.content.encode(data)
            }
            
            if response.status != .ok {
                req.logger.error("Batch execution failed: \(response.status)")
            } else {
                req.logger.info("Batch operations complete. Marker cleanly overwritten.")
            }
        } catch {
            req.logger.error("Network dispatch failure: \(error)")
        }
    }
}
