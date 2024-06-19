import Foundation
import NIO
import NIOHTTP1
import Logging
import Combine

protocol ChannelCallbackHandler {
    func channelRead(context: ChannelHandlerContext, data: NIOAny)
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?)
    func removeHandler(context: ChannelHandlerContext, removalToken: ChannelHandlerContext.RemovalToken)
}

extension ChannelCallbackHandler {
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        context.fireChannelRead(data)
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        context.write(data, promise: promise)
    }
    public func removeHandler(context: ChannelHandlerContext, removalToken: ChannelHandlerContext.RemovalToken) {
        context.leavePipeline(removalToken: removalToken)
    }
}

final class ConnectionHandler {
    init(httpBodyCacheFolderURL: URL, logger: Logger = .init(label: "ConnectionHandler"), dbService: DBService, shared: SharedState) {
        self.httpBodyCacheFolderURL = httpBodyCacheFolderURL
        self.logger = logger
        self.dbService = dbService
        self.shared = shared
    }

    private let httpBodyCacheFolderURL: URL
    private var logger: Logger
    private var callBackHandler: ChannelCallbackHandler?
    
    private let dbService: DBService
    private let shared: SharedState
    
    private var httpBodyCache = HttpBodyCache()
    private var httpRequestID: Int64 = 0
    private var httpResponseID: Int64 = 0

}

extension ConnectionHandler: ChannelDuplexHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias InboundOut = HTTPClientRequestPart
    typealias OutboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPServerResponsePart

    // inbound data for the proxy server (from application -> proxy server): HTTPRequests
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let httpPart = self.unwrapInboundIn(data)

        // Setup the logic for HTTP or HTTPS
        if callBackHandler == nil {
            do {
                try setupCallBackHandler(context: context, data: httpPart)
            } catch {
                logger.error("\(error.localizedDescription)")
                httpErrorAndClose(context: context)
                return
            }
        }
        
        // log the HTTPRequest
        switch httpPart {
        case .head(let head):
            // Write HTTP headers to Heimdall DB
            self.httpRequestID = dbService.insertHttpRequest(httpRequest: HTTPRequest(connection_id: shared.connectionID, url: head.uri, method: head.method.rawValue, version: head.version.description, headers: head.headers.description, bodyCount: 0, contentLength: 0, timestamp: Date())) ?? 00
        case .body(let buffer):
            // Count number of body parts and number of bytes
            let bytesCount = buffer.readableBytes
            httpBodyCache.bodyCount += 1
            httpBodyCache.contentLength += bytesCount
        case .end(_):
            // Update the body info of the HTTPRequest entry, if there is body info
            if (httpBodyCache.bodyCount != 0 || httpBodyCache.contentLength != 0) {
                dbService.updateHTTPRequestBodyInfo(id: self.httpRequestID, bodyCount: httpBodyCache.bodyCount, contentLength: httpBodyCache.contentLength)
                httpBodyCache.reset()
            }
        }

        callBackHandler?.channelRead(context: context, data: data)
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {

        let part = self.unwrapOutboundIn(data)
        
        // log the HTTPResponse
        switch part {
        case .head(let head):
            // Write HTTP headers to Heimdall DB
            self.httpResponseID = dbService.insertHttpResponse(httpResponse: HTTPResponse(httprequest_id: httpRequestID, version: head.version.description, headers: head.headers.description, timestamp: Date())) ?? 00
        case .body(let buffer):
            // Count number of body parts and number of bytes
            let bytesCount = buffer.readableBytes
            httpBodyCache.bodyCount += 1
            httpBodyCache.contentLength += bytesCount
        case .end(_):
            // Update the body info of the HTTPRequest entry
            dbService.updateHTTPResponseBodyInfo(id: self.httpResponseID, bodyCount: httpBodyCache.bodyCount, contentLength: httpBodyCache.contentLength)
            httpBodyCache.reset()
        }
        
        callBackHandler?.write(context: context, data: data, promise: promise)
    }

    func handlerAdded(context: ChannelHandlerContext) {
        // Add logger metadata.
        let description = "\(context.channel.localAddress?.ipAddress ?? "unknown") -> \(context.channel.remoteAddress?.ipAddress ?? "unknown") ::: \(ObjectIdentifier(context.channel))"
        self.logger[metadataKey: "desc"] = "\(description)"
    }
}

extension ConnectionHandler: RemovableChannelHandler {
    func removeHandler(context: ChannelHandlerContext, removalToken: ChannelHandlerContext.RemovalToken) {
        callBackHandler?.removeHandler(context: context, removalToken: removalToken)
    }
}

private extension ConnectionHandler {
    private func setupCallBackHandler(context: ChannelHandlerContext, data: InboundIn) throws {
        guard case .head(let head) = data else {
            throw ConnectProxyError.invalidHTTPMessage
        }

        if head.method == .CONNECT {
            callBackHandler = try TLSChannelHandler(channelHandler: self, httpBodyCacheFolderURL: httpBodyCacheFolderURL)
        } else {
            callBackHandler = try HTTPChannelHandler(channelHandler: self, httpBodyCacheFolderURL: httpBodyCacheFolderURL)
        }
    }

    private func httpErrorAndClose(context: ChannelHandlerContext) {
        let headers = HTTPHeaders([("Content-Length", "0"), ("Connection", "close")])
        let head = HTTPResponseHead(version: .init(major: 1, minor: 1), status: .badRequest, headers: headers)
        context.write(self.wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil))).whenComplete { (_: Result<Void, Error>) in
            context.close(mode: .output, promise: nil)
        }
    }
}

// to count the number of http body parts and the total number of bytes they contain
private struct HttpBodyCache {
    var bodyCount: Int = 0
    var contentLength: Int = 0
    
    mutating func reset() {
        bodyCount = 0
        contentLength = 0
    }
}
