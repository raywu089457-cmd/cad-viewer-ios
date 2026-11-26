import Foundation

/// The byte-order mark some writers put before a text file.
///
/// A DXF is read as text and starts with a group code, so three bytes of BOM in front of that
/// turn the first group code into something no reader recognises. `DXF.read` does not throw —
/// it finds no entities and returns an empty drawing, which the app then shows as a blank canvas
/// while reporting success. Windows editors write a BOM by default, so this is not a rare file:
/// it is a drawing saved on Windows and opened here.
///
/// Only the UTF-8 mark is removed. UTF-16 and UTF-32 marks would mean the file is not ASCII at
/// all, and truncating those bytes would leave something worse than a clear failure.
public enum DXFByteOrderMark {
    /// The UTF-8 byte-order mark, `EF BB BF`.
    public static let utf8: [UInt8] = [0xEF, 0xBB, 0xBF]

    /// Whether the data begins with a UTF-8 byte-order mark.
    public static func present(in data: Data) -> Bool {
        guard data.count >= utf8.count else { return false }
        return Array(data.prefix(utf8.count)) == utf8
    }

    /// The data without a leading UTF-8 byte-order mark, or the same data when there is none.
    public static func stripping(from data: Data) -> Data {
        guard present(in: data) else { return data }
        return data.dropFirst(utf8.count)
    }
}
