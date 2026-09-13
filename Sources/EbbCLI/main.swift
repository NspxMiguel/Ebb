import EbbCore
import Foundation

// The CLI owns its translation table; register it before anything else renders.
L10n.shared.register(CLIStrings.table)

let status = await CLI.run(arguments: Array(CommandLine.arguments.dropFirst()))
exit(status)
