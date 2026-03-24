import ArgumentParser

@main
struct AIEmailCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "aiemail",
        version: "1.0.0",
        description: "AI-powered email client CLI",
        subcommands: [
            AccountCommand.self,
            MailCommand.self,
            SearchCommand.self,
            AICommand.self
        ]
    )
    
    @Option(name: .shortAndLong, help: "Output format: plain, table, json")
    var outputFormat: String = "table"
    
    @Option(name: .shortAndLong, help: "Use specific account email")
    var account: String?
    
    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false
    
    @Flag(name: .long, help: "Show help information")
    var help: Bool = false
}
