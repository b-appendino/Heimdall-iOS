import Foundation
import NIO
import NIOHTTP1
import Logging

public final class ProxyServer {
    
    private var serverBootstrap: ServerBootstrap
    private weak var channel: Channel?
    
    // All child channels (each connection) use the same DBService instance
    init(httpBodyCacheFolderURL: URL, dbService: DBService) {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        serverBootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socket(SOL_SOCKET, SO_REUSEADDR), value: 1)
            .childChannelOption(ChannelOptions.socket(SOL_SOCKET, SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in
                // every child channel has a sharedState instance to exchange data between channelHandlers
                let shared = SharedState()
                return channel.pipeline.addHandler(ConnectionLoggingHandler(dbService: dbService, shared: shared), position: .first)
                    .flatMap {
                        channel.pipeline.addHandler(ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes)))
                    }
                    .flatMap {
                        channel.pipeline.addHandler(HTTPResponseEncoder())
                    }
                    .flatMap {
                        channel.pipeline.addHandler(ConnectionHandler(httpBodyCacheFolderURL: httpBodyCacheFolderURL, dbService: dbService, shared: shared))
                    }
            }
    }

    public func start(ipAddress: String, port: Int, completionHandler: @escaping (Bool) -> Void) {
        serverBootstrap.bind(to: try! SocketAddress(ipAddress: ipAddress, port: port)).whenComplete { [weak self] result in
            switch result {
                case .success(let channel):
                    self?.channel = channel
                    NSLog("Proxy server started. Listening on \(String(describing: channel.localAddress))")
                    completionHandler(true)
                case .failure(let error):
                    NSLog("Failed to start proxy server. Failed to bind \(ipAddress):\(port), \(error)")
                    completionHandler(false)
            }
        }
    }

    public func stop() throws -> Void {
        channel?.close().whenComplete { [weak self] result in
            switch result {
            case .success:
                self?.channel = nil
                NSLog("Proxy server stoped")
            case .failure(let error):
                NSLog("Failed to stop proxy: \(error)")
            }
        }
    }
}

// Used to share the primary key value of the Connection entry (Connection.ID in Heimdall DB)
final class SharedState {
    var connectionID: Int64 = 0
}
