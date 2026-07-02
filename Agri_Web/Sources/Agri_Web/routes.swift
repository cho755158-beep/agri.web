import Vapor

struct LoginState: Content {
    let signedIn: Bool
    let accessToken: String
}

func routes(_ app: Application) throws {
    
    app.get { req async throws -> Response in
        try await req.fileio.asyncStreamFile(
            at: req.application.directory.publicDirectory + "index.html"
        )
    }

    app.get("hello") { req async -> String in
        "Hello, world!"
    }
    
    let api = app.grouped("api").grouped(app.sessions.middleware)
    
    try api.grouped("auth").register(collection: OAuthController())
    
    let protected = api.grouped(GoogleAuthMiddleware())
    
    protected.get("me") { req async throws -> LoginState in
        let token = try await req.tokenManager.getValidAccessToken(req: req)
        return LoginState(
            signedIn: true,
            accessToken: token
        )
    }
}
