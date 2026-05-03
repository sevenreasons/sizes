# PowerShell completion for sizes.

Register-ArgumentCompleter -Native -CommandName sizes -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $words = $commandAst.CommandElements | ForEach-Object { $_.Extent.Text }
    $prev = if ($words.Count -gt 1) { $words[$words.Count - 2] } else { '' }

    switch ($prev) {
        { $_ -in @('-n', '--limit') } {
            '10','20','25','40','50','100' | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
            return
        }
        '--sort' {
            'size','files','share','ext','type' | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
            return
        }
        '--format' {
            'table','tsv','csv','json' | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
            return
        }
        '--group-by' {
            'ext','type' | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
            return
        }
    }

    '-r','--recursive','-n','--limit','-e','--exact','-E','--errors','--exclude','--sort','--format','--group-by','--plain','--no-color','--version','-h','--help' |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_) }
}
