<#
.SYNOPSIS
    Valores centrais da infraestrutura CitizenTech (solução AlertaEncosta).

.DESCRIPTION
    Este é o ÚNICO arquivo que precisa ser editado antes de rodar as etapas.
    Todos os outros scripts carregam este arquivo com:
        . "$PSScriptRoot\00-Config.ps1"

    O que normalmente muda de uma equipe para outra: IP, Prefixo e Gateway
    (precisam bater com a sua rede real, porque a VM usa adaptador em modo Bridge).
#>

$Config = [ordered]@{
    # ---------- Identidade do servidor (seção 2 do roteiro) ----------
    NomeServidor    = 'SRV-CITIZENTECH'
    Dominio         = 'citizentech.local'
    NetBIOS         = 'CITIZENTECH'

    # ---------- Rede: AJUSTE PARA A SUA REDE ----------
    IP              = '192.168.1.10'
    Prefixo         = 24                       # 24 = máscara 255.255.255.0
    Gateway         = '192.168.1.1'
    DnsExternos     = @('8.8.8.8', '1.1.1.1')  # encaminhadores: o DNS do AD usa estes para nomes da internet
    FusoHorario     = 'E. South America Standard Time'   # horário de Brasília (logs com hora certa)

    # ---------- Active Directory ----------
    OU              = 'CitizenTech'
    GrupoAdmins     = 'GG_CitizenTech_Admins'       # equipe que administra a aplicação
    GrupoOperadores = 'GG_CitizenTech_Operadores'   # operadores da Defesa Civil (usuários comuns)

    # ---------- IIS / aplicação AlertaEncosta ----------
    Site            = 'CitizenTech'
    Pool            = 'CitizenTechPool'
    PastaSite       = 'C:\inetpub\citizentech'
    NomeDnsApp      = 'alertaencosta'               # cria o nome alertaencosta.citizentech.local

    # ---------- File Server e DFS ----------
    Compartilhamento = 'CitizenTech'
    PastaShare       = 'C:\Shares\CitizenTech'
    RaizDfs          = 'CitizenTechDFS'
    PastaRaizDfs     = 'C:\DFSRoots\CitizenTechDFS'

    # ---------- GPO ----------
    Gpo             = 'GPO_CitizenTech_Usuarios'

    # ---------- Monitoramento (limiares de alerta) ----------
    LimiteCPU       = 80     # % de uso de CPU acima do qual há alerta
    LimiteRAM_MB    = 500    # MB de memória livre abaixo do qual há alerta
    LimiteDisco_GB  = 15     # GB livres no C: abaixo do qual há alerta (script)
    LimiteDiscoPct  = 15     # % livre no C: abaixo do qual há alerta (Monitor de Desempenho)
    IntervaloColetaSeg       = 15   # coleta do Data Collector Set
    IntervaloMonitorMin      = 5    # tarefa agendada do Monitor-Recursos.ps1
    IntervaloRecuperacaoMin  = 1    # tarefa agendada do Recupera-Site.ps1

    # ---------- Pastas de operação ----------
    PastaScripts    = 'C:\Scripts'
    PastaLogs       = 'C:\Scripts\logs'
    PastaPerfLogs   = 'C:\PerfLogs\CitizenTech'
    PastaTemp       = 'C:\Temp'
}

# Usuários de teste (fictícios). As senhas NÃO ficam no repositório:
# o script 03 pede a senha na hora da criação (Read-Host -AsSecureString).
$UsuariosTeste = @(
    @{ Nome = 'Ana Souza';     Login = 'ana.souza';     Grupo = $Config.GrupoAdmins;     Descricao = 'Administradora da aplicacao AlertaEncosta' }
    @{ Nome = 'Carlos Lima';   Login = 'carlos.lima';   Grupo = $Config.GrupoOperadores; Descricao = 'Operador da Defesa Civil (usuario comum)' }
    @{ Nome = 'Beatriz Alves'; Login = 'beatriz.alves'; Grupo = $Config.GrupoOperadores; Descricao = 'Operadora da Defesa Civil (usuario comum)' }
)

# ---------- Caminhos calculados automaticamente (não precisa mexer) ----------
$RepoRaiz        = Split-Path $PSScriptRoot -Parent                     # pasta citizentech-infra
$PastaEvidencias = Join-Path $RepoRaiz 'evidencias'                     # onde as saídas são salvas
$PastaApp        = Join-Path $RepoRaiz 'app\alertaencosta-web'          # arquivos do site
$DN              = 'DC=' + ($Config.Dominio -replace '\.', ',DC=')      # DC=citizentech,DC=local
$CaminhoOU       = "OU=$($Config.OU),$DN"                               # OU=CitizenTech,DC=citizentech,DC=local
$FQDNServidor    = "$($Config.NomeServidor).$($Config.Dominio)".ToLower()   # srv-citizentech.citizentech.local
