import Foundation

// MARK: - Transaction

struct Transaction: Identifiable, Codable {
    let id: String
    var title: String
    var amount: Double
    var category: TransactionCategory
    var date: Date
    var isIncome: Bool
    
    init(
        id: String = UUID().uuidString,
        title: String,
        amount: Double,
        category: TransactionCategory,
        date: Date = Date(),
        isIncome: Bool = false
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.category = category
        self.date = date
        self.isIncome = isIncome
    }
}

enum TransactionCategory: String, CaseIterable, Codable {
    case food = "Comida"
    case transport = "Transporte"
    case study = "Estudio"
    case entertainment = "Entretenimiento"
    case subscriptions = "Suscripciones"
    case health = "Salud"
    case shopping = "Compras"
    case other = "Otros"
    
    var icon: String {
        switch self {
        case .food:
            return "fork.knife"
        case .transport:
            return "tram.fill"
        case .study:
            return "graduationcap.fill"
        case .entertainment:
            return "gamecontroller.fill"
        case .subscriptions:
            return "creditcard.fill"
        case .health:
            return "heart.fill"
        case .shopping:
            return "bag.fill"
        case .other:
            return "ellipsis.circle.fill"
        }
    }
}

// MARK: - Task

struct GutiTask: Identifiable, Codable {
    let id: UUID
    var title: String
    var category: TaskCategory
    var dueDate: Date?
    var priority: TaskPriority
    var isCompleted: Bool
    
    init(
        id: UUID = UUID(),
        title: String,
        category: TaskCategory = .personal,
        dueDate: Date? = nil,
        priority: TaskPriority = .medium,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.dueDate = dueDate
        self.priority = priority
        self.isCompleted = isCompleted
    }
}

enum TaskCategory: String, CaseIterable, Codable {
    case university = "Universidad"
    case work = "Trabajo"
    case personal = "Personal"
    case project = "Proyecto"
}

enum TaskPriority: String, CaseIterable, Codable {
    case low = "Baja"
    case medium = "Media"
    case high = "Alta"
    
    var colorName: String {
        switch self {
        case .low:
            return "gray"
        case .medium:
            return "cyan"
        case .high:
            return "pink"
        }
    }
}

// MARK: - Calendar Event

struct GutiEvent: Identifiable, Codable {
    let id: UUID
    var title: String
    var date: Date
    var duration: Int
    var location: String?
    var isImportant: Bool
    
    init(
        id: UUID = UUID(),
        title: String,
        date: Date,
        duration: Int = 60,
        location: String? = nil,
        isImportant: Bool = false
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.duration = duration
        self.location = location
        self.isImportant = isImportant
    }
}

// MARK: - Savings Goal

struct SavingsGoal: Identifiable, Codable {
    let id: String
    var title: String
    var targetAmount: Double
    var currentAmount: Double
    var targetDate: Date
    var emoji: String
    var category: String
    
    var progress: Double {
        guard targetAmount > 0 else {
            return 0
        }
        
        return min(
            currentAmount / targetAmount,
            1
        )
    }
    
    var remainingAmount: Double {
        max(targetAmount - currentAmount, 0)
    }
    
    var isCompleted: Bool {
        currentAmount >= targetAmount && targetAmount > 0
    }
    
    var iconName: String {
        switch emoji {
        case "💻", "🖥️":
            return "laptopcomputer"
        case "📱":
            return "iphone"
        case "✈️":
            return "airplane"
        case "🏠":
            return "house.fill"
        case "🛡️":
            return "shield.fill"
        case "🎓":
            return "graduationcap.fill"
        case "🚗":
            return "car.fill"
        case "🎮":
            return "gamecontroller.fill"
        case "💰":
            return "banknote"
        default:
            return "target"
        }
    }
    
    init(
        id: String = UUID().uuidString.lowercased(),
        title: String,
        targetAmount: Double,
        currentAmount: Double,
        targetDate: Date,
        emoji: String = "🎯",
        category: String = "general"
    ) {
        self.id = id
        self.title = title
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
        self.targetDate = targetDate
        self.emoji = emoji
        self.category = category
    }
}

// MARK: - Backend Savings Goal (Supabase)

struct BackendSavingsGoal: Codable, Identifiable {
    let id: String
    let name: String
    let targetAmount: Double
    let currentAmount: Double
    let category: String
    let emoji: String
    let targetDate: String?
    let createdAt: String

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(currentAmount / targetAmount, 1.0)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case targetAmount  = "target_amount"
        case currentAmount = "current_amount"
        case category
        case emoji
        case targetDate    = "target_date"
        case createdAt     = "created_at"
    }
}

struct GoalsResponse: Codable {
    let goals: [BackendSavingsGoal]
}

struct CreateGoalRequest: Codable {
    let name: String
    let targetAmount: Double
    let category: String
    let emoji: String
    let targetDate: String?

    enum CodingKeys: String, CodingKey {
        case name
        case targetAmount = "target_amount"
        case category
        case emoji
        case targetDate   = "target_date"
    }
}

struct DepositGoalRequest: Codable {
    let amount: Double
}

