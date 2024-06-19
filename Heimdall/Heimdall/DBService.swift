import Foundation
import GRDB

class DBService: ObservableObject {

    var appDumpDB: DatabasePool?
    let appDumpDBpath = ConfigService.shared.stringValue(forKey: "AppDumpDatabasePath")
    
    var heimdallDB: DatabasePool?
    let heimdallDBpath = ConfigService.shared.stringValue(forKey: "HeimdallDatabasePath")
    
    var lastBundleIDSeq: Int64 = 0
    
    init() {
        // Create or connect to the AppDump database
        setupDatabase(withFileURL: appDumpDBpath) { [weak self] dbPool in
            // When complete, create the schema if not exists
            self?.appDumpDB = dbPool
            self?.createAppDumpTables()
        }
        // Create or connect to the Heimdall database
        setupDatabase(withFileURL: heimdallDBpath) { [weak self] dbPool in
            // When complete, create the schema if not exists
            self?.heimdallDB = dbPool
            self?.createHeimdallTables()
        }
    }

    func setupDatabase(withFileURL fileURL: String, completion: @escaping (DatabasePool) -> Void) {
        do {
            let dbPool = try openSharedDatabase(at: URL(fileURLWithPath: fileURL))
            NSLog("Database opened successfully")
            completion(dbPool)
        } catch {
            NSLog("Database opening failed: \(error.localizedDescription)")
            NSLog("Retrying to open Database in 2 sec")
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                self.setupDatabase(withFileURL: fileURL, completion: completion)
            }
        }
    }

    func openSharedDatabase(at databaseURL: URL) throws -> DatabasePool {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?
        var dbPool: DatabasePool?
        var dbError: Error?
        coordinator.coordinate(writingItemAt: databaseURL, options: .forMerging, error: &coordinatorError) { url in
            do {
                dbPool = try self.openDatabase(at: url)
            } catch {
                dbError = error
            }
        }
        if let error = dbError ?? coordinatorError {
            throw error
        }
        return dbPool!
    }

    private func openDatabase(at databaseURL: URL) throws -> DatabasePool {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
                var flag: CInt = 1
                
                // Open database in WAL mode
                let code = withUnsafeMutablePointer(to: &flag) { flagP in
                    sqlite3_file_control(db.sqliteConnection, nil, SQLITE_FCNTL_PERSIST_WAL, flagP)
                }
                guard code == SQLITE_OK else {
                    throw DatabaseError(resultCode: ResultCode(rawValue: code))
                }
        }
        let dbPool = try DatabasePool(path: databaseURL.path, configuration: configuration)
        return dbPool
    }
    
    func closeDatabases() {
        // Ensure all operations are completed before closing the databases
        if let appDumpDB = appDumpDB {
            do {
                try appDumpDB.barrierWriteWithoutTransaction { db in
                    try appDumpDB.close()
                    NSLog("AppDump database closed successfully.")
                    
                }
            } catch {
                NSLog("Failed to close AppDump database: \(error.localizedDescription)")
            }
        } else {
            NSLog("AppDump database is nil, nothing to close.")
        }

        if let heimdallDB = heimdallDB {
            do {
                try heimdallDB.barrierWriteWithoutTransaction { db in
                    try heimdallDB.close()
                    NSLog("Heimdall database closed successfully.")
                    
                }
            } catch {
                NSLog("Failed to close Heimdall database: \(error.localizedDescription)")
            }
        } else {
            NSLog("Heimdall database is nil, nothing to close.")
        }
    }
    
    func createAppDumpTables() {
        checkAppDumpDBStatus()
        
        // Create BundleID table
        do {
            try appDumpDB?.write { db in
                try db.create(table: BundleID.databaseTableName, ifNotExists: true) { t in
                    t.autoIncrementedPrimaryKey(BundleID.Columns.ID.rawValue)
                    t.column(BundleID.Columns.Connection_ID.rawValue, .integer)
                    t.column(BundleID.Columns.BundleID.rawValue, .text)
                }
            }
            NSLog("\(BundleID.databaseTableName) table created successfully.")
        } catch {
            NSLog("Failed to create \(BundleID.databaseTableName) table: \(error.localizedDescription)")
        }
        
        // Create BundleIDCache table
        do {
            try appDumpDB?.write { db in
                try db.create(table: BundleIDcache.databaseTableName, ifNotExists: true) { t in
                    t.autoIncrementedPrimaryKey(BundleIDcache.Columns.ID.rawValue)
                    t.column(BundleIDcache.Columns.process.rawValue, .text)
                    t.column(BundleIDcache.Columns.bundleID.rawValue, .text)
                    t.column(BundleIDcache.Columns.createdAt.rawValue, .datetime)
                }
            }
            
            NSLog("\(BundleIDcache.databaseTableName) table created successfully.")
        } catch {
            NSLog("Failed to create \(BundleIDcache.databaseTableName) table: \(error.localizedDescription)")
        }
    }
    
    func createHeimdallTables() {
        checkHeimdallDBStatus()
        
        // Create Connection table
        do {
            try heimdallDB?.write { db in
                try db.create(table: Connection.databaseTableName, ifNotExists: true) { t in
                    t.autoIncrementedPrimaryKey(Connection.Columns.ID.rawValue)
                    t.column(Connection.Columns.port.rawValue, .text)
                    t.column(Connection.Columns.bundleID.rawValue, .text)
                    t.column(Connection.Columns.startTime.rawValue, .datetime)
                    t.column(Connection.Columns.endTime.rawValue, .datetime)
                    t.column(Connection.Columns.totalIn.rawValue, .integer)
                    t.column(Connection.Columns.totalOut.rawValue, .integer)
                }
            }
            NSLog("\(Connection.databaseTableName) table created successfully.")
        } catch {
            NSLog("Failed to create \(Connection.databaseTableName) table: \(error.localizedDescription)")
        }
        
        // Create HTTPRequest table
        do {
            try heimdallDB?.write { db in
                try db.create(table: HTTPRequest.databaseTableName, ifNotExists: true) { t in
                    t.autoIncrementedPrimaryKey(HTTPRequest.Columns.ID.rawValue)
                    t.column(HTTPRequest.Columns.Connection_ID.rawValue).notNull().indexed()
                    t.column(HTTPRequest.Columns.url.rawValue, .text)
                    t.column(HTTPRequest.Columns.method.rawValue, .text)
                    t.column(HTTPRequest.Columns.version.rawValue, .text)
                    t.column(HTTPRequest.Columns.headers.rawValue, .text)
                    t.column(HTTPRequest.Columns.body.rawValue, .text)
                    t.column(HTTPRequest.Columns.bodyCount.rawValue, .integer)
                    t.column(HTTPRequest.Columns.contentLength.rawValue, .integer)
                    t.column(HTTPRequest.Columns.timestamp.rawValue, .datetime)
                    //t.foreignKey([HTTPRequest.Columns.Connection_ID.rawValue], references: Connection.databaseTableName, onUpdate: .cascade)
                }
            }
            
            NSLog("\(HTTPRequest.databaseTableName) table created successfully.")
        } catch {
            NSLog("Failed to create \(HTTPRequest.databaseTableName) table: \(error.localizedDescription)")
        }
        
        // Create HTTPResponse table
        do {
            try heimdallDB?.write { db in
                try db.create(table: HTTPResponse.databaseTableName, ifNotExists: true) { t in
                    t.autoIncrementedPrimaryKey(HTTPResponse.Columns.ID.rawValue)
                    t.column(HTTPResponse.Columns.HTTPRequest_ID.rawValue).notNull().indexed()
                    t.column(HTTPResponse.Columns.version.rawValue, .text)
                    t.column(HTTPResponse.Columns.headers.rawValue, .text)
                    t.column(HTTPResponse.Columns.body.rawValue, .text)
                    t.column(HTTPResponse.Columns.bodyCount.rawValue, .integer)
                    t.column(HTTPResponse.Columns.contentLength.rawValue, .integer)
                    t.column(HTTPResponse.Columns.timestamp.rawValue, .datetime)
                    //t.foreignKey([HTTPResponse.Columns.HTTPRequest_ID.rawValue], references: HTTPRequest.databaseTableName, onUpdate: .cascade)
                }
            }
            
            NSLog("\(HTTPResponse.databaseTableName) table created successfully.")
        } catch {
            NSLog("Failed to create \(HTTPResponse.databaseTableName) table: \(error.localizedDescription)")
        }

    }

    func insertConnection(connection: Connection) -> Int64? {
        checkHeimdallDBStatus()
        var insertedId: Int64? = nil
        
        do {
            try heimdallDB?.write { db in
                try connection.insert(db)
                insertedId = db.lastInsertedRowID
            }
            NSLog("Inserted Connection: ID: \(insertedId ?? 000), startTime: \(connection.startTime), port: \(connection.port)")
        } catch {
            NSLog("Failed to insert connection: \(error.localizedDescription)")
        }
        return insertedId
    }
    
    func updateConnectionInfo(id: Int64, endTime: Date, totalIn: Int, totalOut: Int) {
        checkHeimdallDBStatus()
        
        do {
            try heimdallDB?.write { db in
                let query = Connection.filter(Connection.Columns.ID == id)
                try query.updateAll(db,
                                    [Column(Connection.Columns.endTime.rawValue).set(to: endTime),
                                     Column(Connection.Columns.totalIn.rawValue).set(to: totalIn),
                                     Column(Connection.Columns.totalOut.rawValue).set(to: totalOut)])
                NSLog("Updated Connection info: ID: \(id), endTime: \(endTime.description), totalIn: \(totalIn), totalOut: \(totalOut)")
            }
        } catch {
            NSLog("Failed to update \(Connection.databaseTableName) info: \(error.localizedDescription)")
        }
    }
    
    func insertHttpRequest(httpRequest: HTTPRequest) -> Int64? {
        checkHeimdallDBStatus()
        var insertedId: Int64? = nil
        
        do {
            try heimdallDB?.write { db in
                try httpRequest.insert(db)
                insertedId = db.lastInsertedRowID
                NSLog("Inserted HTTP Request: ID: \(insertedId ?? 000), Connection_ID: \(httpRequest.connection_id)")
            }
        } catch {
            NSLog("Failed to insert \(HTTPRequest.databaseTableName): \(error.localizedDescription)")
        }
        return insertedId
    }
    
    func updateHTTPRequestBodyInfo(id: Int64, bodyCount: Int, contentLength: Int) {
        checkHeimdallDBStatus()
        
        do {
            try heimdallDB?.write { db in
                let query = HTTPRequest.filter(HTTPRequest.Columns.ID == id)
                try query.updateAll(db, [Column(HTTPRequest.Columns.bodyCount.rawValue).set(to: bodyCount), Column(HTTPRequest.Columns.contentLength.rawValue).set(to: contentLength)])
                NSLog("Updated HTTP Request body: ID: \(id), bodyCount: \(bodyCount), contentLength: \(contentLength)")
            }
        } catch {
            NSLog("Failed to update \(HTTPRequest.databaseTableName) body info: \(error.localizedDescription)")
        }
    }
    
    func insertHttpResponse(httpResponse: HTTPResponse) -> Int64? {
        checkHeimdallDBStatus()
        var insertedId: Int64? = nil
        
        do {
            try heimdallDB?.write { db in
                try httpResponse.insert(db)
                insertedId = db.lastInsertedRowID
                NSLog("Inserted HTTP Response: ID: \(insertedId ?? 000), HTTPRequest_ID: \(httpResponse.httprequest_id)")
            }
        } catch {
            NSLog("Failed to insert \(HTTPResponse.databaseTableName): \(error.localizedDescription)")
        }
        return insertedId
    }
    
    func updateHTTPResponseBodyInfo(id: Int64, bodyCount: Int, contentLength: Int) {
        checkHeimdallDBStatus()
        
        do {
            try heimdallDB?.write { db in
                let query = HTTPResponse.filter(HTTPResponse.Columns.ID == id)
                try query.updateAll(db, [Column(HTTPResponse.Columns.bodyCount.rawValue).set(to: bodyCount), Column(HTTPResponse.Columns.contentLength.rawValue).set(to: contentLength)])
                NSLog("Updated HTTP Response body: ID: \(id), bodyCount: \(bodyCount), contentLength: \(contentLength)")
            }
        } catch {
            NSLog("Failed to update \(HTTPResponse.databaseTableName) body info: \(error.localizedDescription)")
        }
    }
    
    func clearBundleIDTable() {
        checkAppDumpDBStatus()

        // Delete all BundleID records in AppDumpDB
        do {
            try appDumpDB?.write { db in
                try db.execute(sql: "DELETE FROM \(BundleID.databaseTableName)")
            }
            NSLog("All \(BundleID.databaseTableName) records deleted successfully.")
        } catch {
            NSLog("Failed to delete \(BundleID.databaseTableName) records: \(error.localizedDescription)")
        }
        
        // Reset the sequence number of BundleID table to 0
        do {
            try appDumpDB?.write { db in
                try db.execute(sql: "UPDATE sqlite_sequence SET seq = 0 WHERE name = '\(BundleID.databaseTableName)'")
            }
            NSLog("Resetted the \(BundleID.databaseTableName) sequence successfully.")
        } catch {
            NSLog("Failed to reset \(BundleID.databaseTableName) sequence: \(error.localizedDescription)")
        }

    }
    
    // Get the highes ID of the AppDump.BundleID table as a starting point to pull new entries
    func fetchBundleIDSeq() {
        checkAppDumpDBStatus()
        
        do {
            return try appDumpDB!.read { db in
                let query =
                """
                SELECT seq FROM sqlite_sequence WHERE name = '\(BundleID.databaseTableName)'
                """
                
                guard let seqValue: Int64? = try Row.fetchOne(db, sql: query)?["seq"] else {
                    NSLog("Error while fetching last \(BundleID.databaseTableName) sequence number: Return value not of type Int")
                    return
                }
                
                NSLog("Fetched last \(BundleID.databaseTableName) seqnr: \(seqValue!)")
                lastBundleIDSeq = seqValue!
            }
        } catch {
            NSLog("Error while fetching last \(BundleID.databaseTableName) sequence number: \(error.localizedDescription)")
            return
        }
    }
    
    // Fetch new entries form the AppDump.BundleID table
    func fetchNewBundleIDs()  -> [BundleID] {
        checkAppDumpDBStatus()
        
        do {
            return try appDumpDB!.read { db -> [BundleID] in
                let query =
                """
                SELECT * FROM BundleID WHERE ID > ?
                """
                
                let bundleIDs = try BundleID.fetchAll(db , sql: query, arguments: [lastBundleIDSeq])
                return bundleIDs
            }
        } catch {
            NSLog("Failed to fetch BundleIDs: \(error.localizedDescription)")
            return []
        }
    }
    
    // Bulk synchronization of bundleID values from the AppDump DB to the Heimdall DB
    func syncBundleIDs() {
        checkHeimdallDBStatus()
        
        let bundleIDs = fetchNewBundleIDs()
        
        let query = """
        UPDATE Connection SET
        bundleID = :BundleID
        WHERE ID = :connection_id
        """
        
        for bundelD in bundleIDs {
            do {
                try heimdallDB?.write { db in
                    try db.execute(sql: query, arguments: ["BundleID": bundelD.bundleID, "connection_id": bundelD.connection_id])
                    lastBundleIDSeq = bundelD.id!
                }
            } catch {
                NSLog("Failed to update Connection record: \(error.localizedDescription)")
            }
        }
        NSLog("Databases synchronized successfully. Updated \(bundleIDs.count) records.")

    }
    
    func syncDatabases() {
        checkHeimdallDBStatus()
        checkAppDumpDBStatus()
        
        let attachSQL = "ATTACH DATABASE '\(appDumpDBpath)' AS appDumpDB"
        let detachSQL = "DETACH DATABASE appDumpDB"
        let updateSQL =
        """
        UPDATE \(Connection.databaseTableName)
        SET \(Connection.Columns.bundleID.rawValue) = (
            SELECT \(Connection.Columns.bundleID.rawValue) FROM appDumpDB.\(BundleID.databaseTableName)
            WHERE appDumpDB.\(BundleID.databaseTableName).\(BundleID.Columns.Connection_ID.rawValue) = \(Connection.databaseTableName).\(Connection.Columns.ID.rawValue)
        )
        WHERE EXISTS (
            SELECT 1 FROM appDumpDB.\(BundleID.databaseTableName)
            WHERE appDumpDB.\(BundleID.databaseTableName).\(BundleID.Columns.Connection_ID.rawValue) = \(Connection.databaseTableName).\(Connection.Columns.ID.rawValue)
        )
        """
                
        do {
            try heimdallDB?.write { db in
                try db.execute(sql: attachSQL)
            }
            NSLog("Database attached successfully.")
        } catch {
            NSLog("Failed to attach database: \(error.localizedDescription)")
        }
        
        do {
            let startDate = Date()
            try heimdallDB?.write { db in
                try db.execute(sql: updateSQL)
                let affectedRows = db.changesCount
                let duration = Date().timeIntervalSince(startDate)
                NSLog("Databases synchronized successfully. Updated \(affectedRows) records in \(duration) seconds.")
            }
        } catch {
            NSLog("Failed to synchronize databases: \(error.localizedDescription)")
        }

        do {
            try heimdallDB?.write { db in
                try db.execute(sql: detachSQL)
            }
            NSLog("Database detached successfully.")
        } catch {
            NSLog("Failed to detach database: \(error.localizedDescription)")
        }
        
        clearBundleIDTable()
    }
    
    func checkHeimdallDBStatus() {
        if heimdallDB == nil {
            NSLog("PortDump database is not initialized. Attempting to set up the database.")
            setupDatabase(withFileURL: heimdallDBpath) { [weak self] dbPool in
                self?.heimdallDB = dbPool
            }
        }
    }
    
    func checkAppDumpDBStatus() {
        if appDumpDB == nil {
            NSLog("Heimdall database is not initialized. Attempting to set up the database.")
            setupDatabase(withFileURL: appDumpDBpath) { [weak self] dbPool in
                self?.appDumpDB = dbPool
            }
        }
    }
}

