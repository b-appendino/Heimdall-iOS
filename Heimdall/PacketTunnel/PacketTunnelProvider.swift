import NetworkExtension

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    private let proxyServerPort = 8080
    private let proxyServerAddress = "127.0.0.1"
    private var proxyServer: ProxyServer!
    
    private var dataURL: URL!
    private var dbService = DBService()
    
    var timer: Timer?
    
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        var realtime = false
        
        // Get the options passed from the containing app
        if let options = options {
            realtime = options["real-time"] as! Bool
        } else {
            NSLog("Error reading Packet Tunnel start options, using default configuraton")
        }
        self.setTunnelNetworkSettings(createSettings()) { error in
            guard error == nil else {
                NSLog("setTunnelNetworkSettings error: \(error!)")
                completionHandler(error)
                return
            }

            // The path the the directory for cached clear-text HTTP body content
            self.dataURL = URL(string: "file:///var/mobile/Documents/httpDump/")
            
            // Start the proxy server
            self.proxyServer = ProxyServer(httpBodyCacheFolderURL: self.dataURL, dbService: self.dbService)
            self.proxyServer.start(ipAddress: self.proxyServerAddress, port: self.proxyServerPort) { (success) -> Void in
                if(success){
                    // When real-time synchonization is enabled start pulling bundleIDs from AppDump DB when the proxy has started
                    if(realtime) {
                        self.startPullingBundleIDs()
                    }
                    completionHandler(nil)
                } else {
                    completionHandler(error)
                }
            }
        }
    }
    
    private func createSettings() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: proxyServerAddress)
        settings.mtu = NSNumber(value: 1500)
        
        let proxySettings = NEProxySettings()
        proxySettings.httpEnabled = true;
        proxySettings.httpServer = NEProxyServer(address: proxyServerAddress, port: Int(proxyServerPort))
        proxySettings.httpsEnabled = true;
        proxySettings.httpsServer = NEProxyServer(address: proxyServerAddress, port: Int(proxyServerPort))
        proxySettings.excludeSimpleHostnames = false;
        proxySettings.autoProxyConfigurationEnabled = false
        proxySettings.exceptionList = []
        proxySettings.matchDomains = [""]
        settings.proxySettings = proxySettings

        return settings
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        do {
            try self.proxyServer.stop()
        } catch let proxyError {
            NSLog("Error stopping proxy server: \(proxyError)")
        }
        self.stopPullingBundleIDs()
        self.dbService.closeDatabases()
        
        completionHandler()
    }
    
    // start periodically querying for new entries in the AppDump.BundleID table and write them to the Heimdall.Connection table
    private func startPullingBundleIDs() {
        dbService.fetchBundleIDSeq()
        
        NSLog("Stating to pull BundleIDs ... ")
        // Start timer to asynchronously pull PortResolver results
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
                self?.dbService.syncBundleIDs()
            }
        }
    }
    
    private func stopPullingBundleIDs() {
        NSLog("Stopping to pull BundleIDs ... ")
        timer?.invalidate()
        self.dbService.syncBundleIDs()
    }
}
