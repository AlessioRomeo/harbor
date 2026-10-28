import Darwin
import Foundation

public enum ShellLauncherError: Error {
    case noPasswordEntry
}

public struct ShellLauncher: Sendable {
    public static let sessionIDVariable = "HARBOR_SESSION_ID"

    private static let appOnlyVariables: Set<String> = ["__CFBundleIdentifier", "TERM_SESSION_ID", "SHELL_SESSION_ID"]
    private static let appOnlyPrefixes = ["XPC_", "__CF"]

    public var executable: String
    public var loginName: String
    public var directory: String
    public var environment: [String: String]

    public init(executable: String, loginName: String, directory: String, environment: [String: String]) {
        self.executable = executable
        self.loginName = loginName
        self.directory = directory
        self.environment = environment
    }

    /// The user's login shell from the password database, started in their home folder as Terminal does.
    public static func userLoginShell(inheriting inherited: [String: String] = ProcessInfo.processInfo.environment) throws -> ShellLauncher {
        guard let entry = getpwuid(getuid()) else { throw ShellLauncherError.noPasswordEntry }
        let shell = String(cString: entry.pointee.pw_shell)
        let home = String(cString: entry.pointee.pw_dir)
        let user = String(cString: entry.pointee.pw_name)

        var environment = inherited.filter { name, _ in
            !appOnlyVariables.contains(name) && !appOnlyPrefixes.contains { name.hasPrefix($0) }
        }
        environment["HOME"] = home
        environment["USER"] = user
        environment["LOGNAME"] = user
        environment["SHELL"] = shell
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "Harbor"
        if environment["LANG"] == nil {
            environment["LANG"] = "en_US.UTF-8"
        }
        return ShellLauncher(
            executable: shell,
            loginName: "-" + (shell as NSString).lastPathComponent,
            directory: home,
            environment: environment
        )
    }

    func environment(for id: UUID) -> [String] {
        var variables = environment
        variables[Self.sessionIDVariable] = id.uuidString
        return variables.map { "\($0.key)=\($0.value)" }.sorted()
    }
}
