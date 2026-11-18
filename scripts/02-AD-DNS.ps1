#Requires -RunAsAdministrator
<#
.SYNOPSIS
    ETAPA 1 (item 3.3 do roteiro) - Instala o Active Directory e cria o domínio citizentech.local.

.DESCRIPTION
    1. Confere se a Etapa 01 foi feita (nome e IP fixo).
    2. Instala a função AD DS com as ferramentas de gerenciamento.
    3. Promove o servidor a controlador de domínio de uma nova floresta,
       instalando junto o servidor DNS (zona citizentech.local).
    4. Reinicia. Depois do reinício, entre como CITIZENTECH\Administrator.

    A senha do Administrador local passa a ser a senha do Administrador do domínio.
    A senha do modo de restauração (DSRM) é pedida aqui: anote em local seguro,
    NÃO coloque no repositório.
#>
. "$PSScriptRoot\00-Config.ps1"
. "$PSScriptRoot\lib\Comum.ps1"

Write-Etapa 'ETAPA 1 - Active Directory e DNS'

# ---------------------------------------------------------------- pré-checagens
if ($env:COMPUTERNAME -ne $Config.NomeServidor) {
    throw "O servidor ainda se chama $env:COMPUTERNAME. Rode o 01-Rede-Hostname.ps1 e reinicie antes."
}
$ipConfigurado = Get-NetIPAddress -AddressFamily IPv4 -IPAddress $Config.IP -ErrorAction SilentlyContinue
if (-not $ipConfigurado) {
    throw "O IP $($Config.IP) não está configurado. Rode o 01-Rede-Hostname.ps1 antes."
}

# DomainRole 4 ou 5 = já é controlador de domínio
$papel = (Get-CimInstance Win32_ComputerSystem).DomainRole
if ($papel -ge 4) {
    Write-Ok "Este servidor já é controlador de domínio ($((Get-CimInstance Win32_ComputerSystem).Domain))."
    Write-Host 'Próximo passo: .\03-AD-Usuarios.ps1' -ForegroundColor Green
    return
}

# ---------------------------------------------------------------- 3.3
Write-Passo '3.3 Instalar a função AD DS'
Invoke-Evidencia -Titulo 'Install-WindowsFeature AD-Domain-Services' -Arquivo '02-ad-dns\install-adds.txt' -Comando {
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools |
        Format-Table Success, RestartNeeded, ExitCode, FeatureResult -AutoSize -Wrap
}

Write-Passo "3.3 Promover a controlador de domínio da floresta $($Config.Dominio)"
Write-Host 'Digite a senha do modo de restauração (DSRM). Guarde essa senha.' -ForegroundColor Yellow
$senhaDsrm = Read-Host -AsSecureString 'Senha DSRM'

Import-Module ADDSDeployment
# -NoRebootOnCompletion: deixa salvar a evidência antes de reiniciar.
$resultado = Install-ADDSForest -DomainName $Config.Dominio -DomainNetbiosName $Config.NetBIOS `
    -InstallDns -SafeModeAdministratorPassword $senhaDsrm `
    -NoRebootOnCompletion -Force

Invoke-Evidencia -Titulo 'Install-ADDSForest (resultado)' -Arquivo '02-ad-dns\install-addsforest.txt' -Comando {
    $resultado | Format-List Status, Message, RebootRequired
}

if ("$($resultado.Status)" -ne 'Success') {
    Write-Aviso 'A promoção não terminou com sucesso. Leia a mensagem acima, corrija e rode de novo.'
    return
}

Write-Host ''
Write-Host "Depois do reinício, faça logon como $($Config.NetBIOS)\Administrator e rode: .\03-AD-Usuarios.ps1" -ForegroundColor Green
Read-Host 'Pressione ENTER para reiniciar agora'
Restart-Computer -Force
