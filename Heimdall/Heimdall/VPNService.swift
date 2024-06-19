import Foundation
import Combine
import NetworkExtension
import UIKit

final class VPNService: ObservableObject {
    @Published private(set) var manager: NETunnelProviderManager?
        
    init() {
        loadConfig()
    }
    
    func loadConfig() {
        // if manager is already loaded: stop
        if manager != nil {
            return
        }
        
        NETunnelProviderManager.loadAllFromPreferences() { [weak self] managers, error in
            guard let self = self else { return }
            
            // If no configuration is available, create and install a new configuration
            if managers?.count == 0 {
                let newManager = makeManager()
                newManager.saveToPreferences() { [weak self] error in
                    if let error = error {
                        NSLog("Failed to install the configuration: \(error.localizedDescription)")
                        return
                    }
                    
                    newManager.loadFromPreferences() { [weak self] error in
                        self?.manager = newManager
                        return
                    }
                }
            }
            
            // If there is at least one configuration available, use the first one
            self.manager = managers?.first
            if let error = error {
                NSLog("Failed to load configurations: \(error.localizedDescription)")
            } 
        }
    }
    
    private func makeManager() -> NETunnelProviderManager {
        let proto = NETunnelProviderProtocol()
        // define the bundle ID of the packet tunnel provider app extension
        proto.providerBundleIdentifier = "de.tomcory.heimdall.PacketTunnel"
        proto.serverAddress = "LocalProxy"
                
        let manager = NETunnelProviderManager()
        manager.localizedDescription = "HeimdallLocalProxy"
        manager.protocolConfiguration = proto
        manager.isEnabled = true
                
        return manager
    }
}

// MARK: - Extensions

// Make NEVPNStatus convertible to a string
extension NEVPNStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .invalid: return "Invalid"
        case .connected: return "Connected"
        case .connecting: return "Connecting"
        case .disconnecting: return "Disconnecting"
        case .reasserting: return "Reconnecting"
        @unknown default: return "Unknown"
        }
    }
}
