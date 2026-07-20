# Automatic or runtime-bound variables whose value adds no insight to the echo
# log or does not exist yet at call time (e.g. $_ inside a pipeline).
$script:SkipVariables = @(
    '_', 'PSItem', 'null', 'true', 'false', 'args', 'input', 'this',
    'foreach', 'switch', 'PSCmdlet', 'MyInvocation', 'PSBoundParameters',
    'PSScriptRoot', 'PSCommandPath', 'Error', 'LASTEXITCODE', 'PID',
    'HOME', 'PWD', 'Host', 'ExecutionContext', 'PROFILE'
)

function Format-EchoValue {
    param($Value, [int] $MaxLength)

    if ($null -eq $Value) { return '<not defined / null>' }
    if ($Value -is [securestring] -or $Value -is [pscredential]) { return '<masked>' }

    if ($Value -is [System.Collections.IDictionary]) {
        $pairs = $Value.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
        $text = '{' + ($pairs -join ', ') + '}'
    }
    elseif ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = @($Value)
        $text = '(' + ($items -join ', ') + ")  [$($items.Count) items]"
    }
    else {
        $text = "$Value"
    }

    if ($text.Length -gt $MaxLength) { $text = $text.Substring(0, $MaxLength) + '…' }
    return $text
}

function Get-EchoVariableUse {
    # Classifies a variable occurrence: does it (potentially) read from the
    # caller's scope, or is it an assignment target inside the block? A write
    # takes effect at the end of its assignment statement because the right-hand
    # side is evaluated first ($a = $a + 1 reads the old value).
    param([System.Management.Automation.Language.VariableExpressionAst] $Variable)

    $node = $Variable
    while ($node.Parent -is [System.Management.Automation.Language.AttributedExpressionAst]) {
        $node = $node.Parent    # [int]$a = 5
    }
    $parent = $node.Parent

    if ($parent -is [System.Management.Automation.Language.AssignmentStatementAst] -and $parent.Left -eq $node) {
        $isCompound = $parent.Operator -ne [System.Management.Automation.Language.TokenKind]::Equals
        return [pscustomobject]@{ Reads = $isCompound; WriteOffset = $parent.Extent.EndOffset }
    }
    if ($parent -is [System.Management.Automation.Language.ForEachStatementAst] -and $parent.Variable -eq $node) {
        return [pscustomobject]@{ Reads = $false; WriteOffset = $node.Extent.StartOffset }
    }
    if ($node.Parent -is [System.Management.Automation.Language.ParameterAst]) {
        return [pscustomobject]@{ Reads = $false; WriteOffset = $node.Extent.StartOffset }
    }
    return [pscustomobject]@{ Reads = $true; WriteOffset = $null }
}

function Invoke-WithEcho {
    <#
    .SYNOPSIS
        Runs a script block and logs the command text beforehand — like ECHO ON in DOS batch files.

    .DESCRIPTION
        The command text is written unchanged via Write-Host (information stream:
        visible in the console, captured by Start-Transcript, redirectable with 6>).
        Below it, type and current value of every variable the block reads appear
        as indented extra lines ("[String] $path = C:\data"), each value truncated
        to -MaxValueLength characters. Resolution only reads variable values in
        the caller's scope and never executes anything.

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

        foreach ($name in $names) {
            try { $value = $PSCmdlet.GetVariableValue($name) } catch { continue }
            $typePrefix = if ($null -ne $value) { "[$($value.GetType().Name)] " } else { '' }
            Write-Host "   $typePrefix`$$name = $(Format-EchoValue -Value $value -MaxLength $MaxValueLength)" @valueStyle
        }
    }

    & $ScriptBlock
}

Export-ModuleMember -Function Invoke-WithEcho
