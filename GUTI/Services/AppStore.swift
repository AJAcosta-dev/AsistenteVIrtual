import Foundation
import Combine

@MainActor
final class AppStore: ObservableObject {

    // MARK: - Published Data

    @Published var transactions: [Transaction] = []
    @Published var tasks: [GutiTask] = []
    @Published var events: [GutiEvent] = []
    @Published var savingsGoals: [SavingsGoal] = []

    // MARK: - Initialization

    init() {
        loadSampleData()

        Task {
            await refreshAll()
        }
    }

    // MARK: - Finance

    var totalIncome: Double {
        transactions
            .filter { $0.isIncome }
            .reduce(0) { $0 + $1.amount }
    }

    var totalExpenses: Double {
        transactions
            .filter { !$0.isIncome }
            .reduce(0) { $0 + $1.amount }
    }

    var balance: Double {
        totalIncome - totalExpenses
    }

    // MARK: - Transactions

    func addTransaction(
        title: String,
        amount: Double,
        category: TransactionCategory,
        isIncome: Bool = false
    ) async {

        do {

            let backendTransaction =
                try await APIService.shared.addTransaction(
                    amount: amount,
                    merchant: title,
                    category: category.rawValue,
                    isIncome: isIncome
                )

            let transaction =
                convertBackendTransaction(
                    backendTransaction
                )

            transactions.insert(
                transaction,
                at: 0
            )

        } catch {

            print(
                "❌ Error creando transacción: \(error)"
            )
        }
    }

    func deleteTransaction(
        _ transaction: Transaction
    ) async {

        do {

            _ = try await APIService.shared.deleteTransaction(
                id: transaction.id
            )

            transactions.removeAll {
                $0.id == transaction.id
            }

        } catch {

            print(
                "❌ Error eliminando transacción: \(error)"
            )
        }
    }

    func loadTransactionsFromBackend() async {

        do {

            let backendTransactions =
                try await APIService.shared.getTransactions()

            transactions =
                backendTransactions.map {
                    convertBackendTransaction($0)
                }

            print(
                "✅ Transacciones cargadas desde backend: \(transactions.count)"
            )

        } catch {

            print(
                "❌ Error cargando transacciones: \(error)"
            )
        }
    }

    private func convertBackendTransaction(
        _ backend: BackendTransaction
    ) -> Transaction {

        let category =
            backendCategory(
                backend.category
            )

        let date =
            parseBackendDate(
                backend.date
            ) ?? Date()

        return Transaction(
            id: backend.id,
            title: backend.merchant,
            amount: backend.amount,
            category: category,
            date: date,
            isIncome: backend.isIncome
        )
    }

