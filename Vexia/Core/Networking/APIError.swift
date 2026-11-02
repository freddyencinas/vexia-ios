import Foundation

/// API error codes mapped from HTTP status and backend error payloads.
nonisolated struct APIError: LocalizedError, Equatable {
    enum Code: String { case timeout = "TIMEOUT", network = "NETWORK_ERROR", unauthorized = "UNAUTHORIZED",
                        server = "SERVER_ERROR", cancelled = "REQUEST_CANCELLED", decoding = "DECODING_ERROR",
                        notFound = "NOT_FOUND", generic = "GENERIC" }
    let message: String
    let code: Code
    let statusCode: Int?
    var serverCode: String? = nil

    var errorDescription: String? { message }

    nonisolated static func from(status: Int, body: JSON) -> APIError {
        // Backend shape: {success:false, error:{code, message, messageKey}} (or legacy string `error`).
        let msg = body["error"]["message"].string ?? body["message"].string ?? body["error"].string ?? String(localized: "Error \(status)")
        let code: Code = switch status {
        case 401: .unauthorized
        case 404: .notFound
        case 500...: .server
        default: .generic
        }
        return APIError(message: msg, code: code, statusCode: status, serverCode: body["error"]["code"].string ?? body["error"].string)
    }

    nonisolated static func from(urlError: URLError) -> APIError {
        switch urlError.code {
        case .timedOut: APIError(message: String(localized: "La solicitud tardó demasiado"), code: .timeout, statusCode: nil)
        case .cancelled: APIError(message: String(localized: "Solicitud cancelada"), code: .cancelled, statusCode: nil)
        default: APIError(message: String(localized: "Sin conexión con el servidor"), code: .network, statusCode: nil)
        }
    }
}
