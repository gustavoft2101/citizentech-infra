#Requires -RunAsAdministrator
<#
.SYNOPSIS
    ETAPA 1 (itens 3.4 e 3.5 do roteiro) - Valida domínio e DNS, cria OU, grupos e usuários.

.DESCRIPTION
    Rode depois do reinício da Etapa 02, logado como CITIZENTECH\Administrator.
      3.4  Get-ADDomain, nslookup, Get-DnsServerZone (+ ipconfig /all com o hostname novo)
      3.4+ Encaminhadores DNS (internet), zona reversa (nslookup sem "UnKnown")
           e o nome alertaencosta.citizentech.local para a aplicação
      3.5  OU CitizenTech, grupos GG_CitizenTech_Admins e GG_CitizenTech_Operadores,
           usuários de teste fictícios
#>
. "$PSScriptRoot\00-Config.ps1"
. "$PSScriptRoot\lib\Comum.ps1"

Write-Etapa 'ETAPA 1 - Validação do domínio, DNS, usuários e grupos'

Import-Module ActiveDirectory
Import-Module DnsServer

# Logo após o boot o AD pode levar 1-2 minutos para responder.
Write-Passo 'Aguardando o Active Directory responder'
$tentativas = 0
while ($true) {
    try { Get-ADDomain -ErrorAction Stop | Out-Null; break }
    catch {
        $tentativas++
        if ($tentativas -ge 24) { throw 'O AD não respondeu em 2 minutos. Confira se a Etapa 02 terminou e reinicie.' }
        Start-Sleep -Seconds 5
    }
}
Write-Ok 'Active Directory respondendo.'

# ---------------------------------------------------------------- DNS: encaminhadores, zona reversa e nome da aplicação
Write-Passo 'DNS: encaminhadores para a internet'
Set-DnsServerForwarder -IPAddress $Config.DnsExternos
Invoke-Evidencia -Titulo 'Encaminhadores DNS' -Arquivo '02-ad-dns\dns-encaminhadores.txt' -Comando {
    Get-DnsServerForwarder | Format-List IPAddress, UseRootHint, Timeout
}

Write-Passo 'DNS: zona reversa (faz o nslookup mostrar o nome do servidor em vez de UnKnown)'
$octetos = $Config.IP.Split('.')
if ($Config.Prefixo -ge 24) {
    $idRede = "$($octetos[0]).$($octetos[1]).$($octetos[2]).0/24"
    $zonaReversa = "$($octetos[2]).$($octetos[1]).$($octetos[0]).in-addr.arpa"
    $nomePtr = $octetos[3]
} else {
    $idRede = "$($octetos[0]).$($octetos[1]).0.0/16"
    $zonaReversa = "$($octetos[1]).$($octetos[0]).in-addr.arpa"
    $nomePtr = "$($octetos[3]).$($octetos[2])"
}
try {
    if (-not (Get-DnsServerZone -Name $zonaReversa -ErrorAction SilentlyContinue)) {
        Add-DnsServerPrimaryZone -NetworkId $idRede -ReplicationScope Forest
        Write-Ok "Zona reversa $zonaReversa criada."
    }
    if (-not (Get-DnsServerResourceRecord -ZoneName $zonaReversa -Name $nomePtr -RRType Ptr -ErrorAction SilentlyContinue)) {
        Add-DnsServerResourceRecordPtr -ZoneName $zonaReversa -Name $nomePtr -PtrDomainName "$FQDNServidor."
        Write-Ok "Registro PTR $($Config.IP) -> $FQDNServidor criado."
    }
} catch {
    Write-Aviso "Zona reversa não criada: $($_.Exception.Message) (não é obrigatório)."
}

Write-Passo "DNS: nome da aplicação $($Config.NomeDnsApp).$($Config.Dominio)"
if (-not (Get-DnsServerResourceRecord -ZoneName $Config.Dominio -Name $Config.NomeDnsApp -RRType A -ErrorAction SilentlyContinue)) {
    Add-DnsServerResourceRecordA -ZoneName $Config.Dominio -Name $Config.NomeDnsApp -IPv4Address $Config.IP
}
Write-Ok "$($Config.NomeDnsApp).$($Config.Dominio) -> $($Config.IP)"

