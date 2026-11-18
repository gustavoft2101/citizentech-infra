#Requires -RunAsAdministrator
<#
.SYNOPSIS
    ETAPA 1 (itens 3.1 e 3.2 do roteiro) - IP fixo, DNS, fuso horário e nome do servidor.

.DESCRIPTION
    1. Registra a versão do Windows (evidência do item 3.1).
    2. Mostra a configuração de rede atual, para conferir IP e gateway da sua rede.
    3. Aplica IP fixo, máscara, gateway e DNS apontando para o próprio servidor
       (ele será o DNS do domínio citizentech.local).
    4. Ajusta o fuso horário para Brasília (os logs ficam com a hora certa).
    5. Renomeia o computador para SRV-CITIZENTECH e reinicia.

    IMPORTANTE: rode no CONSOLE da VM, não por RDP. Trocar o IP derruba conexões remotas.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\01-Rede-Hostname.ps1
#>
. "$PSScriptRoot\00-Config.ps1"
. "$PSScriptRoot\lib\Comum.ps1"

Write-Etapa 'ETAPA 1 - Rede e identidade do servidor'

# ---------------------------------------------------------------- 3.1
Write-Passo '3.1 Versão do Windows Server instalada'
Invoke-Evidencia -Titulo 'Versão do sistema operacional' -Arquivo '01-rede\versao-windows.txt' -Comando {
    Get-CimInstance Win32_OperatingSystem |
        Format-List Caption, Version, BuildNumber, OSArchitecture, InstallDate
}
Write-Host '   Print 01-rede\winver.png: abra o winver (Win+R > winver) e tire o print da tela.' -ForegroundColor DarkGray

# ---------------------------------------------------------------- 3.2
Write-Passo '3.2 Identificar a interface de rede conectada'
Invoke-Evidencia -Titulo 'Adaptadores de rede' -Arquivo '01-rede\get-netadapter.txt' -Comando {
    Get-NetAdapter | Format-Table Name, InterfaceDescription, Status, ifIndex, MacAddress -AutoSize
}

$adaptador = Get-NetAdapter | Where-Object Status -eq 'Up' | Sort-Object ifIndex | Select-Object -First 1
if (-not $adaptador) {
    throw 'Nenhum adaptador de rede conectado. Verifique se a VM está com a placa em modo Bridge.'
}
$indice = $adaptador.ifIndex
Write-Ok "Interface escolhida: '$($adaptador.Name)' (ifIndex $indice)"

Write-Host ''
Write-Host 'Configuração atual (antes do IP fixo). Use estes dados para conferir o 00-Config.ps1:' -ForegroundColor Yellow
Get-NetIPConfiguration -InterfaceIndex $indice |
    Format-List InterfaceAlias, IPv4Address, IPv4DefaultGateway, DNSServer

Write-Host "Valores que serão aplicados (vindos do 00-Config.ps1):" -ForegroundColor Yellow
Write-Host "   IP fixo ....: $($Config.IP)/$($Config.Prefixo)"
Write-Host "   Gateway ....: $($Config.Gateway)"
Write-Host "   DNS ........: $($Config.IP) (o próprio servidor)"
Write-Host "   Hostname ...: $($Config.NomeServidor)"
$resposta = Read-Host 'Confirma? (S/N)'
if ($resposta -notmatch '^[sS]') {
    Write-Aviso 'Cancelado. Ajuste o arquivo 00-Config.ps1 e rode novamente.'
    return
}

Write-Passo 'Aplicando IP fixo'
$ipsAtuais = @(Get-NetIPAddress -InterfaceIndex $indice -AddressFamily IPv4 -ErrorAction SilentlyContinue)
$dhcp      = (Get-NetIPInterface -InterfaceIndex $indice -AddressFamily IPv4).Dhcp

if (($ipsAtuais.IPAddress -contains $Config.IP) -and ($dhcp -eq 'Disabled')) {
    Write-Ok "A interface já está com o IP fixo $($Config.IP). Nada a fazer."
}
else {
    # Desliga o DHCP e remove o IP e o gateway antigos, senão o New-NetIPAddress falha.
    Set-NetIPInterface -InterfaceIndex $indice -AddressFamily IPv4 -Dhcp Disabled
    $ipsAtuais | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    Get-NetRoute -InterfaceIndex $indice -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

    # Comando do roteiro (3.2): IP, máscara (PrefixLength) e gateway
    New-NetIPAddress -InterfaceIndex $indice -IPAddress $Config.IP -PrefixLength $Config.Prefixo `
        -DefaultGateway $Config.Gateway |
        Format-Table IPAddress, PrefixLength, InterfaceIndex, AddressFamily -AutoSize
}

# DNS do servidor = ele mesmo (depois da Etapa 2 ele responde pelo domínio citizentech.local)
Set-DnsClientServerAddress -InterfaceIndex $indice -ServerAddresses $Config.IP
Write-Ok "DNS da interface apontando para $($Config.IP)"

Invoke-Evidencia -Titulo 'Configuração IP aplicada' -Arquivo '01-rede\ip-fixo-aplicado.txt' -Comando {
    Get-NetIPConfiguration -InterfaceIndex $indice |
        Format-List InterfaceAlias, IPv4Address, IPv4DefaultGateway, DNSServer
    Get-NetIPInterface -InterfaceIndex $indice -AddressFamily IPv4 |
        Format-Table InterfaceAlias, AddressFamily, Dhcp -AutoSize
}

Write-Passo 'Fuso horário de Brasília'
Set-TimeZone -Id $Config.FusoHorario
Write-Ok "Fuso horário: $((Get-TimeZone).DisplayName)"

Write-Passo '3.2 Renomear o servidor'
if ($env:COMPUTERNAME -eq $Config.NomeServidor) {
    Write-Ok "O servidor já se chama $($Config.NomeServidor)."
    Write-Host 'Próximo passo: .\02-AD-DNS.ps1' -ForegroundColor Green
}
else {
    Rename-Computer -NewName $Config.NomeServidor -Force
    Write-Ok "Nome alterado de $env:COMPUTERNAME para $($Config.NomeServidor) (vale após reiniciar)."
    Write-Host ''
    Write-Host 'Depois do reinício, faça logon e rode: .\02-AD-DNS.ps1' -ForegroundColor Green
    Read-Host 'Pressione ENTER para reiniciar agora'
    Restart-Computer -Force
}
