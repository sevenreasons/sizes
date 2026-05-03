Register-ArgumentCompleter -Native -CommandName sizes -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $options = @(
        '-r', '--recursive',
        '-n', '--limit',
        '-e', '--exact',
        '-E', '--errors',
        '--no-color',
        '--version',
        '-h', '--help'
    )

    $options |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_) }
}
