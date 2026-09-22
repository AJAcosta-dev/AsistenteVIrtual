import SwiftUI

struct DashboardView: View {
    
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var chat: ChatSession
    @Binding var selectedTab: Int
    
    @State private var showingAddTransaction = false
    @State private var showingAddTask = false
    @State private var showingAddEvent = false
    
    @State private var glasses = 7
    
    // MARK: - Computed Data
    
    private var todayEvents: [GutiEvent] {
        appStore.events
            .filter {
                Calendar.current.isDateInToday($0.date)
            }
            .sorted {
                $0.date < $1.date
            }
    }
    
    private var urgentTask: GutiTask? {
        appStore.pendingTasks
            .filter {
                $0.priority == .high
            }
            .sorted {
                compareTaskDates($0, $1)
            }
            .first
    }
    
    private var nextEvent: GutiEvent? {
        appStore.upcomingEvents.first
    }
    
    private var highPriorityTasks: Int {
        appStore.pendingTasks.filter {
            $0.priority == .high
        }.count
    }
    
    private var greeting: String {
        let hour = Calendar.current.component(
            .hour,
            from: Date()
        )
        
        switch hour {
        case 5..<12:
            return "Buenos días"
        case 12..<19:
            return "Buenas tardes"
        default:
            return "Buenas noches"
        }
    }
    
    // MARK: - BODY
    
    var body: some View {
        ZStack {
            
            Color.appBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                
                // MARK: HEADER
                
                header
                
                // MARK: CONTENT
                
                ScrollView {
                    VStack(
                        alignment: .leading,
                        spacing: 22
                    ) {
                        
                        greetingSection
                        
                        gutiSection
                        
                        priorityCard
                        
                        HStack(spacing: 14) {
                            financeCard
                            tasksCard
                        }
                        
                        quickActions
                        
                        agendaCard
                        
                        wellnessCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 30)
                }
            }
        }
        .preferredColorScheme(.dark)
        
        // MARK: SHEETS
        
        .sheet(
            isPresented: $showingAddTransaction
        ) {
            AddTransactionView()
                .environmentObject(appStore)
        }
        
        .sheet(
            isPresented: $showingAddTask
        ) {
            TaskEditorView()
                .environmentObject(appStore)
        }
        
