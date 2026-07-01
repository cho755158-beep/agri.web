import Vapor

struct GoogleUserInfo: Content {
    let id: String
    let email: String
    let name: String
    let picture: String?
}

func routes(_ app: Application) throws {
    
//    app.get { req async in
//        "It works!"
//    }

    app.get("hello") { req async -> String in
        "Hello, world!"
    }
    
    let api = app.grouped("api").grouped(app.sessions.middleware)
    
    try api.grouped("auth").register(collection: OAuthController())
    
    let protected = api.grouped(GoogleAuthMiddleware())
    
    protected.get("me") { req async throws -> GoogleUserInfo in
        let token = try await req.tokenManager.getValidAccessToken(req: req)
        
        let uri = URI(string: "https://www.googleapis.com/oauth2/v2/userinfo")
                let response = try await req.client.get(uri) { clientReq in
                    clientReq.headers.bearerAuthorization = .init(token: token)
                }
        
        guard response.status == .ok else {
                    req.logger.error("Error: \(response.status)")
                    throw Abort(.internalServerError, reason: "Couldn't find User Info")
                }
        
        let userInfo = try response.content.decode(GoogleUserInfo.self)
                
        return userInfo
    }
}
