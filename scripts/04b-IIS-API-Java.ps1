#Requires -RunAsAdministrator
<#
.SYNOPSIS
    ETAPA 2 (item 4.3 do roteiro) - Caminho B: publica a API AlertaEncosta (Java 21 / Spring Boot) no IIS.

.DESCRIPTION
    A API REST do AlertaEncosta (repositório alertaencosta-api) é o backend da CitizenTech:
    recebe as leituras das estações, calcula o risco de cada setor e emite os alertas.
    Este script a publica no IIS da VM, ao lado do portal do Caminho A (script 04):

      1. Instala o HttpPlatformHandler (módulo do IIS que inicia e vigia o processo java.exe
         e repassa para ele as requisições) e o Application Initialization
      2. Instala o runtime: JDK 21 e Maven em C:\Java
      3. Baixa o código da API do GitHub e gera o .jar (mvn package)
      4. Publica em C:\inetpub\alertaencosta-api (app\, data\, logs\ e web.config)
      5. Cria o pool AlertaEncostaApiPool (sem código gerenciado, sempre ativo)
         e o site AlertaEncostaAPI nas portas 8080 e 80 (nome api.citizentech.local)
      6. Permissões NTFS, firewall (8080) e registro DNS api.citizentech.local
      7. Testa a API (GET /api/v1/setores, /v3/api-docs e Swagger UI)

    Banco de dados: H2 em arquivo (perfil "dev" da API), em C:\inetpub\alertaencosta-api\data.
    As tabelas e os dados do piloto da Vila Brasilândia são criados pelo Flyway na primeira subida.

    Como funciona a recuperação: se o java.exe cair, o HttpPlatformHandler o inicia de novo
    na próxima requisição; se o pool ou o IIS caírem, o Recupera-Site.ps1 e o sc.exe failure
    (etapa 7) cuidam disso, igual ao portal.
#>
param(
    [string]$Ramo          = 'main',     # ramo do repositório da API que será publicado
    [string]$InstaladorJdk = '',         # opcional: instalador do JDK 21 já baixado (senão baixa o Temurin)
    [string]$JarPronto     = ''          # opcional: .jar já gerado com "mvn package" (pula o download do código e o build)
)
. "$PSScriptRoot\00-Config.ps1"
. "$PSScriptRoot\lib\Comum.ps1"

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'     # a barra de progresso deixa os downloads muito lentos no PowerShell 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Etapa 'ETAPA 2 - Caminho B: API AlertaEncosta (Java 21 / Spring Boot) no IIS'

$temp     = $Config.PastaTemp
$jdk      = Join-Path $Config.PastaJava 'jdk21'
$maven    = Join-Path $Config.PastaJava "apache-maven-$($Config.VersaoMaven)"
$javaExe  = Join-Path $jdk 'bin\java.exe'
$pastaJar = Join-Path $Config.PastaApi 'app'
$pastaDb  = Join-Path $Config.PastaApi 'data'
$pastaLog = Join-Path $Config.PastaApi 'logs'
$jar      = Join-Path $pastaJar 'alertaencosta-api.jar'
New-Item -Path $temp, $Config.PastaJava, $pastaJar, $pastaDb, $pastaLog -ItemType Directory -Force | Out-Null

function Baixar {
    param([string]$Url, [string]$Destino)
    Write-Host "   baixando $Url" -ForegroundColor DarkGray
    curl.exe -fsSL --retry 3 -o $Destino $Url
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $Destino)) { throw "Falha ao baixar $Url" }
}

function Extrair {
    # tar.exe (nativo do Windows Server 2022) extrai .zip bem mais rápido que o Expand-Archive
    param([string]$Zip, [string]$Destino)
    New-Item -Path $Destino -ItemType Directory -Force | Out-Null
    tar.exe -xf $Zip -C $Destino
    if ($LASTEXITCODE -ne 0) { throw "Falha ao extrair $Zip" }
}

