//
//  AuthController.swift
//  Agri_Web
//
//  Created by Silas Pham on 1/7/26.
//

import Vapor

struct AuthController: RouteCollection, Sendable {
    
    func boot(routes: any RoutesBuilder) throws {
        let auth = routes.grouped("auth")
        
        // API: GET /auth/login
        auth.get("login") { req -> Response in
            let state = UUID().uuidString
            req.session.data["oauth_state"] = state
            let url = req.tokenManager.getAuthURL(state: state)
            return req.redirect(to: url)
        }
        
        // API: GET /auth/callback (Sửa REDIRECT_URI trỏ về route này)
        auth.get("callback") { req -> Response in
            guard let code = req.query[String.self, at: "code"],
                  let state = req.query[String.self, at: "state"],
                  state == req.session.data["oauth_state"] else {
                throw Abort(.badRequest, reason: "Invalid callback request hoặc sai State")
            }
            
            try await req.tokenManager.exchangeCodeForTokens(req: req, code: code)
            return req.redirect(to: "/dashboard") 
        }
        
        // API: POST /auth/logout
        auth.post("logout") { req -> HTTPStatus in
            req.tokenManager.signOut(req: req)
            return .ok
        }
    }
}
