import Foundation
import SQLite3

final class DatabaseManager {
    
    static let shared = DatabaseManager()
    
    private var db: OpaquePointer?
    private let dbQueue = DispatchQueue(label: "com.aiemail.database", qos: .userInitiated)
    
    private var schemaVersion: Int = 0
    
    private init() {}
    
    // MARK: - Public Interface
    
    func initialize() throws {
        try dbQueue.sync {
            if db != nil {
                throw DatabaseError.alreadyInitialized
            }
            
            let fileManager = FileManager.default
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            
            let dbDir = appSupport.appendingPathComponent("AIEmail", isDirectory: true)
            try fileManager.createDirectory(at: dbDir, withIntermediateDirectories: true)
            
            let dbPath = dbDir.appendingPathComponent("aiemail.sqlite3").path
            
            var tempDb: OpaquePointer?
            let result = sqlite3_open(dbPath, &tempDb)
            
            guard result == SQLITE_OK else {
                let errorMsg = String(cString: sqlite3_errmsg(tempDb))
                sqlite3_close(tempDb)
                throw DatabaseError.executionFailed("Failed to open database: \(errorMsg)")
            }
            
            db = tempDb
            
            try configurePragmas()
            try runMigrations()
            try createSchema()
        }
    }
    
    func close() {
        dbQueue.sync {
            guard let db = db else { return }
            sqlite3_close(db)
            self.db = nil
        }
    }
    
    func execute(_ sql: String) throws {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseError.notInitialized
            }
            
            var errorMsg: UnsafeMutablePointer<CChar>?
            let result = sqlite3_exec(db, sql, nil, nil, &errorMsg)
            
            if result != SQLITE_OK {
                let error = errorMsg != nil ? String(cString: errorMsg!) : "Unknown error"
                sqlite3_free(errorMsg)
                throw DatabaseError.executionFailed(error)
            }
        }
    }
    
    func transaction(_ block: () throws -> Void) throws {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseError.notInitialized
            }
            
            try executeUnsafe("BEGIN TRANSACTION")
            
            do {
                try block()
                try executeUnsafe("COMMIT")
            } catch {
                try executeUnsafe("ROLLBACK")
                throw error
            }
        }
    }
    
    func getDatabase() throws -> OpaquePointer {
        guard let db = db else {
            throw DatabaseError.notInitialized
        }
        return db
    }
    
    // MARK: - Private Helpers
    
    private func configurePragmas() throws {
        guard let db = db else { return }
        
        let pragmas = [
            "PRAGMA journal_mode = WAL",
            "PRAGMA synchronous = NORMAL",
            "PRAGMA foreign_keys = ON",
            "PRAGMA busy_timeout = 5000",
            "PRAGMA cache_size = -64000",
            "PRAGMA temp_store = MEMORY"
        ]
        
        for pragma in pragmas {
            var errorMsg: UnsafeMutablePointer<CChar>?
            let result = sqlite3_exec(db, pragma, nil, nil, &errorMsg)
            if result != SQLITE_OK {
                let error = errorMsg != nil ? String(cString: errorMsg!) : "Unknown error"
                sqlite3_free(errorMsg)
                throw DatabaseError.executionFailed("PRAGMA failed: \(error)")
            }
        }
    }
    
    private func runMigrations() throws {
        let userVersion = try getUserVersion()
        schemaVersion = userVersion
        
        if userVersion < SchemaVersion.initial.rawValue {
            try setUserVersion(SchemaVersion.initial.rawValue)
            schemaVersion = SchemaVersion.initial.rawValue
        }
    }
    
    private func getUserVersion() throws -> Int {
        guard let db = db else {
            throw DatabaseError.notInitialized
        }
        
        var stmt: OpaquePointer?
        let result = sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil)
        
        guard result == SQLITE_OK else {
            throw DatabaseError.executionFailed("Failed to prepare pragma query")
        }
        
        defer { sqlite3_finalize(stmt) }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        
        return 0
    }
    
    private func setUserVersion(_ version: Int) throws {
        try execute("PRAGMA user_version = \(version)")
    }
    
    private func createSchema() throws {
        guard let db = db else {
            throw DatabaseError.notInitialized
        }
        
        let schemaStatements = [
            Schema.createAccountsTable,
            Schema.createFoldersTable,
            Schema.createEmailsTable,
            Schema.createAttachmentsTable,
            Schema.createFTS5Table,
            Schema.createAIProcessingTable
        ]
        
        for sql in schemaStatements {
            var errorMsg: UnsafeMutablePointer<CChar>?
            let result = sqlite3_exec(db, sql, nil, nil, &errorMsg)
            if result != SQLITE_OK {
                let error = errorMsg != nil ? String(cString: errorMsg!) : "Unknown error"
                sqlite3_free(errorMsg)
                throw DatabaseError.executionFailed("Schema creation failed: \(error)")
            }
        }
        
        for indexSQL in Schema.createIndexes {
            try execute(indexSQL)
        }
        
        for triggerSQL in Schema.createFTSTriggers {
            try execute(triggerSQL)
        }
    }
    
    private func executeUnsafe(_ sql: String) throws {
        guard let db = db else {
            throw DatabaseError.notInitialized
        }
        
        var errorMsg: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMsg)
        
        if result != SQLITE_OK {
            let error = errorMsg != nil ? String(cString: errorMsg!) : "Unknown error"
            sqlite3_free(errorMsg)
            throw DatabaseError.executionFailed(error)
        }
    }
}

// MARK: - DatabaseManager Extension for SQLite.swift

extension DatabaseManager {
    func prepareStatement(_ sql: String) throws -> OpaquePointer {
        guard let db = db else {
            throw DatabaseError.notInitialized
        }
        
        var stmt: OpaquePointer?
        let result = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        
        guard result == SQLITE_OK else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.executionFailed("Prepare statement failed: \(errorMsg)")
        }
        
        guard let statement = stmt else {
            throw DatabaseError.executionFailed("Failed to create statement")
        }
        
        return statement
    }
    
    func finalizeStatement(_ stmt: OpaquePointer) {
        sqlite3_finalize(stmt)
    }
}
