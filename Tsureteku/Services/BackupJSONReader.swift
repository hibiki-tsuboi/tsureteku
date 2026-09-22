//
//  BackupJSONReader.swift
//  Tsureteku
//
//  Created by Claude on 2026/09/22.
//

import Foundation

/// バックアップJSONを先頭から少しずつ読むストリーミングリーダー。
/// 写真・動画を base64 で埋め込んだJSONは数GBになりうるため `JSONDecoder` で丸ごと読まず、
/// 構造をたどりながら必要な値だけを取り出す。base64 はデコードしながら直接ファイルへ書き出す。
nonisolated final class BackupJSONReader {
    enum ReadError: Error {
        case unexpectedEnd
        case unexpectedCharacter
        case valueTooLarge
        case invalidBase64
    }

    private static let readChunkSize = 1 << 20
    /// base64 をまとめてデコードする単位（4の倍数）。
    private static let base64DecodeBlockSize = 1 << 20

    private let handle: FileHandle
    private let onRead: (Int64) -> Void
    private var buffer: [UInt8] = []
    private var position = 0
    private var bufferStartOffset: Int64 = 0
    private var reachedEnd = false

    /// - Parameter onRead: ファイルを読み進めるたびに、読み終えたバイト数を渡す（進捗表示用）。
    init(url: URL, onRead: @escaping (Int64) -> Void = { _ in }) throws {
        handle = try FileHandle(forReadingFrom: url)
        self.onRead = onRead
    }

    deinit {
        try? handle.close()
    }

    // MARK: - 構造

    /// オブジェクトを読み、キーごとに `readValue` を呼ぶ。`readValue` はそのキーの値をちょうど1つ読み進めること。
    func readObject(_ readValue: (String) throws -> Void) throws {
        try expect(.openBrace)

        if try peekSignificant() == .closeBrace {
            position += 1
            return
        }

        while true {
            let key = try readString(maxLength: 1024)
            try expect(.colon)
            try readValue(key)

            switch try nextSignificant() {
            case .comma:
                continue
            case .closeBrace:
                return
            default:
                throw ReadError.unexpectedCharacter
            }
        }
    }

    /// 配列を読み、要素ごとに `readElement` を呼ぶ。`readElement` は要素をちょうど1つ読み進めること。
    func readArray(_ readElement: () throws -> Void) throws {
        try expect(.openBracket)

        if try peekSignificant() == .closeBracket {
            position += 1
            return
        }

        while true {
            try readElement()

            switch try nextSignificant() {
            case .comma:
                continue
            case .closeBracket:
                return
            default:
                throw ReadError.unexpectedCharacter
            }
        }
    }

    /// 残りが空白だけであることを確かめる。
    func expectEnd() throws {
        guard try peekSignificant() == nil else {
            throw ReadError.unexpectedCharacter
        }
    }

    // MARK: - 値

    func readString(maxLength: Int) throws -> String {
        guard try peekSignificant() == .quote else {
            throw ReadError.unexpectedCharacter
        }

        // エスケープやサロゲートペアの解釈は JSONDecoder に任せる。
        let raw = try readRawValue(maxLength: maxLength)
        return try JSONDecoder().decode(String.self, from: Data(raw))
    }

    /// 値1つ分のJSONテキストをそのまま返す。`JSONDecoder` で読める小さな値に使う。
    func readRawValue(maxLength: Int) throws -> Data {
        var raw = Data()
        try scanValue { byte in
            guard raw.count < maxLength else {
                throw ReadError.valueTooLarge
            }
            raw.append(byte)
        }
        return raw
    }

    func skipValue() throws {
        try scanValue { _ in }
    }

    /// base64 文字列の値を読み、デコードしながら `output` へ書き出す。
    /// 数百MBの動画でも、メモリに載るのは数MBだけで済む。
    func readBase64String(into output: FileHandle) throws {
        try expect(.quote)

        var pending: [UInt8] = []
        pending.reserveCapacity(Self.base64DecodeBlockSize + Self.readChunkSize)
        var isEscaped = false
        var isClosed = false

        while !isClosed {
            if position >= buffer.count {
                try refill()
                guard position < buffer.count else {
                    throw ReadError.unexpectedEnd
                }
            }

            buffer.withUnsafeBufferPointer { bytes in
                var index = position
                var runStart = index

                while index < bytes.count {
                    let byte = bytes[index]

                    if isEscaped {
                        // base64 に現れうる JSON エスケープは `\/` だけ。
                        if byte == .slash {
                            pending.append(byte)
                        }
                        isEscaped = false
                        index += 1
                        runStart = index
                        continue
                    }

                    guard byte == .quote || byte == .backslash else {
                        index += 1
                        continue
                    }

                    pending.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[runStart..<index]))
                    index += 1
                    runStart = index

                    if byte == .quote {
                        isClosed = true
                        break
                    }

                    isEscaped = true
                }

                if !isClosed {
                    pending.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[runStart..<index]))
                }

                position = index
            }

            if isClosed || pending.count >= Self.base64DecodeBlockSize {
                try flushBase64(&pending, isFinal: isClosed, to: output)
            }
        }
    }

    // MARK: - 内部

    private func flushBase64(_ pending: inout [UInt8], isFinal: Bool, to output: FileHandle) throws {
        // 途中のブロックは4文字単位で区切れば、続きと独立してデコードできる。
        let length = isFinal ? pending.count : pending.count - pending.count % 4
        guard length > 0 else {
            return
        }

        try autoreleasepool {
            guard let decoded = Data(base64Encoded: Data(pending[0..<length])) else {
                throw ReadError.invalidBase64
            }

            try output.write(contentsOf: decoded)
        }

        pending.removeFirst(length)
    }

    /// 値を1つ読み進め、そのバイト列を順に `consume` へ渡す。
    private func scanValue(_ consume: (UInt8) throws -> Void) throws {
        guard let first = try peekSignificant() else {
            throw ReadError.unexpectedEnd
        }

        switch first {
        case .quote:
            try scanString(consume)

        case .openBrace, .openBracket:
            var depth = 0
            repeat {
                guard let byte = try peek() else {
                    throw ReadError.unexpectedEnd
                }

                if byte == .quote {
                    try scanString(consume)
                    continue
                }

                position += 1
                try consume(byte)

                if byte == .openBrace || byte == .openBracket {
                    depth += 1
                } else if byte == .closeBrace || byte == .closeBracket {
                    depth -= 1
                }
            } while depth > 0

        default:
            // 数値・true・false・null
            var length = 0
            while let byte = try peek(), !Self.isDelimiter(byte) {
                position += 1
                length += 1
                try consume(byte)
            }

            guard length > 0 else {
                throw ReadError.unexpectedCharacter
            }
        }
    }

    /// 現在位置の `"` から閉じの `"` までを読み進める。
    private func scanString(_ consume: (UInt8) throws -> Void) throws {
        try consume(try next())

        var isEscaped = false
        while true {
            let byte = try next()
            try consume(byte)

            if isEscaped {
                isEscaped = false
            } else if byte == .backslash {
                isEscaped = true
            } else if byte == .quote {
                return
            }
        }
    }

    private func peek() throws -> UInt8? {
        if position >= buffer.count {
            try refill()

            if position >= buffer.count {
                return nil
            }
        }

        return buffer[position]
    }

    private func next() throws -> UInt8 {
        guard let byte = try peek() else {
            throw ReadError.unexpectedEnd
        }

        position += 1
        return byte
    }

    /// 空白を読み飛ばし、次の文字を消費せずに返す。
    private func peekSignificant() throws -> UInt8? {
        while let byte = try peek() {
            guard Self.isWhitespace(byte) else {
                return byte
            }

            position += 1
        }

        return nil
    }

    private func nextSignificant() throws -> UInt8 {
        guard let byte = try peekSignificant() else {
            throw ReadError.unexpectedEnd
        }

        position += 1
        return byte
    }

    private func expect(_ expected: UInt8) throws {
        guard try nextSignificant() == expected else {
            throw ReadError.unexpectedCharacter
        }
    }

    private func refill() throws {
        guard !reachedEnd else {
            return
        }

        try Task.checkCancellation()

        bufferStartOffset += Int64(buffer.count)
        position = 0

        let data = try autoreleasepool {
            try handle.read(upToCount: Self.readChunkSize)
        }

        if let data, !data.isEmpty {
            buffer = [UInt8](data)
        } else {
            buffer = []
            reachedEnd = true
        }

        onRead(bufferStartOffset)
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == .space || byte == .tab || byte == .lineFeed || byte == .carriageReturn
    }

    private static func isDelimiter(_ byte: UInt8) -> Bool {
        isWhitespace(byte) || byte == .comma || byte == .closeBrace || byte == .closeBracket
    }
}

private nonisolated extension UInt8 {
    static let quote = UInt8(ascii: "\"")
    static let backslash = UInt8(ascii: "\\")
    static let slash = UInt8(ascii: "/")
    static let openBrace = UInt8(ascii: "{")
    static let closeBrace = UInt8(ascii: "}")
    static let openBracket = UInt8(ascii: "[")
    static let closeBracket = UInt8(ascii: "]")
    static let colon = UInt8(ascii: ":")
    static let comma = UInt8(ascii: ",")
    static let space = UInt8(ascii: " ")
    static let tab = UInt8(ascii: "\t")
    static let lineFeed = UInt8(ascii: "\n")
    static let carriageReturn = UInt8(ascii: "\r")
}
