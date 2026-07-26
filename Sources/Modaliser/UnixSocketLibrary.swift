import Darwin
import Foundation
import LispKit
import os

/// Native LispKit library providing line-framed Unix-domain-socket sends, with
/// and without a response.
/// Scheme name: (modaliser unix-socket)
///
/// This is the whole native surface the herdr socket transport needs
/// (ADR-0020). It is deliberately **generic**: Swift owns the AF_UNIX
/// primitive and knows nothing of herdr, JSON, or the
/// `{"id","method","params"}` envelope — those live in Scheme
/// ([[feedback_scheme_driven_design]]).
///
/// The two procedures are the same connect-and-send, differing only in whether
/// they then wait for a reply. Splitting them at that seam — rather than
/// encoding "don't wait" in a magic timeout value — keeps the caller's
/// intent explicit and keeps a deliberately-abandoned reply from being logged
/// as a timeout failure.
///
/// Provides: unix-socket-request, unix-socket-send
final class UnixSocketLibrary: NativeLibrary {

    private static let logger = Logger(subsystem: "dev.antony.Modaliser", category: "unix-socket")

    public required init(in context: Context) throws {
        try super.init(in: context)
    }

    public override class var name: [String] {
        ["modaliser", "unix-socket"]
    }

    public override func dependencies() {
        self.`import`(from: ["lispkit", "base"], "define")
    }

    public override func declarations() {
        self.define(Procedure("unix-socket-request", unixSocketRequestFunction))
        self.define(Procedure("unix-socket-send", unixSocketSendFunction))
    }

    /// (unix-socket-request path line timeout-ms) → response-line | #f
    ///
    /// Connects to the AF_UNIX stream socket at PATH, sends LINE followed by a
    /// newline, reads one line back, closes, and returns that line **without**
    /// its terminating newline. Framing is the primitive's job in both
    /// directions: callers pass and receive bare payload lines.
    ///
    /// Connect-per-request is the model (ADR-0020): one request/response per
    /// connection, the peer closes after responding — so no keep-alive and no
    /// pooling. Anything the peer sends after the first line is discarded.
    ///
    /// TIMEOUT-MS bounds the *whole* round-trip (connect + send + read) as
    /// wall-clock, not each syscall. The call blocks the calling thread — the
    /// eval thread — for at most that long, exactly as a `run-shell` shell-out
    /// blocks it today.
    ///
    /// Returns `#f` on any I/O failure — socket path too long, connect refused,
    /// peer gone, timeout, EOF before any byte arrived. It **never raises**: a
    /// leader press must not raise (ADR-0014/0017 spirit), and the caller maps
    /// `#f` to the backend-health failure path. The *reason* is not discarded
    /// the way `2>/dev/null` discarded CLI errors — it goes to os.Logger,
    /// readable via
    /// `/usr/bin/log show --predicate 'subsystem == "dev.antony.Modaliser"'`.
    ///
    /// Malformed arguments (non-string path/line, non-integer or non-positive
    /// timeout) *do* raise: those are programming errors, not I/O outcomes.
    ///
    /// Use `unix-socket-send` instead when the peer's reply cannot arrive
    /// promptly: waiting here costs the caller's thread the full TIMEOUT-MS.
    private func unixSocketRequestFunction(
        _ pathExpr: Expr,
        _ lineExpr: Expr,
        _ timeoutExpr: Expr
    ) throws -> Expr {
        let path = try pathExpr.asString()
        let line = try lineExpr.asString()
        let timeoutMs = try timeoutExpr.asInt(above: 1)
        guard let response = Self.exchange(
            path: path, payload: line, timeoutMs: timeoutMs, awaitReply: true
        ) else {
            return .false
        }
        return .makeString(response)
    }

    /// (unix-socket-send path line timeout-ms) → #t | #f
    ///
    /// Connect, send LINE followed by a newline, close. **No reply is read.**
    /// Returns `#t` once the payload is on the wire, `#f` if it never got
    /// there — the same non-raising, os.Logger-reported failure contract as
    /// `unix-socket-request`.
    ///
    /// This is for peers whose reply cannot arrive promptly, or at all — a
    /// request the peer answers only after slow work of its own, or one that
    /// kills the peer. Waiting on such a reply would block the eval thread for
    /// the full timeout as a matter of *routine* (ADR-0014's stalled-tap
    /// hazard) and would log a timeout for what is in fact success. Not
    /// waiting costs only the connect+send — sub-millisecond against a local
    /// peer — so TIMEOUT-MS bounds a path that in practice never approaches
    /// it, and exists for a wedged or backlogged peer.
    ///
    /// Abandoning the reply does **not** abandon the request: the bytes are in
    /// the peer's receive buffer before `close`, and AF_UNIX stream delivery
    /// guarantees the peer reads them before seeing EOF.
    private func unixSocketSendFunction(
        _ pathExpr: Expr,
        _ lineExpr: Expr,
        _ timeoutExpr: Expr
    ) throws -> Expr {
        let path = try pathExpr.asString()
        let line = try lineExpr.asString()
        let timeoutMs = try timeoutExpr.asInt(above: 1)
        let sent = Self.exchange(path: path, payload: line, timeoutMs: timeoutMs, awaitReply: false)
        return .makeBoolean(sent != nil)
    }

    // MARK: - The round-trip

