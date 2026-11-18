#Requires -RunAsAdministrator
<#
.SYNOPSIS
    ETAPA 2 (itens 4.1, 4.2 e 4.4 do roteiro) - IIS, publicação do AlertaEncosta e permissões NTFS.

.DESCRIPTION
    Caminho escolhido: A (aplicação estática HTML, CSS e JavaScript).
      4.1  Instala o IIS e as ferramentas de gerenciamento e de log
      4.2  Copia o site para C:\inetpub\citizentech, cria o pool CitizenTechPool
           (sem código gerenciado) e o site CitizenTech na porta 80
      4.4  Permissões NTFS: IIS_IUSRS e IUSR com leitura, equipe admin com alteração
      +    Regra de firewall para a porta 80 e remoção do site padrão do IIS
#>
. "$PSScriptRoot\00-Config.ps1"
. "$PSScriptRoot\lib\Comum.ps1"

Write-Etapa 'ETAPA 2 - Hospedar a aplicação AlertaEncosta no IIS (Caminho A)'

# ---------------------------------------------------------------- 4.1
Write-Passo '4.1 Instalar o IIS'
$recursosIIS = @(
    'Web-Server',            # Servidor Web (IIS) com os recursos padrão (conteúdo estático, documento padrão...)
    'Web-Mgmt-Console',      # Gerenciador do IIS (interface gráfica)
    'Web-Scripting-Tools',   # Módulo WebAdministration do PowerShell (IIS:\)
    'Web-Http-Logging',      # Logs de acesso em C:\inetpub\logs\LogFiles
    'Web-Request-Monitor',   # Monitor de requisições em execução
    'Web-Http-Tracing'       # Rastreamento de solicitações com falha (diagnóstico)
)
Invoke-Evidencia -Titulo 'Install-WindowsFeature Web-Server' -Arquivo '03-iis\install-iis.txt' -Comando {
    Install-WindowsFeature -Name $recursosIIS -IncludeManagementTools |
        Format-Table Success, RestartNeeded, ExitCode, FeatureResult -AutoSize -Wrap
}
Invoke-Evidencia -Titulo 'Recursos Web-* instalados' -Arquivo '03-iis\get-windowsfeature-web.txt' -Comando {
    Get-WindowsFeature -Name Web-* | Where-Object Installed | Format-Table Name, DisplayName, InstallState -AutoSize
}

Import-Module WebAdministration

# ---------------------------------------------------------------- 4.2 arquivos do site
Write-Passo "4.2 Copiar o AlertaEncosta para $($Config.PastaSite)"
if (-not (Test-Path (Join-Path $PastaApp 'index.html'))) {
    throw "Não encontrei o site em $PastaApp. O repositório foi copiado inteiro para a VM?"
}
New-Item -Path $Config.PastaSite -ItemType Directory -Force | Out-Null
Copy-Item -Path "$PastaApp\*" -Destination $Config.PastaSite -Recurse -Force

# servidor.json: o rodapé do site mostra de qual servidor a página veio (prova de que está no IIS da VM)
$versaoIIS = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\InetStp').VersionString
$infoServidor = [ordered]@{
    servidor    = $env:COMPUTERNAME
    dominio     = $Config.Dominio
    ip          = $Config.IP
    iis         = $versaoIIS
    sistema     = (Get-CimInstance Win32_OperatingSystem).Caption
    site        = $Config.Site
    pool        = $Config.Pool
    hospedagem  = 'Caminho A - aplicacao estatica (HTML, CSS, JavaScript)'
    publicadoEm = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
}
$json = $infoServidor | ConvertTo-Json
[System.IO.File]::WriteAllText((Join-Path $Config.PastaSite 'servidor.json'), $json, (New-Object System.Text.UTF8Encoding($false)))

Invoke-Evidencia -Titulo 'Arquivos publicados' -Arquivo '03-iis\arquivos-site.txt' -Comando {
    Get-ChildItem $Config.PastaSite -Recurse -File | Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize
}

# ---------------------------------------------------------------- 4.2 pool e site
Write-Passo '4.2 Pool de aplicativos e site'

# O site padrão também usa a porta 80 sem cabeçalho de host; com ele ativo o novo site não inicia.
if (Test-Path 'IIS:\Sites\Default Web Site') {
    Remove-Website -Name 'Default Web Site'
    Write-Ok 'Site padrão (Default Web Site) removido para liberar a porta 80.'
}

if (-not (Test-Path "IIS:\AppPools\$($Config.Pool)")) {
    New-WebAppPool -Name $Config.Pool | Out-Null
    Write-Ok "Pool $($Config.Pool) criado."
}
# Vazio = "Sem Código Gerenciado". Obrigatório para site estático (evita o erro 500.19).
Set-ItemProperty -Path "IIS:\AppPools\$($Config.Pool)" -Name managedRuntimeVersion -Value ''

