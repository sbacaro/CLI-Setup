# ps/Ui.ps1 — a interface do configurador.
#
# A versão bash lia teclas com `read -rsn1` e media o terminal com `stty`/`tput`.
# Nada disso existe no Windows. Aqui:
#   - tecla vem de [Console]::ReadKey($true), que devolve Key/KeyChar; seta já
#     chega como UpArrow, sem precisar interpretar sequência de escape;
#   - tamanho vem de [Console]::WindowWidth/Height;
#   - cor é ANSI, que o Windows Terminal e o Console do PS 7 renderizam.
#
# O desenho (logo, moldura, rodapé, coluna de etapas) é o mesmo da versão bash:
# quem já usou uma vê a outra igual.

Set-StrictMode -Version Latest

$script:E   = [char]27
$script:R   = "$([char]27)[0m"
$script:B   = "$([char]27)[1m"
$script:W   = "$([char]27)[97m"
$script:G   = "$([char]27)[38;2;122;126;136m"
$script:OK  = "$([char]27)[32m"
$script:ERR = "$([char]27)[31m"
$script:WARN= "$([char]27)[33m"
$script:ACC = "$([char]27)[38;2;126;206;255m"

$script:Linhas = 24
$script:Cols = 80
$script:Larg = 76
$script:Margem = 0
$script:Espaco = ''
$script:Total = 5
$script:Etapa = 0
$script:Spin = '⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
$script:MenuAtivo = $true

function Format-Tinta {
    param([int]$Tom)
    $r = [int]($Tom * 62 / 100)
    $g = [int]($Tom * 86 / 100)
    return "$($script:E)[38;2;$r;$g;${Tom}m"
}

function Write-CursorOff { [Console]::CursorVisible = $false }
function Write-CursorOn  { [Console]::CursorVisible = $true }

function Clear-Linha { Write-Host "`r$($script:E)[2K" -NoNewline }

function Write-Tracos {
    param([int]$N)
    if ($N -le 0) { return '' }
    return ([string]([char]0x2500) * $N)
}

function Write-Regua { return (Write-Tracos ($script:Larg - 4)) }

# Mede o terminal. No redirecionamento o console pode não responder, então há
# fallback e override por variável de ambiente (usado nos testes).
function Measure-Terminal {
    $linhas = 0; $cols = 0
    try { $linhas = [Console]::WindowHeight } catch {}
    try { $cols = [Console]::WindowWidth } catch {}
    if ($linhas -le 0) { $linhas = 24 }
    if ($cols -le 0) { $cols = 80 }
    if ($env:CLI_LINHAS -and $env:CLI_LINHAS -match '^\d+$') { $linhas = [int]$env:CLI_LINHAS }
    if ($env:CLI_COLS   -and $env:CLI_COLS   -match '^\d+$') { $cols   = [int]$env:CLI_COLS }
    if ($linhas -lt 14) { $linhas = 14 }
    if ($cols -lt 44) { $cols = 44 }
    $script:Linhas = $linhas
    $script:Cols = $cols
    $script:Larg = [Math]::Min($cols, 76)

    # A coluna de etapas fica encostada à direita do bloco. Quando cabe, o
    # conjunto bloco+etapas é que fica no meio: só o bloco centralizado com as
    # etapas na borda deixa a tela torta.
    $etapasLarg = 16
    if ($cols -ge ($script:Larg + $etapasLarg + 4)) {
        $script:Margem = [int](($cols - ($script:Larg + $etapasLarg)) / 2)
        if ($script:Margem -lt 2) { $script:Margem = 2 }
    } else {
        $script:Margem = [int](($cols - $script:Larg) / 2)
        if ($script:Margem -lt 0) { $script:Margem = 0 }
    }
    $script:Espaco = ' ' * $script:Margem
}

