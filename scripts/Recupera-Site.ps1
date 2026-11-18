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
    try {
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 10
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
