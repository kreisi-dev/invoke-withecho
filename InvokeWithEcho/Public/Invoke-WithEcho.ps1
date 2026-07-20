function Invoke-WithEcho {
    <#
    .SYNOPSIS
        Runs a script block and logs the command text beforehand — like ECHO ON in DOS batch files.

    .DESCRIPTION
        The command text is written unchanged via Write-Host (information stream:
        visible in the console, captured by Start-Transcript, redirectable with 6>).
        Below it, every variable the block reads appears as a row in an indented
        table (Variable, Type, Count, Value), the value collapsed to a single
        line and truncated to -MaxValueLength characters. Resolution only reads
        variable values in the caller's scope and never executes anything.

        The block's pipeline output is passed through unchanged. Assignments
        therefore belong outside the call, not inside the block:
            $x = Invoke-WithEcho { Get-ChildItem $path }   # correct
            Invoke-WithEcho { $x = Get-ChildItem $path }   # $x evaporates in the child scope

    .PARAMETER ScriptBlock
        The block to execute.

    .PARAMETER MaxValueLength
        Maximum length per logged variable value (default 100); longer values end with ….

    .PARAMETER NoExpand
        Suppresses the variable lines; only the command text is logged.

    .PARAMETER CommandColor
        Console color of the command lines (default: Cyan). Affects console
        rendering only; the transcript contains plain text.

    .PARAMETER ValueColor
        Console color of the variable lines (default: DarkGray).

    .PARAMETER NoColor
        Writes all echo lines in the console's default color.

    .EXAMPLE
        $files = Invoke-WithEcho { Get-ChildItem $sourcePath -Filter *.csv }
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Write-Host is a deliberate design decision here: the information stream is captured by Start-Transcript, redirectable with 6>, and never pollutes the return value.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [scriptblock] $ScriptBlock,

        [ValidateRange(1, [int]::MaxValue)]
        [int] $MaxValueLength = 100,

        [switch] $NoExpand,

        [ConsoleColor] $CommandColor = [ConsoleColor]::Cyan,

        [ConsoleColor] $ValueColor = [ConsoleColor]::DarkGray,

        [switch] $NoColor
    )

    $commandStyle = @{}
    $valueStyle = @{}
    if (-not $NoColor) {
        $commandStyle['ForegroundColor'] = $CommandColor
        $valueStyle['ForegroundColor'] = $ValueColor
    }

    $lines = $ScriptBlock.ToString().Trim() -split '\r?\n'
    $indent = ($lines | Select-Object -Skip 1 | Where-Object { $_.Trim() } |
        ForEach-Object { $_.Length - $_.TrimStart().Length } |
        Measure-Object -Minimum).Minimum
    foreach ($line in $lines) {
        if ($indent -and $line.Length -ge $indent -and -not $line.Substring(0, $indent).Trim()) {
            $line = $line.Substring($indent)
        }
        Write-Host ">> $line" @commandStyle
    }

    if (-not $NoExpand) {
        $occurrences = $ScriptBlock.Ast.FindAll(
            { param($node) $node -is [System.Management.Automation.Language.VariableExpressionAst] },
            $true) | Sort-Object { $_.Extent.StartOffset }

        # Only values read from the caller's scope are logged: a variable whose
        # first read happens after a completed assignment inside the block is
        # block-local and does not appear.
        $firstRead = @{}
        $firstWrite = @{}
        foreach ($occurrence in $occurrences) {
            $name = $occurrence.VariablePath.UserPath
            if ($name -in $script:SkipVariables) { continue }
            $use = Get-EchoVariableUse -Variable $occurrence
            if ($use.Reads -and -not $firstRead.ContainsKey($name)) {
                $firstRead[$name] = $occurrence.Extent.StartOffset
            }
            if ($null -ne $use.WriteOffset -and
                (-not $firstWrite.ContainsKey($name) -or $use.WriteOffset -lt $firstWrite[$name])) {
                $firstWrite[$name] = $use.WriteOffset
            }
        }
        $names = $firstRead.Keys | Where-Object {
            -not $firstWrite.ContainsKey($_) -or $firstRead[$_] -lt $firstWrite[$_]
        } | Sort-Object

        $rows = foreach ($name in $names) {
            try { $value = $PSCmdlet.GetVariableValue($name) } catch { continue }
            $itemCount = if ($null -eq $value) { '-' }
                elseif ($value -is [System.Collections.IDictionary]) { "$($value.Count)" }
                elseif ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) { "$(@($value).Count)" }
                else { '1' }
            [pscustomobject]@{
                Name      = "`$$name"
                Type      = if ($null -eq $value) { '-' } else { $value.GetType().Name }
                ItemCount = $itemCount
                Value     = Format-EchoValue -Value $value -MaxLength $MaxValueLength
            }
        }

        if ($rows) {
            $nameWidth  = (@('Variable') + @($rows.Name)      | Measure-Object -Property Length -Maximum).Maximum
            $typeWidth  = (@('Type')     + @($rows.Type)      | Measure-Object -Property Length -Maximum).Maximum
            $countWidth = (@('Count')    + @($rows.ItemCount) | Measure-Object -Property Length -Maximum).Maximum
            $rowFormat  = "   {0,-$nameWidth}  {1,-$typeWidth}  {2,$countWidth}  {3}"
            Write-Host ($rowFormat -f 'Variable', 'Type', 'Count', 'Value') @valueStyle
            Write-Host ($rowFormat -f ('-' * 8), ('-' * 4), ('-' * 5), ('-' * 5)) @valueStyle
            foreach ($row in $rows) {
                Write-Host ($rowFormat -f $row.Name, $row.Type, $row.ItemCount, $row.Value) @valueStyle
            }
        }
    }

    & $ScriptBlock
}