# ── teclado ────────────────────────────────────────────────────────────────
# Devolve um nome estável, para o resto do código não depender do tipo ConsoleKey.
#   up down left right enter space bs esc eof | <caractere>
function Read-Tecla {
    try {
        $k = [Console]::ReadKey($true)
    } catch {
        return 'eof'
    }
    switch ($k.Key) {
        'UpArrow'    { return 'up' }
        'DownArrow'  { return 'down' }
        'LeftArrow'  { return 'left' }
        'RightArrow' { return 'right' }
        'Enter'      { return 'enter' }
        'Spacebar'   { return 'space' }
        'Backspace'  { return 'bs' }
        'Escape'     { return 'esc' }
        'Tab'        { return 'tab' }
    }
    if ([int]$k.KeyChar -eq 3) { throw [System.OperationCanceledException]::new() }
    if ([int]$k.KeyChar -ge 32) { return [string]$k.KeyChar }
    return ''
}

function Test-ConsoleInterativo {
    try {
        if ([Console]::IsInputRedirected) { return $false }
        if ([Console]::IsOutputRedirected) { return $false }
    } catch { return $false }
    return $true
}

function Assert-Terminal {
    if (Test-ConsoleInterativo) { return }
    Write-Host ''
    Write-Host '  Este configurador precisa de um terminal interativo.'
    Write-Host '  Rode o comando direto no PowerShell, sem redirecionar a saida.'
    Write-Host ''
    exit 1
}

function Write-Cancela {
    Write-CursorOn
    Write-Host "$($script:R)"
    Write-Host ''
    Write-Host "  $($script:G)Cancelado.$($script:R) Nada foi alterado."
    Write-Host ''
    exit 130
}

# ── elementos ──────────────────────────────────────────────────────────────
function Write-Linha {
    param([AllowEmptyString()][string]$Texto = '')
    Write-Host "$($script:Espaco)  $Texto"
}

# Tela limpa, com o cabeçalho e a coluna de etapas.
function Show-Tela {
    param(
        [Parameter(Mandatory)][string]$Dir,
        [int]$Etapa = 0
    )
    $script:Etapa = $Etapa
    Write-Host "$($script:E)[2J$($script:E)[H" -NoNewline
    Write-Etapas
    Write-Host "$($script:E)[H" -NoNewline
    Write-Host ''
    $pad = $script:Larg - 2 - 23 - $Dir.Length
    if ($pad -lt 1) { $pad = 1 }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("$($script:Espaco)  ")
    [void]$sb.Append("$($script:B)$($script:ACC)CLI SETUP$($script:R)")
    [void]$sb.Append("  $($script:G)Configurador$($script:R)")
    [void]$sb.Append(' ' * $pad)
    [void]$sb.Append("$($script:G)$Dir$($script:R)")
    Write-Host $sb.ToString()
    Write-Host "$($script:Espaco)  $($script:G)$(Write-Regua)$($script:R)"
    Write-Host ''
}

function Write-Etapas {
    $col = $script:Margem + $script:Larg + 3
    if ($script:Cols -lt ($col + 16)) { return }
    Write-Host "$($script:E)[3;${col}H$($script:G)Etapas$($script:R)" -NoNewline
    $nomes = @('Chave', 'Ferramentas', 'Modelos', 'Desktop', 'Aplicar')
    for ($i = 1; $i -le 5; $i++) {
        $lin = 3 + $i
        $marca = $nomes[$i - 1]
        if ($i -lt $script:Etapa) {
            Write-Host "$($script:E)[${lin};${col}H$($script:OK)$([char]0x2713)$($script:R) $($script:G)$marca$($script:R)" -NoNewline
        } elseif ($i -eq $script:Etapa) {
            Write-Host "$($script:E)[${lin};${col}H$($script:ACC)$([char]0x25B8)$($script:R) $($script:W)$marca$($script:R)" -NoNewline
        } else {
            Write-Host "$($script:E)[${lin};${col}H$($script:G)$([char]0x00B7)$($script:R) $($script:G)$marca$($script:R)" -NoNewline
        }
    }
}