if (-not (Test-Path "IIS:\Sites\$($Config.Site)")) {
    New-Website -Name $Config.Site -Port 80 -PhysicalPath $Config.PastaSite -ApplicationPool $Config.Pool | Out-Null
    Write-Ok "Site $($Config.Site) criado na porta 80."
} else {
    Set-ItemProperty "IIS:\Sites\$($Config.Site)" -Name physicalPath    -Value $Config.PastaSite
    Set-ItemProperty "IIS:\Sites\$($Config.Site)" -Name applicationPool -Value $Config.Pool
    Write-Ok "Site $($Config.Site) já existia; caminho e pool conferidos."
}
Start-WebAppPool -Name $Config.Pool -ErrorAction SilentlyContinue
Start-Website   -Name $Config.Site -ErrorAction SilentlyContinue

# Firewall: o IIS já cria uma regra, mas deixamos uma explícita com nome do projeto.
if (-not (Get-NetFirewallRule -DisplayName 'CitizenTech - HTTP (80)' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName 'CitizenTech - HTTP (80)' -Direction Inbound -Protocol TCP `
        -LocalPort 80 -Action Allow -Profile Any | Out-Null
}
Write-Ok 'Porta 80 liberada no firewall.'

# ---------------------------------------------------------------- 4.4 NTFS
Write-Passo "4.4 Permissões NTFS em $($Config.PastaSite)"
# GetAccessControl('Access') lê só a lista de permissões (evita erro de "proprietário" no Set-Acl).
$acl = (Get-Item $Config.PastaSite).GetAccessControl('Access')
$acl.SetAccessRule((New-RegraNtfs -Conta 'S-1-5-32-568' -Direitos 'ReadAndExecute'))                         # IIS_IUSRS (identidade do pool)
$acl.SetAccessRule((New-RegraNtfs -Conta 'S-1-5-17'     -Direitos 'ReadAndExecute'))                         # IUSR (acesso anônimo)
$acl.SetAccessRule((New-RegraNtfs -Conta "$($Config.NetBIOS)\$($Config.GrupoAdmins)" -Direitos 'Modify'))    # equipe que publica o site
Set-Acl -Path $Config.PastaSite -AclObject $acl
Write-Ok 'IIS_IUSRS e IUSR: leitura e execução | GG_CitizenTech_Admins: alteração'

Invoke-Evidencia -Titulo 'Get-Acl da pasta do site' -Arquivo '03-iis\get-acl.txt' -Comando {
    Get-Acl $Config.PastaSite | Format-List Path, Owner, AccessToString
    (Get-Acl $Config.PastaSite).Access |
        Format-Table IdentityReference, FileSystemRights, AccessControlType, IsInherited -AutoSize
}

# ---------------------------------------------------------------- validação
Write-Passo 'Validação do site'
Start-Sleep -Seconds 2
Invoke-Evidencia -Titulo 'Get-Website' -Arquivo '03-iis\get-website.txt' -Comando {
    Get-Website -Name $Config.Site | Format-List Name, ID, State, PhysicalPath, ApplicationPool
    Get-WebBinding -Name $Config.Site | Format-Table protocol, bindingInformation -AutoSize
}
Invoke-Evidencia -Titulo 'Get-WebAppPoolState e runtime do pool' -Arquivo '03-iis\get-webapppoolstate.txt' -Comando {
    "Pool $($Config.Pool): $((Get-WebAppPoolState -Name $Config.Pool).Value)"
    Get-Item "IIS:\AppPools\$($Config.Pool)" |
        Select-Object name, state, managedRuntimeVersion, managedPipelineMode | Format-List
}
Invoke-Evidencia -Titulo 'Invoke-WebRequest' -Arquivo '03-iis\invoke-webrequest.txt' -Comando {
    foreach ($endereco in @('http://localhost', "http://$($Config.IP)", "http://$($Config.NomeDnsApp).$($Config.Dominio)")) {
        $r = Invoke-WebRequest -Uri $endereco -UseBasicParsing
        "{0,-45} StatusCode {1} {2}" -f $endereco, $r.StatusCode, $r.StatusDescription
    }
    ''
    'Conteúdo de /servidor.json (gerado na publicação):'
    (Invoke-WebRequest -Uri 'http://localhost/servidor.json' -UseBasicParsing).Content
}

Write-Host ''
Write-Host "Abra no navegador de OUTRA máquina: http://$($Config.IP)  (print 03-iis\navegador-site.png)" -ForegroundColor Green
Write-Host 'Prints desta etapa: get-windowsfeature-web.png, get-website.png, get-webapppoolstate.png,' -ForegroundColor DarkGray
Write-Host '                    navegador-site.png, get-acl.png e aba-seguranca.png' -ForegroundColor DarkGray
Write-Host 'Próximo passo: .\05-FileServer-GPO-RDP-DFS.ps1' -ForegroundColor Green