# ---------------------------------------------------------------- 1. módulos do IIS
Write-Passo '4.3 Módulos do IIS: HttpPlatformHandler e Application Initialization'
Install-WindowsFeature -Name Web-AppInit | Out-Null
Import-Module WebAdministration
if (-not (Get-WebGlobalModule -Name 'httpPlatformHandler' -ErrorAction SilentlyContinue)) {
    $msi = Join-Path $temp 'httpPlatformHandler_amd64.msi'
    Baixar -Url 'https://go.microsoft.com/fwlink/?LinkId=690721' -Destino $msi
    $p = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart" -Wait -PassThru
    if ($p.ExitCode -notin 0, 3010) { throw "Instalação do HttpPlatformHandler terminou com código $($p.ExitCode)" }
}
Write-Ok 'HttpPlatformHandler v1.2 e Application Initialization instalados.'

# ---------------------------------------------------------------- 2. runtime
Write-Passo "4.3 Runtime: JDK 21 e Maven $($Config.VersaoMaven) em $($Config.PastaJava)"
if (-not (Test-Path $javaExe)) {
    if ($InstaladorJdk -and (Test-Path $InstaladorJdk)) {
        # instalador do JDK 21 já baixado (ex.: pasta compartilhada do computador host): instalação silenciosa
        $local = Join-Path $temp (Split-Path $InstaladorJdk -Leaf)
        Copy-Item $InstaladorJdk $local -Force
        $p = Start-Process $local -ArgumentList "/s INSTALLDIR=$jdk" -Wait -PassThru
        if ($p.ExitCode -ne 0) { throw "Instalador do JDK terminou com código $($p.ExitCode)" }
    } else {
        $zip = Join-Path $temp 'jdk21.zip'
        Baixar -Url 'https://api.adoptium.net/v3/binary/latest/21/ga/windows/x64/jdk/hotspot/normal/eclipse?project=jdk' -Destino $zip
        $tmpJdk = Join-Path $temp 'jdk21-extraido'
        Extrair -Zip $zip -Destino $tmpJdk
        Move-Item -Path (Get-ChildItem $tmpJdk -Directory | Select-Object -First 1).FullName -Destination $jdk
    }
}
if (-not $JarPronto) {
    if (-not (Test-Path (Join-Path $maven 'bin\mvn.cmd'))) {
        $zip = Join-Path $temp 'maven.zip'
        Baixar -Url "https://archive.apache.org/dist/maven/maven-3/$($Config.VersaoMaven)/binaries/apache-maven-$($Config.VersaoMaven)-bin.zip" -Destino $zip
        Extrair -Zip $zip -Destino $Config.PastaJava
    }
}
$env:JAVA_HOME = $jdk
$env:Path      = "$jdk\bin;$maven\bin;$env:Path"
[Environment]::SetEnvironmentVariable('JAVA_HOME', $jdk, 'Machine')
Invoke-Evidencia -Titulo 'Runtime instalado (java e mvn)' -Arquivo '03-iis\api-runtime.txt' -Comando {
    cmd /c "`"$javaExe`" -version 2>&1"
    if (Test-Path "$maven\bin\mvn.cmd") { cmd /c "`"$maven\bin\mvn.cmd`" -v 2>&1" }
    Get-WebGlobalModule -Name httpPlatformHandler | Format-List Name, Image
}

