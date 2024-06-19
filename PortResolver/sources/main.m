#import <Foundation/Foundation.h>
#import <sqlite3.h>
#include <signal.h>
#import "NSTask.h"

/**
 Enumerates the types of errors that the PortResolver can encounter.
 */
typedef NS_ENUM(NSUInteger, PortResolverError) {
    PortResolverErrorEmptyShellResult, ///< Indicates an empty result from a shell command.
    PortResolverErrorStringSlicing, ///< Indicates an error slicing a string.
    PortResolverErrorCommandExecution, ///< Indicates a unexpectednfailure in command execution.
    PortResolverErrorProcessNotFound, ///< Indicates failure to find the process for a given port.
    PortResolverErrorPathNotFound ///< Indicates failure to find the path of an executable for a given process.
};

// Environment variables
static NSDictionary *environment;
static NSString *shellPath;
static NSString *portResolverBundleID;

// Database paths and pointers
static NSString *writeDatabasePath;
static NSString *readDatabasePath;
static sqlite3 *readDatabase;
static sqlite3 *writeDatabase;

// The last processed ID of a traffic record form the read DB
static int lastProcessedId = -1;

// Caching for process names to bundle IDs and timestamps
static NSCache *processNameToBundleIDCache;
static NSMutableDictionary *processNameToTimestampCache;

/**
 Connects to both the read (Heimdall) and write (AppDump)  SQLite databases.
 */
static void connectToDatabases() {
    if (sqlite3_open_v2([readDatabasePath UTF8String], &readDatabase, SQLITE_OPEN_READONLY, NULL) == SQLITE_OK) {
        NSLog(@"Connected to read database successfully");
    } else {
        NSLog(@"Failed to open read database: %s", sqlite3_errmsg(readDatabase));
        exit(EXIT_FAILURE);
    }

    if (sqlite3_open([writeDatabasePath UTF8String], &writeDatabase) == SQLITE_OK) {
        NSLog(@"Connected to write database successfully");
    } else {
        NSLog(@"Failed to open write database: %s", sqlite3_errmsg(writeDatabase));
        exit(EXIT_FAILURE);
    }
}

/**
 Disconnects from both the read and write SQLite databases.
 */
static void disconnectFromDatabase() {
    if (sqlite3_close(readDatabase) == SQLITE_OK) {
        NSLog(@"Disconnected from read database successfully");
    } else {
        NSLog(@"Failed to close read database: %s", sqlite3_errmsg(readDatabase));
    }
    
    if (sqlite3_close(writeDatabase) == SQLITE_OK) {
        NSLog(@"Disconnected from write database successfully");
    } else {
        NSLog(@"Failed to close database: %s", sqlite3_errmsg(writeDatabase));
    }
}


/**
 Fills the Bundle ID cache from the write database.
 */
static void fillBundleIDcachefromDB() {
    sqlite3_stmt *statement;
    NSString *query = [NSString stringWithFormat:@"SELECT process, bundleID FROM BundleIDCache"];
    
    if (sqlite3_prepare_v2(writeDatabase, [query UTF8String], -1, &statement, NULL) == SQLITE_OK) {
        while (sqlite3_step(statement) == SQLITE_ROW) {
            NSString *processName = [[NSString alloc] initWithUTF8String:(const char *)sqlite3_column_text(statement, 0)];
            NSString *bundleID = [[NSString alloc] initWithUTF8String:(const char *)sqlite3_column_text(statement, 1)];
            [processNameToBundleIDCache setObject:bundleID forKey:processName];
            
        }
        sqlite3_finalize(statement);
    } else {
        NSLog(@"Failed to fill the BundleID cache with error %s", sqlite3_errmsg(writeDatabase));
    }
}

/**
 Adds a process name and its corresponding bundle ID to the temporary and persitant cache.
 
 @param processName The name of the process.
 @param bundleID The corresponding bundle ID.
 */
static void addToBundleIDcache(NSString *processName, NSString *bundleID) {
    // Add entry to memory cache
    [processNameToBundleIDCache setObject:bundleID forKey:processName];
    
    //Add entry to persistent cache in DB
    NSString *insertSQL = [NSString stringWithFormat:@"INSERT INTO BundleIDCache (process, bundleID, createdAt) VALUES ('%@', '%@', CURRENT_TIMESTAMP)", processName, bundleID];
    const char *insert_stmt = [insertSQL UTF8String];
    sqlite3_stmt *statement;

    if (sqlite3_prepare_v2(writeDatabase, insert_stmt, -1, &statement, NULL) == SQLITE_OK) {
       if (sqlite3_step(statement) == SQLITE_DONE) {
           NSLog(@"Successfully inserted value");
       } else {
           NSLog(@"Failed to insert value");
       }
       sqlite3_finalize(statement);
    }
}

