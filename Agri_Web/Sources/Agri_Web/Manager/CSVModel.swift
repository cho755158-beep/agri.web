//
//  CSVModel.swift
//  Agri_Web
//
//  Created by Silas Pham on 30/6/26.
//

import Vapor

// MARK: - Upload Types & Configs

enum UploadType { case ai, ai_usd, ae, ae_usd }

struct BatchUploadConfig {
    let type: UploadType
    let headers: [String]
    let predicate: ([String]) -> Bool
    let templateID: String
    let datasetKey: String
    let sheetName: String
}

struct UploadTask {
    let url: URL
    let configs: [BatchUploadConfig]
}

// MARK: - CSV Types

struct CSVHeader: Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var columnIndex: Int = 0

    static func createHeaders(data: [String]) -> [CSVHeader] {
        var headers = data.map { CSVHeader(name: $0) }
        var index = 0
        for i in headers.indices {
            headers[i].columnIndex = index
            index += 1
        }
        return headers
    }
}

struct CSVCell: Identifiable, Hashable {
    var id: UUID = UUID()
    var content: String
}

struct CSVRow: Identifiable, Hashable {
    var id: UUID = UUID()
    var cells: [CSVCell]
}

// MARK: - CSV Model

class CSVModel {
    let req: Request
    init(req: Request) {
        self.req = req
    }
    
    // Parsed content
    var content: String = ""
    var header: [CSVHeader] = []
    var rows: [CSVRow] = []
    var filteredRows: [CSVRow] = []

    // UI / naming
    var fileName: String = ""
    var name: String = ""

