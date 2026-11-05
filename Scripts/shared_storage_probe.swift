import Foundation

// Non-UI helper used by verify_shared_storage.py in two signed app bundles.
let arguments = CommandLine.arguments
guard arguments.count == 4,
  let directory = FileManager.default.containerURL(
    forSecurityApplicationGroupIdentifier: arguments[1])
else { fatalError("App Group container unavailable") }
let file = directory.appendingPathComponent(arguments[2])
if arguments[3] == "write" {
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  try Data("app-to-widget".utf8).write(to: file, options: .atomic)
} else if arguments[3] == "read-and-ack" {
  guard try Data(contentsOf: file) == Data("app-to-widget".utf8) else {
    fatalError("Widget could not read the app publication")
  }
  try Data("widget-to-app".utf8).write(to: file, options: .atomic)
} else {
  guard try Data(contentsOf: file) == Data("widget-to-app".utf8) else {
    fatalError("App could not read the widget acknowledgement")
  }
  try FileManager.default.removeItem(at: file)
}
print("Shared App Group probe passed:", arguments[3])
