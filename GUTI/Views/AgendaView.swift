import SwiftUI
import Combine

struct AgendaView: View {
    
    @EnvironmentObject private var appStore: AppStore
    
    @State private var selectedDate = Date()
    @State private var showingAddEvent = false
    @State private var editingEvent: GutiEvent?
    
    @State private var focusRemaining = 25 * 60
    @State private var isFocusRunning = false
    
    private let focusTimer = Timer.publish(
        every: 1,
        on: .main,
        in: .common
    ).autoconnect()
    
    // MARK: - SELECTED DAY EVENTS
    
    private var selectedDayEvents: [GutiEvent] {
        appStore.events
            .filter {
                Calendar.current.isDate(
                    $0.date,
                    inSameDayAs: selectedDate
                )
            }
            .sorted {
                $0.date < $1.date
            }
    }
    
    // MARK: - WEEK
    
    private var weekDates: [Date] {
        
        let calendar = Calendar.current
        
        guard let weekInterval = calendar.dateInterval(
            of: .weekOfYear,
            for: selectedDate
        ) else {
            return []
        }
        
        return (0..<7).compactMap { offset in
            calendar.date(
                byAdding: .day,
                value: offset,
                to: weekInterval.start
            )
        }
    }
    
    // MARK: - BODY
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: 22
                ) {
                    
                    header
                    monthHeader
                    daySelector
                    focusMode
                    dayHeader
                    eventsSection
                    addEventButton
                }
                .padding(20)
            }
            .background(
                Color.appBackground
                    .ignoresSafeArea()
            )
            .sheet(
                isPresented: $showingAddEvent
            ) {
                EventEditorView()
                    .environmentObject(appStore)
            }
            .sheet(
                item: $editingEvent
            ) { event in
                EventEditorView(
                    event: event
                )
                .environmentObject(appStore)
            }
            .onReceive(focusTimer) { _ in
                
                guard isFocusRunning else {
                    return
                }
                
                if focusRemaining > 0 {
                    focusRemaining -= 1
                } else {
                    isFocusRunning = false
                }
            }
            .refreshable {
                await appStore.loadEventsFromBackend()
            }
            .onAppear {
                Task {
                    await appStore.loadEventsFromBackend()
                }
            }
        }
    }
    
    // MARK: - HEADER
    
    private var header: some View {
        VStack(
            alignment: .leading,
            spacing: 5
        ) {
            
            Text("GUTI CORE")
                .font(
                    .system(
                        size: 25,
                        weight: .bold
                    )
                )
            
            HStack {
                
                Circle()
                    .fill(
                        Color.cyanGuti
                    )
                    .frame(
                        width: 8,
                        height: 8
                    )
                
                Text("ONLINE  // AGENDA")
                    .font(
                        .system(
                            size: 12,
                            weight: .medium,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(
                        Color.grayGuti
                    )
            }
        }
    }
    
    // MARK: - MONTH HEADER
    
    private var monthHeader: some View {
        HStack {
            
            VStack(
                alignment: .leading
            ) {
                
                Text(
                    monthYear(
                        selectedDate
                    )
                )
                .font(
                    .system(
                        size: 29,
                        weight: .bold
                    )
                )
                
                Text(
                    "SEMANA \(weekNumber(selectedDate))"
                )
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
            }
            
            Spacer()
            
            HStack(spacing: 10) {
                
                Button {
                    changeSelectedDate(
                        by: -7
                    )
                } label: {
                    calendarArrow(
                        "chevron.left"
                    )
                }
                
                Button {
                    changeSelectedDate(
                        by: 7
                    )
                } label: {
                    calendarArrow(
                        "chevron.right"
                    )
                }
            }
        }
    }
    
    // MARK: - DAY SELECTOR
    
    private var daySelector: some View {
        ScrollView(
            .horizontal,
            showsIndicators: false
        ) {
            HStack(spacing: 12) {
                
                ForEach(
                    weekDates,
                    id: \.self
                ) { date in
                    
                    dayCard(
                        date: date
                    )
                }
            }
        }
    }
    
    private func dayCard(
        date: Date
    ) -> some View {
        
        let isSelected =
            Calendar.current.isDate(
                date,
                inSameDayAs: selectedDate
            )
        
        let hasEvents =
            appStore.events.contains {
                Calendar.current.isDate(
                    $0.date,
                    inSameDayAs: date
                )
            }
        
        return Button {
            withAnimation {
                selectedDate = date
            }
        } label: {
            
            VStack(spacing: 9) {
                
                Text(
                    weekdayLetter(date)
                )
                .font(
                    .system(
                        size: 13,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    isSelected
                    ? Color.cyanGuti
                    : Color.grayGuti
                )
                
                Text(
                    dayNumber(date)
                )
                .font(
                    .system(
                        size: 19,
                        weight: .bold
                    )
                )
                .foregroundStyle(.white)
                
                Circle()
                    .fill(
                        hasEvents
                        ? Color.cyanGuti
                        : Color.clear
                    )
                    .frame(
                        width: 6,
                        height: 6
                    )
            }
            .frame(
                width: 68,
                height: 105
            )
            .background(
                isSelected
                ? Color.cyanGuti.opacity(0.12)
                : Color.cardGuti
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 22
                )
                .stroke(
                    isSelected
                    ? Color.cyanGuti
                    : Color.clear,
                    lineWidth: 1.5
                )
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 22
                )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - FOCUS MODE
    
    private var focusMode: some View {
        HStack {
            
            ZStack {
                
                Circle()
                    .stroke(
                        Color.cyanGuti.opacity(0.18),
                        lineWidth: 7
                    )
                    .frame(
                        width: 75,
                        height: 75
                    )
                
                Circle()
                    .trim(
                        from: 0,
                        to: focusProgress
                    )
                    .stroke(
                        Color.cyanGuti,
                        style: StrokeStyle(
                            lineWidth: 7,
                            lineCap: .round
                        )
                    )
                    .frame(
                        width: 75,
                        height: 75
                    )
                    .rotationEffect(
                        .degrees(-90)
                    )
                
                Image(
                    systemName:
                        isFocusRunning
                        ? "pause.fill"
                        : "clock"
                )
                .font(
                    .system(size: 24)
                )
            }
            
            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                
                Text("MODO ENFOQUE")
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
                
                HStack {
                    
                    Text(
                        formatTime(
                            focusRemaining
                        )
                    )
                    .font(
                        .system(
                            size: 27,
                            weight: .bold,
                            design: .monospaced
                        )
                    )
                    
                    Text(
                        isFocusRunning
                        ? "En progreso"
                        : "25 minutos"
                    )
                    .foregroundStyle(
                        Color.grayGuti
                    )
                }
            }
            
            Spacer()
            
            Button {
                
                if focusRemaining == 0 {
                    focusRemaining = 25 * 60
                }
                
                isFocusRunning.toggle()
                
            } label: {
                
                Label(
                    isFocusRunning
                    ? "PAUSAR"
                    : "INICIAR",
                    systemImage:
                        isFocusRunning
                        ? "pause.fill"
                        : "play.fill"
                )
                .font(
                    .system(
                        size: 13,
                        weight: .bold,
                        design: .monospaced
                    )
                )
                .foregroundStyle(.black)
                .padding(
                    .horizontal,
                    15
                )
                .padding(
                    .vertical,
                    18
                )
                .background(
                    Color.cyanGuti
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 15
                    )
                )
            }
        }
        .padding(15)
        .background(
            Color.cardGuti
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 22
            )
        )
    }
    
    // MARK: - DAY HEADER
    
    private var dayHeader: some View {
        HStack {
            
            Image(
                systemName: "calendar"
            )
            .foregroundStyle(
                Color.cyanGuti
            )
            
            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                
                Text(
                    selectedDateString(
                        selectedDate
                    )
                )
                .font(
                    .system(
                        size: 19,
                        weight: .bold
                    )
                )
                
                if Calendar.current.isDateInToday(
                    selectedDate
                ) {
                    Text("HOY")
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
            
            Text(
                "\(selectedDayEvents.count) " +
                (
                    selectedDayEvents.count == 1
                    ? "ACTIVIDAD"
                    : "ACTIVIDADES"
                )
            )
            .font(
                .system(
                    size: 10,
                    weight: .semibold,
                    design: .monospaced
                )
            )
            .foregroundStyle(
                Color.grayGuti
            )
        }
    }
    
    // MARK: - EVENTS SECTION
    
    private var eventsSection: some View {
        
        VStack(
            alignment: .leading,
            spacing: 13
        ) {
            
            if selectedDayEvents.isEmpty {
                
                emptyEvents
                
            } else {
                
                ForEach(
                    selectedDayEvents
                ) { event in
                    
                    eventCard(
                        event
                    )
                    .contextMenu {
                        
                        Button {
                            editingEvent = event
                        } label: {
                            Label(
                                "Editar",
                                systemImage: "pencil"
                            )
                        }
                        
                        Button(
                            role: .destructive
                        ) {
                            Task {
                                await appStore.deleteEvent(
                                    event
                                )
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
    
    // MARK: - EVENT CARD
    
    private func eventCard(
        _ event: GutiEvent
    ) -> some View {
        
        let color =
            event.isImportant
            ? Color.pinkGuti
            : Color.cyanGuti
        
        return HStack(spacing: 15) {
            
            RoundedRectangle(
                cornerRadius: 10
            )
            .fill(color)
            .frame(width: 7)
            
            VStack(
                alignment: .leading,
                spacing: 7
            ) {
                
                HStack {
                    
                    Text(
                        eventTimeRange(
                            event
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
                        color
                    )
                    
                    if event.isImportant {
                        
                        Text("IMPORTANTE")
                            .font(
                                .system(
                                    size: 9,
                                    weight: .bold,
                                    design: .monospaced
                                )
                            )
                            .foregroundStyle(
                                Color.pinkGuti
                            )
                            .padding(
                                .horizontal,
                                7
                            )
                            .padding(
                                .vertical,
                                4
                            )
                            .background(
                                Color.pinkGuti.opacity(0.12)
                            )
                            .clipShape(Capsule())
                    }
                }
                
                Text(event.title)
                    .font(
                        .system(
                            size: 16,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(.white)
                
                if let location = event.location,
                   !location.isEmpty {
                    
                    Label(
                        location,
                        systemImage:
                            "mappin.and.ellipse"
                    )
                    .font(
                        .system(size: 12)
                    )
                    .foregroundStyle(
                        Color.grayGuti
                    )
                }
                
                Text(
                    "\(event.duration) minutos"
                )
                .font(
                    .system(size: 11)
                )
                .foregroundStyle(
                    Color.grayGuti
                )
            }
            
            Spacer()
            
            Image(
                systemName: "chevron.right"
            )
            .foregroundStyle(
                Color.grayGuti
            )
        }
        .padding(18)
        .frame(
            minHeight: 120
        )
        .background(
            Color.cardGuti
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
                Color.white.opacity(0.05)
            )
        }
    }
    
    // MARK: - EMPTY EVENTS
    
    private var emptyEvents: some View {
        
        VStack(spacing: 12) {
            
            Image(
                systemName:
                    "calendar.badge.plus"
            )
            .font(
                .system(size: 38)
            )
            .foregroundStyle(
                Color.cyanGuti
            )
            
            Text("Día libre")
                .font(
                    .system(
                        size: 18,
                        weight: .bold
                    )
                )
            
            Text(
                "No tienes eventos programados para este día."
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
            
            Button {
                showingAddEvent = true
            } label: {
                
                Text("Agregar evento")
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
    
    // MARK: - ADD EVENT BUTTON
    
    private var addEventButton: some View {
        
        Button {
            showingAddEvent = true
        } label: {
            
            Label(
                "NUEVO EVENTO",
                systemImage: "plus"
            )
            .font(
                .system(
                    size: 14,
                    weight: .bold,
                    design: .monospaced
                )
            )
            .foregroundStyle(
                Color.cyanGuti
            )
            .padding(
                .horizontal,
                24
            )
            .padding(
                .vertical,
                16
            )
            .overlay {
                Capsule()
                    .stroke(
                        Color.cyanGuti,
                        lineWidth: 1
                    )
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: .trailing
        )
    }
    
    // MARK: - HELPERS
    
    private func calendarArrow(
        _ icon: String
    ) -> some View {
        
        Image(
            systemName: icon
        )
        .frame(
            width: 50,
            height: 50
        )
        .background(
            Color.cardGuti
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 15
            )
        )
    }
    
    private func changeSelectedDate(
        by days: Int
    ) {
        selectedDate =
            Calendar.current.date(
                byAdding: .day,
                value: days,
                to: selectedDate
            )
            ?? selectedDate
    }
    
    private func monthYear(
        _ date: Date
    ) -> String {
        
        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: "es_CO"
        )
        formatter.dateFormat = "MMMM yyyy"
        
        return formatter
            .string(from: date)
            .capitalized
    }
    
    private func selectedDateString(
        _ date: Date
    ) -> String {
        
        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: "es_CO"
        )
        formatter.dateFormat =
            "EEEE, d 'de' MMMM"
        
        return formatter
            .string(from: date)
            .capitalized
    }
    
    private func weekNumber(
        _ date: Date
    ) -> Int {
        Calendar.current.component(
            .weekOfYear,
            from: date
        )
    }
    
    private func weekdayLetter(
        _ date: Date
    ) -> String {
        
        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: "es_CO"
        )
        formatter.dateFormat = "EEEEE"
        
        return formatter
            .string(from: date)
            .uppercased()
    }
    
    private func dayNumber(
        _ date: Date
    ) -> String {
        
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        
        return formatter.string(
            from: date
        )
    }
    
    private func eventTimeRange(
        _ event: GutiEvent
    ) -> String {
        
        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: "es_CO"
        )
        formatter.dateFormat = "HH:mm"
        
        let start = formatter.string(
            from: event.date
        )
        
        let endDate =
            Calendar.current.date(
                byAdding: .minute,
                value: event.duration,
                to: event.date
            )
            ?? event.date
        
        let end = formatter.string(
            from: endDate
        )
        
        return "\(start) - \(end)"
    }
    
    private var focusProgress: Double {
        
        let total = 25.0 * 60.0
        
        return 1.0 -
            (
                Double(focusRemaining) /
                total
            )
    }
    
    private func formatTime(
        _ seconds: Int
    ) -> String {
        
        let minutes = seconds / 60
        let seconds = seconds % 60
        
        return String(
            format: "%02d:%02d",
            minutes,
            seconds
        )
    }
}


// MARK: - EVENT EDITOR

struct EventEditorView: View {
    
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss
    
    private let eventToEdit: GutiEvent?
    
    @State private var title: String
    @State private var date: Date
    @State private var duration: Int
    @State private var location: String
    @State private var isImportant: Bool
    
    init(event: GutiEvent? = nil) {
        
        self.eventToEdit = event
        
        _title = State(
            initialValue:
                event?.title ?? ""
        )
        
        _date = State(
            initialValue:
                event?.date ?? Date()
        )
        
        _duration = State(
            initialValue:
                event?.duration ?? 60
        )
        
        _location = State(
            initialValue:
                event?.location ?? ""
        )
        
        _isImportant = State(
            initialValue:
                event?.isImportant ?? false
        )
    }
    
    private var isEditing: Bool {
        eventToEdit != nil
    }
    
    var body: some View {
        NavigationStack {
            
            Form {
                
                Section("Evento") {
                    
                    TextField(
                        "Nombre del evento",
                        text: $title
                    )
                }
                
                Section("Fecha y hora") {
                    
                    DatePicker(
                        "Inicio",
                        selection: $date,
                        displayedComponents: [
                            .date,
                            .hourAndMinute
                        ]
                    )
                }
                
                Section("Duración") {
                    
                    Stepper(
                        value: $duration,
                        in: 15...480,
                        step: 15
                    ) {
                        
                        HStack {
                            
                            Text("Duración")
                            
                            Spacer()
                            
                            Text(
                                "\(duration) min"
                            )
                            .foregroundStyle(
                                Color.grayGuti
                            )
                        }
                    }
                }
                
                Section("Ubicación") {
                    
                    TextField(
                        "Ej. Universidad / Google Meet",
                        text: $location
                    )
                }
                
                Section {
                    
                    Toggle(
                        "Evento importante",
                        isOn: $isImportant
                    )
                }
                
                Section("Vista previa") {
                    
                    VStack(
                        alignment: .leading,
                        spacing: 8
                    ) {
                        
                        Text(
                            title.isEmpty
                            ? "Nuevo evento"
                            : title
                        )
                        .font(
                            .system(
                                size: 17,
                                weight: .bold
                            )
                        )
                        
                        Text(
                            previewDate
                        )
                        .font(
                            .system(size: 13)
                        )
                        .foregroundStyle(
                            Color.grayGuti
                        )
                        
                        if !location.isEmpty {
                            
                            Label(
                                location,
                                systemImage:
                                    "mappin.and.ellipse"
                            )
                            .font(
                                .system(size: 12)
                            )
                            .foregroundStyle(
                                Color.grayGuti
                            )
                        }
                    }
                }
            }
            .navigationTitle(
                isEditing
                ? "Editar evento"
                : "Nuevo evento"
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
        
        if let eventToEdit {
            
            guard let index =
                    appStore.events.firstIndex(
                        where: {
                            $0.id == eventToEdit.id
                        }
                    )
            else {
                return
            }
            
            // Por ahora la edición se actualiza localmente.
            // La sincronización de edición con Supabase
            // la agregaremos cuando implementemos PUT/PATCH.
            
            appStore.events[index].title =
                cleanTitle
            
            appStore.events[index].date =
                date
            
            appStore.events[index].duration =
                duration
            
            appStore.events[index].location =
                location.isEmpty
                ? nil
                : location
            
            appStore.events[index].isImportant =
                isImportant
            
        } else {
            
            Task {
                await appStore.addEvent(
                    title: cleanTitle,
                    startDate: date,
                    description:
                        location.isEmpty
                        ? nil
                        : location,
                    endDate:
                        Calendar.current.date(
                            byAdding: .minute,
                            value: duration,
                            to: date
                        )
                )
            }
        }
        
        dismiss()
    }
    
    // MARK: - PREVIEW
    
    private var previewDate: String {
        
        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: "es_CO"
        )
        formatter.dateFormat =
            "EEEE, d 'de' MMMM • HH:mm"
        
        return formatter
            .string(from: date)
            .capitalized
    }
}
