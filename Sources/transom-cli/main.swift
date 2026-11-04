import CoreFoundation
import Foundation
import TransomEngine

// The `transom` command (VIEW-05, D-07..D-09): checks a command with the URL parser and sends it to the running app over
// a local CFMessagePort. It never starts anything: no app answering is exit 2 (D-08).

func fail(_ message: String, _ code: Int32) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(code)
}

let path: String
switch CLICommandLine.parse(Array(CommandLine.arguments.dropFirst())) {
case .help:
    print(CLICopy.help)
    exit(0)
case .usage(let message):
    fail(message, 64)
case .send(let command):
    path = command
}

// The bundle this copy ships in, through any symlink, names the channel and the scheme (Pitfall 11).
let bundle = Bundle.main.executableURL.flatMap(CLIProtocol.appBundle(executable:)).flatMap { Bundle(url: $0) }
let scheme = bundle.flatMap(TransomURL.registeredScheme(in:)) ?? "transom"
let bundleID = bundle?.bundleIdentifier ?? "com.eightabyte.transom"
let portName = ProcessInfo.processInfo.environment[CLIProtocol.portEnvironmentKey] ?? CLIProtocol.portName(bundleID: bundleID)

let text = "\(scheme)://\(path)"
guard let url = URL(string: text), TransomURL.parse(url, scheme: scheme) != nil else { fail(CLICopy.unknownCommand(path), 64) }
guard let remote = CFMessagePortCreateRemote(nil, portName as CFString) else { fail(CLICopy.notRunning, 2) }

var replyData: Unmanaged<CFData>?
let status = CFMessagePortSendRequest(
    remote, CLIProtocol.version, Data(text.utf8) as CFData, CLIProtocol.timeout, CLIProtocol.timeout, CFRunLoopMode.defaultMode.rawValue, &replyData)
let reply = replyData.map { String(decoding: $0.takeRetainedValue() as Data, as: UTF8.self) }
let outcome = status == kCFMessagePortSuccess && reply != nil
    ? CLIProtocol.exitCode(reply: reply ?? "", command: path) : CLIProtocol.exitCode(sendStatus: status)
if let message = outcome.message { FileHandle.standardError.write(Data("\(message)\n".utf8)) }
exit(outcome.code)
