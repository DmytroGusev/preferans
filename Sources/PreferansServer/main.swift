import Foundation
import Hummingbird
import PreferansServerCore

extension AuthoritativeGameResponse: ResponseEncodable {}

private struct HealthResponse: ResponseEncodable {
    var ok = true
    var service = "preferans-authoritative-engine"
    var stateSchemaVersion = AuthoritativeGameState.schemaVersion
}

@main
enum PreferansServerMain {
    static func main() async throws {
        let router = Router()

        router.get("/health") { _, _ in
            HealthResponse()
        }

        router.post("/v1/games") { request, context -> AuthoritativeGameResponse in
            do {
                let body = try await request.decode(
                    as: CreateAuthoritativeGameRequest.self,
                    context: context
                )
                return try AuthoritativeGameService.create(
                    body,
                    tableID: body.tableID ?? UUID(),
                    dealSeed: UInt64.random(in: UInt64.min...UInt64.max)
                )
            } catch {
                throw HTTPError(.badRequest, message: error.localizedDescription)
            }
        }

        router.post("/v1/commands") { request, context -> AuthoritativeGameResponse in
            do {
                let body = try await request.decode(
                    as: AuthoritativeCommandRequest.self,
                    context: context
                )
                return try await AuthoritativeGameService.apply(body)
            } catch {
                throw HTTPError(.badRequest, message: error.localizedDescription)
            }
        }

        let port = Int(ProcessInfo.processInfo.environment["PORT"] ?? "8080") ?? 8080
        let app = Application(
            router: router,
            configuration: .init(address: .hostname("0.0.0.0", port: port))
        )
        try await app.runService()
    }
}
