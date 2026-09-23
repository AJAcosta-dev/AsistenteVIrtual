import Foundation

// MARK: - Command

struct CommandRequest: Codable {
    let text: String
}

struct CommandResponse: Codable {
    let response: String
    let agent: String?
}

// MARK: - Transactions

struct TransactionsResponse: Codable {
    let transactions: [BackendTransaction]
}

struct BackendTransaction: Codable {
    let id: String
    let amount: Double
    let merchant: String
    let category: String
    let date: String
    let month: Int
    let year: Int
    let isIncome: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case amount
        case merchant
        case category
        case date
        case month
        case year
        case isIncome = "is_income"
    }
}

struct CreateTransactionRequest: Codable {
    let amount: Double
    let merchant: String
    let category: String
    let isIncome: Bool

    enum CodingKeys: String, CodingKey {
        case amount
        case merchant
        case category
        case isIncome = "is_income"
    }
}

struct CreateTransactionResponse: Codable {
    let transaction: BackendTransaction
}

struct DeleteTransactionResponse: Codable {
    let message: String
    let id: String
}

// MARK: - Agenda

struct EventsResponse: Codable {
    let events: [BackendEvent]
}

struct BackendEvent: Codable {
    let id: String
    let title: String
    let description: String?
    let startDate: String
    let endDate: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case startDate = "start_date"
        case endDate = "end_date"
        case createdAt = "created_at"
    }
}

struct CreateEventRequest: Codable {
    let title: String
    let startDate: String
    let description: String?
    let endDate: String?

    enum CodingKeys: String, CodingKey {
        case title
        case startDate = "start_date"
        case description
        case endDate = "end_date"
    }
}

struct CreateEventResponse: Codable {
    let event: BackendEvent
}

struct DeleteEventResponse: Codable {
    let message: String
    let id: String
}

// MARK: - Tasks

struct TasksResponse: Codable {
    let tasks: [BackendTask]
}

struct BackendTask: Codable {
    let id: String
    let title: String
    let description: String?
    let dueDate: String?
    let completed: Bool
    let createdAt: String?
    let priority: String?   // alta | media | baja
    let category: String?   // universidad | trabajo | personal | proyecto
    let status: String?     // pendiente | en_progreso | completado

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case dueDate = "due_date"
        case completed
        case createdAt = "created_at"
        case priority
        case category
        case status
    }
}

struct CreateTaskRequest: Codable {
    let id: String
    let title: String
    let description: String?
    let dueDate: String?
    let priority: String
    let category: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case dueDate = "due_date"
        case priority
        case category
    }
}

struct UpdateTaskRequest: Codable {
    let title: String
    let priority: String
    let category: String
    let dueDate: String?
    let clearDueDate: Bool

    enum CodingKeys: String, CodingKey {
        case title
        case priority
        case category
        case dueDate = "due_date"
        case clearDueDate = "clear_due_date"
    }
}

struct SimpleMessageResponse: Codable {
    let message: String
}

// MARK: - API Errors

enum APIServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(Int)
    case decodingError
    case encodingError
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "La URL del servidor no es válida."

        case .invalidResponse:
            return "El servidor devolvió una respuesta inválida."

        case .serverError(let statusCode):
            return "El servidor devolvió el código \(statusCode)."

        case .decodingError:
            return "No se pudo interpretar la respuesta del servidor."

        case .encodingError:
            return "No se pudo preparar la solicitud."

        case .networkError(let error):
            return "Error de conexión: \(error.localizedDescription)"
        }
    }
}

// MARK: - API Service

final class APIService {

    static let shared = APIService()

    private init() {}

    private let baseURL = "http://100.83.82.72:8000"

    // MARK: - Generic Request