# ---------------------------------------------------------------- 3.4 validações
Write-Passo '3.4 Validar rede, domínio e DNS'
Invoke-Evidencia -Titulo 'ipconfig /all' -Arquivo '01-rede\ipconfig-all.txt' -Comando { ipconfig /all }

Invoke-Evidencia -Titulo 'Get-ADDomain' -Arquivo '02-ad-dns\get-addomain.txt' -Comando {
    Get-ADDomain | Select-Object Name, DNSRoot, NetBIOSName, DomainMode, PDCEmulator | Format-List
}

Invoke-Evidencia -Titulo 'nslookup do servidor e da aplicação' -Arquivo '02-ad-dns\nslookup.txt' -Comando {
    nslookup $FQDNServidor
    nslookup "$($Config.NomeDnsApp).$($Config.Dominio)"
}

Invoke-Evidencia -Titulo 'Get-DnsServerZone' -Arquivo '02-ad-dns\get-dnsserverzone.txt' -Comando {
    Get-DnsServerZone | Format-Table ZoneName, ZoneType, IsDsIntegrated, IsReverseLookupZone -AutoSize
}

# ---------------------------------------------------------------- 3.5 OU, grupos e usuários
Write-Passo '3.5 Unidade organizacional, grupos e usuários'

if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$($Config.OU)'" -SearchBase $DN -SearchScope OneLevel)) {
    New-ADOrganizationalUnit -Name $Config.OU -Path $DN -Description 'Recursos da solucao AlertaEncosta'
    Write-Ok "OU $CaminhoOU criada."
} else { Write-Ok "OU $CaminhoOU já existe." }

foreach ($grupo in @($Config.GrupoAdmins, $Config.GrupoOperadores)) {
    if (-not (Get-ADGroup -Filter "Name -eq '$grupo'")) {
        New-ADGroup -Name $grupo -GroupScope Global -GroupCategory Security -Path $CaminhoOU
        Write-Ok "Grupo $grupo criado."
    } else { Write-Ok "Grupo $grupo já existe." }
}

$precisaSenha = $UsuariosTeste | Where-Object { -not (Get-ADUser -Filter "SamAccountName -eq '$($_.Login)'") }
if ($precisaSenha) {
    Write-Host 'Senha inicial dos usuários de teste (mínimo 8 caracteres, com maiúscula, minúscula, número e símbolo).' -ForegroundColor Yellow
    Write-Host 'Não registre essa senha no GitHub.' -ForegroundColor Yellow
    $senhaUsuarios = Read-Host -AsSecureString 'Senha'
}

foreach ($u in $UsuariosTeste) {
    if (-not (Get-ADUser -Filter "SamAccountName -eq '$($u.Login)'")) {
        New-ADUser -Name $u.Nome -SamAccountName $u.Login -UserPrincipalName "$($u.Login)@$($Config.Dominio)" `
            -DisplayName $u.Nome -Description $u.Descricao -Path $CaminhoOU `
            -AccountPassword $senhaUsuarios -Enabled $true
        Write-Ok "Usuário $($u.Login) criado."
    } else { Write-Ok "Usuário $($u.Login) já existe." }
    Add-ADGroupMember -Identity $u.Grupo -Members $u.Login -ErrorAction SilentlyContinue
}

Invoke-Evidencia -Titulo 'Usuários da OU CitizenTech' -Arquivo '02-ad-dns\usuarios.txt' -Comando {
    Get-ADUser -Filter * -SearchBase $CaminhoOU -Properties Description |
        Select-Object Name, SamAccountName, Enabled, Description | Format-Table -AutoSize
}

Invoke-Evidencia -Titulo 'Membros dos grupos' -Arquivo '02-ad-dns\grupos.txt' -Comando {
    foreach ($g in @($Config.GrupoAdmins, $Config.GrupoOperadores)) {
        "Grupo: $g"
        Get-ADGroupMember -Identity $g | Select-Object Name, SamAccountName, objectClass | Format-Table -AutoSize
    }
}

Write-Host ''
Write-Host 'Prints desta etapa: 01-rede\ipconfig-all.png, 02-ad-dns\get-addomain.png, nslookup.png,' -ForegroundColor DarkGray
Write-Host '                    get-dnsserverzone.png e usuarios-grupos.png' -ForegroundColor DarkGray
Write-Host 'Próximo passo: .\04-IIS-Aplicacao.ps1' -ForegroundColor Green
