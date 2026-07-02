import Vapor

/// configures your application
func configure(_ app: Application) async throws {
    // uncomment to serve files from /Public folder
     app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    
    // register routes
    
    print("VAPOR_IS_STARTING_UP")
    
    // MARK: - CORS
    
    let corsConfiguration = CORSMiddleware.Configuration(
        allowedOrigin: .originBased, // Hoặc .custom("http://127.0.0.1:5500")  Frontend
        allowedMethods: [.GET, .POST, .PUT, .OPTIONS, .DELETE, .PATCH],
        allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith],
        allowCredentials: true
    )
    let cors = CORSMiddleware(configuration: corsConfiguration)
    app.middleware.use(cors, at: .beginning)

    app.sessions.use(.memory)
    app.middleware.use(app.sessions.middleware)
    
    try routes(app)
}
