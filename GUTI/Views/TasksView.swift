import SwiftUI

struct TasksView: View {
    
    @EnvironmentObject private var appStore: AppStore
    
    @State private var searchText = ""
    @State private var selectedFilter: TaskFilter = .all
    @State private var selectedCategory: TaskCategory? = nil
    @State private var showingAddTask = false
    @State private var editingTask: GutiTask?
    
    enum TaskFilter: String, CaseIterable {
        case all = "Todas"
        case pending = "Pendientes"
        case completed = "Completadas"
    }
    
    // MARK: - FILTERED TASKS
    
    private var filteredTasks: [GutiTask] {
        
        appStore.tasks
            .filter { task in
                
                // Filtro de estado
                switch selectedFilter {
                case .all:
                    return true
                    
                case .pending:
                    return !task.isCompleted
                    
                case .completed:
                    return task.isCompleted
                }
            }
            .filter { task in
                
                // Filtro de categoría
                guard let selectedCategory else {
                    return true
                }
                
                return task.category == selectedCategory
            }
            .filter { task in
                
                // Búsqueda
                guard !searchText.isEmpty else {
                    return true
                }
                
                return task.title
                    .localizedCaseInsensitiveContains(
                        searchText
                    )
            }
            .sorted { first, second in
                
                // Primero las no completadas
                if first.isCompleted != second.isCompleted {
                    return !first.isCompleted
                }
                
                // Después por prioridad
                let priorityOrder: [TaskPriority: Int] = [
                    .high: 0,
                    .medium: 1,
                    .low: 2
                ]
                
                let firstPriority =
                    priorityOrder[first.priority] ?? 1
                
                let secondPriority =
                    priorityOrder[second.priority] ?? 1
                
                if firstPriority != secondPriority {
                    return firstPriority < secondPriority
                }
                
                // Finalmente por fecha
                switch (first.dueDate, second.dueDate) {
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
    
    private var pendingCount: Int {
        appStore.pendingTasks.count
    }
    
    private var completedCount: Int {
        appStore.completedTasks.count
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: 22
                ) {
                    
                    // MARK: - HEADER
                    
                    header
                    
                    // MARK: - SEARCH
                    
                    searchBar
                    
                    // MARK: - STATUS FILTER
                    
                    statusFilters
                    
                    // MARK: - CATEGORY FILTER
                    
                    categoryFilters
                    
                    // MARK: - PROGRESS
                    
                    progressCard
                    
                    // MARK: - TASKS
                    
                    tasksSection
                }
                .padding(20)
            }
            .background(
                Color.appBackground
                    .ignoresSafeArea()
            )
            .sheet(
                isPresented: $showingAddTask
            ) {
                TaskEditorView()
                    .environmentObject(appStore)
            }
            .sheet(
                item: $editingTask
            ) { task in
                
                TaskEditorView(
                    task: task
                )
                .environmentObject(appStore)
            }
            .refreshable {
                await appStore.loadTasksFromBackend()
            }
            .onAppear {
                Task {
                    await appStore.loadTasksFromBackend()
                }
            }
        }
    }
    
    // MARK: - HEADER
    
