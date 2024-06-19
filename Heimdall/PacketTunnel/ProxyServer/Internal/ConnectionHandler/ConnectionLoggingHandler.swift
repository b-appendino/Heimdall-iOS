import NIO
import Foundation

// A custom channel handler for logging the size of incoming and outgoing ByteBuffers
final class ConnectionLoggingHandler {
    private let dbService: DBService
    private let shared: SharedState
    private var totalIn = 0
    private var totalOut = 0
    
    init(dbService: DBService, shared: SharedState) {
        self.dbService = dbService
        self.shared = shared
    }
}

extension ConnectionLoggingHandler: ChannelDuplexHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    // inbound data for the proxy server (from application -> proxy server), this means it is accounted to the total bytes leaving the device
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let byteBuffer = self.unwrapInboundIn(data)
        totalOut += byteBuffer.readableBytes

        context.fireChannelRead(self.wrapInboundOut(byteBuffer))
    }

    // outbound data for the proxy server (from proxy server -> application), this means it is accounted to the total bytes received by the device
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let byteBuffer = self.unwrapOutboundIn(data)
        totalIn += byteBuffer.readableBytes

        context.write(self.wrapOutboundOut(byteBuffer), promise: promise)
    }
    
    // New TCP connection established
    public func channelActive(context: ChannelHandlerContext) {
        // Write start time and local port to Heimdall DB
        self.shared.connectionID  = dbService.insertConnection(connection: Connection(port: String(context.remoteAddress?.port ?? 00), startTime: Date())) ?? 00

        context.fireChannelActive()
    }
    
    // TCP connection shut down
    func channelInactive(context: ChannelHandlerContext) {
        // Write end time and total bytes to Heimdall DB
        dbService.updateConnectionInfo(id: shared.connectionID, endTime: Date(), totalIn: totalIn, totalOut: totalOut)

        context.fireChannelInactive()
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        NSLog("Error caught: \(error.localizedDescription)")
        context.close(promise: nil)
    }
}