function Write-Dicas {
    param([string[]]$Dicas)
    $partes = @()
    foreach ($d in $Dicas) {
        $i = $d.IndexOf(':')
        if ($i -lt 0) { $partes += "$($script:B)$($script:W)$d$($script:R)" }
        else {
            $k = $d.Substring(0, $i)
            $v = $d.Substring($i + 1)
            $partes += "$($script:B)$($script:W)$k$($script:R) $($script:G)$v$($script:R)"
        }
    }
    return ($partes -join '   ')
}

function Write-Rodape {
    param([string[]]$Dicas)
    $texto = Write-Dicas $Dicas
    if ($script:Linhas -ge 18) {
        $lin = $script:Linhas - 2
        Write-Host "$($script:E)[${lin};1H$($script:Espaco)  $($script:G)$(Write-Regua)$($script:R)"
        Write-Host "$($script:Espaco)  $texto"
    } else {
        Write-Host ''
        Write-Host "$($script:Espaco)  $($script:G)$(Write-Regua)$($script:R)"
        Write-Host "$($script:Espaco)  $texto"
    }
}

# ── moldura das telas ──────────────────────────────────────────────────────
# As três partes têm a mesma largura visível, então a borda direita fecha.
function Write-CaixaTopo {
    param([Parameter(Mandatory)][string]$Titulo)
    $D = $script:Larg - 7 - $Titulo.Length
    if ($D -lt 1) { $D = 1 }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("$($script:Espaco)  $($script:G)$([char]0x256D)$([char]0x2500)$($script:R)")
    [void]$sb.Append(" $($script:B)$($script:ACC)$Titulo$($script:R) ")
    [void]$sb.Append("$($script:G)$(Write-Tracos $D)$([char]0x256E)$($script:R)")
    Write-Host $sb.ToString()
}

function Write-CaixaLinha {
    param(
        [AllowEmptyString()][string]$Texto = '',
        [int]$Visivel = 0
    )
    $P = $script:Larg - 6 - $Visivel
    if ($P -lt 0) { $P = 0 }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("$($script:Espaco)  $($script:G)$([char]0x2502)$($script:R)  ")
    [void]$sb.Append($Texto)
    [void]$sb.Append(' ' * $P)
    [void]$sb.Append("$($script:G)$([char]0x2502)$($script:R)")
    Write-Host $sb.ToString()
}

function Write-CaixaFundo {
    $D = $script:Larg - 4
    if ($D -lt 1) { $D = 1 }
    Write-Host "$($script:Espaco)  $($script:G)$([char]0x2570)$(Write-Tracos $D)$([char]0x256F)$($script:R)"
}

# ── logotipo ───────────────────────────────────────────────────────────────
$script:LogoCli = @(
    ' ██████╗  ██╗        ██╗'
    '██╔════╝  ██║        ██║'
    '██║        ██║        ██║'
    '██║        ██║        ██║'
    '╚██████╗   ███████╗   ██║'
    ' ╚═════╝   ╚══════╝   ╚═╝'
)
$script:LogoSetup = @(
    '███████╗  ███████╗  ████████╗  ██╗   ██╗  ██████╗'
    '██╔════╝  ██╔════╝  ╚══██╔══╝  ██║   ██║  ██╔══██╗'
    '███████╗  █████╗       ██║     ██║   ██║  ██████╔╝'
    '╚════██║  ██╔══╝       ██║     ██║   ██║  ██╔═══╝'
    '███████║  ███████╗     ██║     ╚██████╔╝  ██║'
    '╚══════╝  ╚══════╝     ╚═╝      ╚═════╝   ╚═╝'
)

function Get-LogoLinha {
    param([int]$i)
    if ($i -lt 6) { return $script:LogoCli[$i] }
    return $script:LogoSetup[$i - 6]
}

