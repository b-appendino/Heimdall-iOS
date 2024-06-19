import Foundation

final class TrafficViewModel: ObservableObject {
    @Published var trafficList: [Connection] = [Connection(id: 0, port: "00000", bundleID: "de.bundleID", startTime: Date(), endTime: Date())]

    let dbService: DBService
    
    init(dbService: DBService) {
        self.dbService = dbService
    }
    
    func loadTraffic() {
        let newTraffic = dbService.fetchLatestTraffic()
        
        trafficList = newTraffic
    }
}
