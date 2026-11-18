# Registro de uso de IA (prompts.md)

Combinado da GS: *"IA como copiloto – permitida para aprender e revisar. Registrem os prompts em um arquivo prompts.md e saibam explicar cada linha."*

| # | Data | Ferramenta | Prompt | O que a IA gerou | Como a equipe validou |
|---|---|---|---|---|---|
| 1 | 17/11/2026 | Claude (Anthropic) | "Preciso que faça para mim isso de operating system", com três anexos: o roteiro da atividade de Operating Systems, o briefing da GS 2026.2 CitizenTech e o documento de arquitetura do AlertaEncosta (TOGAF/ArchiMate) | Estrutura deste repositório; scripts PowerShell comentados das etapas 1 a 6 (baseados nos comandos do roteiro, com ajustes para funcionar em Windows em português); `Monitor-Recursos.ps1`, `Teste-Falha.ps1`, `Recupera-Site.ps1`, `Gerar-Carga.ps1`; portal estático do AlertaEncosta com dados simulados; README, roteiro de configuração, ficha e roteiro do vídeo | ✏️ preencher: execução de cada script na VM, conferência das saídas em `evidencias/`, prints, teste de falha |

✏️ Acrescentem aqui os próximos prompts que usarem (dúvidas, correções de erro na VM etc.).

## O que nenhuma IA fez por nós

- Executar os scripts na VM, tirar os prints e gravar o vídeo.
- Os arquivos em `evidencias/` são saídas reais da nossa VM.

## Pontos para saber explicar na apresentação

- Por que o pool é "sem código gerenciado" (site estático, evita o erro 500.19).
- Diferença entre permissão de compartilhamento (SMB) e permissão NTFS (vale a mais restritiva).
- Por que o `sc.exe failure` não age num `Stop-Service` e quem recupera nesse caso (tarefa agendada).
- Por que usamos SIDs e GUIDs (Windows em português x inglês).
- O que são os eventos 9001, 9101, 2031, 4624, 4663 e 7031/7036.
