import Foundation

/// A 64-bit FNV-1a hash of a frame's pixel bytes, used to detect identical frames.
public struct FrameDigest: Hashable, Sendable, CustomStringConvertible {
    public static let fnvOffsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
    public static let fnvPrime: UInt64 = 0x0000_0100_0000_01b3

    public let value: UInt64

    public init(value: UInt64) {
        self.value = value
    }

    /// Hashes every byte of `bytes`.
    public init(bytes: UnsafeRawBufferPointer) {
        var hasher = FNV1a64()
        hasher.combine(bytes)
        value = hasher.value
    }

    /// Hashes every byte of `bytes`, using contiguous storage when available.
    public init<C: Collection>(_ bytes: C) where C.Element == UInt8 {
        var hasher = FNV1a64()
        let usedFastPath: Void? = bytes.withContiguousStorageIfAvailable { buffer in
            hasher.combine(UnsafeRawBufferPointer(buffer))
        }
        if usedFastPath == nil {
            for byte in bytes {
                hasher.combine(byte)
            }
        }
        value = hasher.value
    }

    /// Hashes a bitmap row by row, ignoring per-row padding.
    ///
    /// Bitmaps often have `bytesPerRow` larger than the bytes actually used by a
    /// row; that padding is not guaranteed to be stable, so only the first
    /// `rowLength` bytes of each of the `rowCount` rows are hashed. Rows that fall
    /// outside `bytes` are skipped. With a non-positive stride or row length the
    /// whole buffer is hashed.
    public init(rows bytes: UnsafeRawBufferPointer, bytesPerRow: Int, rowLength: Int, rowCount: Int) {
        var hasher = FNV1a64()
        if bytesPerRow > 0, rowLength > 0 {
            let usedLength = min(rowLength, bytesPerRow)
            for row in 0..<max(0, rowCount) {
                let start = row * bytesPerRow
                guard start < bytes.count else { break }
                let end = min(start + usedLength, bytes.count)
                hasher.combine(UnsafeRawBufferPointer(rebasing: bytes[start..<end]))
            }
        } else {
            hasher.combine(bytes)
        }
        value = hasher.value
    }

    public var description: String {
        let hex = String(value, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}

/// Streaming FNV-1a (64-bit) hasher.
struct FNV1a64 {
    private(set) var value = FrameDigest.fnvOffsetBasis

    mutating func combine(_ byte: UInt8) {
        value = (value ^ UInt64(byte)) &* FrameDigest.fnvPrime
    }

    mutating func combine(_ buffer: UnsafeRawBufferPointer) {
        var hash = value
        for byte in buffer {
            hash = (hash ^ UInt64(byte)) &* FrameDigest.fnvPrime
        }
        value = hash
    }
}