        .sheet(
            isPresented: $showingAddEvent
        ) {
            EventEditorView()
                .environmentObject(appStore)
        }
        .refreshable {
            await appStore.refreshAll()
        }
        .onAppear {
            Task {
                await appStore.refreshAll()
            }
        }
    }
    
    // MARK: - GREETING
    
    private var greetingSection: some View {
        VStack(
            alignment: .leading,
            spacing: 5
        ) {
            
            Text("\(greeting), Jacobo")
                .font(
                    .system(
                        size: 28,
                        weight: .bold
                    )
                )
                .foregroundStyle(.white)
            
            Text(
                "\(formattedToday()) • \(todayEvents.count) " +
                (
                    todayEvents.count == 1
                    ? "evento hoy"
                    : "eventos hoy"
                )
            )
            .font(
                .system(size: 15)
            )
            .foregroundStyle(
                Color.grayGuti
            )
        }
    }
    
    // MARK: - HEADER
    
    private var header: some View {
        HStack {
            
            HStack(spacing: 10) {
                
                ZStack {
                    
                    RoundedRectangle(
                        cornerRadius: 9
                    )
                    .fill(
                        Color.cardGuti
                    )
                    .frame(
                        width: 38,
                        height: 38
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 9
                        )
                        .stroke(
                            Color.cyanGuti.opacity(0.4),
                            lineWidth: 1
                        )
                    }
                    
                    Image(systemName: "cpu")
                        .foregroundStyle(
                            Color.cyanGuti
                        )
                }
                
                HStack(spacing: 6) {
                    
                    Text("GUTI")
                        .font(
                            .system(
                                size: 17,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(.white)
                    
                    Circle()
                        .fill(
                            appStore.connection == .offline
                            ? Color.pinkGuti
                            : Color.cyanGuti
                        )
                        .frame(
                            width: 7,
                            height: 7
                        )
                        .accessibilityLabel(
                            appStore.connection == .offline
                            ? "Sin conexión"
                            : "En línea"
                        )
                }
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                
                ZStack(alignment: .topTrailing) {
                    
                    Circle()
                        .fill(
                            Color.cardGuti
                        )
                        .frame(
                            width: 40,
                            height: 40
                        )
                    
                    Image(systemName: "bell")
                        .foregroundStyle(
                            Color.grayGuti
                        )
                    
                    if highPriorityTasks > 0 {
                        Circle()
                            .fill(
                                Color.cyanGuti
                            )
                            .frame(
                                width: 7,
                                height: 7
                            )
                            .offset(
                                x: -8,
                                y: 8
                            )
                    }
                }
                
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.cyanGuti.opacity(0.6),
                                Color.purpleGuti.opacity(0.6)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(
                        width: 40,
                        height: 40
                    )
                    .overlay {
                        Image(
                            systemName: "person.fill"
                        )
                        .foregroundStyle(.white)
                    }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Color.appBackground.opacity(0.95)
        )
    }
    
    // MARK: - PRIORITY CARD
    
    private var priorityCard: some View {
        
        Group {
            
            if let task = urgentTask {
                
                VStack(
                    alignment: .leading,
                    spacing: 18
                ) {
                    
                    HStack {
                        
                        Label(
                            "TAREA PRIORITARIA",
                            systemImage: "circle.fill"
                        )
                        .font(
                            .system(
                                size: 11,
                                weight: .medium,
                                design: .monospaced
                            )
                        )
                        .foregroundStyle(
                            Color.pinkGuti
                        )
                        .padding(
                            .horizontal,
                            10
                        )
                        .padding(
                            .vertical,
                            7
                        )
                        .background(
                            Color.pinkGuti.opacity(0.1)
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 7
                            )
                        )
                        
                        Spacer()
                        
                        Text(
                            task.category.rawValue
                        )
                        .font(
                            .system(size: 12)
                        )
                        .foregroundStyle(
                            Color.grayGuti
                        )
                    }
                    
                    VStack(
                        alignment: .leading,
                        spacing: 5
                    ) {
                        
                        Text(task.title)
                            .font(
                                .system(
                                    size: 21,
                                    weight: .bold
                                )
                            )
                            .foregroundStyle(.white)
                        
                        if let dueDate = task.dueDate {
                            
                            Text(
                                dueDateDescription(
                                    dueDate
                                )
                            )
                            .font(
                                .system(size: 15)
                            )
                            .foregroundStyle(
                                Color.grayGuti
                            )
                            
                        } else {
                            
                            Text("Sin fecha límite")
                                .font(
                                    .system(size: 15)
                                )
                                .foregroundStyle(
                                    Color.grayGuti
                                )
                        }
                    }
                    
                    HStack {
                        
                        VStack(
                            alignment: .leading,
                            spacing: 5
                        ) {
                            
                            Text("PRIORIDAD")
                                .font(
                                    .system(
                                        size: 11,
                                        weight: .medium,
                                        design: .monospaced
                                    )
                                )
                                .foregroundStyle(
                                    Color.grayGuti
                                )
                            
                            Text(
                                task.priority.rawValue
                                    .uppercased()
                            )
                            .font(
                                .system(
                                    size: 17,
                                    weight: .bold
                                )
                            )
                            .foregroundStyle(
                                Color.pinkGuti
                            )
                        }
                        
                        Spacer()
                        
                        Button {
                            withAnimation {
                                appStore.toggleTask(task)
                            }
                        } label: {
                            
                            Label(
                                "Completar",
                                systemImage: "checkmark"
                            )
                            .font(
                                .system(
                                    size: 14,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(
                                Color.appBackground
                            )
                            .padding(
                                .horizontal,
                                15
                            )
                            .padding(
                                .vertical,
                                13
                            )
                            .background(
                                Color.cyanGuti
                            )
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 13
                                )
                            )
                        }
                    }
                }
                .padding(20)
                .background(
                    LinearGradient(
                        colors: [
                            Color(
                                red: 0.075,
                                green: 0.105,
                                blue: 0.17
                            ),
                            Color.cardGuti
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 22
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 22
                    )
                    .stroke(
                        Color.white.opacity(0.08),
                        lineWidth: 1
                    )
                }
                
            } else {
                
                emptyPriorityCard
            }
        }
    }
    
    private var emptyPriorityCard: some View {
        HStack(spacing: 15) {
            
            Image(
                systemName: "checkmark.seal.fill"
            )
            .font(
                .system(size: 32)
            )
            .foregroundStyle(
                Color.cyanGuti
            )
            
            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                
                Text("Todo bajo control")
                    .font(
                        .system(
                            size: 18,
                            weight: .bold
                        )
                    )
                
                Text(
                    "No tienes tareas de alta prioridad pendientes."
                )
                .font(
                    .system(size: 13)
                )
                .foregroundStyle(
                    Color.grayGuti
                )
            }
            
            Spacer()
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
    
    // MARK: - FINANCE CARD
    
    private var financeCard: some View {
        VStack(
            alignment: .leading,
            spacing: 15
        ) {
            
            HStack {
                
                Text("Finanzas")
                    .foregroundStyle(
                        Color.grayGuti
                    )
                
                Spacer()
                
                Image(
                    systemName: "wallet.pass"
                )
                .foregroundStyle(
                    Color.cyanGuti
                )
            }
            .font(
                .system(
                    size: 13,
                    weight: .medium
                )
            )
            
            Text(
                formatCurrency(
                    appStore.balance
                )
            )
            .font(
                .system(
                    size: 20,
                    weight: .bold,
                    design: .monospaced
                )
            )
            .foregroundStyle(.white)
            
            Text("Balance disponible")
                .font(
                    .system(size: 12)
                )
                .foregroundStyle(
                    Color.grayGuti
                )
            
            Spacer()
            
            VStack(
                alignment: .leading,
                spacing: 7
            ) {
                
                HStack {
                    Text("Ingresos")
                    
                    Spacer()
                    
                    Text(
                        formatCurrency(
                            appStore.totalIncome
                        )
                    )
                    .foregroundStyle(.green)
                }
                
                HStack {
                    Text("Gastos")
                    
                    Spacer()
                    
                    Text(
                        formatCurrency(
                            appStore.totalExpenses
                        )
                    )
                    .foregroundStyle(
                        Color.pinkGuti
                    )
                }
            }
            .font(
                .system(
                    size: 11,
                    weight: .semibold,
                    design: .monospaced
                )
            )
            .foregroundStyle(
                Color.grayGuti
            )
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 170
        )
        .padding(18)
        .background(
            Color.cardGuti
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 20
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20
            )
            .stroke(
                Color.white.opacity(0.06),
                lineWidth: 1
            )
        }
    }
    
    // MARK: - TASKS CARD
    
    private var tasksCard: some View {
        VStack(
            alignment: .leading,
            spacing: 15
        ) {
            
            HStack {
                
                Text("Tareas")
                    .foregroundStyle(
                        Color.grayGuti
                    )
                
                Spacer()
                
                Image(
                    systemName: "checkmark.circle"
                )
                .foregroundStyle(
                    Color.purpleGuti
                )
            }
            .font(
                .system(
                    size: 13,
                    weight: .medium
                )
            )
            
            Text(
                "\(appStore.pendingTasks.count)"
            )
            .font(
                .system(
                    size: 25,
                    weight: .bold,
                    design: .monospaced
                )
            )
            .foregroundStyle(.white)
            
            Text(
                appStore.pendingTasks.count == 1
                ? "tarea pendiente"
                : "tareas pendientes"
            )
            .font(
                .system(size: 12)
            )
            .foregroundStyle(
                Color.grayGuti
            )
            
            Spacer()
            
            HStack {
                
                GeometryReader { geometry in
                    
                    ZStack(
                        alignment: .leading
                    ) {
                        
                        Capsule()
                            .fill(
                                Color.white.opacity(0.1)
                            )
                        
                        Capsule()
                            .fill(
                                Color.purpleGuti
                            )
                            .frame(
                                width:
                                    geometry.size.width
                                    * appStore.taskCompletionProgress
                            )
                    }
                }
                .frame(height: 7)
                
                Text(
                    "\(Int(appStore.taskCompletionProgress * 100))%"
                )
                .font(
                    .system(
                        size: 11,
                        design: .monospaced
                    )
                )
                .foregroundStyle(
                    Color.grayGuti
                )
            }
            
            Text(
                "\(appStore.completedTasks.count) completadas"
            )
            .font(
                .system(size: 11)
            )
            .foregroundStyle(
                Color.grayGuti
            )
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 170
        )
        .padding(18)
        .background(
            Color.cardGuti
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 20
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20
            )
            .stroke(
                Color.white.opacity(0.06),
                lineWidth: 1
            )
        }
    }
    
    // MARK: - QUICK ACTIONS
    
    private var quickActions: some View {
        HStack(spacing: 14) {
            
            quickAction(
                icon: "banknote",
                title: "+ Gasto",
                color: Color.cyanGuti
            ) {
                showingAddTransaction = true
            }
            
            quickAction(
                icon: "checkmark.circle",
                title: "+ Tarea",
                color: Color.purpleGuti
            ) {
                showingAddTask = true
            }
            
            quickAction(
                icon: "calendar",
                title: "+ Evento",
                color: .white
            ) {
                showingAddEvent = true
            }
        }
    }
    
    private func quickAction(
        icon: String,
        title: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        
        Button {
            action()
        } label: {
            
            VStack(spacing: 9) {
                
                Image(
                    systemName: icon
                )
                .font(
                    .system(
                        size: 20,
                        weight: .semibold
                    )
                )
                .foregroundStyle(color)
                .frame(
                    width: 42,
                    height: 42
                )
                .background(
                    color.opacity(0.1)
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 10
                    )
                )
                
                Text(title)
                    .font(
                        .system(
                            size: 12,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(.white)
            }
            .frame(
                maxWidth: .infinity
            )
            .padding(.vertical, 18)
            .background(
                Color.cardGuti
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 15
                )
            )
        }
    }
    
    // MARK: - AGENDA CARD
    
    private var agendaCard: some View {
        VStack(
            alignment: .leading,
            spacing: 15
        ) {
            
            HStack {
                
                Label(
                    "Próxima actividad",
                    systemImage: "calendar"
                )
                .font(
                    .system(
                        size: 17,
                        weight: .bold
                    )
                )
                
                Spacer()
                
                Text(
                    "\(todayEvents.count) hoy"
                )
                .font(
                    .system(
                        size: 11,
                        weight: .semibold,
                        design: .monospaced
                    )
                )
                .foregroundStyle(
                    Color.grayGuti
                )
            }
            
            if let event = nextEvent {
                
                HStack(spacing: 15) {
                    
                    VStack(spacing: 4) {
                        
                        Text(
                            eventTimeString(
                                event.date
                            )
                        )
                        .font(
                            .system(
                                size: 17,
                                weight: .bold,
                                design: .monospaced
                            )
                        )
                        .foregroundStyle(
                            event.isImportant
                            ? Color.pinkGuti
                            : Color.cyanGuti
                        )
                        
                        Text(
                            "\(event.duration)m"
                        )
                        .font(
                            .system(size: 10)
                        )
                        .foregroundStyle(
                            Color.grayGuti
                        )
                    }
                    .frame(
                        width: 65
                    )
                    
                    VStack(
                        alignment: .leading,
                        spacing: 5
                    ) {
                        
                        Text(event.title)
                            .font(
                                .system(
                                    size: 16,
                                    weight: .bold
                                )
                            )
                        
                        if let location = event.location {
                            
                            Label(
                                location,
                                systemImage: "mappin.and.ellipse"
                            )
                            .font(
                                .system(size: 12)
                            )
                            .foregroundStyle(
                                Color.grayGuti
                            )
                        }
                    }
                    
                    Spacer()
                }
                .padding(15)
                .background(
                    Color.white.opacity(0.04)
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 15
                    )
                )
                
            } else {
                
                VStack(spacing: 8) {
                    
                    Image(
                        systemName: "calendar.badge.checkmark"
                    )
                    .font(
                        .system(size: 30)
                    )
                    .foregroundStyle(
                        Color.cyanGuti
                    )
                    
                    Text("No hay próximos eventos")
                        .font(
                            .system(
                                size: 15,
                                weight: .semibold
                            )
                        )
                    
                    Text("Tu agenda está libre.")
                        .font(
                            .system(size: 12)
                        )
                        .foregroundStyle(
                            Color.grayGuti
                        )
                }
                .frame(
                    maxWidth: .infinity
                )
                .padding(.vertical, 15)
            }
        }
        .padding(20)
        .background(
            Color.cardGuti
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 20
            )
        )
    }
    
    // MARK: - WELLNESS
    
    private var wellnessCard: some View {
        VStack(
            alignment: .leading,
            spacing: 18
        ) {
            
            HStack {
                
                Label(
                    "Bienestar diario",
                    systemImage: "heart"
                )
                .font(
                    .system(
                        size: 17,
                        weight: .bold
                    )
                )
                
                Spacer()
                
                Text("Seguimiento manual")
                    .font(
                        .system(size: 11)
                    )
                    .foregroundStyle(
                        Color.grayGuti
                    )
            }
            
            VStack(spacing: 12) {
                
                HStack {
                    
                    Label(
                        "Hidratación",
                        systemImage: "drop"
                    )
                    .foregroundStyle(
                        Color.cyanGuti
                    )
                    
                    Spacer()
                    
                    Button {
                        if glasses > 0 {
                            glasses -= 1
                        }
                    } label: {
                        
                        Image(
                            systemName: "minus"
                        )
                        .frame(
                            width: 32,
                            height: 32
                        )
                        .background(
                            Color.white.opacity(0.08)
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 7
                            )
                        )
                    }
                    
                    Text(
                        String(
                            format: "%.2fL",
                            Double(glasses) * 0.25
                        )
                    )
                    .font(
                        .system(
                            size: 13,
                            weight: .bold,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(
                        Color.cyanGuti
                    )
                    
                    Button {
                        if glasses < 12 {
                            glasses += 1
                        }
                    } label: {
                        
                        Image(
                            systemName: "plus"
                        )
                        .foregroundStyle(
                            Color.appBackground
                        )
                        .frame(
                            width: 32,
                            height: 32
                        )
                        .background(
                            Color.cyanGuti
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 7
                            )
                        )
                    }
                }
                .font(
                    .system(size: 13)
                )
                
                progressBar(
                    progress: min(
                        Double(glasses) / 10.0,
                        1.0
                    ),
                    color: Color.cyanGuti
                )
                
                HStack {
                    
                    Text(
                        "\(glasses) de 10 vasos"
                    )
                    
                    Spacer()
                    
                    Text("Meta 2.5L")
                }
                .font(
                    .system(size: 11)
                )
                .foregroundStyle(
                    Color.grayGuti
                )
            }
            .padding(15)
            .background(
                Color.cardGuti
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 15
                )
            )
        }
        .padding(20)
        .background(
            Color.cardGuti.opacity(0.7)
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 20
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20
            )
            .stroke(
                Color.white.opacity(0.06),
                lineWidth: 1
            )
        }
    }
    
    // MARK: - PROGRESS BAR
    
    private func progressBar(
        progress: Double,
        color: Color
    ) -> some View {
        
        GeometryReader { geometry in
            
            ZStack(
                alignment: .leading
            ) {
                
                Capsule()
                    .fill(
                        Color.white.opacity(0.1)
                    )
                
                Capsule()
                    .fill(color)
                    .frame(
                        width:
                            geometry.size.width
                            * min(
                                max(progress, 0),
                                1
                            )
                    )
            }
        }
        .frame(height: 8)
    }
    
    // MARK: - GUTI
    
    /// Acceso directo por voz: abre la pestaña GUTI y empieza a escuchar.
    private var gutiSection: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                selectedTab = 4
            }
            if appStore.connection != .offline {
                chat.startRecording()
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 46, height: 46)
                    
                    Image(systemName: "mic.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("HABLAR CON GUTI")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(appStore.connection == .offline ? Color.pinkGuti : .white)
                            .frame(width: 7, height: 7)
                        
                        Text(gutiStatusText)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Image(systemName: "waveform")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .symbolEffect(.variableColor.iterative, options: .repeat(.continuous))
            }
            .padding(15)
            .background(
                LinearGradient(
                    colors: [Color.cyanGuti.opacity(0.85), Color.purpleGuti],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .shadow(color: Color.purpleGuti.opacity(0.25), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hablar con GUTI")
    }
    
    private var gutiStatusText: String {
        switch appStore.connection {
        case .online: return "Toca y pregunta lo que necesites"
        case .offline: return "Sin conexión con el servidor"
        case .checking: return "Conectando…"
        }
    }
    
    // MARK: - HELPERS
    
    private func eventTimeString(
        _ date: Date
    ) -> String {
        
        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: "es_CO"
        )
        formatter.dateFormat = "HH:mm"
        
        return formatter.string(
            from: date
        )
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
    
    private func formattedToday() -> String {
        
        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: "es_CO"
        )
        formatter.dateFormat =
            "EEEE, d 'de' MMMM"
        
        return formatter
            .string(from: Date())
            .capitalizedFirst
    }
    
    private func dueDateDescription(
        _ date: Date
    ) -> String {
        
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            
            let formatter = DateFormatter()
            formatter.locale = Locale(
                identifier: "es_CO"
            )
            formatter.dateFormat =
                "'Hoy a las' HH:mm"
            
            return formatter.string(
                from: date
            )
        }
        
        if calendar.isDateInTomorrow(date) {
            
            let formatter = DateFormatter()
            formatter.locale = Locale(
                identifier: "es_CO"
            )
            formatter.dateFormat =
                "'Mañana a las' HH:mm"
            
            return formatter.string(
                from: date
            )
        }
        
        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: "es_CO"
        )
        formatter.dateFormat =
            "EEE d MMM • HH:mm"
        
        return formatter
            .string(from: date)
            .capitalized
    }
    
    private func compareTaskDates(
        _ first: GutiTask,
        _ second: GutiTask
    ) -> Bool {
        
        switch (
            first.dueDate,
            second.dueDate
        ) {
            
        case let (date1?, date2?):
            return date1 < date2
            
        case (_?, nil):
            return true
            
        case (nil, _?):
            return false
            
        default:
            return first.title < second.title
        }
    }
}

// MARK: - PREVIEW

#Preview {
    DashboardView(
        selectedTab: .constant(0)
    )
    .environmentObject(
        AppStore()
    )
    .environmentObject(
        ChatSession()
    )
}
