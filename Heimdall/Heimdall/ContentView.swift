import SwiftUI

// Preparatory for further Views
struct ContentView: View {
        
    @StateObject var vpnService = VPNService()
    @StateObject var dbService = DBService()
    
    var body: some View {
        TabView{
            SettingsView(model: SettingsViewModel(vpnService: vpnService, dbService: dbService))
                .tabItem {
                    Label("Settings", systemImage: "square.and.pencil")
                }
        }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
