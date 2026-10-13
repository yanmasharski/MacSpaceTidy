import Darwin
import Foundation

/// One entry of a folder, as `getattrlistbulk` returns it.
struct BulkEntry {
    static let TYPE_FILE: UInt32 = 1
    static let TYPE_DIRECTORY: UInt32 = 2

    let name: String
    let type: UInt32
    let modifiedSeconds: Int
    let fileID: UInt64
    let linkCount: UInt32
    /// Bytes allocated on disk, all forks. Zero for folders.
    let allocatedBytes: Int64
    let hasError: Bool

    var isDirectory: Bool {
        return type == BulkEntry.TYPE_DIRECTORY
    }
}

/// Reads a whole folder with `getattrlistbulk(2)`: one system call returns names, types, dates and sizes
/// for hundreds of entries, instead of one `readdir` and one `lstat` per file.
/// The idea comes from SpaceGuard (https://github.com/mkrn/spaceguard); this code is written from the Apple man page.
final class BulkDirectoryReader {
    // Attribute bits from <sys/attr.h>. Spelled out because the imported macros have mixed integer types.
    private static let CMN_NAME: UInt32 = 0x0000_0001
    private static let CMN_OBJTYPE: UInt32 = 0x0000_0008
    private static let CMN_MODTIME: UInt32 = 0x0000_0400
    private static let CMN_FILEID: UInt32 = 0x0200_0000
    private static let CMN_ERROR: UInt32 = 0x2000_0000
    private static let CMN_RETURNED_ATTRS: UInt32 = 0x8000_0000
    private static let FILE_LINKCOUNT: UInt32 = 0x0000_0001
    private static let FILE_ALLOCSIZE: UInt32 = 0x0000_0004
    // Record layout: length (4), attribute_set_t (20: common, volume, dir, file, fork), then the values.
    private static let COMMON_SET_OFFSET = 4
    private static let FILE_SET_OFFSET = 16
    private static let VALUES_OFFSET = 24
    private static let NAME_FIELD_BYTES = 8
    private static let TIMESPEC_BYTES = 16
    private static let BUFFER_BYTES = 256 * 1024

    private let buffer = UnsafeMutableRawPointer.allocate(byteCount: BulkDirectoryReader.BUFFER_BYTES, alignment: 16)
    private var request = attrlist()

    init() {
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = BulkDirectoryReader.CMN_RETURNED_ATTRS | BulkDirectoryReader.CMN_NAME | BulkDirectoryReader.CMN_ERROR
            | BulkDirectoryReader.CMN_OBJTYPE | BulkDirectoryReader.CMN_MODTIME | BulkDirectoryReader.CMN_FILEID
        request.fileattr = BulkDirectoryReader.FILE_LINKCOUNT | BulkDirectoryReader.FILE_ALLOCSIZE
    }

    deinit {
        buffer.deallocate()
    }

    /// Calls `body` for every entry of an open folder. Returns false when reading failed.
    @discardableResult
    func forEachEntry(of descriptor: Int32, _ body: (BulkEntry) -> Void) -> Bool {
        while true {
            let count = getattrlistbulk(descriptor, &request, buffer, BulkDirectoryReader.BUFFER_BYTES, 0)
            if count < 0 {
                if errno == EINTR {
                    continue
                }
                return false
            }
            if count == 0 {
                return true
            }
            var record = UnsafeRawPointer(buffer)
            for _ in 0..<count {
                let length = Int(record.loadUnaligned(as: UInt32.self))
                if let entry = parse(record) {
                    body(entry)
                }
                record += length
            }
        }
    }

    private func parse(_ record: UnsafeRawPointer) -> BulkEntry? {
        let common = record.loadUnaligned(fromByteOffset: BulkDirectoryReader.COMMON_SET_OFFSET, as: UInt32.self)
        let file = record.loadUnaligned(fromByteOffset: BulkDirectoryReader.FILE_SET_OFFSET, as: UInt32.self)
        var field = record + BulkDirectoryReader.VALUES_OFFSET
        var hasError = false
        var name = ""
        var type: UInt32 = 0
        var modified = 0
        var fileID: UInt64 = 0
        var linkCount: UInt32 = 1
        var allocated: Int64 = 0
        if common & BulkDirectoryReader.CMN_ERROR != 0 {
            hasError = field.loadUnaligned(as: UInt32.self) != 0
            field += MemoryLayout<UInt32>.size
        }
        if common & BulkDirectoryReader.CMN_NAME != 0 {
            let offset = Int(field.loadUnaligned(as: Int32.self))
            name = String(cString: (field + offset).assumingMemoryBound(to: CChar.self))
            field += BulkDirectoryReader.NAME_FIELD_BYTES
        }
        if common & BulkDirectoryReader.CMN_OBJTYPE != 0 {
            type = field.loadUnaligned(as: UInt32.self)
            field += MemoryLayout<UInt32>.size
        }
        if common & BulkDirectoryReader.CMN_MODTIME != 0 {
            modified = field.loadUnaligned(as: Int.self)
            field += BulkDirectoryReader.TIMESPEC_BYTES
        }
        if common & BulkDirectoryReader.CMN_FILEID != 0 {
            fileID = field.loadUnaligned(as: UInt64.self)
            field += MemoryLayout<UInt64>.size
        }
        if file & BulkDirectoryReader.FILE_LINKCOUNT != 0 {
            linkCount = field.loadUnaligned(as: UInt32.self)
            field += MemoryLayout<UInt32>.size
        }
        if file & BulkDirectoryReader.FILE_ALLOCSIZE != 0 {
            allocated = field.loadUnaligned(as: Int64.self)
        }
        return BulkEntry(
            name: name, type: type, modifiedSeconds: modified, fileID: fileID,
            linkCount: linkCount, allocatedBytes: allocated, hasError: hasError
        )
    }
}
