import Foundation
import GRDB
import SignalServiceKit

/// Database schema for image hashes
struct ImageHashRecord: Codable, FetchableRecord, PersistableRecord {
    let id: Int64?
    let hash: String
    let conversationId: String
    let timestamp: Date
    let attachmentId: String?
    let filename: String?
    let blocked: Bool
    
    init(id: Int64? = nil, hash: String, conversationId: String, timestamp: Date = Date(), attachmentId: String? = nil, filename: String? = nil, blocked: Bool = false) {
        self.id = id
        self.hash = hash
        self.conversationId = conversationId
        self.timestamp = timestamp
        self.attachmentId = attachmentId
        self.filename = filename
        self.blocked = blocked
    }
    
    // Define table name
    static var databaseTableName: String { "image_hashes" }
    
    // Define database column names
    enum Columns: String, ColumnExpression {
        case id, hash, conversationId, timestamp, attachmentId, filename, blocked
    }
}

/// Manages storage and retrieval of image hashes
class HashDatabase {
    private let databaseQueue: DatabaseQueue
    private static let shared = HashDatabase()
    
    static func getInstance() -> HashDatabase {
        return shared
    }
    
    private init() {
        // Get the app's document directory
        let fileManager = FileManager.default
        let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let databaseURL = documentDirectory.appendingPathComponent("image_hashes.sqlite")
        
        // Create the database
        do {
            databaseQueue = try DatabaseQueue(path: databaseURL.path)
            try migrateDatabaseIfNeeded()
        } catch {
            owsFailDebug("Could not open database: \(error)")
            fatalError("Database initialization failed: \(error)")
        }
    }
    
    // MARK: - Schema Migration
    
    private func migrateDatabaseIfNeeded() throws {
        try databaseQueue.write { db in
            // Check if table exists
            let tableExists = try db.tableExists(ImageHashRecord.databaseTableName)
            
            if !tableExists {
                // Create the table if it doesn't exist
                try db.create(table: ImageHashRecord.databaseTableName) { t in
                    t.autoIncrementedPrimaryKey("id")
                    t.column("hash", .text).notNull()
                    t.column("conversationId", .text).notNull()
                    t.column("timestamp", .datetime).notNull()
                    t.column("attachmentId", .text)
                    t.column("filename", .text)
                    t.column("blocked", .boolean).notNull().defaults(to: false)
                    
                    // Add indexes
                    t.index(["hash"])
                    t.index(["conversationId"])
                    t.index(["blocked"])
                }
            } else {
                // Check if blocked column exists, add it if it doesn't
                let columns = try db.columns(in: ImageHashRecord.databaseTableName)
                let columnNames = columns.map { $0.name }
                
                if !columnNames.contains("blocked") {
                    try db.alter(table: ImageHashRecord.databaseTableName) { t in
                        t.add(column: "blocked", .boolean).notNull().defaults(to: false)
                    }
                    Logger.info("Added 'blocked' column to image_hashes table")
                }
            }
        }
    }
    
    // MARK: - Database Operations
    
    /// Add a new image hash to the database
    func addImageHash(hash: String, conversationId: String, attachmentId: String? = nil, filename: String? = nil) -> Bool {
        do {
            let record = ImageHashRecord(
                hash: hash,
                conversationId: conversationId,
                timestamp: Date(),
                attachmentId: attachmentId,
                filename: filename,
                blocked: false
            )
            
            try databaseQueue.write { db in
                try record.insert(db)
            }
            Logger.debug("Added hash \(hash) to database")
            return true
        } catch {
            owsFailDebug("Failed to add image hash: \(error)")
            return false
        }
    }
    
