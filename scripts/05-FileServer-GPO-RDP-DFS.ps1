#Requires -RunAsAdministrator
<#
.SYNOPSIS
    ETAPAS 2 e 3 (itens 4.5, 5.1, 5.2 e 5.3 do roteiro) - File Server, GPO, acesso remoto e DFS.

.DESCRIPTION
      4.5  Compartilhamento \\SRV-CITIZENTECH\CitizenTech com permissões de
           compartilhamento E permissões NTFS (admins alteram, usuários do domínio leem)
      5.1  GPO_CitizenTech_Usuarios ligada à OU CitizenTech: bloqueia o Painel de Controle
      5.2  Acesso remoto por RDP com autenticação em nível de rede (NLA)
      5.3  Namespace DFS de domínio \\citizentech.local\CitizenTechDFS

    Nomes de grupos padrão ("Domain Users", "Everyone"...) são obtidos pelo SID,
    então o script funciona com o Windows em português ou em inglês.
#>
. "$PSScriptRoot\00-Config.ps1"
. "$PSScriptRoot\lib\Comum.ps1"

Write-Etapa 'ETAPAS 2 e 3 - File Server, GPO, RDP e DFS'

Import-Module ActiveDirectory
$sidDominio        = (Get-ADDomain).DomainSID.Value
$usuariosDominio   = Get-NomeConta "$sidDominio-513"      # Domain Users / Usuários do domínio
$administradores   = Get-NomeConta 'S-1-5-32-544'          # BUILTIN\Administrators / Administradores
$todos             = Get-NomeConta 'S-1-1-0'               # Everyone / Todos
$grupoAdmins       = "$($Config.NetBIOS)\$($Config.GrupoAdmins)"
$caminhoUNC        = "\\$($Config.NomeServidor)\$($Config.Compartilhamento)"

# ---------------------------------------------------------------- 4.5 File Server
Write-Passo '4.5 File Server e compartilhamento'
Install-WindowsFeature -Name FS-FileServer -IncludeManagementTools | Out-Null
New-Item -Path $Config.PastaShare -ItemType Directory -Force | Out-Null

# Permissões NTFS da pasta compartilhada
$acl = (Get-Item $Config.PastaShare).GetAccessControl('Access')
$acl.SetAccessRule((New-RegraNtfs -Conta $grupoAdmins     -Direitos 'Modify'))
$acl.SetAccessRule((New-RegraNtfs -Conta $usuariosDominio -Direitos 'ReadAndExecute'))
Set-Acl -Path $Config.PastaShare -AclObject $acl

# Permissões de compartilhamento (a permissão efetiva é a mais restritiva entre SMB e NTFS)
if (-not (Get-SmbShare -Name $Config.Compartilhamento -ErrorAction SilentlyContinue)) {
    New-SmbShare -Name $Config.Compartilhamento -Path $Config.PastaShare `
        -FullAccess $grupoAdmins, $administradores `
        -Description 'Documentos da operacao AlertaEncosta (dados simulados)' | Out-Null
    Write-Ok "Compartilhamento $caminhoUNC criado."
}
Grant-SmbShareAccess -Name $Config.Compartilhamento -AccountName $usuariosDominio -AccessRight Read -Force | Out-Null

# Arquivo de exemplo (simulado) para testar o acesso a partir do cliente
$exemplo = Join-Path $Config.PastaShare 'LEIA-ME-plano-de-contingencia-SIMULADO.txt'
if (-not (Test-Path $exemplo)) {
    Set-Content -Path $exemplo -Encoding UTF8 -Value @(
        'AlertaEncosta - Plano de contingência (DOCUMENTO SIMULADO PARA FINS ACADÊMICOS)'
        'Setores: BR-01 a BR-04 (Vila Brasilândia) | Pontos de apoio: PA-1 a PA-3'
        'Nenhum dado pessoal real é armazenado neste servidor.'
    )
}

Invoke-Evidencia -Titulo 'Get-SmbShare e permissões' -Arquivo '04-ntfs-gpo\get-smbshare.txt' -Comando {
    Get-SmbShare | Format-Table Name, Path, ScopeName, Description -AutoSize
    Get-SmbShareAccess -Name $Config.Compartilhamento | Format-Table Name, AccountName, AccessControlType, AccessRight -AutoSize
    "NTFS de $($Config.PastaShare):"
    (Get-Acl $Config.PastaShare).Access | Format-Table IdentityReference, FileSystemRights, AccessControlType, IsInherited -AutoSize
    "Teste local do caminho de rede: Test-Path $caminhoUNC = $(Test-Path $caminhoUNC)"
}

# ---------------------------------------------------------------- 5.1 GPO
Write-Passo '5.1 GPO: bloquear o Painel de Controle para os usuários da OU CitizenTech'
Import-Module GroupPolicy
try   { $gpo = Get-GPO -Name $Config.Gpo -ErrorAction Stop }
catch { $gpo = New-GPO -Name $Config.Gpo -Comment 'AlertaEncosta: bloqueia o Painel de Controle para usuarios da OU CitizenTech' }

$links = (Get-GPInheritance -Target $CaminhoOU).GpoLinks | Where-Object DisplayName -eq $Config.Gpo
if (-not $links) { New-GPLink -Name $Config.Gpo -Target $CaminhoOU -LinkEnabled Yes | Out-Null }

