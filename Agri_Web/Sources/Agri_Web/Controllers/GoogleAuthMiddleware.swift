//
//  GoogleAuthMiddleware.swift
//  Agri_Web
//
//  Created by Silas Pham on 1/7/26.
//

import Vapor

struct GoogleAuthMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        _ = try await request.tokenManager.getValidAccessToken(req: request)
        
        return try await next.respond(to: request)
    }
}