# ---------------------------------------------------------------- 3. código e build
$commit = 'desconhecido'
if ($JarPronto) {
    Write-Passo "4.3 Usar o .jar já gerado com mvn package: $JarPronto"
    if (-not (Test-Path $JarPronto)) { throw "Não encontrei $JarPronto" }
    $jarGerado = Get-Item $JarPronto
    try {
        $info   = Invoke-RestMethod -Uri ("https://api.github.com/repos/" + ($Config.RepoApi -replace '^https://github.com/', '') + "/commits/$Ramo") -UseBasicParsing -TimeoutSec 20
        $commit = $info.sha
    } catch { }
} else {
    Write-Passo "4.3 Baixar a API ($($Config.RepoApi), ramo $Ramo) e gerar o .jar"
    $nomeRepo = Split-Path $Config.RepoApi -Leaf
    try {
        $info   = Invoke-RestMethod -Uri ("https://api.github.com/repos/" + ($Config.RepoApi -replace '^https://github.com/', '') + "/commits/$Ramo") -UseBasicParsing
        $commit = $info.sha
    } catch { Write-Aviso 'Não consegui consultar o commit pela API do GitHub; seguindo assim mesmo.' }
    $zip   = Join-Path $temp "$nomeRepo.zip"
    $fonte = Join-Path $temp "$nomeRepo-fonte"
    if (Test-Path $fonte) { Remove-Item $fonte -Recurse -Force }
    Baixar -Url "$($Config.RepoApi)/archive/refs/heads/$Ramo.zip" -Destino $zip
    Extrair -Zip $zip -Destino $fonte
    $projeto = (Get-ChildItem $fonte -Directory | Select-Object -First 1).FullName

    Push-Location $projeto
    try {
        # -DskipTests: os 16 testes da API já rodam no repositório dela; aqui só empacotamos
        cmd /c "`"$maven\bin\mvn.cmd`" -B -q -DskipTests package 2>&1"
        if ($LASTEXITCODE -ne 0) { throw 'mvn package falhou (veja a saída acima).' }
    } finally { Pop-Location }
    $jarGerado = Get-ChildItem (Join-Path $projeto 'target') -Filter '*.jar' |
        Where-Object Name -notlike '*original*' | Select-Object -First 1
    if (-not $jarGerado) { throw 'O build não gerou o .jar em target\.' }

}

# ---------------------------------------------------------------- 4. publicação
Write-Passo "4.3 Publicar em $($Config.PastaApi)"
if (Test-Path "IIS:\AppPools\$($Config.PoolApi)") { Stop-WebAppPool -Name $Config.PoolApi -ErrorAction SilentlyContinue; Start-Sleep -Seconds 3 }
Get-Process java -ErrorAction SilentlyContinue | Where-Object Path -eq $javaExe | Stop-Process -Force
Copy-Item -Path $jarGerado.FullName -Destination $jar -Force

$dbUrl = 'jdbc:h2:file:' + ((Join-Path $pastaDb 'alertaencosta') -replace '\\', '/')
$argumentos = @(
    '-Xms128m', '-Xmx512m',
    '-jar', "&quot;$jar&quot;",
    '--server.port=%HTTP_PLATFORM_PORT%',          # porta que o HttpPlatformHandler escolhe para o java.exe
    "--spring.datasource.url=$dbUrl",              # banco H2 em arquivo dentro da pasta da API
    '--spring.h2.console.enabled=false',           # console web do H2 desligado no servidor
    '--spring.jpa.show-sql=false'
) -join ' '

$webConfig = @"
<?xml version="1.0" encoding="UTF-8"?>
<!--
  API AlertaEncosta (Caminho B - Java 21 / Spring Boot) gerado pelo script 04b-IIS-API-Java.ps1.
  O HttpPlatformHandler inicia o java.exe, repassa as requisições e o reinicia se ele cair.
  Commit publicado: $commit
-->
<configuration>
  <system.webServer>
    <handlers>
      <add name="httpPlatformHandler" path="*" verb="*" modules="httpPlatformHandler" resourceType="Unspecified" />
    </handlers>
    <httpPlatform processPath="$javaExe"
                  arguments="$argumentos"
                  startupTimeLimit="180"
                  startupRetryCount="3"
                  requestTimeout="00:02:00"
                  stdoutLogEnabled="true"
                  stdoutLogFile="$pastaLog\java-stdout">
      <environmentVariables>
        <environmentVariable name="JAVA_HOME" value="$jdk" />
      </environmentVariables>
    </httpPlatform>
    <httpProtocol>
      <customHeaders>
        <remove name="X-Powered-By" />
        <add name="X-Content-Type-Options" value="nosniff" />
      </customHeaders>
    </httpProtocol>
  </system.webServer>
</configuration>
"@
[System.IO.File]::WriteAllText((Join-Path $Config.PastaApi 'web.config'), $webConfig, (New-Object System.Text.UTF8Encoding($false)))
Write-Ok "Jar publicado: $jar ($([math]::Round((Get-Item $jar).Length / 1MB, 1)) MB, commit $($commit.Substring(0, [math]::Min(7, $commit.Length))))"

# ---------------------------------------------------------------- 5. pool e site
Write-Passo '4.3 Pool de aplicativos e site da API'
if (-not (Test-Path "IIS:\AppPools\$($Config.PoolApi)")) { New-WebAppPool -Name $Config.PoolApi | Out-Null }
$caminhoPool = "IIS:\AppPools\$($Config.PoolApi)"
Set-ItemProperty $caminhoPool -Name managedRuntimeVersion -Value ''               # sem código gerenciado (.NET não é usado)
Set-ItemProperty $caminhoPool -Name startMode -Value 'AlwaysRunning'              # sobe junto com o IIS
Set-ItemProperty $caminhoPool -Name processModel.idleTimeout -Value '00:00:00'    # não desliga a API por inatividade
Set-ItemProperty $caminhoPool -Name recycling.periodicRestart.time -Value '00:00:00'

if (-not (Test-Path "IIS:\Sites\$($Config.SiteApi)")) {
    New-Website -Name $Config.SiteApi -Port $Config.PortaApi -PhysicalPath $Config.PastaApi -ApplicationPool $Config.PoolApi | Out-Null
} else {
    Set-ItemProperty "IIS:\Sites\$($Config.SiteApi)" -Name physicalPath    -Value $Config.PastaApi
    Set-ItemProperty "IIS:\Sites\$($Config.SiteApi)" -Name applicationPool -Value $Config.PoolApi
}
$cabecalho = "$($Config.NomeDnsApi).$($Config.Dominio)"
if (-not (Get-WebBinding -Name $Config.SiteApi -Port 80 -HostHeader $cabecalho)) {
    New-WebBinding -Name $Config.SiteApi -Protocol http -Port 80 -HostHeader $cabecalho
}
Set-ItemProperty "IIS:\Sites\$($Config.SiteApi)" -Name applicationDefaults.preloadEnabled -Value $true

# libera as seções handlers e httpPlatform só para este site (no applicationHost.config elas vêm travadas)
foreach ($secao in 'system.webServer/handlers', 'system.webServer/httpPlatform') {
    Set-WebConfiguration -PSPath 'MACHINE/WEBROOT/APPHOST' -Location $Config.SiteApi -Filter $secao `
        -Metadata overrideMode -Value Allow
}

# ---------------------------------------------------------------- 6. NTFS, firewall e DNS
Write-Passo '4.4 Permissões NTFS, firewall e DNS da API'
$contaPool = "IIS AppPool\$($Config.PoolApi)"
$pasta = Get-Item $Config.PastaApi
$acl = $pasta.GetAccessControl('Access')
$acl.SetAccessRule((New-RegraNtfs -Conta 'S-1-5-32-568' -Direitos 'ReadAndExecute'))                      # IIS_IUSRS
$acl.SetAccessRule((New-RegraNtfs -Conta "$($Config.NetBIOS)\$($Config.GrupoAdmins)" -Direitos 'Modify'))
$pasta.SetAccessControl($acl)
foreach ($p in $pastaDb, $pastaLog) {                                    # só o pool da API grava banco e logs
    $item = Get-Item $p
    $acl = $item.GetAccessControl('Access')
    $acl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($contaPool, 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
    $item.SetAccessControl($acl)
}
Write-Ok "${contaPool}: alteração em data\ e logs\ | IIS_IUSRS: leitura | GG_CitizenTech_Admins: alteração"

if (-not (Get-NetFirewallRule -DisplayName "CitizenTech - API ($($Config.PortaApi))" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "CitizenTech - API ($($Config.PortaApi))" -Direction Inbound -Protocol TCP `
        -LocalPort $Config.PortaApi -Action Allow -Profile Any | Out-Null
}
if (-not (Get-DnsServerResourceRecord -ZoneName $Config.Dominio -Name $Config.NomeDnsApi -RRType A -ErrorAction SilentlyContinue)) {
    Add-DnsServerResourceRecordA -ZoneName $Config.Dominio -Name $Config.NomeDnsApi -IPv4Address $Config.IP
}
Write-Ok "Porta $($Config.PortaApi) liberada; DNS $cabecalho -> $($Config.IP)"

Start-WebAppPool -Name $Config.PoolApi -ErrorAction SilentlyContinue
Start-Website    -Name $Config.SiteApi -ErrorAction SilentlyContinue

# ---------------------------------------------------------------- 7. validação
Write-Passo 'Validação da API (a primeira subida do Spring Boot leva até ~2 minutos)'
$urlBase = "http://localhost:$($Config.PortaApi)"
$limite  = (Get-Date).AddMinutes(4)
do {
    try { $ok = (Invoke-WebRequest "$urlBase/api/v1/setores" -UseBasicParsing -TimeoutSec 30).StatusCode -eq 200 } catch { $ok = $false }
    if (-not $ok) { Write-Host '   aguardando a API subir...' -ForegroundColor DarkGray; Start-Sleep -Seconds 10 }
} until ($ok -or (Get-Date) -gt $limite)
if (-not $ok) { Write-Aviso "A API não respondeu. Veja $pastaLog e o Visualizador de Eventos (Aplicativo)." }

Invoke-Evidencia -Titulo 'Get-Website e pools (portal + API)' -Arquivo '03-iis\api-get-website.txt' -Comando {
    Get-Website | Format-Table Name, ID, State, PhysicalPath, ApplicationPool -AutoSize
    Get-WebBinding -Name $Config.SiteApi | Format-Table protocol, bindingInformation -AutoSize
    Get-ChildItem IIS:\AppPools | Where-Object Name -in $Config.Pool, $Config.PoolApi |
        Format-Table Name, State, managedRuntimeVersion, startMode -AutoSize
}
Invoke-Evidencia -Titulo 'Processo java.exe iniciado pelo IIS' -Arquivo '03-iis\api-processo.txt' -Comando {
    Get-CimInstance Win32_Process -Filter "Name='java.exe'" | ForEach-Object {
        $pai = Get-CimInstance Win32_Process -Filter "ProcessId=$($_.ParentProcessId)"
        [pscustomobject]@{ PID = $_.ProcessId; Processo = $_.Name; 'Iniciado por' = "$($pai.Name) (PID $($pai.ProcessId))"; 'Memória (MB)' = [math]::Round($_.WorkingSetSize / 1MB) }
    } | Format-Table -AutoSize
}
Invoke-Evidencia -Titulo 'Teste HTTP da API' -Arquivo '03-iis\api-invoke-webrequest.txt' -Comando {
    foreach ($endereco in @("$urlBase/api/v1/setores", "http://$($Config.IP):$($Config.PortaApi)/v3/api-docs",
                            "$urlBase/swagger-ui/index.html", "http://$cabecalho/api/v1/pontos-apoio")) {
        try { $r = Invoke-WebRequest -Uri $endereco -UseBasicParsing -TimeoutSec 30; $c = "$($r.StatusCode) $($r.StatusDescription)" }
        catch { $c = "ERRO $($_.Exception.Message)" }
        "{0,-55} {1}" -f $endereco, $c
    }
    ''
    'GET /api/v1/setores (dados do piloto da Vila Brasilândia):'
    (Invoke-RestMethod "$urlBase/api/v1/setores" -UseBasicParsing).conteudo |
        Format-Table id, codigo, nome, tipoRisco, nivelRiscoAtual -AutoSize
}

Write-Host ''
Write-Host "Swagger da API no navegador de OUTRA máquina: http://$($Config.IP):$($Config.PortaApi)/swagger-ui.html" -ForegroundColor Green
Write-Host "Próximo passo: rodar de novo o .\08-Tolerancia-Falhas.ps1 para a recuperação vigiar também a API" -ForegroundColor Green
