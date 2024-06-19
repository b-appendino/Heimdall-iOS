import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: SettingsViewModel

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Local VPN")) {
                    Toggle(isOn: $model.vpnIsRunning, label: { Text("Start/Stop") })
                        .onChange(of: model.vpnIsRunning) { value in
                            if value == true{
                                model.buttonStartVPNTapped()
                            } else {
                                model.buttonStopVPNTapped()
                            }
                        }
                    HStack{
                        Text("Status")
                        Spacer()
                        Text(model.vpnStatus).bold()
                    }
                }
                Section(header: Text("Port Resolver Daemon")) {
                    Toggle(isOn: $model.daemonIsRunning, label: { Text("Start/Stop") })
                        .onChange(of: model.daemonIsRunning) { value in
                            if value == true{
                                model.buttonStartDaemonTapped()
                            } else {
                                model.buttonStopDaemonTapped()
                            }
                        }
                    HStack{
                        Text("Status")
                        Spacer()
                        Text(model.daemonIsRunning ? "Running" : "Terminated").bold()
                    }
                }
                Section(header: Text("Utility")) {
                    Toggle(isOn: $model.realTimeMonitoring, label: { Text("Real-time Monitoring") }).disabled(model.vpnIsRunning)
                    Button(action: model.syncDatabases) { Text("Synchronize Databases") }
                }
            }
            .alert(isPresented: $model.isShowingError) {
                Alert(
                    title: Text(self.model.errorTitle),
                    message: Text(self.model.errorMessage),
                    dismissButton: .cancel()
                )
            }
            .navigationBarTitle("Settings")
        }
    }
}

struct TunnelView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(model: .init(vpnService: VPNService(), dbService: DBService()))
    }
}