    /// Block a specific image signature
    func blockSignature(_ hash: String) -> Bool {
        do {
            try databaseQueue.write { db in
                // Update any existing records with this hash
                try db.execute(
                    sql: "UPDATE \(ImageHashRecord.databaseTableName) SET blocked = 1 WHERE hash = ?",
                    arguments: [hash]
                )
                
                // If no records were updated, create a new blocked record
                let count = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM \(ImageHashRecord.databaseTableName) WHERE hash = ?",
                    arguments: [hash]
                ) ?? 0
                
                if count == 0 {
                    let record = ImageHashRecord(
                        hash: hash,
                        conversationId: "blocked_manually",
                        timestamp: Date(),
                        blocked: true
                    )
                    try record.insert(db)
                }
            }
            Logger.info("Blocked hash signature: \(hash)")
            return true
        } catch {
            owsFailDebug("Failed to block hash: \(error)")
            return false
        }
    }
    
    /// Unblock a previously blocked signature
    func unblockSignature(_ hash: String) -> Bool {
        do {
            try databaseQueue.write { db in
                try db.execute(
                    sql: "UPDATE \(ImageHashRecord.databaseTableName) SET blocked = 0 WHERE hash = ?",
                    arguments: [hash]
                )
            }
            Logger.info("Unblocked hash signature: \(hash)")
            return true
        } catch {
            owsFailDebug("Failed to unblock hash: \(error)")
            return false
        }
    }
    
    /// Check if an image signature is blocked
    func isSignatureBlocked(_ hash: String) -> Bool {
        do {
            return try databaseQueue.read { db in
                let count = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM \(ImageHashRecord.databaseTableName) WHERE hash = ? AND blocked = 1",
                    arguments: [hash]
                ) ?? 0
                return count > 0
            }
        } catch {
            owsFailDebug("Failed to check if hash is blocked: \(error)")
            return false
        }
    }
    
    /// Get all blocked signatures
    func getBlockedSignatures() -> [ImageHashRecord] {
        do {
            return try databaseQueue.read { db in
                try ImageHashRecord
                    .filter(ImageHashRecord.Columns.blocked == true)
                    .order(ImageHashRecord.Columns.timestamp.desc)
                    .fetchAll(db)
            }
        } catch {
            owsFailDebug("Failed to fetch blocked hashes: \(error)")
            return []
        }
    }
    
    /// Get all image hashes
    func getAllImageHashes() -> [ImageHashRecord] {
        do {
            return try databaseQueue.read { db in
                try ImageHashRecord
                    .order(ImageHashRecord.Columns.timestamp.desc)
                    .fetchAll(db)
            }
        } catch {
            owsFailDebug("Failed to fetch hashes: \(error)")
            return []
        }
    }
    
    /// Find similar images based on hash distance
    func findSimilarImages(hash: String, threshold: Int) -> [ImageHashRecord] {
        // Get all hashes to compare
        let allRecords = getAllImageHashes()
        
        // Compare and filter
        return allRecords.filter { record in
            ImageHasher.areImagesSimilar(hash, record.hash, threshold: threshold)
        }
    }
    
    /// Clear old hashes
    func clearOldHashes(olderThan: Date) -> Int {
        do {
            return try databaseQueue.write { db in
                // Keep blocked hashes regardless of age
                try ImageHashRecord
                    .filter(ImageHashRecord.Columns.timestamp < olderThan)
                    .filter(ImageHashRecord.Columns.blocked == false)
                    .deleteAll(db)
            }
        } catch {
            owsFailDebug("Failed to clear old hashes: \(error)")
            return 0
        }
    }
    
    /// Delete all hashes
    func deleteAllHashes() -> Int {
        do {
            return try databaseQueue.write { db in
                try ImageHashRecord.deleteAll(db)
            }
        } catch {
            owsFailDebug("Failed to delete all hashes: \(error)")
            return 0
        }
    }
    
    /// Delete all non-blocked hashes
    func clearNonBlockedHashes() -> Int {
        do {
            return try databaseQueue.write { db in
                try ImageHashRecord
                    .filter(ImageHashRecord.Columns.blocked == false)
                    .deleteAll(db)
            }
        } catch {
            owsFailDebug("Failed to clear non-blocked hashes: \(error)")
            return 0
        }
    }
}