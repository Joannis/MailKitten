import Lynx
import Schrodinger

#if os(Linux)
    import Glibc
#else
    import Darwin
#endif

extension SMTPClient {
    func send(_ command: String) throws -> Future<Replies> {
        return try self.send([UInt8](command.utf8))
    }
    
    func send(_ command: [UInt8]) throws -> Future<Replies> {
        let future = Future<Replies>()
        self.replyFuture = future
        
        try self.client.send(data: command + [0x20, 0x0d, 0x0a])
        
        return future
    }
}

enum SMTPError : Error {
    case invalidReply, multipleSimultaniousCommands, noGreeting, invalidEHLOMessage, unsupportedMechanisms([String]), invalidCredentials, error(Int)
}

struct Replies {
    struct Reply {
        let code: Int
        let line: [UInt8]
        
        func assert(code: Int) throws {
            guard self.code == code else {
                throw SMTPError.error(code)
            }
        }
    }
    
    func assertSingleReply() throws -> Reply {
        guard let reply = replies.first, replies.count == 1 else {
            throw SMTPError.invalidReply
        }
        
        return reply
    }
    
    var replies = [Reply]()
    
    init(from pointer: UnsafePointer<UInt8>, count: Int) throws {
        var count = count
        var position = 0
        var end: Int
        
        replies: while position &+ 5 < count {
            guard count > 5,
                let string = String(bytes: UnsafeBufferPointer(start: pointer.advanced(by: position), count: 3), encoding: .utf8),
                let code = Int(string) else {
                    throw SMTPError.invalidReply
            }
            
            position = position &+ 3
            end = position
            defer { position = end }
            
            while end &+ 1 < count {
                defer { end += 1 }
                
                // \r\n
                if pointer[end] == 0x0d, pointer[end &+ 1] == 0x0a {
                    defer { end += 1 }
                    
                    replies.append(Reply(code: code, line: Array(UnsafeBufferPointer(start: pointer.advanced(by: position), count: end &- position))))
                    
                    continue replies
                }
            }
            
            throw SMTPError.invalidReply
        }
    }
}

