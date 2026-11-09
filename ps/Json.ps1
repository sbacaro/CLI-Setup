# ps/Json.ps1 — leitura e escrita de JSON sem dependência externa.
#
# A versão bash precisava de node ou python3 porque não tinha JSON nativo no
# shell. O PowerShell 7 tem ConvertFrom-Json/ConvertTo-Json embutidos, então
# aqui não há escolha de ferramenta: é sempre o runtime.
#
# Regras que vieram da versão bash e continuam valendo:
#   - nenhuma função adivinha o formato: o arquivo é lido inteiro e validado;
#   - gravação é atômica (tmp + rename), então um arquivo corrompido nunca é
#     sobrescrito no meio;
#   - ordem das chaves é preservada ([ordered]) — o app lê a config como texto
#     em alguns caminhos e a ordem estável ajuda a inspecionar.

Set-StrictMode -Version Latest

# Converte o que veio do ConvertFrom-Json (PSCustomObject) em estruturas que
# aceitam escrita livre. O PSCustomObject do PS 7.4 é imutável em alguns casos,
# e mesclar é justamente adicionar chave.
function ConvertTo-OrderedMap {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $o = [ordered]@{}
        foreach ($p in $Value.PSObject.Properties) {
            $o[$p.Name] = ConvertTo-OrderedMap $p.Value
        }
        return $o
    }
    # Array antes de qualquer outra checagem: um array de 1 elemento vira
    # escalar do jeito errado, e o PSCustomObject também é IEnumerable — era
    # isso que fazia "methods": [{...}] voltar como objeto.
    if ($Value -is [System.Array]) {
        $arr = @()
        foreach ($item in $Value) { $arr += ,(ConvertTo-OrderedMap $item) }
        return ,$arr
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $o = [ordered]@{}
        foreach ($k in $Value.Keys) { $o[$k] = ConvertTo-OrderedMap $Value[$k] }
        return $o
    }
    return $Value
}

# Lê um arquivo JSON como mapa ordenado. Devolve $null se não existe ou é vazio.
# Lança se o conteúdo for inválido — quem chama decide o que fazer.
function Read-JsonMap {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return [ordered]@{} }
    $text = [IO.File]::ReadAllText($Path)
    if ([string]::IsNullOrWhiteSpace($text)) { return [ordered]@{} }
    $obj = $text | ConvertFrom-Json -ErrorAction Stop
    $map = ConvertTo-OrderedMap $obj
    if ($map -isnot [System.Collections.IDictionary]) {
        throw "não é um objeto JSON"
    }
    return $map
}

function Test-JsonEmpty {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    $t = [IO.File]::ReadAllText($Path)
    return [string]::IsNullOrWhiteSpace($t)
}

function Test-JsonValid {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    try {
        $null = Read-JsonMap $Path
        return $true
    } catch {
        return $false
    }
}

# Grava texto de forma atômica: escreve num .tmp e renomeia.
# UTF-8 sem BOM — o BOM quebra o leitor dos apps que esperam JSON puro.
function Write-FileAtomic {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $tmp = "$Path.cli-tmp"
    [IO.File]::WriteAllText($tmp, $Content, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function ConvertTo-JsonText {
    param([Parameter(Mandatory)]$Value, [int]$Depth = 24)
    return ($Value | ConvertTo-Json -Depth $Depth)
}

# Escreve um objeto como JSON formatado (2 espaços), atômico, sem BOM.
function Write-JsonFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Value)
    Write-FileAtomic -Path $Path -Content ((ConvertTo-JsonText $Value) + "`n")
}

# Lê um campo por caminho pontuado ("env.MINHA_VAR"). Devolve $null se faltar.
function Get-JsonPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Field
    )
    $map = $null
    try { $map = Read-JsonMap $Path } catch { return $null }
    $cur = $map
    foreach ($seg in $Field.Split('.')) {
        if ($null -eq $cur) { return $null }
        if ($cur -isnot [System.Collections.IDictionary]) { return $null }
        if (-not $cur.Contains($seg)) { return $null }
        $cur = $cur[$seg]
    }
    return $cur
}

# Mescla $Add dentro de $Target. Objetos internos são fundidos, não trocados —
# o mesmo comportamento do json_op "merge" da versão bash, que é o que preserva
# as chaves que o usuário já tinha.
function Merge-JsonMap {
    param($Target, $Add)
    if ($Target -isnot [System.Collections.IDictionary]) { $Target = [ordered]@{} }
    foreach ($k in $Add.Keys) {
        $v = $Add[$k]
        if ($v -is [System.Collections.IDictionary] -and
            $Target.Contains($k) -and $Target[$k] -is [System.Collections.IDictionary]) {
            $Target[$k] = Merge-JsonMap $Target[$k] $v
        } else {
            $Target[$k] = $v
        }
    }
    return $Target
}

# json_op equivalente. Operações:
#   merge       mescla (objetos internos fundidos)
#   merge-keep  só adiciona chave que ainda não existe
#   del         remove as chaves listadas
function Update-JsonFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateSet('merge', 'merge-keep', 'del')][string]$Operation,
        $Value
    )
    $map = $null
    try {
        $map = Read-JsonMap $Path
    } catch {
        Write-Error "arquivo corrompido, nada foi alterado: $Path"
        return $false
    }
    switch ($Operation) {
        'merge'      { $map = Merge-JsonMap $map $Value }
        'merge-keep' {
            foreach ($k in $Value.Keys) {
                if (-not $map.Contains($k)) { $map[$k] = $Value[$k] }
            }
        }
        'del' {
            foreach ($k in $Value) { if ($map.Contains($k)) { $map.Remove($k) } }
        }
    }
    Write-JsonFile -Path $Path -Value $map
    return $true
}