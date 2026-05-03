# PowerShell completion for sizes.

Register-ArgumentCompleter -Native -CommandName sizes -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $words = $commandAst.CommandElements | ForEach-Object { $_.Extent.Text }
    $prev = if ($words.Count -gt 1) { $words[$words.Count - 2] } else { '' }

    switch ($prev) {
        { $_ -in @('-n', '--limit') } { '10','20','25','40','50','100' | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }; return }
        '--depth' { '0','1','2','3','4','5' | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }; return }
        '--min-size' { '1M','10M','100M','1G','10G' | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }; return }
        '--min-share' { '0.01','0.1','1','5' | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }; return }
        '--type' { 'video','image','audio','archive','doc','data','database','model','code','font','3d','binary','subs','meta','game','none','other' | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }; return }
        '--sort' { 'size','files','share','ext','type' | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }; return }
        '--format' { 'table','tsv','csv','json' | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }; return }
        '--group-by' { 'ext','type' | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }; return }
    }

    '-r','--recursive','--depth','--follow','-n','--limit','--min-size','--min-share','-e','--exact','-E','--errors','--include','--exclude','--type','--top-files','--sort','--format','--group-by','--plain','--no-progress','--no-color','--upgrade','--check','--version','-h','--help' |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_) }
}