    private func backendCategory(
        _ category: String
    ) -> TransactionCategory {

        switch category
            .lowercased()
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            ) {

        case "alimentación",
             "alimentacion",
             "comida":
            return .food

        case "transporte":
            return .transport

        case "educación",
             "educacion",
             "estudio":
            return .study

        case "entretenimiento":
            return .entertainment

        case "suscripciones",
             "suscripción",
             "suscripcion":
            return .subscriptions

        case "salud":
            return .health

        case "compras":
            return .shopping

        case "servicios",
             "vivienda",
             "ahorro",
             "otros",
             "otro":
            return .other

        default:
            return .other
        }
    }

    // MARK: - Agenda

    var upcomingEvents: [GutiEvent] {

        events
            .filter {
                $0.date >= Date()
            }
            .sorted {
                $0.date < $1.date
            }
    }

    func loadEventsFromBackend() async {

        do {

            let backendEvents =
                try await APIService.shared.getEvents()

            events =
                backendEvents.compactMap {
                    convertBackendEvent($0)
                }

            events.sort {
                $0.date < $1.date
            }

            print(
                "✅ Eventos cargados desde backend: \(events.count)"
            )

        } catch {

            print(
                "❌ Error cargando eventos: \(error)"
            )
        }
    }

    func addEvent(
        title: String,
        startDate: Date,
        description: String? = nil,
        endDate: Date? = nil
    ) async {

        do {

            let backendEvent =
                try await APIService.shared.addEvent(
                    title: title,
                    startDate: startDate,
                    description: description,
                    endDate: endDate
                )

            guard let event =
                    convertBackendEvent(
                        backendEvent
                    )
            else {
                return
            }

            events.append(
                event
            )

            events.sort {
                $0.date < $1.date
            }

            print(
                "✅ Evento creado: \(event.title)"
            )

        } catch {

            print(
                "❌ Error creando evento: \(error)"
            )
        }
    }

    func deleteEvent(
        _ event: GutiEvent
    ) async {

        do {

            _ = try await APIService.shared.deleteEvent(
                id: event.id.uuidString
            )

            events.removeAll {
                $0.id == event.id
            }

            print(
                "✅ Evento eliminado: \(event.title)"
            )

        } catch {

            print(
                "❌ Error eliminando evento: \(error)"
            )
        }
    }

    private func convertBackendEvent(
        _ backend: BackendEvent
    ) -> GutiEvent? {

        guard let startDate =
                parseBackendDate(
                    backend.startDate
                )
        else {

            print(
                "❌ No se pudo interpretar la fecha del evento: \(backend.title)"
            )

            return nil
        }

        // ------------------------------------------------
        // Duración
        // ------------------------------------------------

        var duration = 60

        if let endDateString = backend.endDate,
           let endDate = parseBackendDate(
                endDateString
           ) {

            let seconds =
                endDate.timeIntervalSince(
                    startDate
                )

            let minutes =
                Int(
                    seconds / 60
                )

            if minutes > 0 {
                duration = minutes
            }
        }

        return GutiEvent(
            id:
                UUID(
                    uuidString: backend.id
                ) ?? UUID(),

            title:
                backend.title,

            date:
                startDate,

            duration:
                duration,

            location:
                backend.description,

            isImportant:
                false
        )
    }

    // MARK: - Date Parsing

    private func parseBackendDate(
        _ value: String
    ) -> Date? {

        let isoFormatter =
            ISO8601DateFormatter()

        // ISO con milisegundos

        isoFormatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]

        if let date =
            isoFormatter.date(
                from: value
            ) {

            return date
        }

        // ISO sin milisegundos

        isoFormatter.formatOptions = [
            .withInternetDateTime
        ]

        if let date =
            isoFormatter.date(
                from: value
            ) {

            return date
        }

        // DateFormatter con microsegundos

        let formatter =
            DateFormatter()

        formatter.locale =
            Locale(
                identifier: "en_US_POSIX"
            )

        formatter.timeZone =
            TimeZone(
                secondsFromGMT: 0
            )

        formatter.dateFormat =
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"

        if let date =
            formatter.date(
                from: value
            ) {

            return date
        }

        // DateFormatter normal

        formatter.dateFormat =
            "yyyy-MM-dd'T'HH:mm:ssXXXXX"

        if let date =
            formatter.date(
                from: value
            ) {

            return date
        }

        // Sin timezone

        formatter.dateFormat =
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"

        if let date =
            formatter.date(
                from: value
            ) {

            return date
        }

        return nil
    }

    // MARK: - Tasks

    var pendingTasks: [GutiTask] {

        tasks
            .filter {
                !$0.isCompleted
            }
            .sorted {
                compareTaskDates(
                    $0,
                    $1
                )
            }
    }

    var completedTasks: [GutiTask] {

        tasks
            .filter {
                $0.isCompleted
            }
            .sorted {
                compareTaskDates(
                    $0,
                    $1
                )
            }
    }

    var taskCompletionProgress: Double {

        guard !tasks.isEmpty else {
            return 0
        }

        let completed =
            tasks.filter {
                $0.isCompleted
            }.count

        return Double(completed) /
            Double(tasks.count)
    }

    func refreshAll() async {
        await loadTransactionsFromBackend()
        await loadEventsFromBackend()
        await loadTasksFromBackend()
        await loadGoalsFromBackend()
    }

    func loadTasksFromBackend() async {
        do {
            let backendTasks = try await APIService.shared.getTasks()
            tasks = backendTasks.map { b in
                let dueDate = b.dueDate.flatMap { parseBackendDate($0) }
                return GutiTask(
                    id: UUID(uuidString: b.id) ?? UUID(),
                    title: b.title,
                    category: .personal,
                    dueDate: dueDate,
                    priority: .medium,
                    isCompleted: b.completed
                )
            }
            tasks.sort { compareTaskDates($0, $1) }
            print("✅ Tareas cargadas desde backend: \(tasks.count)")
        } catch {
            print("❌ Error cargando tareas desde backend: \(error)")
        }
    }

    // MARK: - Savings Goals

    func loadGoalsFromBackend() async {
        do {
            let backendGoals = try await APIService.shared.getGoals()
            savingsGoals = backendGoals.map(mapBackendGoal)
            print("✅ Metas de ahorro cargadas: \(savingsGoals.count)")
        } catch {
            print("❌ Error cargando metas de ahorro: \(error)")
        }
    }

    func addGoal(
        name: String,
        targetAmount: Double,
        currentAmount: Double = 0,
        category: String = "general",
        emoji: String = "🎯",
        targetDate: Date? = nil
    ) async {
        let dateString = targetDate.map { formatSimpleDate($0) }

        do {
            let bg = try await APIService.shared.createGoal(
                name: name,
                targetAmount: targetAmount,
                category: category,
                emoji: emoji,
                targetDate: dateString
            )
            let goal = mapBackendGoal(bg)
            savingsGoals.append(goal)

            if currentAmount > 0 {
                await depositToGoal(goalId: goal.id, amount: currentAmount)
            } else {
                print("✅ Meta creada: \(name)")
            }
        } catch {
            let fallbackDate = targetDate ?? Calendar.current.date(
                byAdding: .month, value: 6, to: Date()
            ) ?? Date()

            let goal = SavingsGoal(
                title: name,
                targetAmount: targetAmount,
                currentAmount: min(max(currentAmount, 0), targetAmount),
                targetDate: fallbackDate,
                emoji: emoji,
                category: category
            )
            savingsGoals.append(goal)
            print("⚠️ Meta creada localmente: \(name) — \(error)")
        }
    }

    func depositToGoal(goalId: String, amount: Double) async {
        guard amount > 0,
              let index = savingsGoals.firstIndex(where: { $0.id == goalId }) else {
            return
        }

        savingsGoals[index].currentAmount = min(
            savingsGoals[index].currentAmount + amount,
            savingsGoals[index].targetAmount
        )

        do {
            let updated = try await APIService.shared.depositToGoal(
                id: goalId,
                amount: amount
            )
            if let updatedIndex = savingsGoals.firstIndex(where: { $0.id == goalId }) {
                savingsGoals[updatedIndex].currentAmount = updated.currentAmount
                print("✅ Depósito registrado en '\(savingsGoals[updatedIndex].title)'")
            }
        } catch {
            print("⚠️ Depósito guardado localmente: \(error)")
        }
    }

    func deleteGoal(_ goal: SavingsGoal) async {
        savingsGoals.removeAll { $0.id == goal.id }
        do {
            try await APIService.shared.deleteGoal(id: goal.id)
        } catch {
            print("⚠️ Meta eliminada localmente: \(error)")
        }
    }

    private func mapBackendGoal(_ bg: BackendSavingsGoal) -> SavingsGoal {
        let parsedDate: Date
        if let ds = bg.targetDate, let d = parseSimpleDate(ds) {
            parsedDate = d
        } else {
            parsedDate = Calendar.current.date(
                byAdding: .year, value: 1, to: Date()
            ) ?? Date()
        }

        return SavingsGoal(
            id: bg.id,
            title: bg.name,
            targetAmount: bg.targetAmount,
            currentAmount: bg.currentAmount,
            targetDate: parsedDate,
            emoji: bg.emoji,
            category: bg.category
        )
    }

    private func parseSimpleDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }

    private func formatSimpleDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func addTask(
        title: String,
        category: TaskCategory = .personal,
        dueDate: Date? = nil,
        priority: TaskPriority = .medium
    ) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }

        let task = GutiTask(
            title: cleanTitle,
            category: category,
            dueDate: dueDate,
            priority: priority,
            isCompleted: false
        )

        tasks.append(task)
        tasks.sort { compareTaskDates($0, $1) }

        // Sincronizar en background con Supabase
        Task {
            do {
                _ = try await APIService.shared.addTask(
                    title: cleanTitle,
                    description: nil,
                    dueDate: dueDate.map { APIService.iso8601String(from: $0) }
                )
            } catch {
                print("❌ Error sincronizando tarea en backend: \(error)")
            }
        }
    }

    func toggleTask(_ task: GutiTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isCompleted.toggle()

        Task {
            do {
                try await APIService.shared.toggleTask(id: task.id.uuidString.lowercased())
            } catch {
                print("❌ Error toggling task en backend: \(error)")
            }
        }
    }

    func deleteTask(_ task: GutiTask) {
        tasks.removeAll { $0.id == task.id }

        Task {
            do {
                try await APIService.shared.deleteTask(id: task.id.uuidString.lowercased())
            } catch {
                print("❌ Error eliminando tarea en backend: \(error)")
            }
        }
    }

    private func compareTaskDates(
        _ first: GutiTask,
        _ second: GutiTask
    ) -> Bool {

        // Primero tareas sin completar

        if first.isCompleted != second.isCompleted {
            return !first.isCompleted
        }

        // Después prioridad

        let priorityOrder: [
            TaskPriority: Int
        ] = [
            .high: 0,
            .medium: 1,
            .low: 2
        ]

        let firstPriority =
            priorityOrder[
                first.priority
            ] ?? 1

        let secondPriority =
            priorityOrder[
                second.priority
            ] ?? 1

        if firstPriority != secondPriority {

            return firstPriority <
                secondPriority
        }

        // Después fecha

        switch (
            first.dueDate,
            second.dueDate
        ) {

        case let (
            firstDate?,
            secondDate?
        ):

            return firstDate <
                secondDate

        case (
            _?,
            nil
        ):

            return true

        case (
            nil,
            _?
        ):

            return false

        case (
            nil,
            nil
        ):

            return first.title <
                second.title
        }
    }

    // MARK: - Sample Data

    private func loadSampleData() {

        // ------------------------------------------------
        // Tasks
        // ------------------------------------------------

        tasks = [

            GutiTask(
                title: "Entregar proyecto de GUTI",
                category: .project,
                dueDate:
                    Calendar.current.date(
                        byAdding: .day,
                        value: 2,
                        to: Date()
                    ),
                priority: .high
            ),

            GutiTask(
                title: "Estudiar para el parcial",
                category: .university,
                dueDate:
                    Calendar.current.date(
                        byAdding: .day,
                        value: 4,
                        to: Date()
                    ),
                priority: .medium
            )
        ]

        // ------------------------------------------------
        // Events
        // ------------------------------------------------

        events = [
            GutiEvent(
                title: "Reunión de proyecto",
                date:
                    Calendar.current.date(
                        byAdding: .day,
                        value: 1,
                        to: Date()
                    ) ?? Date(),
                duration: 60
            )
        ]

        // ------------------------------------------------
        // Savings Goals
        // ------------------------------------------------

        savingsGoals = []

        // ------------------------------------------------
        // Transactions
        //
        // Estos datos son solamente fallback mientras
        // se obtiene la información real de Supabase.
        // ------------------------------------------------

        transactions = [

            Transaction(
                title: "Exito",
                amount: 42_500,
                category: .food,
                date: Date(),
                isIncome: false
            )
        ]
    }
}