    private var header: some View {
        HStack {
            
            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                
                Text("Tareas y Proyectos")
                    .font(
                        .system(
                            size: 24,
                            weight: .bold
                        )
                    )
                
                HStack(spacing: 7) {
                    
                    Circle()
                        .fill(
                            Color.cyanGuti
                        )
                        .frame(
                            width: 8,
                            height: 8
                        )
                    
                    Text(
                        pendingCount == 1
                        ? "1 tarea pendiente"
                        : "\(pendingCount) tareas pendientes"
                    )
                    .foregroundStyle(
                        Color.grayGuti
                    )
                }
                .font(
                    .system(
                        size: 14
                    )
                )
            }
            
            Spacer()
            
            Button {
                showingAddTask = true
            } label: {
                
                Image(
                    systemName: "plus"
                )
                .font(
                    .system(
                        size: 19,
                        weight: .bold
                    )
                )
                .foregroundStyle(.black)
                .frame(
                    width: 48,
                    height: 48
                )
                .background(
                    Color.cyanGuti
                )
                .clipShape(Circle())
            }
        }
    }
    
    // MARK: - SEARCH
    
    private var searchBar: some View {
        HStack(spacing: 10) {
            
            Image(
                systemName: "magnifyingglass"
            )
            .foregroundStyle(
                Color.grayGuti
            )
            
            TextField(
                "Buscar tareas...",
                text: $searchText
            )
            .foregroundStyle(.white)
            
            if !searchText.isEmpty {
                
                Button {
                    searchText = ""
                } label: {
                    
                    Image(
                        systemName: "xmark.circle.fill"
                    )
                    .foregroundStyle(
                        Color.grayGuti
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            Color.cardGuti
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 17
            )
        )
    }
    
    // MARK: - STATUS FILTERS
    
    private var statusFilters: some View {
        HStack(spacing: 8) {
            
            ForEach(
                TaskFilter.allCases,
                id: \.self
            ) { filter in
                
                Button {
                    withAnimation {
                        selectedFilter = filter
                    }
                } label: {
                    
                    Text(filter.rawValue)
                        .font(
                            .system(
                                size: 13,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            selectedFilter == filter
                            ? .black
                            : Color.grayGuti
                        )
                        .padding(.horizontal, 15)
                        .padding(.vertical, 11)
                        .background(
                            selectedFilter == filter
                            ? Color.cyanGuti
                            : Color.cardGuti
                        )
                        .clipShape(Capsule())
                }
            }
            
            Spacer()
        }
    }
    
    // MARK: - CATEGORY FILTERS
    
    private var categoryFilters: some View {
        ScrollView(
            .horizontal,
            showsIndicators: false
        ) {
            HStack(spacing: 10) {
                
                categoryChip(
                    title: "Todas",
                    category: nil
                )
                
                ForEach(
                    TaskCategory.allCases,
                    id: \.self
                ) { category in
                    
                    categoryChip(
                        title: category.rawValue,
                        category: category
                    )
                }
            }
        }
    }
    
    private func categoryChip(
        title: String,
        category: TaskCategory?
    ) -> some View {
        
        let isSelected =
            selectedCategory == category
        
        return Button {
            
            withAnimation {
                selectedCategory = category
            }
            
        } label: {
            
            Text(title)
                .font(
                    .system(
                        size: 13,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    isSelected
                    ? .black
                    : Color.grayGuti
                )
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                .background(
                    isSelected
                    ? Color.cyanGuti
                    : Color.cardGuti
                )
                .clipShape(Capsule())
        }
    }
    
    // MARK: - PROGRESS
    
    private var progressCard: some View {
        
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            
            HStack {
                
                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    
                    Text("PROGRESO GENERAL")
                        .font(
                            .system(
                                size: 12,
                                weight: .semibold,
                                design: .monospaced
                            )
                        )
                        .foregroundStyle(
                            Color.grayGuti
                        )
                    
                    Text(
                        "\(completedCount) de \(appStore.tasks.count) completadas"
                    )
                    .font(
                        .system(
                            size: 17,
                            weight: .bold
                        )
                    )
                }
                
                Spacer()
                
                Text(
                    "\(Int(appStore.taskCompletionProgress * 100))%"
                )
                .font(
                    .system(
                        size: 22,
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    Color.cyanGuti
                )
            }
            
            ProgressView(
                value: appStore.taskCompletionProgress
            )
            .tint(
                Color.cyanGuti
            )
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
    
    // MARK: - TASKS SECTION
    
    private var tasksSection: some View {
        
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            
            HStack {
                
                Text(sectionTitle)
                    .font(
                        .system(
                            size: 16,
                            weight: .bold
                        )
                    )
                
                Text(
                    "\(filteredTasks.count)"
                )
                .foregroundStyle(
                    Color.grayGuti
                )
                
                Spacer()
                
                Button {
                    showingAddTask = true
                } label: {
                    
                    Label(
                        "Nueva",
                        systemImage: "plus"
                    )
                    .font(
                        .system(
                            size: 13,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        Color.cyanGuti
                    )
                }
            }
            
            if filteredTasks.isEmpty {
                
                emptyState
                
            } else {
                
                ForEach(
                    filteredTasks
                ) { task in
                    
                    taskCard(task)
                        .contextMenu {
                            
                            Button {
                                editingTask = task
                            } label: {
                                Label(
                                    "Editar",
                                    systemImage: "pencil"
                                )
                            }
                            
                            Button {
                                withAnimation {
                                    appStore.toggleTask(task)
                                }
                            } label: {
                                Label(
                                    task.isCompleted
                                    ? "Marcar pendiente"
                                    : "Completar",
                                    systemImage:
                                        task.isCompleted
                                        ? "arrow.uturn.backward"
                                        : "checkmark"
                                )
                            }
                            
                            Button(
                                role: .destructive
                            ) {
                                withAnimation {
                                    appStore.deleteTask(task)
                                }
                            } label: {
                                Label(
                                    "Eliminar",
                                    systemImage: "trash"
                                )
                            }
                        }
                }
            }
        }
    }
    
    private var sectionTitle: String {
        
        switch selectedFilter {
        case .all:
            return "TODAS LAS TAREAS"
            
        case .pending:
            return "PENDIENTES"
            
        case .completed:
            return "COMPLETADAS"
        }
    }
    
    // MARK: - TASK CARD
    
    private func taskCard(
        _ task: GutiTask
    ) -> some View {
        
        Button {
            withAnimation {
                appStore.toggleTask(task)
            }
        } label: {
            
            HStack(
                alignment: .top,
                spacing: 15
            ) {
                
                // CHECKBOX
                
                Image(
                    systemName:
                        task.isCompleted
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .font(
                    .system(size: 27)
                )
                .foregroundStyle(
                    task.isCompleted
                    ? Color.cyanGuti
                    : priorityColor(
                        task.priority
                    )
                )
                
                VStack(
                    alignment: .leading,
                    spacing: 9
                ) {
                    
                    // CATEGORÍA + PRIORIDAD
                    
                    HStack(spacing: 7) {
                        
                        Text(
                            task.category.rawValue
                        )
                        .font(
                            .system(
                                size: 11,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            Color.purpleGuti
                        )
                        .padding(
                            .horizontal,
                            9
                        )
                        .padding(
                            .vertical,
                            6
                        )
                        .background(
                            Color.purpleGuti
                                .opacity(0.15)
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 7
                            )
                        )
                        
                        priorityBadge(
                            task.priority
                        )
                    }
                    
                    // TÍTULO
                    
                    Text(task.title)
                        .font(
                            .system(
                                size: 16,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            .white
                        )
                        .multilineTextAlignment(
                            .leading
                        )
                        .strikethrough(
                            task.isCompleted
                        )
                    
                    // FECHA
                    
                    if let dueDate = task.dueDate {
                        
                        HStack(spacing: 5) {
                            
                            Image(
                                systemName:
                                    "calendar"
                            )
                            
                            Text(
                                dueDateText(
                                    dueDate
                                )
                            )
                        }
                        .font(
                            .system(size: 12)
                        )
                        .foregroundStyle(
                            dueDateColor(
                                dueDate,
                                completed:
                                    task.isCompleted
                            )
                        )
                    }
                    
                    // ESTADO
                    
                    if task.isCompleted {
                        
                        Text("COMPLETADA")
                            .font(
                                .system(
                                    size: 10,
                                    weight: .bold,
                                    design: .monospaced
                                )
                            )
                            .foregroundStyle(
                                Color.cyanGuti
                            )
                    }
                }
                
                Spacer()
                
                // MENU
        
                Image(
                    systemName:
                        "ellipsis"
                )
                .foregroundStyle(
                    Color.grayGuti
                )
            }
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
                    task.isCompleted
                    ? Color.cyanGuti.opacity(0.12)
                    : Color.white.opacity(0.05)
                )
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            
            Button {
                editingTask = task
            } label: {
                Label(
                    "Editar",
                    systemImage: "pencil"
                )
            }
            
            Button(
                role: .destructive
            ) {
                withAnimation {
                    appStore.deleteTask(task)
                }
            } label: {
                Label(
                    "Eliminar",
                    systemImage: "trash"
                )
            }
        }
    }
    
    // MARK: - PRIORITY BADGE
    
    private func priorityBadge(
        _ priority: TaskPriority
    ) -> some View {
        
        Text(priority.rawValue)
            .font(
                .system(
                    size: 10,
                    weight: .bold
                )
            )
            .foregroundStyle(
                priorityColor(priority)
            )
            .padding(
                .horizontal,
                8
            )
            .padding(
                .vertical,
                5
            )
            .background(
                priorityColor(priority)
                    .opacity(0.12)
            )
            .clipShape(
                Capsule()
            )
    }
    
    // MARK: - EMPTY STATE
    
    private var emptyState: some View {
        
        VStack(spacing: 12) {
            
            Image(
                systemName:
                    searchText.isEmpty
                    ? "checkmark.circle"
                    : "magnifyingglass"
            )
            .font(
                .system(size: 38)
            )
            .foregroundStyle(
                Color.cyanGuti
            )
            
            Text(
                searchText.isEmpty
                ? "No hay tareas aquí"
                : "No encontramos tareas"
            )
            .font(
                .system(
                    size: 17,
                    weight: .bold
                )
            )
            
            Text(
                searchText.isEmpty
                ? "Puedes crear una nueva tarea usando el botón +."
                : "Prueba con otro término de búsqueda."
            )
            .font(
                .system(size: 14)
            )
            .foregroundStyle(
                Color.grayGuti
            )
            .multilineTextAlignment(
                .center
            )
            
            if searchText.isEmpty {
                
                Button {
                    showingAddTask = true
                } label: {
                    Text("Crear tarea")
                        .font(
                            .system(
                                size: 14,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(.black)
                        .padding(
                            .horizontal,
                            20
                        )
                        .padding(
                            .vertical,
                            12
                        )
                        .background(
                            Color.cyanGuti
                        )
                        .clipShape(Capsule())
                }
            }
        }
        .frame(
            maxWidth: .infinity
        )
        .padding(.vertical, 35)
        .padding(.horizontal, 20)
        .background(
            Color.cardGuti
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 22
            )
        )
    }
    
    // MARK: - HELPERS
    
    private func priorityColor(
        _ priority: TaskPriority
    ) -> Color {
        
        switch priority {
        case .high:
            return Color.pinkGuti
            
        case .medium:
            return Color.cyanGuti
            
        case .low:
            return Color.grayGuti
        }
    }
    
    private func dueDateText(
        _ date: Date
    ) -> String {
        
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            
            let formatter = DateFormatter()
            formatter.locale = Locale(
                identifier: "es_CO"
            )
            formatter.dateFormat = "'Hoy,' HH:mm"
            
            return formatter.string(
                from: date
            )
        }
        
        if calendar.isDateInTomorrow(date) {
            
            let formatter = DateFormatter()
            formatter.locale = Locale(
                identifier: "es_CO"
            )
            formatter.dateFormat = "HH:mm"
            
            return "Mañana, \(formatter.string(from: date))"
        }
        
        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: "es_CO"
        )
        formatter.dateFormat = "EEE d MMM, HH:mm"
        
        return formatter.string(
            from: date
        )
    }
    
    private func dueDateColor(
        _ date: Date,
        completed: Bool
    ) -> Color {
        
        if completed {
            return Color.grayGuti
        }
        
        if date < Date() {
            return Color.pinkGuti
        }
        
        if Calendar.current.isDateInToday(date) {
            return Color.pinkGuti
        }
        
        return Color.grayGuti
    }
}


// MARK: - TASK EDITOR

struct TaskEditorView: View {
    
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss
    
    private let taskToEdit: GutiTask?
    
    @State private var title: String
    @State private var category: TaskCategory
    @State private var priority: TaskPriority
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    
    init(task: GutiTask? = nil) {
        
        self.taskToEdit = task
        
        _title = State(
            initialValue:
                task?.title ?? ""
        )
        
        _category = State(
            initialValue:
                task?.category ?? .university
        )
        
        _priority = State(
            initialValue:
                task?.priority ?? .medium
        )
        
        _hasDueDate = State(
            initialValue:
                task?.dueDate != nil
        )
        
        _dueDate = State(
            initialValue:
                task?.dueDate
                ?? Calendar.current.date(
                    byAdding: .day,
                    value: 1,
                    to: Date()
                )
                ?? Date()
        )
    }
    
    private var isEditing: Bool {
        taskToEdit != nil
    }
    
    var body: some View {
        NavigationStack {
            
            Form {
                
                // MARK: - TITLE
                
                Section("Tarea") {
                    
                    TextField(
                        "¿Qué necesitas hacer?",
                        text: $title
                    )
                }
                
                // MARK: - CATEGORY
                
                Section("Categoría") {
                    
                    Picker(
                        "Categoría",
                        selection: $category
                    ) {
                        
                        ForEach(
                            TaskCategory.allCases,
                            id: \.self
                        ) { category in
                            
                            Text(
                                category.rawValue
                            )
                            .tag(category)
                        }
                    }
                }
                
                // MARK: - PRIORITY
                
                Section("Prioridad") {
                    
                    Picker(
                        "Prioridad",
                        selection: $priority
                    ) {
                        
                        ForEach(
                            TaskPriority.allCases,
                            id: \.self
                        ) { priority in
                            
                            HStack {
                                
                                Circle()
                                    .fill(
                                        priorityColor(
                                            priority
                                        )
                                    )
                                    .frame(
                                        width: 8,
                                        height: 8
                                    )
                                
                                Text(
                                    priority.rawValue
                                )
                            }
                            .tag(priority)
                        }
                    }
                }
                
                // MARK: - DATE
                
                Section("Fecha límite") {
                    
                    Toggle(
                        "Tiene fecha límite",
                        isOn: $hasDueDate
                    )
                    
                    if hasDueDate {
                        
                        DatePicker(
                            "Fecha y hora",
                            selection: $dueDate,
                            displayedComponents: [
                                .date,
                                .hourAndMinute
                            ]
                        )
                    }
                }
                
                // MARK: - PREVIEW
                
                Section("Vista previa") {
                    
                    VStack(
                        alignment: .leading,
                        spacing: 10
                    ) {
                        
                        Text(
                            title.isEmpty
                            ? "Nueva tarea"
                            : title
                        )
                        .font(
                            .system(
                                size: 16,
                                weight: .semibold
                            )
                        )
                        
                        HStack {
                            
                            Text(
                                category.rawValue
                            )
                            
                            Text("•")
                            
                            Text(
                                priority.rawValue
                            )
                            
                            if hasDueDate {
                                Text("•")
                                
                                Text(
                                    dueDateText(
                                        dueDate
                                    )
                                )
                            }
                        }
                        .font(
                            .system(size: 12)
                        )
                        .foregroundStyle(
                            Color.grayGuti
                        )
                    }
                }
            }
            .navigationTitle(
                isEditing
                ? "Editar tarea"
                : "Nueva tarea"
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
                    
                    Button(
                        isEditing
                        ? "Guardar"
                        : "Crear"
                    ) {
                        save()
                    }
                    .disabled(
                        title
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .isEmpty
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - SAVE
    
    private func save() {
        
        let cleanTitle = title
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        
        guard !cleanTitle.isEmpty else {
            return
        }
        
        if let taskToEdit {
            
            guard let index =
                    appStore.tasks.firstIndex(
                        where: {
                            $0.id == taskToEdit.id
                        }
                    )
            else {
                return
            }
            
            appStore.tasks[index].title =
                cleanTitle
            
            appStore.tasks[index].category =
                category
            
            appStore.tasks[index].priority =
                priority
            
            appStore.tasks[index].dueDate =
                hasDueDate
                ? dueDate
                : nil
            
        } else {
            
            appStore.addTask(
                title: cleanTitle,
                category: category,
                dueDate:
                    hasDueDate
                    ? dueDate
                    : nil,
                priority: priority
            )
        }
        
        dismiss()
    }
    
    // MARK: - HELPERS
    
    private func priorityColor(
        _ priority: TaskPriority
    ) -> Color {
        
        switch priority {
        case .high:
            return Color.pinkGuti
            
        case .medium:
            return Color.cyanGuti
            
        case .low:
            return Color.grayGuti
        }
    }
    
    private func dueDateText(
        _ date: Date
    ) -> String {
        
        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: "es_CO"
        )
        formatter.dateFormat =
            "dd/MM HH:mm"
        
        return formatter.string(
            from: date
        )
    }
}
