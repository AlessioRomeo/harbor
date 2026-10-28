import Darwin
import Foundation
import HarborCore
import HarborHost

signal(SIGPIPE, SIG_IGN)

let host: SessionHost
do {
    host = SessionHost(paths: .standard, launcher: try ShellLauncher.userLoginShell())
    try host.start()
} catch SessionHostError.alreadyRunning {
    exit(0)
} catch {
    FileHandle.standardError.write(Data("harbor-host: \(error)\n".utf8))
    exit(1)
}

let shutdownSignals = [SIGTERM, SIGHUP, SIGINT].map { number in
    signal(number, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
    source.setEventHandler {
        host.shutdown()
        exit(0)
    }
    source.resume()
    return source
}

withExtendedLifetime(shutdownSignals) {
    dispatchMain()
}