Set-GPRegistryValue -Name $Config.Gpo `
    -Key 'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' `
    -ValueName 'NoControlPanel' -Type DWord -Value 1 | Out-Null
Write-Ok "GPO $($Config.Gpo) criada, configurada e ligada a $CaminhoOU"

New-Item -Path $Config.PastaTemp -ItemType Directory -Force | Out-Null
$relatorio = Join-Path $Config.PastaTemp 'GPO_Report.html'
Get-GPOReport -Name $Config.Gpo -ReportType Html -Path $relatorio
Copy-Item $relatorio (Join-Path $PastaEvidencias '04-ntfs-gpo\GPO_Report.html') -Force
Write-Ok "Relatório HTML: $relatorio (cópia em evidencias\04-ntfs-gpo)"

Invoke-Evidencia -Titulo 'Get-GPO -All e vínculo na OU' -Arquivo '04-ntfs-gpo\gpo.txt' -Comando {
    Get-GPO -All | Format-Table DisplayName, GpoStatus, CreationTime, ModificationTime -AutoSize
    (Get-GPInheritance -Target $CaminhoOU).GpoLinks | Format-Table DisplayName, Enabled, Enforced, Target -AutoSize
    Get-GPRegistryValue -Name $Config.Gpo -Key 'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' |
        Format-Table ValueName, Type, Value, PolicyState -AutoSize
}

# ---------------------------------------------------------------- 5.2 RDP
Write-Passo '5.2 Acesso remoto (RDP com NLA)'
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -Value 1
# O grupo de regras "Área de Trabalho Remota" / "Remote Desktop" pelo identificador interno (independe do idioma)
Enable-NetFirewallRule -Group '@FirewallAPI.dll,-28752'
Write-Ok 'RDP habilitado, NLA exigido e regras de firewall ativas.'

Invoke-Evidencia -Titulo 'Configuração do RDP' -Arquivo '04-ntfs-gpo\rdp.txt' -Comando {
    Get-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' |
        Format-List fDenyTSConnections
    Get-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' |
        Format-List UserAuthentication, PortNumber
    Get-NetFirewallRule -Group '@FirewallAPI.dll,-28752' | Format-Table DisplayName, Enabled, Direction, Action -AutoSize
    Test-NetConnection -ComputerName $FQDNServidor -Port 3389 |
        Format-List ComputerName, RemoteAddress, RemotePort, TcpTestSucceeded
}

# ---------------------------------------------------------------- 5.3 DFS
Write-Passo '5.3 DFS: namespace de domínio'
Install-WindowsFeature -Name FS-DFS-Namespace, FS-DFS-Replication -IncludeManagementTools | Out-Null
Start-Service Dfs -ErrorAction SilentlyContinue

New-Item -Path $Config.PastaRaizDfs -ItemType Directory -Force | Out-Null
if (-not (Get-SmbShare -Name $Config.RaizDfs -ErrorAction SilentlyContinue)) {
    New-SmbShare -Name $Config.RaizDfs -Path $Config.PastaRaizDfs -ReadAccess $todos -FullAccess $administradores | Out-Null
}

# Namespace de domínio: o caminho usa o nome do DOMÍNIO e o destino é o compartilhamento do servidor.
$raizDfs   = "\\$($Config.Dominio)\$($Config.RaizDfs)"
$pastaDfs  = "$raizDfs\Documentos"
try   { Get-DfsnRoot -Path $raizDfs -ErrorAction Stop | Out-Null; Write-Ok "Raiz DFS $raizDfs já existe." }
catch {
    New-DfsnRoot -Path $raizDfs -TargetPath "\\$($Config.NomeServidor)\$($Config.RaizDfs)" -Type DomainV2 | Out-Null
    Write-Ok "Raiz DFS $raizDfs criada."
}
try   { Get-DfsnFolder -Path $pastaDfs -ErrorAction Stop | Out-Null }
catch {
    New-DfsnFolder -Path $pastaDfs -TargetPath $caminhoUNC | Out-Null
    Write-Ok "Pasta DFS $pastaDfs -> $caminhoUNC"
}

Invoke-Evidencia -Titulo 'Get-DfsnRoot' -Arquivo '04-ntfs-gpo\dfs.txt' -Comando {
    Get-DfsnRoot | Format-Table Path, Type, State, Description -AutoSize
    Get-DfsnFolder -Path "$raizDfs\*" | Format-Table Path, State -AutoSize
    Get-DfsnFolderTarget -Path $pastaDfs | Format-Table Path, TargetPath, State -AutoSize
    "Conteúdo via DFS ($pastaDfs):"
    Get-ChildItem $pastaDfs | Format-Table Name, Length, LastWriteTime -AutoSize
}

Write-Host ''
Write-Host 'Testes a fazer em OUTRA máquina (prints):' -ForegroundColor Green
Write-Host "  - Explorador de Arquivos: $caminhoUNC  (04-ntfs-gpo\acesso-share-cliente.png)"
Write-Host "  - mstsc /v:$($Config.IP)  e no terminal remoto digite: hostname  (04-ntfs-gpo\rdp-conexao.png)"
Write-Host '  - Logon de um usuário comum da OU (ex.: carlos.lima) sem acesso ao Painel de Controle'
Write-Host '    (04-ntfs-gpo\usuario-sem-painel.png) - veja docs\roteiro-configuracao.md, item 5.1'
Write-Host 'Próximo passo: .\06-Auditoria-Logs.ps1' -ForegroundColor Green