/**
 Retrieves the last processed ID of a traffic record from the read database.
 
 @return The highest ID from the traffic table found in the read database.
 */
static NSInteger getLastProcessedID() {
    int highestID = -1; // Default to -1
    sqlite3_stmt *statement;
    NSString *query = [NSString stringWithFormat:@"SELECT seq FROM sqlite_sequence WHERE name = 'Connection'"];
    
    if (sqlite3_prepare_v2(readDatabase, [query UTF8String], -1, &statement, NULL) == SQLITE_OK) {
        while (sqlite3_step(statement) == SQLITE_ROW) {
            highestID = sqlite3_column_int(statement, 0);
        }
        sqlite3_finalize(statement);
    } else {
        NSLog(@"Failed to get last processed ID with error %s", sqlite3_errmsg(readDatabase));
    }
    
    return highestID;
}

/**
 Creates and returns an NSError object based on the given error code and message.
 
 @param errorCode The error code.
 @param errorMessage The error message.
 @return An NSError object encapsulating the error details.
 */
static NSError *createError(NSInteger errorCode, NSString *errorMessage) {
    NSDictionary *userInfo = @{NSLocalizedDescriptionKey: errorMessage};
    NSError *error = [NSError errorWithDomain:portResolverBundleID code:errorCode userInfo:userInfo];
    return error;
}

/**
 Executes a shell command and returns the result.
 
 @param command The shell command to execute.
 @param error A pointer to an NSError object to capture any errors.
 @return The output from the shell command, or nil if an error occurred.
 */
