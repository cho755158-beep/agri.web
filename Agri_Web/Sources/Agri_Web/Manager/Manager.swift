//
//  Manager.swift
//  Agri_Web
//
//  Created by Silas Pham on 30/6/26.
//

import Vapor

@available(macOS 14.0, *)


extension Request {
    var gsManager: GSManager {
        .init(req: self)
    }
    
    var csvModel: CSVModel {
        .init(req: self)
    }
    
    var tokenManager: TokenManager {
        .init()
    }
}

//struct Request {
//    static func make(
//        url: URL,
//        method: String,
//        accessToken: String? = nil,
//        body: Data? = nil,
//        isJSON: Bool = true
//    ) -> URLRequest {
//        var request = URLRequest(url: url)
//        request.httpMethod = method
//        if isJSON {
//            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
//        }
//        if let token = accessToken {
//            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
//        }
//        request.httpBody = body
//        return request
//    }
//}
