import Darwin
import Foundation

public final class PTY: @unchecked Sendable {
    public let pid: pid_t
    private let master: Int32
    private let queue = DispatchQueue(label: "trama.pty")
    private let writeQueue = DispatchQueue(label: "trama.pty.write")
    private let lock = NSLock()
    private var open = true
    private var readSource: DispatchSourceRead?
    private var exitSource: DispatchSourceProcess?
    private let onOutput: ([UInt8]) -> Void
    private let onExit: (Int32?) -> Void

    public static func defaultEnvironment() -> [String] {
        var environment = ["TERM=xterm-256color", "COLORTERM=truecolor", "LANG=en_US.UTF-8"]
        let current = ProcessInfo.processInfo.environment
        for key in ["LOGNAME", "USER", "DISPLAY", "HOME"] {
            if let value = current[key] {
                environment.append("\(key)=\(value)")
            }
        }
        return environment
    }

    public init(
        executable: String,
        arguments: [String],
        environment: [String] = PTY.defaultEnvironment(),
        directory: String?,
        columns: Int,
        rows: Int,
        onOutput: @escaping ([UInt8]) -> Void,
        onExit: @escaping (Int32?) -> Void
    ) throws {
        self.onOutput = onOutput
        self.onExit = onExit

        var size = winsize(ws_row: UInt16(rows), ws_col: UInt16(columns), ws_xpixel: 0, ws_ypixel: 0)
        let argv = PTY.allocateStrings(arguments)
        let envp = PTY.allocateStrings(environment)
        let path = strdup(executable)
        let cwd = directory.flatMap { strdup($0) }
        defer {
            PTY.freeStrings(argv, count: arguments.count)
            PTY.freeStrings(envp, count: environment.count)
            free(path)
            free(cwd)
        }

        var descriptor: Int32 = 0
        let child = forkpty(&descriptor, nil, nil, &size)
        if child < 0 {
            throw TramaError("não consegui abrir um terminal")
        }
        if child == 0 {
            if let cwd {
                _ = chdir(cwd)
            }
            _ = execve(path, argv, envp)
            _exit(127)
        }
        pid = child
        master = descriptor
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        startSources()
    }

    public func write(_ bytes: [UInt8]) {
        writeQueue.async { [self] in
            var offset = 0
            while offset < bytes.count {
                lock.lock()
                guard open else {
                    lock.unlock()
                    return
                }
                let written = bytes.withUnsafeBytes { buffer in
                    Darwin.write(master, buffer.baseAddress! + offset, bytes.count - offset)
                }
                lock.unlock()
                if written > 0 {
                    offset += written
                } else if written < 0, errno == EAGAIN {
                    var wait = pollfd(fd: master, events: Int16(POLLOUT), revents: 0)
                    _ = poll(&wait, 1, 100)
                } else if written < 0, errno == EINTR {
                    continue
                } else {
                    return
                }
            }
        }
    }

    public func resize(columns: Int, rows: Int) {
        var size = winsize(ws_row: UInt16(rows), ws_col: UInt16(columns), ws_xpixel: 0, ws_ypixel: 0)
        lock.lock()
        defer { lock.unlock() }
        guard open else { return }
        _ = ioctl(master, TIOCSWINSZ, &size)
    }

    public func terminate() {
        kill(pid, SIGHUP)
        queue.asyncAfter(deadline: .now() + 2) { [self] in
            lock.lock()
            let stillOpen = open
            lock.unlock()
            if stillOpen {
                kill(pid, SIGKILL)
            }
        }
    }

    private func startSources() {
        let reader = DispatchSource.makeReadSource(fileDescriptor: master, queue: queue)
        reader.setEventHandler { [self] in drain() }
        let descriptor = master
        reader.setCancelHandler { close(descriptor) }
        let watcher = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
        watcher.setEventHandler { [self] in childExited() }
        readSource = reader
        exitSource = watcher
        reader.resume()
        watcher.resume()
    }

    private func drain() {
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = read(master, &buffer, buffer.count)
            if count > 0 {
                onOutput(Array(buffer[0..<count]))
            } else if count < 0, errno == EINTR {
                continue
            } else {
                return
            }
        }
    }

    private func childExited() {
        drain()
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        let exitCode: Int32? = (status & 0x7f) == 0 ? (status >> 8) & 0xff : nil
        lock.lock()
        open = false
        lock.unlock()
        readSource?.cancel()
        exitSource?.cancel()
        readSource = nil
        exitSource = nil
        onExit(exitCode)
    }

    private static func allocateStrings(_ strings: [String]) -> UnsafeMutablePointer<UnsafeMutablePointer<CChar>?> {
        let array = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: strings.count + 1)
        for (index, string) in strings.enumerated() {
            array[index] = strdup(string)
        }
        array[strings.count] = nil
        return array
    }

    private static func freeStrings(_ array: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>, count: Int) {
        for index in 0..<count {
            free(array[index])
        }
        array.deallocate()
    }
}
