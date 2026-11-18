#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Laboratório (item 5.1, opção 2): permite ou remove o logon local do grupo de operadores
    no controlador de domínio, para demonstrar a GPO_CitizenTech_Usuarios com um usuário comum.

.DESCRIPTION
    Num controlador de domínio só administradores podem fazer logon no console. Para mostrar a
    restrição do Painel de Controle com carlos.lima sem criar outra VM, este script adiciona o
    grupo GG_CitizenTech_Operadores ao direito "Permitir logon local" (SeInteractiveLogonRight)
    da Default Domain Controllers Policy, sem remover as contas que já estão lá.

    A edição usa o caminho suportado pelo módulo GroupPolicy: Backup-GPO, ajuste do GptTmpl.inf
    do backup e Import-GPO (o Import grava no SYSVOL e atualiza a versão da GPO no AD).

    Depois do print, rode com -Remover para voltar ao padrão (boa prática de segurança).

.EXAMPLE
    .\Permitir-Logon-Operadores.ps1            # permite
    .\Permitir-Logon-Operadores.ps1 -Remover   # volta ao padrão
#>
param([switch]$Remover)

. "$PSScriptRoot\00-Config.ps1"
. "$PSScriptRoot\lib\Comum.ps1"
Import-Module GroupPolicy, ActiveDirectory

$nomeGpo = 'Default Domain Controllers Policy'
$acao    = if ($Remover) { 'remover' } else { 'permitir' }
Write-Etapa "Logon local dos operadores no servidor ($acao)"

$sidGrupo = (Get-ADGroup -Identity $Config.GrupoOperadores).SID.Value
$entrada  = "*$sidGrupo"

# 1. Backup da GPO
Write-Passo "Backup da $nomeGpo"
$pastaBackup = Join-Path $env:TEMP ('gpo-dc-' + (Get-Date -Format 'yyyyMMddHHmmss'))
New-Item -ItemType Directory -Path $pastaBackup -Force | Out-Null
$backup = Backup-GPO -Name $nomeGpo -Path $pastaBackup
$inf = Get-ChildItem -Path (Join-Path $pastaBackup "{$($backup.Id)}") -Recurse -Filter 'GptTmpl.inf' |
    Select-Object -First 1 -ExpandProperty FullName
if (-not $inf) { throw 'GptTmpl.inf não encontrado no backup da GPO.' }

# 2. Ajuste do direito SeInteractiveLogonRight no backup
Write-Passo "Ajustando 'Permitir logon local' ($($Config.GrupoOperadores))"
$linhas     = Get-Content -Path $inf -Encoding Unicode
$encontrou  = $false
$novas = foreach ($linha in $linhas) {
    if ($linha -match '^\s*SeInteractiveLogonRight\s*=\s*(.*)$') {
        $encontrou = $true
        $contas = @($Matches[1].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -ne $entrada })
        if (-not $Remover) { $contas += $entrada }
        'SeInteractiveLogonRight = ' + ($contas -join ',')
    }
    else { $linha }
}
if (-not $encontrou -and -not $Remover) {
    # A política não define o direito: cria a linha logo abaixo de [Privilege Rights].
    $novas = foreach ($linha in $novas) {
        $linha
        if ($linha -match '^\[Privilege Rights\]') { "SeInteractiveLogonRight = *S-1-5-32-544,$entrada" }
    }
}
Set-Content -Path $inf -Value $novas -Encoding Unicode

# 3. Importa de volta e aplica
Write-Passo 'Import-GPO e gpupdate'
Import-GPO -BackupId $backup.Id -Path $pastaBackup -TargetName $nomeGpo | Out-Null
gpupdate /target:computer /force | Out-Null
Remove-Item -Path $pastaBackup -Recurse -Force -ErrorAction SilentlyContinue

# 4. Evidência: direito efetivo no servidor, com os nomes das contas
$arquivoDireitos = Join-Path $env:TEMP 'direitos-usuario.inf'
Invoke-Evidencia -Titulo "Permitir logon local no servidor ($acao operadores)" -Arquivo '04-ntfs-gpo\logon-local-operadores.txt' -Comando {
    secedit /export /areas USER_RIGHTS /cfg $arquivoDireitos | Out-Null
    $linha = Select-String -Path $arquivoDireitos -Pattern '^SeInteractiveLogonRight' | Select-Object -First 1
    ($linha.Line -split '=', 2)[1].Split(',') | ForEach-Object {
        $item = $_.Trim()
        $nome = $item
        if ($item.StartsWith('*')) {
            try { $nome = Get-NomeConta $item.TrimStart('*') } catch { $nome = $item }
        }
        [pscustomobject]@{ Conta = $nome; Identificador = $item }
    } | Format-Table -AutoSize
}

if ($Remover) {
    Write-Ok 'Operadores sem logon local no servidor (padrão restaurado).'
} else {
    Write-Ok "Agora saia da sessão e entre como $($Config.NetBIOS)\carlos.lima para testar a GPO."
    Write-Host 'Depois do print, volte como Administrator e rode: .\Permitir-Logon-Operadores.ps1 -Remover' -ForegroundColor Yellow
}
