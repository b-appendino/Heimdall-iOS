import SwiftUI
import Combine
import NetworkExtension

final class SettingsViewModel: ObservableObject {
    
    @Published var vpnIsRunning = false
    @Published private(set) var vpnStatus: String = "Unknown"

    @Published var daemonIsRunning = false
    
    @Published var realTimeMonitoring = true


    @Published var isShowingError = false
    @Published private(set) var errorTitle = ""
    @Published private(set) var errorMessage = ""
    
    private var timer: Timer?

    private let dbService: DBService
    private let vpnService: VPNService

    private var observers = [AnyObject]()

    init(vpnService: VPNService, dbService: DBService) {
        self.vpnService = vpnService
        self.dbService = dbService
        
        // Add observers to automatically update the status indicator and toggle button if the VPN status or the VPN configuration changes
        observers.append(NotificationCenter.default
            .addObserver(forName: .NEVPNStatusDidChange, object: vpnService.manager?.connection, queue: .main) { [weak self] _ in
                self?.refresh()
        })

        observers.append(NotificationCenter.default
            .addObserver(forName: .NEVPNConfigurationChange, object: vpnService.manager, queue: .main) { [weak self] _ in
                self?.refresh()
        })
        
        startCheckingDaemonStatus()
        
        refresh()
    }
    
    deinit {
        timer?.invalidate()
    }

    func buttonStartVPNTapped() {
        do {
            if vpnService.manager == nil { vpnService.loadConfig() }
            try vpnService.manager?.connection.startVPNTunnel(options: ["real-time":realTimeMonitoring] as [String : NSObject])
        } catch {
            self.showError(title: "Failed to start VPN tunnel", message: error.localizedDescription)
        }
    }

    func buttonStopVPNTapped() {
        vpnService.manager?.connection.stopVPNTunnel()
    }
    
    // Refresh the variables represented by the UI elements
    private func refresh() {
        self.vpnStatus = vpnService.manager?.connection.status.description ?? "Unknown"
        
        if vpnService.manager?.connection.status == .connected && self.vpnIsRunning == false {
            self.vpnIsRunning = true
        } else if vpnService.manager?.connection.status == .disconnected && self.vpnIsRunning == true {
            self.vpnIsRunning = false
        }
    }
    
    // Execute system commands to start the PortResolver
    func buttonStartDaemonTapped() {
        do {
            // Change the access permissions to the plist file of the PortResolver
            var shellCommand = "sudo chmod 600 \(ConfigService.shared.stringValue(forKey: "DaemonPlistPath"))\(ConfigService.shared.stringValue(forKey: "DaemonLable")).plist"
            try shell(shellCommand)
            // Load the plist file of the PortResolver
            shellCommand = "sudo launchctl load \(ConfigService.shared.stringValue(forKey: "DaemonPlistPath"))\(ConfigService.shared.stringValue(forKey: "DaemonLable")).plist"
            try shell(shellCommand)
            checkDaemonStatus()
        } catch {
            self.showError(title: "Failed to start daemon", message: error.localizedDescription)
        }
    }

    // Execute system commands to stop the PortResolver
    func buttonStopDaemonTapped() {
        do {
            // Unload the plist file of the PortResolver
            let shellCommand = "sudo launchctl unload \(ConfigService.shared.stringValue(forKey: "DaemonPlistPath"))\(ConfigService.shared.stringValue(forKey: "DaemonLable")).plist"
            try shell(shellCommand)
            checkDaemonStatus()
        } catch {
            self.showError(title: "Failed to stop daemon", message: error.localizedDescription)
        }
    }
    
    // Starts periodically checking the status of the PortResolver
    func startCheckingDaemonStatus() {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.checkDaemonStatus()
        }
    }
    
    // Execute system command to check the status of the PortResolver
    private func checkDaemonStatus() {
        do {
            let shellCommand = "launchctl list | grep \(ConfigService.shared.stringValue(forKey: "DaemonLable"))"
            let shellResult = try shell(shellCommand)
            
            self.daemonIsRunning = shellResult.contains(ConfigService.shared.stringValue(forKey: "DaemonLable"))
        } catch {
            self.showError(title: "Failed to check daemon status", message: error.localizedDescription)
        }
    }
    
    @discardableResult
    private func shell(_ command: String) throws -> String {
        let task = NSTask()!
        let pipe = Pipe()
    
        task.setStandardError(pipe)
        task.setStandardOutput(pipe)
        task.setStandardInput(nil)
            
        task.setEnvironment(["PATH" : ConfigService.shared.stringValue(forKey: "PATH")])
        task.setLaunchPath(ConfigService.shared.stringValue(forKey: "SHELL"))
        task.setArguments(["-c", command])
                
        task.launch()
        task.waitUntilExit()
    
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)!
                
        return output
    }
    
    // Stop the PacketTunnel and the PortResolver and start the bulk synchronization of databases
    func syncDatabases() {
        buttonStopVPNTapped()
        buttonStopDaemonTapped()
        dbService.syncDatabases()
    }

    // Show an error pop-up
    private func showError(title: String, message: String) {
        self.errorTitle = title
        self.errorMessage = message
        self.isShowingError = true
    }
}
