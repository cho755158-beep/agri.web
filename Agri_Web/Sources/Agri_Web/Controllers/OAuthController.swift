//
//  OAuthController.swift
//  Agri_Web
//
//  Created by Silas Pham on 29/6/26.
//
import Vapor

struct OAuthController: RouteCollection, Sendable {

    func boot(routes: any RoutesBuilder) throws {
        routes.get("login", use: loginHandler)
        routes.get("callback", use: callbackHandler)
        routes.post("logout", use: logoutHandler)
    }

    @Sendable func loginHandler(req: Request) async throws -> Response {
        let state = UUID().uuidString
        
        req.session.data["oauth_state"] = state
        
        let authURL = req.tokenManager.getAuthURL(state: state)
        
        return req.redirect(to: authURL)
    }
    
    @Sendable func callbackHandler(req: Request) async throws -> Response {
        guard let code = req.query[String.self, at: "code"],
              let state = req.query[String.self, at: "state"] else {
            throw Abort(.badRequest, reason: "Missing code/state")
        }
        
        guard state == req.session.data["oauth_state"] else {
            throw Abort(.badRequest, reason: "Oudated state")
        }
        
        try await req.tokenManager.exchangeCodeForTokens(req: req, code: code)
        
        req.session.data["oauth_state"] = nil
        
        return req.redirect(to: "/")
    }
    
    @Sendable
    func logoutHandler(req: Request) async throws -> HTTPStatus {
        req.tokenManager.signOut(req: req)
        
        return .ok
    }
}
