import SwiftUI

struct FinanceView: View {
    
    @EnvironmentObject private var appStore: AppStore
    
    @State private var showingAddTransaction = false
    @State private var showingAllTransactions = false
    @State private var showingAddGoal = false
    @State private var goalForDeposit: SavingsGoal?
    @State private var goalPendingDelete: SavingsGoal?
    
    // MARK: - CURRENT MONTH
    
    private var currentMonthName: String {
        
        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: "es_CO"
        )
        formatter.dateFormat = "MMMM yyyy"
        
        return formatter
            .string(from: Date())
            .capitalized
    }
    
    private var monthTransactions: [Transaction] {
        
        let calendar = Calendar.current
        
        return appStore.transactions.filter {
            calendar.isDate(
                $0.date,
                equalTo: Date(),
                toGranularity: .month
            )
        }
    }
    
    private var expenseTransactions: [Transaction] {
        monthTransactions.filter {
            !$0.isIncome
        }
    }
    
    private var expenseByCategory:
        [(category: TransactionCategory, amount: Double)] {
        
        let grouped = Dictionary(
            grouping: expenseTransactions,
            by: { $0.category }
        )
        
        return grouped
            .map {
                (
                    category: $0.key,
                    amount: $0.value.reduce(0) {
                        $0 + $1.amount
                    }
                )
            }
            .sorted {
                $0.amount > $1.amount
            }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                
                header
                
                Divider()
                    .overlay(
                        Color.white.opacity(0.07)
                    )
                
                balanceCard
                
                monthlyExpensesCard
                
                savingsGoalCard
                
                recentTransactionsCard
                
                Button {
                    showingAddTransaction = true
                } label: {
                    Label(
                        "Nueva Transacción",
                        systemImage: "plus"
                    )
                    .font(
                        .system(
                            size: 17,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        Color.cyanGuti
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 25
                        )
                    )
                }
            }
            .padding(20)
        }
        .background(
            Color.appBackground
                .ignoresSafeArea()
        )
        .sheet(
            isPresented: $showingAddTransaction
        ) {
            AddTransactionView()
                .environmentObject(appStore)
        }
        .sheet(
            isPresented: $showingAllTransactions
        ) {
            AllTransactionsView()
                .environmentObject(appStore)
        }
        .sheet(
            isPresented: $showingAddGoal
        ) {
            AddSavingsGoalView()
                .environmentObject(appStore)
        }
        .sheet(
            item: $goalForDeposit
        ) { goal in
            DepositSavingsGoalView(goal: goal)
                .environmentObject(appStore)
        }
        .confirmationDialog(
            "Eliminar meta",
            isPresented: Binding(
                get: { goalPendingDelete != nil },
                set: { if !$0 { goalPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                if let goal = goalPendingDelete {
                    Task {
                        await appStore.deleteGoal(goal)
                    }
                }
                goalPendingDelete = nil
            }
            Button("Cancelar", role: .cancel) {
                goalPendingDelete = nil
            }
        } message: {
            if let goal = goalPendingDelete {
                Text("Se eliminará “\(goal.title)” y su progreso.")
            }
        }
        .refreshable {
            await appStore.loadTransactionsFromBackend()
            await appStore.loadGoalsFromBackend()
        }
        .onAppear {
            Task {
                await appStore.loadTransactionsFromBackend()
                await appStore.loadGoalsFromBackend()
            }
        }
    }
    
    // MARK: - HEADER
    
    private var header: some View {
        HStack {
            
            VStack(alignment: .leading) {
                
                Text("GUTI")
                    .font(
                        .system(
                            size: 30,
                            weight: .bold
                        )
                    )
                
                Text("FINANZAS")
                    .font(
                        .system(
                            size: 14,
                            weight: .semibold,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(
                        Color.grayGuti
                    )
                
                Text("PERSONALES")
                    .font(
                        .system(
                            size: 14,
                            weight: .semibold,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(
                        Color.grayGuti
                    )
            }
            
            Spacer()
            
            HStack(spacing: 10) {
                
                Image(
                    systemName: "calendar"
                )
                
                Text(currentMonthName)
                    .font(
                        .system(
                            size: 15,
                            weight: .bold
                        )
                    )
            }
            .foregroundStyle(
                Color.grayGuti
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Color.cardGuti
            )
            .clipShape(Capsule())
        }
    }
    
    // MARK: - BALANCE
    
    private var balanceCard: some View {
        VStack(spacing: 18) {
            
            Text("BALANCE DISPONIBLE")
                .font(
                    .system(
                        size: 15,
                        weight: .medium
                    )
                )
                .foregroundStyle(
                    Color.grayGuti
                )
            
            HStack(
                alignment: .lastTextBaseline,
                spacing: 7
            ) {
                
                Text(
                    formatCurrency(
                        appStore.balance
                    )
                )
                .font(
                    .system(
                        size: 43,
                        weight: .bold,
                        design: .monospaced
                    )
                )
                
                Text("COP")
                    .font(
                        .system(
                            size: 17,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        Color.grayGuti
                    )
            }
            
            HStack {
                
                financeValue(
                    title: "Ingresos",
                    value: appStore.totalIncome,
                    color: .green
                )
                
                Divider()
                    .frame(height: 25)
                
                financeValue(
                    title: "Gastos",
                    value: appStore.totalExpenses,
                    color: Color.pinkGuti
                )
            }
            .padding(16)
            .background(
                Color.cardGuti
            )
            .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
    }
    
    // MARK: - MONTHLY EXPENSES
    
    private var monthlyExpensesCard: some View {
        VStack(
            alignment: .leading,
            spacing: 18
        ) {
            
            HStack {
                
                Text("Gastos del Mes")
                    .font(
                        .system(
                            size: 18,
                            weight: .bold
                        )
                    )
                
                Spacer()
                
                Text(
                    formatCurrency(
                        expenseTransactions.reduce(
                            0
                        ) {
                            $0 + $1.amount
                        }
                    ) + " COP"
                )
                .foregroundStyle(
                    Color.grayGuti
                )
                .font(
                    .system(
                        size: 15,
                        weight: .semibold,
                        design: .monospaced
                    )
                )
            }
            
            // BARRA DE CATEGORÍAS
            
            let monthlyExpenseTotal =
                expenseTransactions.reduce(0) {
                    $0 + $1.amount
                }
            
            if monthlyExpenseTotal > 0 {
                
                GeometryReader { geometry in
                    
                    HStack(spacing: 3) {
                        
                        ForEach(
                            expenseByCategory,
                            id: \.category
                        ) { item in
                            
                            Rectangle()
                                .fill(
                                    categoryColor(
                                        item.category
                                    )
                                )
                                .frame(
                                    width:
                                        geometry.size.width
                                        * CGFloat(
                                            item.amount
                                            / monthlyExpenseTotal
                                        )
                                )
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 8)
            }
            
            // CATEGORÍAS
            
            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: 14
            ) {
                
                ForEach(
                    expenseByCategory,
                    id: \.category
                ) { item in
                    
                    expenseItem(
                        category: item.category,
                        amount: item.amount
                    )
                }
            }
        }
        .padding(20)
        .background(
            Color.cardGuti
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 22
            )
        )
    }
    
    // MARK: - SAVINGS GOAL
    
    private var savingsGoalCard: some View {
        
        VStack(spacing: 14) {
            
            if appStore.savingsGoals.isEmpty {
                emptySavingsGoalCard
            } else {
                ForEach(appStore.savingsGoals) { goal in
                    savingsGoalItem(goal)
                }
                
                Button {
                    showingAddGoal = true
                } label: {
                    Label(
                        "Nueva meta",
                        systemImage: "plus"
                    )
                    .font(
                        .system(
                            size: 15,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(Color.purpleGuti)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.cardGuti)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 18)
                    )
                }
            }
        }
    }
    
    private var emptySavingsGoalCard: some View {
        VStack(spacing: 14) {
            
            Image(systemName: "target")
                .font(.system(size: 30))
                .foregroundStyle(Color.purpleGuti)
            
            Text("Crea tu primera meta de ahorro")
                .font(
                    .system(
                        size: 16,
                        weight: .semibold
                    )
                )
            
            Text("Define un objetivo y ve subiendo el progreso.")
                .font(.system(size: 13))
                .foregroundStyle(Color.grayGuti)
                .multilineTextAlignment(.center)
            
            Button {
                showingAddGoal = true
            } label: {
                Text("Nueva meta")
                    .font(
                        .system(
                            size: 15,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(.black)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Color.cyanGuti)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color.cardGuti)
        .clipShape(
            RoundedRectangle(cornerRadius: 22)
        )
    }
    
    private func savingsGoalItem(
        _ goal: SavingsGoal
    ) -> some View {
        
        VStack(
            alignment: .leading,
            spacing: 15
        ) {
            
            HStack {
                
                Image(
                    systemName: goal.iconName
                )
                .font(
                    .system(size: 25)
                )
                .foregroundStyle(
                    Color.purpleGuti
                )
                .frame(
                    width: 55,
                    height: 55
                )
                .background(
                    Color.purpleGuti.opacity(0.15)
                )
                .clipShape(Circle())
                
                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    
                    Text(goal.title)
                        .font(
                            .system(
                                size: 18,
                                weight: .bold
                            )
                        )
                    
                    Text(
                        goal.isCompleted
                        ? "¡Meta alcanzada!"
                        : "Meta de ahorro"
                    )
                    .foregroundStyle(
                        goal.isCompleted
                        ? Color.cyanGuti
                        : Color.grayGuti
                    )
                }
                
                Spacer()
                
                Text(
                    "\(Int(goal.progress * 100))%"
                )
                .font(
                    .system(
                        size: 20,
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    Color.purpleGuti
                )
            }
            
            ProgressView(
                value: goal.progress
            )
            .tint(
                LinearGradient(
                    colors: [
                        Color.cyanGuti,
                        Color.purpleGuti
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            
            HStack {
                
                Text(
                    formatCurrency(
                        goal.currentAmount
                    )
                )
                
                Spacer()
                
                Text(
                    "Meta: \(formatCurrency(goal.targetAmount))"
                )
            }
            .font(
                .system(
                    size: 13,
                    weight: .semibold,
                    design: .monospaced
                )
            )
            .foregroundStyle(
                Color.grayGuti
            )
            
            if !goal.isCompleted {
                HStack {
                    Text(
                        "Faltan \(formatCurrency(goal.remainingAmount))"
                    )
                    .font(
                        .system(
                            size: 12,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(Color.grayGuti)
                    
                    Spacer()
                    
                    Button {
                        goalForDeposit = goal
                    } label: {
                        Text("Ahorrar")
                            .font(
                                .system(
                                    size: 14,
                                    weight: .bold
                                )
                            )
                            .foregroundStyle(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.cyanGuti)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(20)
        .background(
            Color.cardGuti
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 22
            )
        )
        .contextMenu {
            if !goal.isCompleted {
                Button {
                    goalForDeposit = goal
                } label: {
                    Label("Ahorrar", systemImage: "plus.circle")
                }
            }
            
            Button(role: .destructive) {
                goalPendingDelete = goal
            } label: {
                Label("Eliminar meta", systemImage: "trash")
            }
        }
    }
    
    // MARK: - RECENT TRANSACTIONS
    
    private var recentTransactionsCard: some View {
        VStack(
            alignment: .leading,
            spacing: 15
        ) {
            
            HStack {
                
                Text("Movimientos Recientes")
                    .font(
                        .system(
                            size: 18,
                            weight: .bold
                        )
                    )
                
                Spacer()
                
                Button {
                    showingAllTransactions = true
                } label: {
                    Text("Ver todos")
                        .foregroundStyle(
                            Color.cyanGuti
                        )
                }
            }
            
            if monthTransactions.isEmpty {
                
                VStack(spacing: 10) {
                    
                    Image(
                        systemName: "tray"
                    )
                    .font(
                        .system(size: 30)
                    )
                    .foregroundStyle(
                        Color.grayGuti
                    )
                    
                    Text(
                        "No hay movimientos todavía"
                    )
                    .foregroundStyle(
                        Color.grayGuti
                    )
                }
                .frame(
                    maxWidth: .infinity
                )
                .padding(.vertical, 20)
                
            } else {
                
                ForEach(
                    Array(
                        monthTransactions.prefix(5)
                    )
                ) { transaction in
                    
                    transactionRow(
                        transaction
                    )
                }
            }
        }
        .padding(20)
        .background(
            Color.cardGuti
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 22
            )
        )
    }
    
    // MARK: - TRANSACTION ROW
    
    private func transactionRow(
        _ transaction: Transaction
    ) -> some View {
        
        HStack(spacing: 15) {
            
            Image(
                systemName:
                    transaction.category.icon
            )
            .foregroundStyle(
                transaction.isIncome
                ? .green
                : Color.cyanGuti
            )
            .frame(
                width: 45,
                height: 45
            )
            .background(
                Color.white.opacity(0.06)
            )
            .clipShape(Circle())
            
            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                
                Text(transaction.title)
                    .font(
                        .system(
                            size: 15,
                            weight: .semibold
                        )
                    )
                
                Text(
                    transactionDate(
                        transaction.date
                    )
                )
                .font(
                    .system(size: 12)
                )
                .foregroundStyle(
                    Color.grayGuti
                )
            }
            
            Spacer()
            
            Text(
                transaction.isIncome
                ? "+\(formatCurrency(transaction.amount))"
                : "-\(formatCurrency(transaction.amount))"
            )
            .font(
                .system(
                    size: 14,
                    weight: .bold,
                    design: .monospaced
                )
            )
            .foregroundStyle(
                transaction.isIncome
                ? .green
                : Color.pinkGuti
            )
        }
    }
    
    // MARK: - FINANCE VALUE
    
    private func financeValue(
        title: String,
        value: Double,
        color: Color
    ) -> some View {
        
        HStack {
            
            Circle()
                .fill(color)
                .frame(
                    width: 9,
                    height: 9
                )
            
            // Título arriba y monto abajo: los montos en millones no caben en una línea.
            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(title)
                    .font(
                        .system(size: 12)
                    )
                    .foregroundStyle(
                        Color.grayGuti
                    )
                
                Text(
                    formatCurrency(value)
                )
                .font(
                    .system(
                        size: 15,
                        weight: .bold,
                        design: .monospaced
                    )
                )
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            
            Spacer(minLength: 0)
        }
    }
    
    // MARK: - EXPENSE ITEM
    
    private func expenseItem(
        category: TransactionCategory,
        amount: Double
    ) -> some View {
        
        HStack {
            
            Circle()
                .fill(
                    categoryColor(category)
                )
                .frame(
                    width: 10,
                    height: 10
                )
            
            Text(category.shortName)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            
            Spacer(minLength: 4)
            
            Text(
                formatCurrency(amount)
            )
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(
                Color.grayGuti
            )
            .font(
                .system(
                    size: 13,
                    design: .monospaced
                )
            )
        }
        .font(
            .system(size: 14)
        )
    }
    
    // MARK: - HELPERS
    
    private func formatCurrency(
        _ value: Double
    ) -> String {
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(
            identifier: "es_CO"
        )
        formatter.maximumFractionDigits = 0
        
        return "$" + (
            formatter.string(
                from: NSNumber(
                    value: value
                )
            ) ?? "0"
        )
    }
    
    private func transactionDate(
        _ date: Date
    ) -> String {
        
        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: "es_CO"
        )
        
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "'Hoy,' HH:mm"
        } else if Calendar.current.isDateInYesterday(date) {
            formatter.dateFormat = "'Ayer'"
        } else {
            formatter.dateFormat = "dd MMM, HH:mm"
        }
        
        return formatter.string(
            from: date
        )
    }
    
    private func categoryColor(
        _ category: TransactionCategory
    ) -> Color {
        
        switch category {
        case .food:
            return Color.cyanGuti
            
        case .transport:
            return Color.purpleGuti
            
        case .study:
            return .yellow
            
        case .entertainment:
            return .blue
            
        case .subscriptions:
            return Color.pinkGuti
            
        case .health:
            return .green
            
        case .shopping:
            return .orange
            
        case .other:
            return Color.grayGuti
        }
    }
}


// MARK: - ADD TRANSACTION

struct AddTransactionView: View {
    
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var title = ""
    @State private var amount = ""
    @State private var category: TransactionCategory = .food
    @State private var isIncome = false
    
    private var parsedAmount: Double? {
        parseAmount(amount)
    }
    
    var body: some View {
        NavigationStack {
            
            Form {
                
                Section("Tipo") {
                    
                    Picker(
                        "Movimiento",
                        selection: $isIncome
                    ) {
                        
                        Text("Gasto")
                            .tag(false)
                        
                        Text("Ingreso")
                            .tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("Información") {
                    
                    TextField(
                        "Descripción",
                        text: $title
                    )
                    
                    TextField(
                        "Valor",
                        text: $amount
                    )
                    .keyboardType(
                        .decimalPad
                    )
                    
                    Picker(
                        "Categoría",
                        selection: $category
                    ) {
                        
                        ForEach(
                            TransactionCategory.allCases,
                            id: \.self
                        ) { category in
                            
                            Label(
                                category.rawValue,
                                systemImage:
                                    category.icon
                            )
                            .tag(category)
                        }
                    }
                }
                
                if let parsedAmount {
                    
                    Section("Vista previa") {
                        
                        HStack {
                            
                            Text(
                                isIncome
                                ? "Ingreso"
                                : "Gasto"
                            )
                            
                            Spacer()
                            
                            Text(
                                isIncome
                                ? "+\(formatPreview(parsedAmount))"
                                : "-\(formatPreview(parsedAmount))"
                            )
                            .foregroundStyle(
                                isIncome
                                ? .green
                                : Color.pinkGuti
                            )
                        }
                    }
                }
            }
            .navigationTitle(
                "Nueva Transacción"
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    
                    Button("Cancelar") {
                        dismiss()
                    }
                }
                
                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {
                    
                    Button("Guardar") {
                        saveTransaction()
                    }
                    .disabled(
                        title
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .isEmpty
                        || parsedAmount == nil
                        || parsedAmount == 0
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func saveTransaction() {
        
        guard let value = parsedAmount,
              value > 0 else {
            return
        }
        
        Task {
            await appStore.addTransaction(
                title: title
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                amount: value,
                category: category,
                isIncome: isIncome
            )
        }
        
        dismiss()
    }
    
    private func parseAmount(
        _ text: String
    ) -> Double? {
        
        let cleaned = text
            .replacingOccurrences(
                of: ".",
                with: ""
            )
            .replacingOccurrences(
                of: ",",
                with: "."
            )
        
        return Double(cleaned)
    }
    
    private func formatPreview(
        _ value: Double
    ) -> String {
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(
            identifier: "es_CO"
        )
        formatter.maximumFractionDigits = 0
        
        return "$" + (
            formatter.string(
                from: NSNumber(
                    value: value
                )
            ) ?? "0"
        )
    }
}


// MARK: - ALL TRANSACTIONS

struct AllTransactionsView: View {
    
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        
        NavigationStack {
            
            List {
                
                if appStore.transactions.isEmpty {
                    
                    ContentUnavailableView(
                        "Sin movimientos",
                        systemImage: "tray",
                        description: Text(
                            "Todavía no has registrado movimientos."
                        )
                    )
                    
                } else {
                    
                    ForEach(
                        appStore.transactions
                    ) { transaction in
                        
                        HStack(spacing: 15) {
                            
                            Image(
                                systemName:
                                    transaction.category.icon
                            )
                            .frame(
                                width: 40,
                                height: 40
                            )
                            .background(
                                Color.white.opacity(0.06)
                            )
                            .clipShape(Circle())
                            
                            VStack(
                                alignment: .leading,
                                spacing: 4
                            ) {
                                
                                Text(
                                    transaction.title
                                )
                                .font(
                                    .system(
                                        size: 15,
                                        weight: .semibold
                                    )
                                )
                                
                                Text(
                                    transaction.category.rawValue
                                )
                                .font(
                                    .system(size: 12)
                                )
                                .foregroundStyle(
                                    Color.grayGuti
                                )
                            }
                            
                            Spacer()
                            
                            Text(
                                transaction.isIncome
                                ? "+\(formatCurrency(transaction.amount))"
                                : "-\(formatCurrency(transaction.amount))"
                            )
                            .foregroundStyle(
                                transaction.isIncome
                                ? .green
                                : Color.pinkGuti
                            )
                        }
                        .padding(.vertical, 5)
                    }
                    .onDelete { indexSet in
                        
                        for index in indexSet {
                            
                            let transaction =
                                appStore.transactions[index]
                            
                            Task {
                                await appStore.deleteTransaction(
                                    transaction
                                )
                            }
                        }
                    }
                }
            }
            .navigationTitle(
                "Movimientos"
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                
                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {
                    
                    Button("Cerrar") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func formatCurrency(
        _ value: Double
    ) -> String {
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(
            identifier: "es_CO"
        )
        formatter.maximumFractionDigits = 0
        
        return "$" + (
            formatter.string(
                from: NSNumber(
                    value: value
                )
            ) ?? "0"
        )
    }
}


// MARK: - ADD SAVINGS GOAL

private struct GoalEmojiOption: Identifiable {
    let emoji: String
    let category: String
    var id: String { emoji }
}

struct AddSavingsGoalView: View {
    
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var title = ""
    @State private var targetAmount = ""
    @State private var currentAmount = ""
    @State private var selectedEmoji = "📱"
    @State private var targetDate = Calendar.current.date(
        byAdding: .month,
        value: 6,
        to: Date()
    ) ?? Date()
    
    private let emojiOptions: [GoalEmojiOption] = [
        GoalEmojiOption(emoji: "📱", category: "tecnologia"),
        GoalEmojiOption(emoji: "💻", category: "tecnologia"),
        GoalEmojiOption(emoji: "✈️", category: "viaje"),
        GoalEmojiOption(emoji: "🛡️", category: "seguridad"),
        GoalEmojiOption(emoji: "🎓", category: "educacion"),
        GoalEmojiOption(emoji: "🏠", category: "vivienda"),
        GoalEmojiOption(emoji: "🚗", category: "transporte"),
        GoalEmojiOption(emoji: "🎮", category: "entretenimiento"),
        GoalEmojiOption(emoji: "💰", category: "general"),
        GoalEmojiOption(emoji: "🎯", category: "general")
    ]
    
    private var parsedTarget: Double? {
        parseAmount(targetAmount)
    }
    
    private var parsedCurrent: Double {
        parseAmount(currentAmount) ?? 0
    }
    
    private var selectedCategory: String {
        emojiOptions.first {
            $0.emoji == selectedEmoji
        }?.category ?? "general"
    }
    
    var body: some View {
        NavigationStack {
            
            Form {
                
                Section("Meta") {
                    
                    TextField(
                        "Ej: Nuevo iPhone",
                        text: $title
                    )
                    
                    TextField(
                        "Valor objetivo",
                        text: $targetAmount
                    )
                    .keyboardType(.decimalPad)
                    
                    TextField(
                        "Ya ahorrado (opcional)",
                        text: $currentAmount
                    )
                    .keyboardType(.decimalPad)
                    
                    DatePicker(
                        "Fecha objetivo",
                        selection: $targetDate,
                        in: Date()...,
                        displayedComponents: .date
                    )
                }
                
                Section("Ícono") {
                    
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible()),
                            count: 5
                        ),
                        spacing: 12
                    ) {
                        
                        ForEach(emojiOptions) { option in
                            
                            Text(option.emoji)
                                .font(.system(size: 28))
                                .frame(
                                    width: 48,
                                    height: 48
                                )
                                .background(
                                    selectedEmoji == option.emoji
                                    ? Color.purpleGuti.opacity(0.25)
                                    : Color.white.opacity(0.05)
                                )
                                .clipShape(Circle())
                                .onTapGesture {
                                    selectedEmoji = option.emoji
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                if let parsedTarget, parsedTarget > 0 {
                    
                    Section("Vista previa") {
                        
                        HStack {
                            Text("Progreso inicial")
                            Spacer()
                            Text(
                                "\(Int(min(parsedCurrent / parsedTarget, 1) * 100))%"
                            )
                            .foregroundStyle(Color.purpleGuti)
                            .fontWeight(.bold)
                        }
                    }
                }
            }
            .navigationTitle("Nueva meta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        saveGoal()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private var canSave: Bool {
        !title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        && (parsedTarget ?? 0) > 0
        && parsedCurrent >= 0
        && parsedCurrent <= (parsedTarget ?? 0)
    }
    
    private func saveGoal() {
        
        guard let target = parsedTarget, target > 0 else {
            return
        }
        
        Task {
            await appStore.addGoal(
                name: title.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
                targetAmount: target,
                currentAmount: parsedCurrent,
                category: selectedCategory,
                emoji: selectedEmoji,
                targetDate: targetDate
            )
        }
        
        dismiss()
    }
    
    private func parseAmount(
        _ text: String
    ) -> Double? {
        
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !cleaned.isEmpty else {
            return nil
        }
        
        let normalized = cleaned
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
        
        return Double(normalized)
    }
}


// MARK: - DEPOSIT TO GOAL

struct DepositSavingsGoalView: View {
    
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss
    
    let goal: SavingsGoal
    
    @State private var amount = ""
    
    private var parsedAmount: Double? {
        parseAmount(amount)
    }
    
    private var liveGoal: SavingsGoal {
        appStore.savingsGoals.first {
            $0.id == goal.id
        } ?? goal
    }
    
    var body: some View {
        NavigationStack {
            
            Form {
                
                Section("Meta") {
                    HStack {
                        Text(liveGoal.emoji)
                            .font(.system(size: 28))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(liveGoal.title)
                                .fontWeight(.semibold)
                            Text(
                                "\(formatCurrency(liveGoal.currentAmount)) de \(formatCurrency(liveGoal.targetAmount))"
                            )
                            .font(.caption)
                            .foregroundStyle(Color.grayGuti)
                        }
                    }
                    
                    ProgressView(value: liveGoal.progress)
                        .tint(Color.purpleGuti)
                }
                
                Section("¿Cuánto vas a ahorrar?") {
                    
                    TextField(
                        "Valor",
                        text: $amount
                    )
                    .keyboardType(.decimalPad)
                }
                
                if let parsedAmount, parsedAmount > 0 {
                    
                    Section("Resultado") {
                        
                        let nextAmount = min(
                            liveGoal.currentAmount + parsedAmount,
                            liveGoal.targetAmount
                        )
                        let nextProgress = liveGoal.targetAmount > 0
                            ? nextAmount / liveGoal.targetAmount
                            : 0
                        
                        HStack {
                            Text("Nuevo total")
                            Spacer()
                            Text(formatCurrency(nextAmount))
                                .fontWeight(.bold)
                        }
                        
                        HStack {
                            Text("Progreso")
                            Spacer()
                            Text("\(Int(nextProgress * 100))%")
                                .foregroundStyle(Color.purpleGuti)
                                .fontWeight(.bold)
                        }
                    }
                }
            }
            .navigationTitle("Ahorrar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        saveDeposit()
                    }
                    .disabled(
                        parsedAmount == nil
                        || parsedAmount == 0
                        || liveGoal.isCompleted
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func saveDeposit() {
        
        guard let value = parsedAmount, value > 0 else {
            return
        }
        
        Task {
            await appStore.depositToGoal(
                goalId: liveGoal.id,
                amount: value
            )
        }
        
        dismiss()
    }
    
    private func parseAmount(
        _ text: String
    ) -> Double? {
        
        let cleaned = text
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
        
        return Double(cleaned)
    }
    
    private func formatCurrency(
        _ value: Double
    ) -> String {
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "es_CO")
        formatter.maximumFractionDigits = 0
        
        return "$" + (
            formatter.string(from: NSNumber(value: value)) ?? "0"
        )
    }
}
