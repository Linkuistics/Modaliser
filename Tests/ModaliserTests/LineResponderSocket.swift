import Darwin
import Foundation

/// A throwaway AF_UNIX stream responder. Deliberately builds its own
/// `sockaddr_un` rather than reusing the library's, so a bug in the library's
/// address construction cannot cancel itself out.
///
/// Shared by the two layers ADR-0020 splits the socket work across: the native
/// primitive's own tests (`UnixSocketLibraryTests`) and the Scheme herdr
/// transport's (`ModaliserMuxesHerdrLibraryTests`). Neither needs herdr
/// installed, let alone running.
final class LineResponderSocket {

    enum Behaviour {
        /// Read one line, reply `echo:<line>` and close.
        case echo
        /// Accept and hold the connection open without replying, so the client
        /// hits its deadline rather than seeing EOF.
        case silent
        /// Read one line, record it, and reply with a fixed line. Lets a test
        /// assert the exact bytes a caller put on the wire — the request
        /// format is a contract with herdr, so it is worth pinning.
        case canned(String)
    }

    struct FixtureError: Error { let message: String }

    let path: String
    private let listenFd: Int32
    private let behaviour: Behaviour
    private let lock = NSLock()
    private var stopping = false

    init(behaviour: Behaviour) throws {
        Self.ignoreSigpipe()
        self.behaviour = behaviour
        self.path = Self.temporarySocketPath()

        unlink(path)
        var address = try Self.address(for: path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw FixtureError(message: "socket() failed: \(errno)") }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                bind(fd, generic, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            Darwin.close(fd)
            throw FixtureError(message: "bind(\(path)) failed: \(errno)")
        }
        guard listen(fd, 4) == 0 else {
            Darwin.close(fd)
            throw FixtureError(message: "listen() failed: \(errno)")
        }
        // Non-blocking accept so the loop can notice stop() without a close
        // racing a thread blocked in accept().
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        self.listenFd = fd

        // A dedicated Thread, not DispatchQueue.global(): this is an unbounded
        // blocking accept loop, and under the full suite the global pool's
        // workers are all parked in long shell-outs — the loop would never be
        // scheduled, and the client would (correctly) time out against a
        // responder that was never listening.
        let thread = Thread { [weak self] in self?.serve() }
        thread.name = "LineResponderSocket"
        thread.start()
    }

    func stop() {
        lock.lock()
        stopping = true
        lock.unlock()
    }

    /// Replying to a client that has already gone away is *normal* here — a
    /// send-only client (`unix-socket-send`) closes as soon as its bytes are
    /// on the wire, and the peer's reply then lands on a broken pipe. The
    /// write must fail with `EPIPE`, not kill the test process with SIGPIPE.
    ///
    /// The obvious per-socket guard is not enough. `SO_NOSIGPIPE` can only be
    /// applied to the *accepted* socket, i.e. after the client may already
    /// have closed — at which point `setsockopt` itself fails with `EINVAL`
    /// and the option silently never takes effect. That is load-dependent:
    /// with a busy machine the responder thread reaches `accept` late, so the
    /// suite dies while the same test passes in isolation. Suppressing the
    /// signal process-wide does not depend on socket state and cannot lose
    /// that race.
    ///
    /// This is a fixture-only concern: the library under test sets
    /// `SO_NOSIGPIPE` on a *fresh* socket before `connect`, where there is no
    /// peer that could have closed and the call cannot fail this way.
    private static let ignoreSigpipeOnce: Void = { signal(SIGPIPE, SIG_IGN) }()

    private static func ignoreSigpipe() { _ = ignoreSigpipeOnce }

    static func temporarySocketPath() -> String {
        let name = "mdlr-\(UUID().uuidString.prefix(8)).sock"
        return (NSTemporaryDirectory() as NSString).appendingPathComponent(name)
    }

    private var isStopping: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopping
    }

    private func serve() {
        while !isStopping {
            var descriptor = pollfd(fd: listenFd, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, 50) > 0 else { continue }
            let clientFd = accept(listenFd, nil, nil)
            guard clientFd >= 0 else { continue }
            // Darwin's accepted socket inherits O_NONBLOCK from the listener;
            // clear it so the fixture's reads are plainly blocking.
            let flags = fcntl(clientFd, F_GETFL, 0)
            _ = fcntl(clientFd, F_SETFL, flags & ~O_NONBLOCK)
            // Best-effort only: this fails with EINVAL when the client has
            // already closed, which is precisely the case that needs it —
            // hence the process-wide SIGPIPE suppression above, which is what
            // actually makes the write safe.
            var noSigPipe: Int32 = 1
            _ = setsockopt(
                clientFd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size)
            )
            handle(clientFd)
            Darwin.close(clientFd)
        }
        Darwin.close(listenFd)
        unlink(path)
    }

    private var recordedRequest: String?

    /// The request line the most recent client sent, for `.canned` responders.
    ///
    /// Guarded on BOTH sides, which matters more than it looks: a *send-only*
    /// client (`unix-socket-send`) returns the instant its bytes are on the
    /// wire, so a test reading this genuinely races the responder thread still
    /// writing it — there is no round-trip to order the two. Reading a Swift
    /// `String?` through that race traps the process. A request/response client
    /// is ordered by its own reply and never noticed.
    var lastRequest: String? {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequest
    }

    /// Blocks until a request line has been recorded, or TIMEOUT elapses.
    ///
    /// The polling belongs here rather than in each test: a send-only test has
    /// nothing to synchronise on by construction, and hand-rolled waits are
    /// exactly where the unguarded read crept in.
    func awaitRequest(timeout: TimeInterval = 2.0) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let line = lastRequest { return line }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return lastRequest
    }

    private func handle(_ clientFd: Int32) {
        switch behaviour {
        case .canned(let reply):
            guard let line = Self.readLine(clientFd) else { return }
            lock.lock()
            recordedRequest = line
            lock.unlock()
            // EPIPE here is expected against a send-only client, and ignored:
            // the assertion those tests make is about what the responder
            // RECEIVED, not whether it managed to reply.
            let bytes = Array((reply + "\n").utf8)
            _ = bytes.withUnsafeBufferPointer { buffer in
                Darwin.send(clientFd, buffer.baseAddress, buffer.count, 0)
            }
        case .echo:
            guard let line = Self.readLine(clientFd) else { return }
            let reply = Array(("echo:" + line + "\n").utf8)
            _ = reply.withUnsafeBufferPointer { buffer in
                Darwin.send(clientFd, buffer.baseAddress, buffer.count, 0)
            }
        case .silent:
            Thread.sleep(forTimeInterval: 3.0)
        }
    }

    private static func readLine(_ fd: Int32) -> String? {
        var received: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 1024)
        while !received.contains(UInt8(ascii: "\n")) {
            let count = chunk.withUnsafeMutableBufferPointer { buffer in
                Darwin.recv(fd, buffer.baseAddress, buffer.count, 0)
            }
            guard count > 0 else { return nil }
            received.append(contentsOf: chunk[0..<count])
        }
        let newline = received.firstIndex(of: UInt8(ascii: "\n"))!
        return String(decoding: received[..<newline], as: UTF8.self)
    }

    private static func address(for path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else {
            throw FixtureError(message: "fixture socket path too long: \(path)")
        }
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
}