    // Date parsing
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yy"
        return formatter
    }()

    // Template headers & mappings
    let templateHeadersforAI = ["1","2","3","4","5","6","7","8","9","10","11","12","13","14"]
    let templateHeadersforAE = ["1","2","3","4","5","6","7","8","9","10","11","12","13","14","15"]

    let mappingsforAI: [String: String] = [
        "1":"custnm","2":"acctno","3":"","4":"ccy","5":"","6":"acrfmdt","7":"acrtodt","8":"intrt","9":"acrbamt","10":"","11":"acrbamt","12":"adjamt","13":"adjacctlocal","14":"acctlocal"
    ]
    let mappingsforAI_USD: [String: String] = [
        "1":"custnm","2":"acctno","3":"","4":"ccy","5":"","6":"acrfmdt","7":"acrtodt","8":"intrt","9":"acrbamt","10":"","11":"acrbamt","12":"adjamt","13":"adjacctlocal","14":"acctlocal"
    ]
    let mappingsforAE: [String: String] = [
        "1":"","2":"custseq","3":"custnm","4":"acctno","5":"acrbamt","6":"ccy","7":"","8":"acrbamt","9":"acrfmdt","10":"acrtodt","11":"intrt","12":"adjamt","13":"adjacctlocal","14":"acctlocal","15":"refno"
    ]
    let mappingforAE_USD: [String: String] = [
        "1":"","2":"custseq","3":"custnm","4":"acctno","5":"acrbamt","6":"ccy","7":"","8":"","9":"acrfmdt","10":"acrtodt","11":"intrt","12":"adjamt","13":"adjacctlocal","14":"acctlocal","15":"refno"
    ]

    // Sheet endpoints
    let AEsheetID = "1nm0rShI2MlIGLHtum_bD24vPGYdIb_o0rPDPkWeg_0s"
    let AIsheetID = "1i4MDSk4zNcrHJfLL8mdZ3n5NTRVSEqpLsliLrdrdnGo"

    let acctref = ["-","401002","421201","421202","421203","403101"]

    // MARK: - Parse & reset
    func parseCSV(content: String) {
        do {
            let data = try EnumeratedCSV(string: content, loadColumns: false)
            header = CSVHeader.createHeaders(data: data.header)
            rows = data.rows.map { CSVRow(cells: $0.map { CSVCell(content: $0) }) }
            filteredRows = rows
        } catch { print(error) }
    }

    private func parseDate(_ value: String) -> Date? {
        if let date = dateFormatter.date(from: value) { return date }
        if let serial = Double(value) {
            return Calendar.current.date(byAdding: .day, value: Int(serial), to: Date(timeIntervalSince1970: -2209161600))
        }
        return nil
    }

    func resetCSV() {
        content = ""
        header = []
        rows = []
        filteredRows = []
        fileName = ""
    }

    // MARK: - Filter data
    func filterRows(
        from sourceRows: [CSVRow],
        currentHeaders: [CSVHeader],
        headersToFind: [String],
        predicate: ([String]) -> Bool
    ) -> [CSVRow] {
        let indices = headersToFind.compactMap { name in
            currentHeaders.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.columnIndex
        }
        guard indices.count == headersToFind.count else { return [] }
        return sourceRows.filter { row in
            guard indices.allSatisfy(row.cells.indices.contains) else { return false }
            let values = indices.map { row.cells[$0].content }
            return predicate(values)
        }
    }

    enum DateRange { case lessThan365, between365and730, moreThan730 }

    func filterDateRows(_ first: String, _ second: String, range: DateRange) -> Bool {
        guard let date1 = parseDate(first), let date2 = parseDate(second) else { return false }
        let days = abs(Calendar.current.dateComponents([.day], from: date1, to: date2).day ?? Int.max)
        switch range {
        case .lessThan365: return days < 365
        case .between365and730: return days >= 365 && days < 730
        case .moreThan730: return days >= 730
        }
    }

    // MARK: - Upload helpers
    func columnIndex(for headerName: String) -> Int? {
        header.first { $0.name.caseInsensitiveCompare(headerName) == .orderedSame }?.columnIndex
    }

    func values(
        from rows: [CSVRow],
        currentHeaders: [CSVHeader],
        templateHeaders: [String],
        mappings: [String: String]
    ) -> [[String]] {
        rows.map { row in
            templateHeaders.map { templateHeader in
                guard let csvHeader = mappings[templateHeader],
                      let index = currentHeaders.first(where: { $0.name.caseInsensitiveCompare(csvHeader) == .orderedSame })?.columnIndex,
                      row.cells.indices.contains(index) else { return "" }
                return row.cells[index].content
            }
        }
    }

    // MARK: - Upload orchestrators
    func uploadAI(
        rowsToProcess: [CSVRow],
        currentHeaders: [CSVHeader],
        headers: [String],
        predicate: ([String]) -> Bool,
        templateID: String,
        datasetKey: String,
        sheetName: String
    ) async {
        let filtered = filterRows(from: rowsToProcess, currentHeaders: currentHeaders, headersToFind: headers, predicate: predicate)
        let values = values(from: filtered, currentHeaders: currentHeaders, templateHeaders: templateHeadersforAI, mappings: mappingsforAI)
        await req.gsManager.populateDynamicTemplate(values, sheetID: AIsheetID, template: templateID, dataset: datasetKey, sheetName: sheetName)
    }

    func uploadAI_USD(
        rowsToProcess: [CSVRow],
        currentHeaders: [CSVHeader],
        headers: [String],
        predicate: ([String]) -> Bool,
        templateID: String,
        datasetKey: String,
        sheetName: String
    ) async {
        let filtered = filterRows(from: rowsToProcess, currentHeaders: currentHeaders, headersToFind: headers, predicate: predicate)
        let values = values(from: filtered, currentHeaders: currentHeaders, templateHeaders: templateHeadersforAI, mappings: mappingsforAI_USD)
        await req.gsManager.populateDynamicTemplate(values, sheetID: AIsheetID, template: templateID, dataset: datasetKey, sheetName: sheetName)
    }

    func uploadAE(
        rowsToProcess: [CSVRow],
        currentHeaders: [CSVHeader],
        headers: [String],
        predicate: ([String]) -> Bool,
        templateID: String,
        datasetKey: String,
        sheetName: String
    ) async {
        let filtered = filterRows(from: rowsToProcess, currentHeaders: currentHeaders, headersToFind: headers, predicate: predicate)
        print(datasetKey, filtered.count)
        let values = values(from: filtered, currentHeaders: currentHeaders, templateHeaders: templateHeadersforAE, mappings: mappingsforAE)
        await req.gsManager.populateDynamicTemplate(values, sheetID: AEsheetID, template: templateID, dataset: datasetKey, sheetName: sheetName)
    }

    func uploadAE_USD(
        rowsToProcess: [CSVRow],
        currentHeaders: [CSVHeader],
        headers: [String],
        predicate: ([String]) -> Bool,
        templateID: String,
        datasetKey: String,
        sheetName: String
    ) async {
        let filtered = filterRows(from: rowsToProcess, currentHeaders: currentHeaders, headersToFind: headers, predicate: predicate)
        let values = values(from: filtered, currentHeaders: currentHeaders, templateHeaders: templateHeadersforAE, mappings: mappingforAE_USD)
        await req.gsManager.populateDynamicTemplate(values, sheetID: AEsheetID, template: templateID, dataset: datasetKey, sheetName: sheetName)
    }

    // MARK: - Multi-file upload
    func uploadFiles(for tasks: [UploadTask]) async {
        for task in tasks {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let data = try EnumeratedCSV(string: content, loadColumns: false)

                let isolatedHeaders = CSVHeader.createHeaders(data: data.header)
                let isolatedRows: [CSVRow] = data.rows.map { CSVRow(cells: $0.map { CSVCell(content: $0) }) }

                for config in task.configs {
                    #if DEBUG
                    let previewFiltered = filterRows(from: isolatedRows, currentHeaders: isolatedHeaders, headersToFind: config.headers, predicate: config.predicate)
                    print("[Upload] dataset=\(config.datasetKey) count=\(previewFiltered.count)")
                    #endif
                    switch config.type {
                    case .ai:
                        await uploadAI(rowsToProcess: isolatedRows, currentHeaders: isolatedHeaders, headers: config.headers, predicate: config.predicate, templateID: config.templateID, datasetKey: config.datasetKey, sheetName: config.sheetName)
                    case .ai_usd:
                        await uploadAI_USD(rowsToProcess: isolatedRows, currentHeaders: isolatedHeaders, headers: config.headers, predicate: config.predicate, templateID: config.templateID, datasetKey: config.datasetKey, sheetName: config.sheetName)
                    case .ae:
                        await uploadAE(rowsToProcess: isolatedRows, currentHeaders: isolatedHeaders, headers: config.headers, predicate: config.predicate, templateID: config.templateID, datasetKey: config.datasetKey, sheetName: config.sheetName)
                    case .ae_usd:
                        await uploadAE_USD(rowsToProcess: isolatedRows, currentHeaders: isolatedHeaders, headers: config.headers, predicate: config.predicate, templateID: config.templateID, datasetKey: config.datasetKey, sheetName: config.sheetName)
                    }
                }
            } catch {
                req.logger.error("\(error)")
            }
        }
    }
}
