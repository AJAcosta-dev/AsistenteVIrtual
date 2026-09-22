import SwiftUI

struct ContentView: View {
    
    // En DEBUG se puede abrir una pestaña concreta con el argumento de lanzamiento
    // `-GUTIInitialTab <n>` (útil para capturas y pruebas en el simulador).
    #if DEBUG
    @State private var selectedTab = UserDefaults.standard.integer(forKey: "GUTIInitialTab")
    #else
    @State private var selectedTab = 0
    #endif
    @StateObject private var appStore = AppStore()
    @StateObject private var chat = ChatSession()
    
    var body: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()
            
            switch selectedTab {
            case 0:
                DashboardView(selectedTab: $selectedTab)
                
            case 1:
                FinanceView()
                
            case 2:
                AgendaView()
                
            case 3:
                TasksView()
                
            case 4:
                GutiChatView()
                
            default:
                DashboardView(selectedTab: $selectedTab)
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomNavigation(
                selectedTab: $selectedTab
            )
        }
        .preferredColorScheme(.dark)
        .environmentObject(appStore)
        .environmentObject(chat)
        .task {
            // Tras cada respuesta de GUTI (p. ej. "agrega una tarea") se refrescan las demás pestañas.
            chat.onResponse = { [weak appStore] in
                await appStore?.refreshAll()
            }

            #if DEBUG
            // `-GUTIAutoPrompt "<texto>"` envía un comando al abrir (pruebas en simulador).
            if let prompt = UserDefaults.standard.string(forKey: "GUTIAutoPrompt") {
                chat.send(prompt)
            }
            #endif
        }
    }
}

struct BottomNavigation: View {
    
    @Binding var selectedTab: Int
    
    private let cyan = Color.cyanGuti
    private let purple = Color.purpleGuti
    
    let items = [
        ("square.grid.2x2", "Inicio"),
        ("wallet.pass", "Finanzas"),
        ("calendar", "Agenda"),
        ("checkmark.square", "Tareas"),
        ("sparkles", "GUTI")
    ]
    
    var body: some View {
        HStack {
            ForEach(0..<items.count, id: \.self) { index in
                
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = index
                    }
                } label: {
                    VStack(spacing: 5) {
                        
                        Image(systemName: items[index].0)
                            .font(.system(size: 20, weight: .semibold))
                        
                        Text(items[index].1)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(
                        selectedTab == index
                        ? (index == 4 ? purple : cyan)
                        : Color.grayGuti
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        selectedTab == index
                        ? Color.white.opacity(0.06)
                        : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 7)
        .padding(.bottom, 5)
        .background(Color.appBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }
}

extension Color {
    
    static let appBackground = Color(
        red: 0.035,
        green: 0.047,
        blue: 0.075
    )
    
    static let cardGuti = Color(
        red: 0.065,
        green: 0.078,
        blue: 0.110
    )
    
    static let cyanGuti = Color(
        red: 0.0,
        green: 0.90,
        blue: 0.98
    )
    
    static let purpleGuti = Color(
        red: 0.72,
        green: 0.58,
        blue: 1.0
    )
    
    static let grayGuti = Color(
        red: 0.55,
        green: 0.61,
        blue: 0.70
    )
    
    static let pinkGuti = Color(
        red: 1.0,
        green: 0.55,
        blue: 0.58
    )
}

#Preview {
    ContentView()
}

extension String {
    /// Solo la primera letra en mayúscula ("Martes, 22 de septiembre"),
    /// a diferencia de `capitalized`, que produciría "Martes, 22 De Septiembre".
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
