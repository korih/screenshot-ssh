import Foundation
import PackagePlugin

/// Generates Payload.generated.swift from VERSION and every file under vm/.
@main
struct EmbedPayload: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let root = context.package.directory
        let versionFile = root.appending("VERSION")
        let vmDir = root.appending("vm")
        let output = context.pluginWorkDirectory.appending("Payload.generated.swift")

        var inputs = [versionFile]
        if let walker = FileManager.default.enumerator(atPath: vmDir.string) {
            for case let relative as String in walker {
                var isDir: ObjCBool = false
                let path = vmDir.appending(relative)
                if FileManager.default.fileExists(atPath: path.string, isDirectory: &isDir), !isDir.boolValue {
                    inputs.append(path)
                }
            }
        }

        return [
            .buildCommand(
                displayName: "Embedding VERSION and vm/ payload",
                executable: try context.tool(named: "sshot-embed").path,
                arguments: [versionFile.string, vmDir.string, output.string],
                inputFiles: inputs,
                outputFiles: [output]
            )
        ]
    }
}
