# Ficha da CitizenTech – AlertaEncosta

## Identificação

| Campo | Resposta |
|---|---|
| Nome | **AlertaEncosta** |
| Cidade e bairro | São Paulo (SP) · Vila Brasilândia, zona norte |
| Desafio da GS | "Chuvas e encostas: alertas de chuva forte e rotas seguras para quem mora em áreas de risco" |
| Cidadão beneficiado | Morador de encosta ou área alagável (primário); idosos e pessoas com deficiência (prioridade); agente da Defesa Civil; líder comunitário (NUPDEC) |
| Problema, em uma frase | Quem mora em área de risco só descobre que a chuva ficou perigosa quando a água ou a terra já chegou, porque os alertas atuais são genéricos, chegam tarde e não dizem para onde ir |

## Equipe

| Integrante | RM |
|---|---|
| Gustavo Neri Santos | RM560239 |
| Matheus Aparecido Rocha Plati | RM559813 |
| Gustavo Pandolfo Meroni | RM560271 |
| Gabriel Machado Belardino | RM550121 |
| Gustavo Franco Tárano | RM559616 |

## Como funciona, do sensor ao morador

1. A estação ESP32 na encosta mede chuva acumulada, umidade do solo e nível da água no córrego e envia as leituras para a API.
2. A API REST grava as leituras no banco e chama o modelo de Machine Learning, que calcula o risco (baixo, médio, alto) de cada setor.
3. Quando o risco passa do limite, a API envia um alerta push para os moradores do setor, com a rota a pé até o ponto de apoio mais próximo.
4. O morador confirma no app que está seguro ou pede ajuda, e pode reportar trincas e água subindo com foto e localização.
5. A Defesa Civil acompanha tudo no painel desktop.
6. **Toda a parte web roda em um Windows Server com IIS, monitorado e com recuperação automática de falhas (este repositório).**

## O tamanho do problema

| Indicador | Valor | Fonte |
|---|---|---|
| Pessoas em áreas de risco no Brasil (872 municípios) | 8,3 milhões | IBGE/Cemaden, Censo 2010 |
| Pessoas em áreas de risco na cidade de São Paulo | 674.329 (6,0% da população) | IBGE, 2018 |
| Áreas de risco geológico alto ou muito alto mapeadas | 14.720 áreas, mais de 4 milhões de pessoas | Serviço Geológico do Brasil, 2024 |
| Ocorrências de desastre registradas pelo Cemaden em 2024 | mais de 1,6 mil (recorde de alertas) | Agência Gov, jan. 2025 |
| Redução de danos com 24 h de aviso antes de um evento extremo | até 30% | OMM, Early Warnings for All |

## Impacto e indicadores

Meta do piloto: **80% dos moradores cadastrados recebem o alerta pelo menos 2 horas antes** de a chuva atingir o limite de risco do seu setor.

- Antecedência média do alerta (minutos entre o aviso e o pico da chuva no setor)
- Percentual de moradores alertados que confirmaram estar em local seguro
- Número de reportes de trincas e alagamentos atendidos pela Defesa Civil
- Pessoas com mobilidade reduzida retiradas antes do evento

## ODS

- **ODS 11** – meta 11.5: reduzir mortes e pessoas afetadas por catástrofes
- **ODS 13** – meta 13.1: resiliência e capacidade de adaptação a riscos climáticos
- **ODS 3** – meta 3.d: alerta precoce e gestão de riscos à saúde

## O que este servidor entrega

| Parte da infraestrutura | Tipo | Como foi implementado |
|---|---|---|
| Servidor AlertaEncosta (Windows Server, VM) | Servidor | VM `SRV-CITIZENTECH`, IP fixo, domínio `citizentech.local` |
| Windows Server 2022 | Software do sistema | instalação Desktop Experience |
| IIS | Software do sistema | sites `CitizenTech` (portal) e `AlertaEncostaAPI` (API), pools `CitizenTechPool` e `AlertaEncostaApiPool` |
| Runtime Java | Software do sistema | JDK 21 em `C:\Java\jdk21`; o HttpPlatformHandler do IIS inicia e vigia o `java.exe` |
| Active Directory e DNS | Software do sistema | floresta `citizentech.local`, OU `CitizenTech`, grupos e usuários, zona direta e reversa |
| Hospedagem web (IIS) | Serviço | portal em `http://alertaencosta.citizentech.local` e API REST (Java/Spring Boot) em `http://192.168.200.230:8080` e `http://api.citizentech.local` |
| Persistência de dados | Serviço | banco H2 da API em `C:\inetpub\alertaencosta-api\data`, gravado só pelo pool da API |
| Autenticação de domínio | Serviço | operadores da Defesa Civil no grupo `GG_CitizenTech_Operadores`, GPO aplicada à OU |
| Monitoramento e recuperação de falhas | Serviço | Monitor de Desempenho com alertas, `Monitor-Recursos.ps1`, `sc.exe failure`, `Recupera-Site.ps1` |
| Rede do domínio | Rede | DNS, compartilhamento SMB, DFS, RDP |

Requisito atendido: **"Servidor monitorado e tolerante a falhas – o sistema não pode cair durante a chuva."** Em um evento de chuva forte o número de acessos ao portal e à API sobe exatamente quando o serviço é mais necessário; por isso os alertas de CPU, memória e disco e a recuperação automática em segundos são o centro desta entrega.

Princípios aplicados no servidor:

| Princípio | Aplicação |
|---|---|
| Privacidade por padrão (LGPD) | dados simulados; nenhuma senha no repositório; auditoria de acesso aos arquivos |
| Acessibilidade e linguagem simples | portal com letras grandes, alto contraste, nível de risco sempre escrito (não só por cor) |
| Funcionar com pouca conectividade | portal leve, sem bibliotecas externas, só arquivos estáticos |
| Segurança | firewall do Windows ativo, liberando só HTTP (80) e RDP (3389) além das regras padrão do controlador de domínio; RDP com NLA; cabeçalhos de segurança no IIS; site padrão removido; acesso de operadores pelo AD |
