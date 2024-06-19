import SwiftUI

struct TrafficView: View {
        
    @ObservedObject var model: TrafficViewModel

    var body: some View {
        VStack{
            Button(action: model.loadTraffic) { Text("Refresh") }.padding()
            List {
                ForEach(model.trafficList) { traffic in
                    TrafficRow(connection: traffic)
                }.padding()
            }
        }
    }
}

struct TrafficRow: View {
    var connection: Connection
    
    var body: some View {
        HStack {
            Text(connection.bundleID ?? "null")
            Text(" -> ")
            Text(connection.port)
        }
    }
}

struct TrafficListView_Previews: PreviewProvider {
    static var previews: some View {
        TrafficView(model: TrafficViewModel(dbService: DBService()))
    }
}
