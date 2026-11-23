import Foundation
import zlib

enum HealthImportError: LocalizedError {
    case invalidArchive, missingExport, unsupportedArchive, corruptExport, invalidXML, emptyExport

    var errorDescription: String? {
        switch self {
        case .invalidArchive: "无法读取这个 ZIP 文件。"
        case .missingExport: "ZIP 中找不到「健康」的导出 XML。"
        case .unsupportedArchive: "这个 ZIP 的压缩方式、加密或分卷格式暂不支持。"
        case .corruptExport: "压缩包中的导出文件不完整或校验失败。"
        case .invalidXML: "文件不是有效的 Apple「健康」导出 XML。"
        case .emptyExport: "这份导出中没有可显示的健康记录。"
        }
    }
}

struct HealthZip {
    private struct Entry {
        let method: UInt16
        let flags: UInt16
        let checksum: UInt32
        let compressed: UInt64
        let expanded: UInt64
        let position: UInt64
    }

    private struct Directory {
        let offset: UInt64
        let length: UInt64
        let count: UInt64
    }

    private static let chunkSize = 64 * 1_024
    private let source: FileHandle
    private let length: UInt64

    static func unpack(_ archive: URL, to output: URL, progress: (Double) -> Void) throws {
        let source = try FileHandle(forReadingFrom: archive)
        defer { try? source.close() }
        let zip = try Self(source: source)
        let entry = try zip.exportEntry()
        let destination = try FileHandle(forWritingTo: output)
        defer { try? destination.close() }
        try zip.extract(entry, to: destination, progress: progress)
    }

    private init(source: FileHandle) throws {
        self.source = source
        length = try source.seekToEnd()
    }

    private func directory() throws -> Directory {
        let tailSize = Int(min(length, 65_557))
        guard tailSize >= 22 else { throw HealthImportError.invalidArchive }
        let tailStart = length - UInt64(tailSize)
        let tail = try read(tailSize, at: tailStart)
        for index in stride(from: tailSize - 22, through: 0, by: -1) {
            guard tail.u32(index) == 0x0605_4b50,
                  index + 22 + Int(tail.u16(index + 20)) == tailSize else { continue }
            guard tail.u16(index + 4) == 0, tail.u16(index + 6) == 0 else {
                throw HealthImportError.unsupportedArchive
            }
            let count = tail.u16(index + 10)
            let size = tail.u32(index + 12)
            let start = tail.u32(index + 16)
            if count != .max, size != .max, start != .max {
                guard count == tail.u16(index + 8) else { throw HealthImportError.unsupportedArchive }
                return Directory(offset: UInt64(start), length: UInt64(size), count: UInt64(count))
            }

            let endOffset = tailStart + UInt64(index)
            guard endOffset >= 20 else { throw HealthImportError.invalidArchive }
            let locator = try read(20, at: endOffset - 20)
            guard locator.u32(0) == 0x0706_4b50 else { throw HealthImportError.invalidArchive }
            guard locator.u32(4) == 0, locator.u32(16) == 1 else { throw HealthImportError.unsupportedArchive }
            let record = try read(56, at: locator.u64(8))
            guard record.u32(0) == 0x0606_4b50, record.u64(4) >= 44 else {
                throw HealthImportError.invalidArchive
            }
            guard record.u32(16) == 0, record.u32(20) == 0, record.u64(24) == record.u64(32) else {
                throw HealthImportError.unsupportedArchive
            }
            return Directory(offset: record.u64(48), length: record.u64(40), count: record.u64(32))
        }
        throw HealthImportError.invalidArchive
    }

    private func exportEntry() throws -> Entry {
        let directory = try directory()
        guard directory.offset <= length, directory.length <= length - directory.offset,
              directory.count <= directory.length / 46 else { throw HealthImportError.invalidArchive }
        let end = directory.offset + directory.length
        let preferred: Set<String> = ["export.xml", "导出.xml", "輸出.xml", "匯出.xml"]
        var cursor = directory.offset
        var fallback: Entry?
        for _ in 0..<directory.count {
            try Task.checkCancellation()
            guard cursor <= end, end - cursor >= 46 else { throw HealthImportError.invalidArchive }
            let header = try read(46, at: cursor)
            guard header.u32(0) == 0x0201_4b50 else { throw HealthImportError.invalidArchive }
            let nameLength = Int(header.u16(28))
            let extraLength = Int(header.u16(30))
            let remainingLength = UInt64(nameLength + extraLength + Int(header.u16(32)))
            guard remainingLength <= end - cursor - 46 else { throw HealthImportError.invalidArchive }
            let nameData = try read(nameLength, at: cursor + 46)
            let name = String(decoding: nameData, as: UTF8.self).split(separator: "/").last?.lowercased() ?? ""
            if preferred.contains(name) || (fallback == nil && name.hasSuffix(".xml") && !name.contains("cda")) {
                let extra = try read(extraLength, at: cursor + 46 + UInt64(nameLength))
                let candidate = try makeEntry(header: header, extra: extra)
                if preferred.contains(name) { return candidate }
                fallback = candidate
            }
            cursor += 46 + remainingLength
        }
        guard let fallback else { throw HealthImportError.missingExport }
        return fallback
    }

