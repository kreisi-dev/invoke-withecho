# Automatische bzw. laufzeitgebundene Variablen, deren Wert im Echo-Log keinen
# Mehrwert hat oder zum Aufrufzeitpunkt noch nicht existiert (z. B. $_ in einer Pipeline).
$script:SkipVariables = @(
    '_', 'PSItem', 'null', 'true', 'false', 'args', 'input', 'this',
    'foreach', 'switch', 'PSCmdlet', 'MyInvocation', 'PSBoundParameters',
    'PSScriptRoot', 'PSCommandPath', 'Error', 'LASTEXITCODE', 'PID',
    'HOME', 'PWD', 'Host', 'ExecutionContext', 'PROFILE'
)

function Format-EchoValue {
    param($Value, [int] $MaxLength)

    if ($null -eq $Value) { return '<nicht definiert / null>' }
    if ($Value -is [securestring] -or $Value -is [pscredential]) { return '<geheim>' }

    if ($Value -is [System.Collections.IDictionary]) {
        $pairs = $Value.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
        $text = '{' + ($pairs -join ', ') + '}'
    }
    elseif ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = @($Value)
        $text = '(' + ($items -join ', ') + ")  [$($items.Count) Elemente]"
    }
    else {
        $text = "$Value"
    }

    if ($text.Length -gt $MaxLength) { $text = $text.Substring(0, $MaxLength) + '…' }
    return $text
}

function Get-EchoVariableUse {
    # Klassifiziert eine Variablen-Fundstelle: liest sie (potenziell) den Scope des
    # Aufrufers, oder ist sie ein Schreibziel im Block? Beim Schreiben zählt als
    # Zeitpunkt das Ende des Zuweisungs-Statements, weil die rechte Seite vorher
    # ausgewertet wird ($a = $a + 1 liest den alten Wert).
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
        Führt einen ScriptBlock aus und loggt vorher den Befehlstext — wie ECHO ON in DOS-Batchdateien.

    .DESCRIPTION
        Der Befehlstext wird unverändert per Write-Host ausgegeben (Information-Stream:
        sichtbar in der Konsole, wird von Start-Transcript erfasst, per 6> umleitbar).
        Darunter erscheinen die aktuellen Werte aller im Block referenzierten Variablen
        als eingerückte Zusatzzeilen, pro Wert gekürzt auf -MaxValueLength Zeichen.
        Die Auflösung liest nur Variablenwerte im Scope des Aufrufers und führt nichts aus.

        Die Pipeline-Ausgabe des Blocks wird unverändert durchgereicht. Zuweisungen
        gehören daher vor den Aufruf, nicht in den Block:
            $x = Invoke-WithEcho { Get-ChildItem $path }   # richtig
            Invoke-WithEcho { $x = Get-ChildItem $path }   # $x verpufft im Child-Scope

    .PARAMETER ScriptBlock
        Der auszuführende Block.

    .PARAMETER MaxValueLength
        Maximale Länge pro geloggtem Variablenwert (Default 100), danach wird mit … gekürzt.

    .PARAMETER NoExpand
        Unterdrückt die Variablen-Zusatzzeilen; nur der Befehlstext wird geloggt.

    .PARAMETER CommandColor
        Konsolenfarbe der Befehlszeilen (Default: Cyan). Betrifft nur die Darstellung
        in der Konsole; im Transcript steht reiner Text.

    .PARAMETER ValueColor
        Konsolenfarbe der Variablen-Zusatzzeilen (Default: DarkGray).

    .PARAMETER NoColor
        Gibt alle Echo-Zeilen in der Standardfarbe der Konsole aus.

    .EXAMPLE
        $dateien = Invoke-WithEcho { Get-ChildItem $quellPfad -Filter *.csv }
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Write-Host ist hier Designentscheidung: Information-Stream wird von Start-Transcript erfasst, ist per 6> umleitbar und verschmutzt den Rückgabewert nicht.')]
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

        # Geloggt wird nur, was aus dem Aufrufer-Scope gelesen wird: eine Variable,
        # deren erste Lesung nach einer abgeschlossenen Zuweisung im Block liegt,
        # ist blocklokal und erscheint nicht.
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
            Write-Host "   `$$name = $(Format-EchoValue -Value $value -MaxLength $MaxValueLength)" @valueStyle
        }
    }

    & $ScriptBlock
}

Export-ModuleMember -Function Invoke-WithEcho