function Get-LogoTom {
    param([int]$i, [int]$S)
    $t = 236 - $i * 9
    if ($t -lt 132) { $t = 132 }
    if ($S -ge 0) {
        $d = [Math]::Abs($i - $S)
        switch ($d) {
            0 { $t = 255 }
            1 { $t = $t + 52 }
            2 { $t = $t + 26 }
        }
        if ($t -gt 255) { $t = 255 }
    }
    return $t
}

# ── escrita animada ────────────────────────────────────────────────────────
function Write-Digita {
    param([string]$Texto)
    foreach ($ch in $Texto.ToCharArray()) {
        Write-Host $ch -NoNewline
        Start-Sleep -Milliseconds 6
    }
}

function Show-Abertura {
    param([string]$Versao)
    Write-Host "$($script:E)[2J$($script:E)[H" -NoNewline
    Write-CursorOff

    if ($script:Cols -lt 58 -or $script:Linhas -lt 20) {
        Write-Host "$($script:E)[H"
        Write-Host "$($script:Espaco)  $($script:B)$($script:ACC)CLI SETUP$($script:R)  $($script:G)Configurador$($script:R)"
        Start-Sleep -Milliseconds 300
    } else {
        $logoLarg = 52
        $col = $script:Margem + [int](($script:Larg - $logoLarg) / 2)
        if ($col -lt 2) { $col = 2 }
        $topo = [int](($script:Linhas - 15) / 2)
        if ($topo -lt 2) { $topo = 2 }

        # linhas surgem de cima para baixo
        for ($i = 0; $i -lt 12; $i++) {
            $lin = $topo + $i
            Write-Host "$($script:E)[${lin};${col}H$(Format-Tinta (Get-LogoTom $i -1))$(Get-LogoLinha $i)$($script:R)" -NoNewline
            Start-Sleep -Milliseconds 40
        }
        # o brilho atravessa duas vezes, a segunda mais rápida
        for ($s = -2; $s -lt 14; $s++) {
            for ($i = 0; $i -lt 12; $i++) {
                $lin = $topo + $i
                Write-Host "$($script:E)[${lin};${col}H$(Format-Tinta (Get-LogoTom $i $s))$(Get-LogoLinha $i)$($script:R)" -NoNewline
            }
            Start-Sleep -Milliseconds 30
        }
        for ($s = -4; $s -lt 14; $s++) {
            for ($i = 0; $i -lt 12; $i++) {
                $lin = $topo + $i
                Write-Host "$($script:E)[${lin};${col}H$(Format-Tinta (Get-LogoTom $i $s))$(Get-LogoLinha $i)$($script:R)" -NoNewline
            }
            Start-Sleep -Milliseconds 16
        }
    }

    $sub = "Configurador de terminal  ·  api.kodeo.com.br  ·  v$Versao"
    if ($script:Linhas -lt 20 -or $script:Cols -lt 58) {
        $linSub = 3; $col = 2
    } else {
        $linSub = $topo + 13
    }
    Write-Host "$($script:E)[${linSub};${col}H$($script:G)" -NoNewline
    Write-Digita $sub
    Write-Host "$($script:R)"
    Start-Sleep -Milliseconds 400
}

