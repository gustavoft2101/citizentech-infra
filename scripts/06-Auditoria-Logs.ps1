#Requires -RunAsAdministrator
<#
.SYNOPSIS
    ETAPA 3 (item 5.4 do roteiro) - Auditoria de logon e de acesso a arquivos, logs do IIS.

.DESCRIPTION
    1. Liga a auditoria (sucesso e falha) de: Logon, Logoff, Sistema de Arquivos,
       Gerenciamento de Contas de Usuário e de Grupos de Segurança.
       As subcategorias são passadas pelo GUID, que funciona em Windows em português
       e em inglês (o nome "Logon" muda de idioma, o GUID não).
    2. Aumenta o log Security para 256 MB (mais histórico para acompanhamento).
    3. Coloca regras de auditoria (SACL) na pasta do site e na pasta compartilhada.
    4. Gera um acesso de teste e consulta os eventos 4624/4625/4663 no log Security.
    5. Lista os logs do IIS em C:\inetpub\logs\LogFiles.
#>
. "$PSScriptRoot\00-Config.ps1"
. "$PSScriptRoot\lib\Comum.ps1"

Write-Etapa 'ETAPA 3 - Auditoria e logs'

# ---------------------------------------------------------------- política de auditoria
Write-Passo '5.4 Política de auditoria (auditpol)'
$subcategorias = [ordered]@{
    'Logon'                                       = '{0CCE9215-69AE-11D9-BED3-505054503030}'
    'Logoff'                                      = '{0CCE9216-69AE-11D9-BED3-505054503030}'
    'File System / Sistema de Arquivos'           = '{0CCE921D-69AE-11D9-BED3-505054503030}'
    'User Account Management / Contas de Usuário' = '{0CCE9235-69AE-11D9-BED3-505054503030}'
    'Security Group Management / Grupos'          = '{0CCE9237-69AE-11D9-BED3-505054503030}'
}
foreach ($item in $subcategorias.GetEnumerator()) {
    auditpol /set "/subcategory:$($item.Value)" /success:enable /failure:enable | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Ok "Auditoria de $($item.Key): sucesso e falha" }
    else { Write-Aviso "Falha ao configurar $($item.Key) (código $LASTEXITCODE)" }
}

Limit-EventLog -LogName Security -MaximumSize 256MB
Write-Ok 'Log Security com até 256 MB.'

Invoke-Evidencia -Titulo 'auditpol /get /category:*' -Arquivo '07-logs\auditpol.txt' -Comando {
    auditpol /get /category:*
}

# ---------------------------------------------------------------- SACL nas pastas
Write-Passo 'Regras de auditoria (SACL) nas pastas do site e do compartilhamento'
$todosSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-1-0')   # Everyone / Todos
$pastasAuditadas = @(
    @{ Pasta = $Config.PastaSite;  Direitos = 'ReadData, WriteData' }                 # igual ao roteiro
    @{ Pasta = $Config.PastaShare; Direitos = 'ReadData, WriteData, Delete' }         # quem lê, grava e apaga no share
)
foreach ($p in $pastasAuditadas) {
    $regra = New-Object System.Security.AccessControl.FileSystemAuditRule(
        $todosSid, $p.Direitos, 'ContainerInherit,ObjectInherit', 'None', 'Success,Failure')
    $pasta = Get-Item $p.Pasta
    $acl = $pasta.GetAccessControl('Audit')
    $acl.AddAuditRule($regra)
    # SetAccessControl grava SÓ a seção alterada (a SACL). Não use Set-Acl aqui: com um objeto
    # lido só com 'Audit', o Set-Acl grava também uma DACL vazia (nula) e a pasta e os arquivos
    # perdem as permissões NTFS (o site passa a dar erro 500.19 / 401.3).
    $pasta.SetAccessControl($acl)
    Write-Ok "Auditoria em $($p.Pasta): $($p.Direitos)"
}

Invoke-Evidencia -Titulo 'Regras de auditoria (Get-Acl -Audit)' -Arquivo '07-logs\sacl.txt' -Comando {
    foreach ($p in $pastasAuditadas) {
        "Pasta: $($p.Pasta)"
        (Get-Acl -Path $p.Pasta -Audit).Audit |
            Format-Table IdentityReference, FileSystemRights, AuditFlags, InheritanceFlags -AutoSize
    }
}

# ---------------------------------------------------------------- gerar eventos de teste
Write-Passo 'Gerando acessos de teste (site e compartilhamento)'
Invoke-WebRequest -Uri 'http://localhost' -UseBasicParsing | Out-Null
$arquivoTeste = Join-Path $Config.PastaShare 'teste-auditoria.txt'
Set-Content -Path $arquivoTeste -Value "Teste de auditoria $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Get-Content -Path $arquivoTeste | Out-Null
Start-Sleep -Seconds 3

# ---------------------------------------------------------------- consultar logs
Write-Passo 'Consultando o log Security'
Invoke-Evidencia -Titulo 'Últimos eventos do log Security' -Arquivo '07-logs\eventos-security.txt' -Comando {
    Get-WinEvent -LogName Security -MaxEvents 20 |
        Select-Object TimeCreated, Id, @{ n = 'Resumo'; e = { ($_.Message -split "`r?`n")[0] } } |
        Format-Table -AutoSize -Wrap

    'Logons (4624 sucesso / 4625 falha) - últimos 10:'
    Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4624, 4625 } -MaxEvents 10 |
        Select-Object TimeCreated, Id,
            @{ n = 'Conta';         e = { $_.Properties[5].Value } },
            @{ n = 'TipoDeLogon';   e = { if ($_.Id -eq 4624) { $_.Properties[8].Value } else { $_.Properties[10].Value } } } |
        Format-Table -AutoSize

    'Acesso a arquivos auditados (4663) nas pastas do projeto - últimos 10:'
    Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4663 } -MaxEvents 500 -ErrorAction SilentlyContinue |
        Where-Object { "$($_.Properties[6].Value)" -match 'citizentech' } | Select-Object -First 10 |
        Select-Object TimeCreated, Id,
            @{ n = 'Conta';   e = { $_.Properties[1].Value } },
            @{ n = 'Arquivo'; e = { $_.Properties[6].Value } } |
        Format-Table -AutoSize -Wrap
}

# ---------------------------------------------------------------- logs do IIS
Write-Passo 'Logs do IIS'
netsh http flush logbuffer | Out-Null     # o IIS grava os logs em lote; isto força a gravação agora
Invoke-Evidencia -Titulo 'Arquivos de log do IIS' -Arquivo '07-logs\iis-logs.txt' -Comando {
    Get-ChildItem 'C:\inetpub\logs\LogFiles' -Recurse -File |
        Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize
}
Invoke-Evidencia -Titulo 'Últimas linhas do log do IIS' -Arquivo '07-logs\iis-log-amostra.txt' -Comando {
    $ultimo = Get-ChildItem 'C:\inetpub\logs\LogFiles' -Recurse -Filter *.log |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    "Arquivo: $($ultimo.FullName)"
    Get-Content $ultimo.FullName -Tail 15
}

Write-Host ''
Write-Host 'Prints desta etapa: 07-logs\auditpol.png, eventviewer-security.png (eventvwr.msc > Logs do Windows > Segurança)' -ForegroundColor DarkGray
Write-Host '                    e iis-logs-pasta.png (C:\inetpub\logs\LogFiles aberto no Explorador)' -ForegroundColor DarkGray
Write-Host 'Próximo passo: .\07-Monitoramento.ps1' -ForegroundColor Green
