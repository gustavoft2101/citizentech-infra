<#
.SYNOPSIS
    Recupera-Site.ps1 (item 7.3 do roteiro) - Verifica e religa serviço, pool e site do IIS.

.DESCRIPTION
    Instalado em C:\Scripts\Recupera-Site.ps1 pelo 08-Tolerancia-Falhas.ps1 e executado
    a cada 1 minuto pela tarefa agendada CitizenTech_Recuperacao (como SYSTEM).

    Ordem da verificação (de baixo para cima, porque cada camada depende da anterior):
      1. Serviços WAS e W3SVC   -> sem eles não existe pool nem site
      2. Pool CitizenTechPool   -> sem ele o site responde 503
      3. Site CitizenTech
      4. Teste HTTP real        -> se ainda falhar, executa iisreset
      5. API Java (Caminho B)   -> pool, site e GET /api/v1/setores; se falhar, recicla o pool
                                   (o HttpPlatformHandler sobe o java.exe de novo)

    Só escreve no recuperacao.log quando alguma ação foi necessária (o log fica limpo
    e cada linha é um incidente). Cada recuperação também vira o evento 9101 no log
    Application (origem CitizenTechRecuperacao).

    Diferença em relação ao roteiro: o roteiro verificava pool -> site -> serviço.
    Com o W3SVC parado, o Start-Website falha; por isso o serviço vem primeiro.
#>
param(
    [string]$Site      = 'CitizenTech',
    [string]$Pool      = 'CitizenTechPool',
    [string]$Url       = 'http://localhost',
    [string]$SiteApi   = 'AlertaEncostaAPI',
    [string]$PoolApi   = 'AlertaEncostaApiPool',
    [string]$UrlApi    = 'http://localhost:8080/api/v1/setores',
    [string]$PastaLogs = 'C:\Scripts\logs'
)

$log = Join-Path $PastaLogs 'recuperacao.log'
New-Item -Path $PastaLogs -ItemType Directory -Force | Out-Null
$acoes = 0

function Registrar {
    param([string]$Texto, [string]$Tipo = 'Warning')
    $linha = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $Texto"
    Add-Content -Path $log -Value $linha
    Write-Host $linha -ForegroundColor Cyan
    try {
        Write-EventLog -LogName Application -Source 'CitizenTechRecuperacao' -EventId 9101 -EntryType $Tipo `
            -Message "AlertaEncosta / $env:COMPUTERNAME - $Texto" -ErrorAction Stop
    } catch { }   # a origem do evento é criada pelo 08-Tolerancia-Falhas.ps1; sem ela, só o arquivo de log
}

function Testar-Http {
    param([string]$Endereco = $Url, [int]$Tempo = 10)
    try {
        $r = Invoke-WebRequest -Uri $Endereco -UseBasicParsing -TimeoutSec $Tempo
        return [int]$r.StatusCode
    } catch {
        if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }
        return 0
    }
}

# ---------------------------------------------------------------- 1. serviços
foreach ($nomeServico in @('WAS', 'W3SVC')) {
    $servico = Get-Service -Name $nomeServico
    if ($servico.Status -ne 'Running') {
        Registrar "Servico $nomeServico estava $($servico.Status). Iniciando."
        try {
            Start-Service -Name $nomeServico -ErrorAction Stop
            $acoes++
        } catch {
            Registrar "Falha ao iniciar ${nomeServico}: $($_.Exception.Message)" 'Error'
        }
    }
}
if ($acoes -gt 0) { Start-Sleep -Seconds 3 }

Import-Module WebAdministration

# ---------------------------------------------------------------- 2. pool
try {
    $estadoPool = (Get-WebAppPoolState -Name $Pool).Value
    if ($estadoPool -ne 'Started') {
        Registrar "Pool $Pool estava $estadoPool. Reiniciando."
        if ($estadoPool -eq 'Stopping') { Start-Sleep -Seconds 3 }
        Start-WebAppPool -Name $Pool -ErrorAction Stop
        $acoes++
    }
} catch {
    Registrar "Erro ao verificar/iniciar o pool ${Pool}: $($_.Exception.Message)" 'Error'
}

# ---------------------------------------------------------------- 3. site
try {
    $estadoSite = (Get-Website -Name $Site).State
    if ($estadoSite -ne 'Started') {
        Registrar "Site $Site estava $estadoSite. Iniciando."
        Start-Website -Name $Site -ErrorAction Stop
        $acoes++
    }
} catch {
    Registrar "Erro ao verificar/iniciar o site ${Site}: $($_.Exception.Message)" 'Error'
}

# ---------------------------------------------------------------- 4. teste HTTP
$codigo = Testar-Http
if ($codigo -eq 200) {
    if ($acoes -gt 0) { Registrar "Recuperado: site respondendo com HTTP $codigo." 'Information' }
    else { Write-Host "$(Get-Date -Format 'HH:mm:ss') Tudo normal: W3SVC, WAS, pool e site ativos; HTTP 200." -ForegroundColor Green }
}
else {
    Registrar "Site nao responde (HTTP $codigo). Executando iisreset."
    iisreset /restart | Out-Null
    Start-Sleep -Seconds 10
    $codigo = Testar-Http
    if ($codigo -eq 200) { Registrar "Recuperado apos iisreset. HTTP $codigo." 'Information' }
    else { Registrar "Falha persistente (HTTP $codigo). Verificar logs do IIS e o Visualizador de Eventos." 'Error' }
}

# ---------------------------------------------------------------- 5. API Java (Caminho B, script 04b)
if (Test-Path "IIS:\Sites\$SiteApi") {
    $acoesApi = 0
    try {
        if ((Get-WebAppPoolState -Name $PoolApi).Value -ne 'Started') {
            Registrar "Pool $PoolApi (API) parado. Iniciando."
            Start-WebAppPool -Name $PoolApi -ErrorAction Stop; $acoesApi++
        }
        if ((Get-Website -Name $SiteApi).State -ne 'Started') {
            Registrar "Site $SiteApi (API) parado. Iniciando."
            Start-Website -Name $SiteApi -ErrorAction Stop; $acoesApi++
        }
    } catch { Registrar "Erro ao verificar a API: $($_.Exception.Message)" 'Error' }

    # o Spring Boot leva alguns segundos para subir: espera até 2 min antes de concluir que falhou
    $limite = (Get-Date).AddMinutes(2)
    do {
        $codigoApi = Testar-Http -Endereco $UrlApi -Tempo 30
        if ($codigoApi -ne 200) { Start-Sleep -Seconds 10 }
    } until ($codigoApi -eq 200 -or (Get-Date) -gt $limite)

    if ($codigoApi -ne 200) {
        Registrar "API nao responde (HTTP $codigoApi). Reciclando o pool $PoolApi."
        Restart-WebAppPool -Name $PoolApi -ErrorAction SilentlyContinue
        $acoesApi++
    } elseif ($acoesApi -gt 0) {
        Registrar "Recuperado: API respondendo com HTTP $codigoApi." 'Information'
    } else {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') API normal: GET /api/v1/setores HTTP 200." -ForegroundColor Green
    }
}
