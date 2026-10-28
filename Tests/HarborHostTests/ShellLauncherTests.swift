import Testing
@testable import HarborHost

struct ShellLauncherTests {
    @Test func dropsWhatBelongsToTheAppAndToClaudeCode() throws {
        let inherited = [
            "PATH": "/usr/bin:/bin",
            "LANG": "it_IT.UTF-8",
            "XPC_SERVICE_NAME": "application.com.alessioromeo.harbor",
            "__CFBundleIdentifier": "com.alessioromeo.harbor",
            "HARBOR_DATA_DIR": "/tmp/test",
            "CLAUDECODE": "1",
            "CLAUDE_CODE_CHILD_SESSION": "1",
            "CLAUDE_CODE_MESSAGING_TOKEN": "secret",
            "AI_AGENT": "claude-code",
        ]
        let environment = try ShellLauncher.userLoginShell(inheriting: inherited).environment
        #expect(environment["PATH"] == "/usr/bin:/bin")
        #expect(environment["LANG"] == "it_IT.UTF-8")
        for name in ["XPC_SERVICE_NAME", "__CFBundleIdentifier", "HARBOR_DATA_DIR", "CLAUDECODE", "CLAUDE_CODE_CHILD_SESSION", "CLAUDE_CODE_MESSAGING_TOKEN", "AI_AGENT"] {
            #expect(environment[name] == nil, "\(name) leaked into the shell")
        }
        #expect(environment["TERM_PROGRAM"] == "Harbor")
    }
}