    private func performRequest<T: Decodable>(
        url: URL,
        method: String,
        body: Data? = nil
    ) async throws -> T {

        var request = URLRequest(url: url)

        request.httpMethod = method

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        if let body {
            request.httpBody = body
        }

        do {

            let (data, response) = try await URLSession.shared.data(
                for: request
            )

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIServiceError.invalidResponse
            }

            guard 200..<300 ~= httpResponse.statusCode else {
                throw APIServiceError.serverError(
                    httpResponse.statusCode
                )
            }

            do {

                return try JSONDecoder().decode(
                    T.self,
                    from: data
                )

            } catch {

                print(
                    "❌ Error decodificando respuesta:"
                )

                print(
                    String(
                        data: data,
                        encoding: .utf8
                    ) ?? "Respuesta no legible"
                )

                throw APIServiceError.decodingError
            }

        } catch let error as APIServiceError {

            throw error

        } catch {

            throw APIServiceError.networkError(error)
        }
    }

    // MARK: - Health

    /// Comprueba si el backend responde (timeout corto para no bloquear la UI).
    func isReachable() async -> Bool {
        guard let url = URL(string: "\(baseURL)/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Command

    func sendCommand(
        _ text: String
    ) async throws -> CommandResponse {

        guard let url = URL(
            string: "\(baseURL)/api/command"
        ) else {
            throw APIServiceError.invalidURL
        }

        let requestBody = CommandRequest(
            text: text
        )

        let body: Data

        do {

            body = try JSONEncoder().encode(
                requestBody
            )

        } catch {

            throw APIServiceError.encodingError
        }

        return try await performRequest(
            url: url,
            method: "POST",
            body: body
        )
    }

    // MARK: - Transactions

    func getTransactions() async throws -> [
        BackendTransaction
    ] {

        guard let url = URL(
            string: "\(baseURL)/api/financial/transactions"
        ) else {
            throw APIServiceError.invalidURL
        }

        let response: TransactionsResponse =
            try await performRequest(
                url: url,
                method: "GET"
            )

        return response.transactions
    }

    func addTransaction(
        amount: Double,
        merchant: String,
        category: String,
        isIncome: Bool = false
    ) async throws -> BackendTransaction {

        guard let url = URL(
            string: "\(baseURL)/api/financial/transactions"
        ) else {
            throw APIServiceError.invalidURL
        }

        let requestBody = CreateTransactionRequest(
            amount: amount,
            merchant: merchant,
            category: category,
            isIncome: isIncome
        )

        let body: Data

        do {

            body = try JSONEncoder().encode(
                requestBody
            )

        } catch {

            throw APIServiceError.encodingError
        }

        let response: CreateTransactionResponse =
            try await performRequest(
                url: url,
                method: "POST",
                body: body
            )

        return response.transaction
    }

    func deleteTransaction(
        id: String
    ) async throws -> DeleteTransactionResponse {

        guard let url = URL(
            string:
                "\(baseURL)/api/financial/transactions/\(id)"
        ) else {
            throw APIServiceError.invalidURL
        }

        return try await performRequest(
            url: url,
            method: "DELETE"
        )
    }

    // MARK: - Agenda

    func getEvents() async throws -> [
        BackendEvent
    ] {

        guard let url = URL(
            string: "\(baseURL)/api/agenda/events"
        ) else {
            throw APIServiceError.invalidURL
        }

        let response: EventsResponse =
            try await performRequest(
                url: url,
                method: "GET"
            )

        return response.events
    }

    func addEvent(
        title: String,
        startDate: Date,
        description: String? = nil,
        endDate: Date? = nil
    ) async throws -> BackendEvent {

        guard let url = URL(
            string: "\(baseURL)/api/agenda/events"
        ) else {
            throw APIServiceError.invalidURL
        }

        let requestBody = CreateEventRequest(
            title: title,
            startDate: Self.iso8601String(
                from: startDate
            ),
            description: description,
            endDate: endDate.map {
                Self.iso8601String(from: $0)
            }
        )

        let body: Data

        do {

            body = try JSONEncoder().encode(
                requestBody
            )

        } catch {

            throw APIServiceError.encodingError
        }

        let response: CreateEventResponse =
            try await performRequest(
                url: url,
                method: "POST",
                body: body
            )

        return response.event
    }

    func deleteEvent(
        id: String
    ) async throws -> DeleteEventResponse {

        guard let url = URL(
            string: "\(baseURL)/api/agenda/events/\(id)"
        ) else {
            throw APIServiceError.invalidURL
        }

        return try await performRequest(
            url: url,
            method: "DELETE"
        )
    }

    // MARK: - Tasks

    func getTasks() async throws -> [BackendTask] {
        guard let url = URL(string: "\(baseURL)/api/tasks") else {
            throw APIServiceError.invalidURL
        }
        let response: TasksResponse = try await performRequest(url: url, method: "GET")
        return response.tasks
    }

    func addTask(
        id: String,
        title: String,
        description: String? = nil,
        dueDate: String? = nil,
        priority: String,
        category: String
    ) async throws -> SimpleMessageResponse {
        guard let url = URL(string: "\(baseURL)/api/tasks") else {
            throw APIServiceError.invalidURL
        }
        let requestBody = CreateTaskRequest(
            id: id,
            title: title,
            description: description,
            dueDate: dueDate,
            priority: priority,
            category: category
        )
        let body = try JSONEncoder().encode(requestBody)
        return try await performRequest(url: url, method: "POST", body: body)
    }

    func updateTask(
        id: String,
        title: String,
        priority: String,
        category: String,
        dueDate: String?
    ) async throws {
        guard let url = URL(string: "\(baseURL)/api/tasks/\(id)") else {
            throw APIServiceError.invalidURL
        }
        let requestBody = UpdateTaskRequest(
            title: title,
            priority: priority,
            category: category,
            dueDate: dueDate,
            clearDueDate: dueDate == nil
        )
        let body = try JSONEncoder().encode(requestBody)
        struct UpdateTaskResponse: Codable {}
        let _: UpdateTaskResponse = try await performRequest(url: url, method: "PATCH", body: body)
    }

    func toggleTask(id: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/tasks/\(id)/toggle") else {
            throw APIServiceError.invalidURL
        }
        var patchReq = URLRequest(url: url)
        patchReq.httpMethod = "PATCH"
        patchReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await URLSession.shared.data(for: patchReq)
    }

    func deleteTask(id: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/tasks/\(id)") else {
            throw APIServiceError.invalidURL
        }
        var delReq = URLRequest(url: url)
        delReq.httpMethod = "DELETE"
        _ = try await URLSession.shared.data(for: delReq)
    }

    // MARK: - Savings Goals

    func getGoals() async throws -> [BackendSavingsGoal] {
        guard let url = URL(string: "\(baseURL)/api/financial/goals") else {
            throw APIServiceError.invalidURL
        }
        let response: GoalsResponse = try await performRequest(url: url, method: "GET")
        return response.goals
    }

    func createGoal(
        name: String,
        targetAmount: Double,
        category: String = "general",
        emoji: String = "🎯",
        targetDate: String? = nil
    ) async throws -> BackendSavingsGoal {
        guard let url = URL(string: "\(baseURL)/api/financial/goals") else {
            throw APIServiceError.invalidURL
        }
        let requestBody = CreateGoalRequest(
            name: name,
            targetAmount: targetAmount,
            category: category,
            emoji: emoji,
            targetDate: targetDate
        )
        let body = try JSONEncoder().encode(requestBody)

        struct GoalCreateResponse: Codable {
            let goal: BackendSavingsGoal
            let message: String
        }
        let response: GoalCreateResponse = try await performRequest(url: url, method: "POST", body: body)
        return response.goal
    }

    func depositToGoal(id: String, amount: Double) async throws -> BackendSavingsGoal {
        guard let url = URL(string: "\(baseURL)/api/financial/goals/\(id)/deposit") else {
            throw APIServiceError.invalidURL
        }
        let requestBody = DepositGoalRequest(amount: amount)
        let body = try JSONEncoder().encode(requestBody)

        struct DepositResponse: Codable {
            let goal: BackendSavingsGoal
            let message: String
        }
        let response: DepositResponse = try await performRequest(url: url, method: "PATCH", body: body)
        return response.goal
    }

    func deleteGoal(id: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/financial/goals/\(id)") else {
            throw APIServiceError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        _ = try await URLSession.shared.data(for: req)
    }

    // MARK: - Date Helpers

    static func iso8601String(
        from date: Date
    ) -> String {

        let formatter = ISO8601DateFormatter()

        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]

        return formatter.string(from: date)
    }
}