    /// Connect, send, and — when AWAIT-REPLY — read one line back.
    ///
    /// Returns `nil` on any failure. On success with AWAIT-REPLY it yields the
    /// reply line; without it, the empty string, which `unix-socket-send`
    /// reads only as "the payload got there".
    private static func exchange(
        path: String,
        payload: String,
        timeoutMs: Int,
        awaitReply: Bool
    ) -> String? {
        let deadline = DispatchTime.now() + .milliseconds(timeoutMs)

        guard var address = socketAddress(for: path) else {
            log(path, "socket path too long (\(path.utf8.count) bytes)")
            return nil
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            log(path, "socket() failed: \(errnoText())")
            return nil
        }
        defer { Darwin.close(fd) }

        // Non-blocking for the duration: every wait then goes through poll()
        // against the single deadline above.
        let flags = fcntl(fd, F_GETFL, 0)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            log(path, "fcntl(O_NONBLOCK) failed: \(errnoText())")
            return nil
        }
        // Without this, writing to a peer that has already closed raises
        // SIGPIPE and kills the process instead of returning EPIPE.
        var noSigPipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        guard connect(fd: fd, to: &address, path: path, deadline: deadline),
              send(fd: fd, payload: payload + "\n", path: path, deadline: deadline)
        else {
            return nil
        }
        guard awaitReply else {
            return ""
        }
        return readLine(fd: fd, path: path, deadline: deadline)
    }

    private static func connect(
        fd: Int32,
        to address: inout sockaddr_un,
        path: String,
        deadline: DispatchTime
    ) -> Bool {
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                Darwin.connect(fd, generic, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result == 0 {
            return true
        }
        guard errno == EINPROGRESS else {
            log(path, "connect failed: \(errnoText())")
            return false
        }
        guard wait(fd: fd, for: Int16(POLLOUT), deadline: deadline) else {
            log(path, "connect timed out")
            return false
        }
        var pending: Int32 = 0
        var size = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &pending, &size) == 0 else {
            log(path, "getsockopt(SO_ERROR) failed: \(errnoText())")
            return false
        }
        guard pending == 0 else {
            log(path, "connect failed: \(errnoText(pending))")
            return false
        }
        return true
    }

    private static func send(
        fd: Int32,
        payload: String,
        path: String,
        deadline: DispatchTime
    ) -> Bool {
        let bytes = Array(payload.utf8)
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBufferPointer { buffer in
                Darwin.send(fd, buffer.baseAddress, buffer.count, 0)
            }
            if written > 0 {
                offset += written
            } else if written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                guard wait(fd: fd, for: Int16(POLLOUT), deadline: deadline) else {
                    log(path, "send timed out after \(offset)/\(bytes.count) bytes")
                    return false
                }
            } else if written < 0 && errno == EINTR {
                continue
            } else {
                log(path, "send failed after \(offset)/\(bytes.count) bytes: \(errnoText())")
                return false
            }
        }
        return true
    }

    /// Reads until the first newline, or until the peer closes. A stream that
    /// ends without a newline still yields its bytes as the line (the usual
    /// last-line-need-not-be-terminated convention); a peer that closes having
    /// sent nothing yields `nil`.
    private static func readLine(fd: Int32, path: String, deadline: DispatchTime) -> String? {
        var received: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            if let newline = received.firstIndex(of: UInt8(ascii: "\n")) {
                return String(decoding: received[..<newline], as: UTF8.self)
            }
            guard wait(fd: fd, for: Int16(POLLIN), deadline: deadline) else {
                log(path, "read timed out after \(received.count) bytes")
                return nil
            }
            let count = chunk.withUnsafeMutableBufferPointer { buffer in
                Darwin.recv(fd, buffer.baseAddress, buffer.count, 0)
            }
            if count > 0 {
                received.append(contentsOf: chunk[0..<count])
            } else if count == 0 {
                guard !received.isEmpty else {
                    log(path, "peer closed without responding")
                    return nil
                }
                return String(decoding: received, as: UTF8.self)
            } else if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK {
                continue
            } else {
                log(path, "read failed after \(received.count) bytes: \(errnoText())")
                return nil
            }
        }
    }

    // MARK: - POSIX helpers

    /// Waits for EVENTS on FD, bounded by DEADLINE. `false` means the deadline
    /// passed (or poll failed); a readiness event *or* an error condition
    /// (POLLERR/POLLHUP) returns `true` and lets the following send/recv report
    /// the actual errno.
    private static func wait(fd: Int32, for events: Int16, deadline: DispatchTime) -> Bool {
        while true {
            let remaining = millisecondsRemaining(until: deadline)
            guard remaining > 0 else { return false }
            var descriptor = pollfd(fd: fd, events: events, revents: 0)
            // A very large timeout-ms saturates the deadline at
            // DISPATCH_TIME_FOREVER, so REMAINING can exceed what poll's Int32
            // takes — narrowing would trap. Clamp and let the loop re-check.
            let budget = Int32(min(remaining, Int(Int32.max)))
            let ready = poll(&descriptor, 1, budget)
            if ready > 0 {
                return true
            } else if ready == 0 {
                return false
            } else if errno == EINTR {
                continue
            } else {
                return false
            }
        }
    }

    private static func millisecondsRemaining(until deadline: DispatchTime) -> Int {
        let now = DispatchTime.now()
        guard deadline > now else { return 0 }
        let nanoseconds = deadline.uptimeNanoseconds - now.uptimeNanoseconds
        return Int((nanoseconds + 999_999) / 1_000_000)
    }

    /// Builds the AF_UNIX address for PATH, or `nil` when the path does not fit
    /// `sun_path` (104 bytes on Darwin, NUL included).
    private static func socketAddress(for path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { return nil }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                for (index, byte) in bytes.enumerated() {
                    destination[index] = CChar(bitPattern: byte)
                }
                destination[bytes.count] = 0
            }
        }
        return address
    }

    private static func errnoText(_ code: Int32? = nil) -> String {
        let value = code ?? errno
        return "\(String(cString: strerror(value))) (errno \(value))"
    }

    private static func log(_ path: String, _ reason: String) {
        logger.notice("unix-socket-request \(path, privacy: .public): \(reason, privacy: .public)")
    }
}