static NSString *shell(NSString *command, NSError **error) {
    @try {
        NSTask *task = [[NSTask alloc] init];
        
        // Setup the environment variables
        [task setEnvironment:environment];
        [task setLaunchPath:shellPath];
        [task setArguments:@[@"-c", command]];

        NSPipe *pipe = [NSPipe pipe];
        [task setStandardOutput:pipe];

        [task launch];
        [task waitUntilExit];

        // Handle a termination status that is not 0
        if ([task terminationStatus] != 0) {
            if (error != NULL) {
                NSDictionary *userInfo = @{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Execution of command %@ exited with status %d", command, [task terminationStatus]], @"terminationStatus": @([task terminationStatus])};
                *error = [NSError errorWithDomain:portResolverBundleID code:PortResolverErrorCommandExecution userInfo:userInfo];
            }
            return nil;
        }

        NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
        NSString *result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

        // Handle a emtry string as a result
        if (result.length == 0) {
            if (error != NULL) {
                *error = createError(PortResolverErrorEmptyShellResult, [NSString stringWithFormat:@"Execution of command %@ resulted in an empty string", command]);
            }
            return nil;
        }

        return result;
    } @catch (NSException *exception) {
        if (error != NULL) {
            *error = createError(PortResolverErrorCommandExecution, [NSString stringWithFormat:@"Exception during command execution %@ : %@", command, exception.reason]);
        }
        return nil;
    }
}

/**
 Resolves a port to a bundle ID by executing shell commands.
 
 @param port The port to resolve.
 @param error A pointer to an NSError object to capture any errors.
 @return The bundle ID associated with the port, or nil if an error occurred.
 */
static NSString *resolvePort(NSInteger port, NSError **error) {
    @try {
        NSString *shellCommand = [NSString stringWithFormat:@"sudo lsof -i :%ld -n -P -Fcp", (long)port];
        NSError *executionError = nil;
        NSString *shellResult = shell(shellCommand, &executionError);

        if (executionError != nil) {
            if (executionError.code == PortResolverErrorCommandExecution && [executionError.userInfo[@"terminationStatus"] intValue] == 1) {
                *error = createError(PortResolverErrorProcessNotFound, [NSString stringWithFormat:@"Process info not found for port: %ld", (long)port]);
                return nil;
            }
            *error = executionError;
            return nil;
        }
        
        NSArray *inputLines = [shellResult componentsSeparatedByString:@"\n"];

        NSString *pid = nil;
        NSString *pname = nil;

        // Extract the PID and process name from the lsof output
        for (NSString *line in inputLines) {
            if ([line hasPrefix:@"p"]) {
                pid = [line substringFromIndex:1]; // Remove the 'p' prefix
            } else if ([line hasPrefix:@"c"]) {
                pname = [line substringFromIndex:1]; // Remove the 'c' prefix
                if (![pname isEqualToString:@"PacketTunnel"]) {
                    NSLog(@"First valid process found - PID: %@, Name: %@", pid, pname);
                    break; // Stop processing as soon as the first valid process is found
                }
            }
        }
        
        // Attempt to retrieve the bundle ID from the cache
        NSString *cachedBundleID = [processNameToBundleIDCache objectForKey:pname];
        if (cachedBundleID) {
            NSLog(@"Found BundleID: %@ for process: %@ in cache", cachedBundleID, pname);
            return cachedBundleID; // Return the cached value if it exists
        } else {
            // Check if the process name exists in the timestamp dictionary
            NSDate *lastCheckDate = processNameToTimestampCache[pname];
            if (lastCheckDate) {
                NSTimeInterval timeSinceLastCheck = [[NSDate date] timeIntervalSinceDate:lastCheckDate];
                if (timeSinceLastCheck < 100) {
                    // If the entry is still within its lifespan, return nil to indicate no bundleID was found previously
                    NSDictionary *userInfo = @{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Path to executable not found previously for Process: %@, PID: %@", pname, pid], @"pname": pname};
                    *error = [NSError errorWithDomain:portResolverBundleID code:PortResolverErrorPathNotFound userInfo:userInfo];
                    return nil;
                }
                // If the entry is beyond its lifespan, remove it from the dictionary and continue with new check
                [processNameToTimestampCache removeObjectForKey:pname];
            }
        }

        shellCommand = [NSString stringWithFormat:@"sudo lsof -p %@ -Fn | grep .app/", pid];
        NSString *resolvedResult = shell(shellCommand, &executionError);

        if (executionError != nil) {
            if (executionError.code == PortResolverErrorCommandExecution && [executionError.userInfo[@"terminationStatus"] intValue] == 1) {
                //Add Process to cache
                [processNameToTimestampCache setObject:[NSDate date] forKey:pname];
                NSDictionary *userInfo = @{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Path to executable not found for Process: %@, PID: %@", pname, pid], @"pname": pname};
                *error = [NSError errorWithDomain:portResolverBundleID code:PortResolverErrorPathNotFound userInfo:userInfo];
                return nil;
            }
            //Not adding process to cache because this is a edge case
            *error = executionError;
            return nil;
        }
        
        //remove trailing 'n'
        NSString *pathToExecutable = [resolvedResult substringFromIndex:1];
        NSRange appRange = [pathToExecutable rangeOfString:@".app/"];
        if (appRange.location != NSNotFound) {
            // Include ".app/" in the result and cut off everything after
            NSString *finalPath = [pathToExecutable substringToIndex:NSMaxRange(appRange)];
            pathToExecutable = [finalPath stringByAppendingString:@"Info.plist"];
        } else {
            //Not adding process to cache because this is a edge case
            *error = createError(PortResolverErrorStringSlicing, [NSString stringWithFormat:@"Failed to get path to executable from string: \n %@", resolvedResult]);
            return nil;
        }

        shellCommand = [NSString stringWithFormat:@"plutil -key CFBundleIdentifier \"%@\"", pathToExecutable];
        NSString *finalResult = shell(shellCommand, error);

        if (*error != nil) {
            //Not adding process to cache because this is a edge case
            return nil;
        }
        
        // Add bundleID to cache
        addToBundleIDcache(pname, finalResult);

        return finalResult;
    } @catch (NSException *exception) {
        if (error != NULL) {
            *error = createError(PortResolverErrorCommandExecution, [NSString stringWithFormat:@"Exception during resolvePort(%ld): %@", (long)port, exception.reason]);
        }
        return nil;
    }
}

/**
 Fetches ports, resolves ports and writes their associated bundle IDs to the database.
 */
static void resolvePortsAndWriteToDB() {
    // Get the ports to resolve and its ID as a cross-database foreign key
    const char *query = "SELECT ID, port FROM Connection WHERE ID > ?";
    sqlite3_stmt *statement;

    if (sqlite3_prepare_v2(readDatabase, query, -1, &statement, NULL) == SQLITE_OK) {
        sqlite3_bind_int(statement, 1, lastProcessedId);
        
        NSLog(@"Getting new ports with lastProcessedId: %d", lastProcessedId);

        while (sqlite3_step(statement) == SQLITE_ROW) {
            int rowId = sqlite3_column_int(statement, 0);
            int port = sqlite3_column_int(statement, 1);
            
            NSDate *portStartTime = [NSDate date]; // Start timer for resolving the port

            NSError *resolveError = nil;
            NSString *bundleID = resolvePort(port, &resolveError);
            
            NSDate *portEndTime = [NSDate date]; // End timer for resolving the port
            NSTimeInterval portProcessingTime = [portEndTime timeIntervalSinceDate:portStartTime];

            // Capture if and what kind of error occured
            if (resolveError != nil) {
                NSLog(@"Processed rowId: %d, port %d got error: '%@' took %.2f seconds", rowId, port, resolveError.localizedDescription, portProcessingTime);
                if (resolveError.code == PortResolverErrorProcessNotFound){
                    bundleID = @"1";
                } else if (resolveError.code == PortResolverErrorPathNotFound){
                    bundleID = [NSString stringWithFormat:@"2_%@", resolveError.userInfo[@"pname"]];
                } else {
                    bundleID = resolveError.localizedDescription;
                }
            } else {
                NSLog(@"Processed rowId: %d, port %d got BundleID: %@ took %.2f seconds", rowId, port, bundleID, portProcessingTime);
            }

            // Insert the BundleID or the error with the cross-database foreign key
            const char *insertQuery = "INSERT INTO BundleID (Connection_ID, bundleID) VALUES (?, ?)";
            sqlite3_stmt *insertStmt;

            if (sqlite3_prepare_v2(writeDatabase, insertQuery, -1, &insertStmt, NULL) == SQLITE_OK) {
                sqlite3_bind_int(insertStmt, 1, rowId);
                sqlite3_bind_text(insertStmt, 2, [bundleID UTF8String], -1, SQLITE_STATIC);

                if (sqlite3_step(insertStmt) != SQLITE_DONE) {
                    NSLog(@"Error writing to database: %s", sqlite3_errmsg(writeDatabase));
                    lastProcessedId = rowId; // Update the last processed id
                    continue;
                }
                sqlite3_finalize(insertStmt);
            } else {
                NSLog(@"Error preparing insert statement: %s", sqlite3_errmsg(writeDatabase));
                lastProcessedId = rowId; // Update the last processed id
                continue;
            }
            
            lastProcessedId = rowId; // Update the last processed id
        }
        sqlite3_finalize(statement);
    } else {
        NSLog(@"Error preparing select statement: %s", sqlite3_errmsg(readDatabase));
    }
}

/**
 Handles termination signals for cleanup operations.
 
 @param signum The signal number.
 */
static void signalHandler(int signum) {
    NSLog(@"Received SIGTERM, disconnecting from databases...");
    disconnectFromDatabase();
    exit(0); // Exit gracefully
}

/**
 The main function of the program.
 
 @param argc The number of command-line arguments.
 @param argv The array of command-line arguments.
 @return An integer indicating the success or failure of the program.
 */
int main(int argc, const char *argv[]) {
    // Handles termination signals for cleanup operations
    signal(SIGTERM, signalHandler);
    
    @autoreleasepool {
        // Get environment vairables from .plist file
        environment = [[NSProcessInfo processInfo] environment];
        readDatabasePath = environment[@"HeimdallDatabasePath"];
        writeDatabasePath = environment[@"AppDumpDatabasePath"];
        shellPath = environment[@"SHELL"];
        portResolverBundleID = environment[@"DaemonLable"];

        if (!readDatabasePath || !writeDatabasePath || !shellPath) {
            NSLog(@"One or more required environment variables are not set.");
            return 1; // Exit with an error code
        }
        
        // Setup DB connections
        connectToDatabases();
        // Set the start ID of traffic records (ports) to the highes available sequence number
        lastProcessedId = getLastProcessedID();

        // Setup caches
        processNameToBundleIDCache = [[NSCache alloc] init];
        processNameToTimestampCache = [[NSMutableDictionary alloc] init];
        fillBundleIDcachefromDB();

        // Loop infinitely, pulling ports form the read DB, resolving ports to BundleIDs and writing ports to the read DB
        while (1) {
            resolvePortsAndWriteToDB();
            sleep(1);
        }
    }
    return 0;
}
