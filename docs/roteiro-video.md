# Roteiro do vídeo (até 7 minutos)

Gravar a tela da VM (e do seu computador nos trechos de navegador/RDP) com OBS Studio ou a Barra de Jogo do Windows (Win+G). Deixe tudo pronto antes de gravar: PowerShell como Administrador aberto em `C:\citizentech-infra\scripts`, `perfmon`, `taskschd.msc`, `services.msc` e `eventvwr.msc` já abertos, e o navegador do seu computador em `http://192.168.200.230`.

Sugestão: cada integrante narra um bloco (o roteiro tem 8 blocos para 5 pessoas).

| Tempo | Bloco | O que mostrar / digitar | O que falar |
|---|---|---|---|
| 0:00 – 0:40 | **Servidor** | `hostname` · `ipconfig /all` · `Get-ADDomain \| Select Name, DNSRoot` | "Este é o SRV-CITIZENTECH, o servidor do AlertaEncosta: IP fixo 192.168.200.230, DNS apontando para ele mesmo e controlador do domínio citizentech.local." |
| 0:40 – 1:30 | **AD e DNS** | `Get-ADUser -Filter * -SearchBase "OU=CitizenTech,DC=citizentech,DC=local" \| Select Name, SamAccountName, Enabled` · `Get-ADGroupMember GG_CitizenTech_Admins` · `nslookup alertaencosta.citizentech.local 192.168.200.230` · `Get-DnsServerZone` | "Criamos a OU CitizenTech com o grupo dos administradores da aplicação e o dos operadores da Defesa Civil. O DNS resolve o servidor e o nome da aplicação, e tem zona reversa." |
| 1:30 – 2:40 | **IIS** | `Get-WindowsFeature Web-* \| ? Installed` · `Get-Website` · `Get-WebAppPoolState CitizenTechPool` · Gerenciador do IIS (site e pool) · `Get-Acl C:\inetpub\citizentech` · aba Segurança | "Caminho A: o portal é estático, então o pool roda sem código gerenciado. A pasta só dá leitura para o IIS e alteração para quem publica." |
| 2:40 – 3:30 | **GPO e compartilhamento** | `Get-GPO -All` · relatório `GPO_Report.html` · `Get-SmbShare` · no seu computador `\\192.168.200.230\CitizenTech` · `\\citizentech.local\CitizenTechDFS` · tela do usuário comum sem Painel de Controle · conexão RDP com `hostname` | "A GPO bloqueia o Painel de Controle dos operadores. Os documentos ficam no compartilhamento, também publicado no DFS. A administração remota é por RDP com NLA." |
| 3:30 – 4:30 | **Monitoramento** | `perfmon` com `CitizenTech_Monitor` e `CitizenTech_Alertas` ativos · rodar `C:\Scripts\Gerar-Carga.ps1` e mostrar o gráfico subindo e a linha amarela "CPU alta" · evento 9001 e evento 2031 no Visualizador · tarefa no Agendador | "Monitoramos CPU, memória e disco de dois jeitos: o alerta nativo do Monitor de Desempenho e o script agendado a cada 5 minutos. Os dois geram eventos no Visualizador." |
| 4:30 – 5:40 | **Teste de falha** | `C:\Scripts\Teste-Falha.ps1 -Cenario Crash` (volta em ~5 s) · navegador fora do ar e depois de volta · `sc.exe qfailure W3SVC` · `Get-Content C:\Scripts\logs\recuperacao.log` | "Agora derrubamos o IIS de propósito. O site sai do ar e o Windows reinicia o serviço sozinho em segundos. Se alguém parar o serviço ou o pool, a tarefa de recuperação religa em até 1 minuto, e tudo fica no recuperacao.log." |
| 5:40 – 6:40 | **Logs e auditoria** | `auditpol /get /category:*` (trecho) · Visualizador de Eventos > Segurança (4624 logon, 4663 acesso a arquivo) · `C:\inetpub\logs\LogFiles` com o log aberto | "Auditamos logons e acesso aos arquivos do site e do compartilhamento. Os acessos ao portal ficam no log do IIS." |
| 6:40 – 7:00 | **Encerramento** | navegador com o AlertaEncosta, rodapé "Servido por SRV-CITIZENTECH" · `.\09-Validacao-Final.ps1` rolando | "A infraestrutura do AlertaEncosta está no ar, monitorada e se recupera sozinha. Obrigado!" |

Dicas:

- Ensaie uma vez antes. O teste `-Cenario Crash` leva menos de 30 s; o cenário padrão (Stop-Service) pode levar até 1 min, então use o Crash no vídeo e mostre o `recuperacao.log` dos testes feitos antes.
- Aumente a fonte do PowerShell (Propriedades > Fonte 18 ou mais) para ficar legível no vídeo.
- Corte esperas na edição; o limite é 7 minutos.
- Suba no YouTube como "Não listado" e coloque o link no README (campo ✏️).