    private func makeEntry(header: Data, extra: Data) throws -> Entry {
        let originalExpanded = header.u32(24)
        let originalCompressed = header.u32(20)
        let originalPosition = header.u32(42)
        var expanded = UInt64(originalExpanded)
        var compressed = UInt64(originalCompressed)
        var position = UInt64(originalPosition)
        let disk = header.u16(34)
        guard disk == 0 else { throw HealthImportError.unsupportedArchive }
        if originalExpanded == .max || originalCompressed == .max || originalPosition == .max {
            var offset = 0
            var found = false
            while offset + 4 <= extra.count {
                let size = Int(extra.u16(offset + 2))
                let start = offset + 4
                guard size <= extra.count - start else { throw HealthImportError.invalidArchive }
                if extra.u16(offset) == 1 {
                    var index = start
                    func next64() throws -> UInt64 {
                        guard index + 8 <= start + size else { throw HealthImportError.invalidArchive }
                        defer { index += 8 }
                        return extra.u64(index)
                    }
                    if originalExpanded == .max { expanded = try next64() }
                    if originalCompressed == .max { compressed = try next64() }
                    if originalPosition == .max { position = try next64() }
                    found = true
                    break
                }
                offset = start + size
            }
            guard found else { throw HealthImportError.invalidArchive }
        }
        return Entry(method: header.u16(10), flags: header.u16(8), checksum: header.u32(16),
                     compressed: compressed, expanded: expanded, position: position)
    }

    private func extract(_ entry: Entry, to destination: FileHandle, progress: (Double) -> Void) throws {
        guard entry.flags & 1 == 0, entry.method == 0 || entry.method == 8 else {
            throw HealthImportError.unsupportedArchive
        }
        let header = try read(30, at: entry.position)
        guard header.u32(0) == 0x0403_4b50, header.u16(8) == entry.method else {
            throw HealthImportError.corruptExport
        }
        let start = entry.position + 30 + UInt64(header.u16(26)) + UInt64(header.u16(28))
        guard start <= length, entry.compressed <= length - start else { throw HealthImportError.corruptExport }
        try source.seek(toOffset: start)
        var left = entry.compressed
        var written: UInt64 = 0
        var checksum = crc32(0, nil, 0)
        var lastPercent = -1

        func write(_ data: Data) throws {
            guard UInt64(data.count) <= entry.expanded - written else { throw HealthImportError.corruptExport }
            checksum = data.withUnsafeBytes { bytes in
                crc32(checksum, bytes.bindMemory(to: UInt8.self).baseAddress, UInt32(bytes.count))
            }
            try destination.write(contentsOf: data)
            written += UInt64(data.count)
        }

        func input() throws -> Data {
            try Task.checkCancellation()
            let data = try read(Int(min(left, UInt64(Self.chunkSize))))
            left -= UInt64(data.count)
            let fraction = entry.compressed == 0 ? 1 : Double(entry.compressed - left) / Double(entry.compressed)
            let percent = Int(fraction * 100)
            if percent != lastPercent {
                progress(fraction)
                lastPercent = percent
            }
            return data
        }

        if entry.method == 0 {
            guard entry.compressed == entry.expanded else { throw HealthImportError.corruptExport }
            while left > 0 { try write(input()) }
        } else {
            var stream = z_stream()
            guard inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                throw HealthImportError.corruptExport
            }
            defer { inflateEnd(&stream) }
            var output = [UInt8](repeating: 0, count: Self.chunkSize)
            var ended = false

            while left > 0, !ended {
                let data = try input()
                try data.withUnsafeBytes { raw in
                    guard let base = raw.bindMemory(to: UInt8.self).baseAddress else {
                        throw HealthImportError.corruptExport
                    }
                    stream.next_in = UnsafeMutablePointer(mutating: base)
                    stream.avail_in = UInt32(raw.count)
                    repeat {
                        try Task.checkCancellation()
                        let oldInput = stream.avail_in
                        let status = output.withUnsafeMutableBufferPointer { target in
                            stream.next_out = target.baseAddress
                            stream.avail_out = UInt32(target.count)
                            return inflate(&stream, Z_NO_FLUSH)
                        }
                        let produced = Self.chunkSize - Int(stream.avail_out)
                        if produced > 0 { try write(Data(output.prefix(produced))) }
                        if status == Z_STREAM_END {
                            ended = true
                            break
                        }
                        if status == Z_BUF_ERROR, stream.avail_in == 0 { break }
                        guard status == Z_OK, produced > 0 || stream.avail_in < oldInput else {
                            throw HealthImportError.corruptExport
                        }
                    } while stream.avail_in > 0 || stream.avail_out == 0
                }
            }
            guard ended, left == 0, stream.avail_in == 0 else { throw HealthImportError.corruptExport }
        }
        guard written == entry.expanded, checksum == entry.checksum else { throw HealthImportError.corruptExport }
    }

    private func read(_ count: Int, at offset: UInt64) throws -> Data {
        guard offset <= length, UInt64(count) <= length - offset else { throw HealthImportError.invalidArchive }
        try source.seek(toOffset: offset)
        return try read(count)
    }

    private func read(_ count: Int) throws -> Data {
        var data = Data()
        while data.count < count {
            guard let chunk = try source.read(upToCount: count - data.count), !chunk.isEmpty else {
                throw HealthImportError.invalidArchive
            }
            data.append(chunk)
        }
        return data
    }
}

private extension Data {
    func u16(_ offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func u32(_ offset: Int) -> UInt32 {
        UInt32(u16(offset)) | (UInt32(u16(offset + 2)) << 16)
    }

    func u64(_ offset: Int) -> UInt64 {
        UInt64(u32(offset)) | (UInt64(u32(offset + 4)) << 32)
    }
}
