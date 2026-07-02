//
//  TokenManager.swift
//  Agri_Web
//
//  Created by Silas Pham on 30/6/26.
//

import Vapor

struct GoogleOAuthResponse: Content {
    let access_token: String
    let refresh_token: String?
    let expires_in: Double
}

struct TokenExchangePayload: Content {
    let code: String
    let client_id: String
    let client_secret: String
    let redirect_uri: String
    let grant_type: String
}

struct TokenRefreshPayload: Content {
    let client_id: String
    let client_secret: String
    let refresh_token: String
    let grant_type: String
}

public class TokenManager {
    private let clientID: String
    private let clientSecret: String
    private let redirectURI: String
    
    public init() {
        guard let clientID = Environment.get("CLIENT_ID"),
              let clientSecret = Environment.get("CLIENT_SECRET"),
              let redirectURI = Environment.get("REDIRECT_URI") else {
            fatalError("Missing: CLIENT_ID, CLIENT_SECRET, REDIRECT_URI")
        }
        
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
    }
    
    // Debugging
//    public init() {
//        self.clientID = Environment.get("CLIENT_ID")
//            ?? ""
//        self.clientSecret = Environment.get("CLIENT_SECRET")
//            ?? ""
//        self.redirectURI = Environment.get("REDIRECT_URI")
//            ?? ""
//    }
    
    func getAuthURL(state: String) -> String {
        return "https://accounts.google.com/o/oauth2/v2/auth?response_type=code&client_id=\(clientID)&redirect_uri=\(redirectURI)&scope=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fspreadsheets%20https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fgmail.readonly&state=\(state)&access_type=offline&prompt=consent"
    }
    
    func exchangeCodeForTokens(req: Request, code: String) async throws {
        let uri = URI(string: "https://oauth2.googleapis.com/token")
        
        let payload = TokenExchangePayload(
            code: code,
            client_id: clientID,
            client_secret: clientSecret,
            redirect_uri: redirectURI,
            grant_type: "authorization_code"
        )
        
        let response = try await req.client.post(uri) { clientReq in
            try clientReq.content.encode(payload)
        }
        
        guard response.status == .ok else {
            throw Abort(.badRequest, reason: "Error exchanging token: \(response.status)")
        }
        
        let tokenData = try response.content.decode(GoogleOAuthResponse.self)
        let expireAt = Date().addingTimeInterval(tokenData.expires_in).timeIntervalSince1970
        
        req.session.data["accessToken"] = tokenData.access_token
        if let refreshToken = tokenData.refresh_token {
            req.session.data["refreshToken"] = refreshToken
        }
        
        req.session.data["expireAt"] = String(expireAt)
    }
    
    func getValidAccessToken(req: Request) async throws -> String {
        guard let expireString = req.session.data["expireAt"],
              let expireAt = Double(expireString) else {
            throw Abort(.unauthorized, reason: "User haven't signed in")
        }
        
        if Date().timeIntervalSince1970 >= expireAt {
            guard let refreshToken = req.session.data["refreshToken"] else {
                throw Abort(.unauthorized, reason: "No refresh token found")
            }
            
            let uri = URI(string: "https://oauth2.googleapis.com/token")
            let payload = TokenRefreshPayload(
                client_id: clientID,
                client_secret: clientSecret,
                refresh_token: refreshToken,
                grant_type: "refresh_token"
            )
            
            let response = try await req.client.post(uri) { clientReq in
                try clientReq.content.encode(payload)
            }
            
            guard response.status == .ok else {
                throw Abort(.unauthorized, reason: "Can't refresh")
            }
            
            let tokenData = try response.content.decode(GoogleOAuthResponse.self)
            let newExpireAt = Date().addingTimeInterval(tokenData.expires_in).timeIntervalSince1970
            
            req.session.data["accessToken"] = tokenData.access_token
            req.session.data["expireAt"] = String(newExpireAt)
            
            return tokenData.access_token
        }
        
        guard let token = req.session.data["accessToken"] else {
            throw Abort(.unauthorized)
        }
        return token
    }
    
    func signOut(req: Request) {
        req.session.destroy()
    }
}
