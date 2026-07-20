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