// MARK: - Table Structures

struct Connection: Codable, Identifiable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var port: String
    var bundleID: String?
    var startTime: Date
    var endTime: Date?
    var totalIn: Int?
    var totalOut: Int?

    static let databaseTableName = "Connection"
    
    // Define table columns
    enum Columns: String, ColumnExpression {
        case ID, port, bundleID, startTime, endTime, totalIn, totalOut
    }
}

struct HTTPRequest: Codable, Identifiable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var connection_id: Int64
    var url: String?
    var method: String?
    var version: String
    var headers: String
    var body: String?
    var bodyCount: Int?
    var contentLength: Int?
    var timestamp: Date

    static let databaseTableName = "HTTPRequest"
    
    // Define table columns
    enum Columns: String, ColumnExpression {
        case ID, Connection_ID, url, method, version, headers, body, bodyCount, contentLength, timestamp
    }
}

struct HTTPResponse: Codable, Identifiable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var httprequest_id: Int64
    var version: String
    var headers: String
    var body: String?
    var bodyCount: Int?
    var contentLength: Int?
    var timestamp: Date

    static let databaseTableName = "HTTPResponse"
    
    // Define table columns
    enum Columns: String, ColumnExpression {
        case ID, HTTPRequest_ID, version, headers, body, bodyCount, contentLength, timestamp
    }
}

struct BundleID: Codable, Identifiable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var connection_id: String
    var bundleID: String

    static let databaseTableName = "BundleID"
    
    // Define table columns
    enum Columns: String, ColumnExpression {
        case ID, Connection_ID, BundleID
    }
}

struct BundleIDcache: Codable, Identifiable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var process: String
    var bundleID: String
    var createAt: Date

    static let databaseTableName = "BundleIDcache"
    
    // Define table columns
    enum Columns: String, ColumnExpression {
        case ID, process, bundleID, createdAt
    }
}