# ── menu de seleção ────────────────────────────────────────────────────────
# Desenha uma lista com cursor, marcação e status por linha. Devolve o índice
# em que o usuário confirmou, ou -1 se voltou.
#   - Itens: array de objetos com Nome, Estado (texto) e Acao (texto)
#   - Multi: $true para caixas [x]; $false para coluna única
function Show-Menu {
    param(
        [Parameter(Mandatory)][array]$Itens,
        [bool[]]$Marcado = @(),
        [bool]$Multi = $true,
        [string[]]$Rodape = @(),
        [bool]$PermiteVoltar = $true,
        [int]$Inicial = 0
    )
    $n = $Itens.Count
    if ($n -eq 0) { return @{ Indice = -1; Marcado = $Marcado } }

    $largNome = 0
    foreach ($it in $Itens) {
        if ($it.Nome.Length -gt $largNome) { $largNome = $it.Nome.Length }
    }
    $largNome += 2

    $cur = $Inicial
    if ($cur -lt 0 -or $cur -ge $n) { $cur = 0 }
    $sel = @()
    for ($i = 0; $i -lt $n; $i++) {
        $sel += [bool]($i -lt $Marcado.Count -and $Marcado[$i])
    }

    $desenha = {
        for ($i = 0; $i -lt $n; $i++) {
            $pre = '  '
            if ($i -eq $cur) { $pre = "$($script:ACC)$([char]0x276F)$($script:R) " }
            $caixa = "$($script:G)[ ]$($script:R)"
            if ($sel[$i]) { $caixa = "$($script:ACC)[x]$($script:R)" }

            $it = $Itens[$i]
            $estado = "$($script:G)$($it.Estado)$($script:R)"
            $acao = "$($script:G)  $($it.Acao)$($script:R)"
            if ($it.Estado -eq 'configurado')     { $estado = "$($script:OK)configurado$($script:R)" }
            if ($it.Estado -eq 'nao encontrado')  { $estado = "$($script:G)nao encontrado$($script:R)" }
            if ($sel[$i]) { $acao = "  $($script:W)$([char]0x2192) $($it.Acao)$($script:R)" }

            Clear-Linha
            $sb = New-Object System.Text.StringBuilder
            [void]$sb.Append("$($script:Espaco)  $pre$caixa ")
            [void]$sb.Append("$($script:W)$($it.Nome)$($script:R)")
            [void]$sb.Append(' ' * ($largNome - $it.Nome.Length))
            # O estado ocupa coluna fixa de 18: com o texto mais longo
            # ("nao configurado") ainda sobra um espaço antes da ação.
            [void]$sb.Append($estado)
            [void]$sb.Append(' ' * [Math]::Max(1, 18 - $it.Estado.Length))
            [void]$sb.Append($acao)
            Write-Host $sb.ToString()
        }
    }

    & $desenha
    Write-Rodape $Rodape

    for ($iter = 0; $iter -lt 10000; $iter++) {
        try {
            $k = Read-Tecla
        } catch {
            Write-Cancela
        }
        switch ($k) {
            'up'   { $cur = ($cur + $n - 1) % $n }
            'down' { $cur = ($cur + 1) % $n }
            'k'    { $cur = ($cur + $n - 1) % $n }
            'j'    { $cur = ($cur + 1) % $n }
            'space' { if ($Multi) { $sel[$cur] = -not $sel[$cur] } }
            'a'     { for ($i = 0; $i -lt $n; $i++) { $sel[$i] = $true } }
            'A'     { for ($i = 0; $i -lt $n; $i++) { $sel[$i] = $true } }
            'left'  { if ($PermiteVoltar) { return @{ Indice = -1; Marcado = $sel } } }
            'b'     { if ($PermiteVoltar) { return @{ Indice = -1; Marcado = $sel } } }
            'B'     { if ($PermiteVoltar) { return @{ Indice = -1; Marcado = $sel } } }
            'eof'   { Write-Cancela }
            'enter' {
                if (-not $Multi) { return @{ Indice = $cur; Marcado = $sel } }
                $algum = $false
                foreach ($s in $sel) { if ($s) { $algum = $true } }
                if ($algum) { return @{ Indice = $cur; Marcado = $sel } }
            }
            'tab' { }
        }
        Write-Host "$($script:E)[${n}A" -NoNewline
        & $desenha
    }
    return @{ Indice = -1; Marcado = $sel }
}

