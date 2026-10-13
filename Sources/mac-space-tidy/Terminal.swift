import Darwin

/// Raw-mode terminal on the alternate screen. Restores the normal screen on exit, even after SIGTERM.
final class Terminal {
    enum Key: Equatable {
        case up
        case down
        case left
        case right
        case pageUp
        case pageDown
        case enter
        case space
        case escape
        case interrupt
        case character(Character)
    }

    private static let ENTER_SCREEN = "\u{1B}[?1049h\u{1B}[?25l"
    private static let LEAVE_SCREEN = "\u{1B}[?25h\u{1B}[?1049l"
    private static let HOME = "\u{1B}[H"
    private static let CLEAR_LINE_END = "\u{1B}[K"
    private static let CLEAR_SCREEN_END = "\u{1B}[J"
    private static let DEFAULT_WIDTH = 100
    private static let DEFAULT_HEIGHT = 30
    private static let READ_BUFFER_BYTES = 16

    var width: Int {
        return Int(windowSize().ws_col).nonZero ?? Terminal.DEFAULT_WIDTH
    }

    var height: Int {
        return Int(windowSize().ws_row).nonZero ?? Terminal.DEFAULT_HEIGHT
    }

    static var isInteractive: Bool {
        return isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1
    }

    func enter() {
        tcgetattr(STDIN_FILENO, &savedTerminalSettings)
        var raw = savedTerminalSettings
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON | ISIG | IEXTEN)
        raw.c_iflag &= ~tcflag_t(IXON | ICRNL)
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        signal(SIGTERM, restoreAndExit)
        signal(SIGHUP, restoreAndExit)
        write(Terminal.ENTER_SCREEN)
    }

    func leave() {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &savedTerminalSettings)
        write(Terminal.LEAVE_SCREEN)
    }

    /// Draws the whole frame. Lines must already fit the width.
    func draw(_ lines: [String]) {
        let frame = lines.prefix(height).joined(separator: Terminal.CLEAR_LINE_END + "\r\n")
        write(Terminal.HOME + frame + Terminal.CLEAR_LINE_END + Terminal.CLEAR_SCREEN_END)
    }

    /// Nil when no key came within the timeout.
    func readKey(timeoutMilliseconds: Int32) -> Key? {
        var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        guard poll(&descriptor, 1, timeoutMilliseconds) > 0 else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: Terminal.READ_BUFFER_BYTES)
        let count = read(STDIN_FILENO, &buffer, buffer.count)
        guard count > 0 else {
            return nil
        }
        return Terminal.parse(Array(buffer.prefix(count)))
    }

    private static func parse(_ bytes: [UInt8]) -> Key? {
        switch bytes {
        case [0x1B, 0x5B, 0x41], [0x1B, 0x4F, 0x41]: return .up
        case [0x1B, 0x5B, 0x42], [0x1B, 0x4F, 0x42]: return .down
        case [0x1B, 0x5B, 0x43], [0x1B, 0x4F, 0x43]: return .right
        case [0x1B, 0x5B, 0x44], [0x1B, 0x4F, 0x44]: return .left
        case [0x1B, 0x5B, 0x35, 0x7E]: return .pageUp
        case [0x1B, 0x5B, 0x36, 0x7E]: return .pageDown
        case [0x1B]: return .escape
        case [0x0D], [0x0A]: return .enter
        case [0x20]: return .space
        case [0x03]: return .interrupt
        default:
            guard bytes.count == 1, bytes[0] >= 0x21, bytes[0] < 0x7F else {
                return nil
            }
            return .character(Character(UnicodeScalar(bytes[0])))
        }
    }

    private func windowSize() -> winsize {
        var size = winsize()
        _ = ioctl(STDOUT_FILENO, TIOCGWINSZ, &size)
        return size
    }

    private func write(_ text: String) {
        var text = text
        text.withUTF8 { buffer in
            _ = Darwin.write(STDOUT_FILENO, buffer.baseAddress, buffer.count)
        }
    }
}

/// Kept global so the signal handler can restore the terminal.
nonisolated(unsafe) private var savedTerminalSettings = termios()

private func restoreAndExit(_ signalNumber: Int32) {
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &savedTerminalSettings)
    let leave = "\u{1B}[?25h\u{1B}[?1049l"
    _ = leave.withCString { Darwin.write(STDOUT_FILENO, $0, strlen($0)) }
    _exit(128 + signalNumber)
}

private extension Int {
    var nonZero: Int? {
        return self == 0 ? nil : self
    }
}