# Espera uma tecla específica (enter, volar, sair). Devolve 'enter' | 'left' | 'sair'.
function Wait-Continuar {
    param([bool]$PermiteVoltar = $true)
    for ($iter = 0; $iter -lt 10000; $iter++) {
        try { $k = Read-Tecla } catch { Write-Cancela }
        switch ($k) {
            'enter' { return 'enter' }
            'left'  { if ($PermiteVoltar) { return 'left' } }
            'esc'   { if ($PermiteVoltar) { return 'left' } }
            'eof'   { Write-Cancela }
        }
    }
    return 'sair'
}

# Remove o trecho entre as marcas. Usado pelo shell e pelo config.toml.
function Remove-BlocoMarcado {
    param([string]$Texto, [string]$Ini, [string]$Fim, [switch]$TabelaProvedor)
    $out = @()
    $dentro = $false
    $tabela = $false
    foreach ($l in ($Texto -split "`r?`n")) {
        $t = $l.Trim()

        # Marcas antigas do provedor eram puro comentário. Elas iam do início
        # do provedor até o fim do ARQUIVO, então removê-las levava junto
        # plugins e mcp_servers que o app tinha acrescentado depois.
        if ($t -eq '# >>> kodeo provider >>>' -or $t -eq '# <<< kodeo provider <<<') { continue }

        if ($t -eq $Ini) { $dentro = $true; continue }
        if ($t -eq $Fim) { $dentro = $false; continue }

        # Em TOML a tabela do provedor vai do cabeçalho até o próximo "["
        if ($TabelaProvedor) {
            if ($t -match '^\[model_providers\.kodeo\]') { $tabela = $true; continue }
            if ($tabela -and $t -match '^\[') { $tabela = $false }
            if ($tabela) { continue }
        }

        if (-not $dentro) { $out += $l }
    }
    return ($out -join "`n")
}


# ── passo (spinner) ────────────────────────────────────────────────────────
# Executa um bloco com indicador girando e devolve o resultado.
# Diferença da versão bash: lá o comando rodava em subshell e variável setada
# dentro dele se perdia — foi o que quebrou o modelo do Codex. Aqui o bloco roda
# num runspace separado, mas o que precisa atravessar vai por arquivo, que é o
# desenho explícito e não depende de escopo.
function Invoke-Passo {
    param(
        [Parameter(Mandatory)][string]$Texto,
        [Parameter(Mandatory)][scriptblock]$Acao
    )
    Clear-Linha
    Write-Host "$($script:Espaco)  $($script:ACC)$($script:Spin[0])$($script:R) $Texto" -NoNewline
    $i = 0
    $job = Start-ThreadJob -ScriptBlock $Acao -ErrorAction SilentlyContinue
    if ($null -eq $job) {
        # Sem ThreadJob disponível: executa direto.
        Clear-Linha
        try {
            & $Acao | Out-Null
            $ok = $true
        } catch {
            $ok = $false
            $script:PassoErro = $_.Exception.Message
        }
        if ($ok) {
            Write-Host "$($script:Espaco)  $($script:OK)$([char]0x2713)$($script:R) $Texto"
            return $true
        }
        Write-Host "$($script:Espaco)  $($script:ERR)$([char]0xD7)$($script:R) $Texto $($script:G)($script:PassoErro)$($script:R)"
        return $false
    }
    while ($job.State -eq 'Running') {
        Clear-Linha
        Write-Host "$($script:Espaco)  $($script:ACC)$($script:Spin[$i % $script:Spin.Length])$($script:R) $Texto" -NoNewline
        Start-Sleep -Milliseconds 60
        $i++
    }
    Clear-Linha
    $erro = ''
    try {
        $null = Receive-Job $job -ErrorAction Stop
        $ok = ($job.State -eq 'Completed')
    } catch {
        $ok = $false
        $erro = $_.Exception.Message
    }
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    if ($ok) {
        Write-Host "$($script:Espaco)  $($script:OK)$([char]0x2713)$($script:R) $Texto"
        return $true
    }
    Write-Host "$($script:Espaco)  $($script:ERR)$([char]0xD7)$($script:R) $Texto $($script:G)($erro)$($script:R)"
    return $false
}