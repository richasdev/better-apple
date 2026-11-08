# Performance e validação

## Ambiente medido

2026-11-08: MacBook Pro Apple silicon, 16 GiB de memória física, macOS **27.0.1 (26A434)**, Xcode **27.0 (27A266a)**, Swift **6.4**, linguagem Swift 5 e deployment target macOS 14. Não houve execução em macOS 14/15 ou hardware Intel nesta sessão.

## Resultados da fundação 0.1.0

| Verificação | Resultado |
|---|---|
| Swift Package build/test | Passou; 7 XCTest, 0 falhas |
| Xcode Debug arm64 | BUILD SUCCEEDED |
| Xcode Release universal | BUILD SUCCEEDED; `lipo` confirmou arm64 e x86_64 |
| Serviços nativos | Harness compilado/executado; timer, sistema e registro de atalhos verificados |
| Rotina interna Debug | 11 verificações passaram com configurações isoladas |
| Time Profiler | Captura de 10 s concluída; exportação `time-profile` com 12 amostras |

A amostra inicial Release, antes da inclusão do serviço opcional de atalhos, teve RSS médio de **78,94 MiB**, máximo **79,33 MiB** e `%CPU` médio de **0,02%**, máximo **0,1%**, em 20 leituras de `ps` espaçadas por um segundo. Island compacta, sem música conectada, sem Dock/widgets e Settings fechada. A medição final, incluindo o serviço de atalhos desativado, teve RSS médio de **84,87 MiB**, máximo **85,16 MiB**, CPU média **0,005%** e máxima **0,1%** em 20 amostras. Os dados estão no relatório JSON em `Validation/`.

RSS não equivale ao footprint físico do Activity Monitor. `%CPU` de `ps` é uma estimativa reportada pelo sistema e não representa a média de todas as possíveis cargas. O teste curto apenas confirma comportamento inicial nesse cenário; não comprova a meta de RAM em uso comum, estabilidade por horas ou 60 FPS. A captura do Time Profiler é uma evidência de execução do profiling; não equivale a uma auditoria de vazamentos. As poucas amostras incluem atendimento a eventos do AppKit/run loop.

O build Debug com Settings aberta chegou a aproximadamente **104 MiB de RSS** em uma leitura isolada. Abrir Settings, carregar capas, renderizar vários widgets e os caches do SwiftUI podem elevar o uso de memória. A janela de Settings libera seu hosting view ao fechar. Comparações de performance devem usar Release, registrar quais superfícies estão ativas e manter as mesmas condições.

## Controles implementados

- Módulos inativos não iniciam seus serviços.
- Visibilidade configurada e oclusão real das janelas determinam demanda para calendário, música, sistema e ticks do timer.
- Sono/despertar suspende os serviços visuais e reconcilia deadlines.
- Música: intervalo de 2 s apenas conectada e visível; máximo de um snapshot em trânsito; comandos de sliders agrupados em 120 ms.
- Sistema: intervalo de 3 s com tolerância, leituras em fila utility, histórico de amostragem resetado ao parar.
- Calendário: notificação de alteração, atualização no despertar e próximo término de evento; sem timer repetitivo.
- Timer: conclusão única; UI com ticks de 1 s apenas quando necessária.
- Widget oculto desmonta NSHostingView. Relógios usam TimelineView; não há atualização global do desktop.
- Notas e layout agrupam persistência por 300 ms, com flush no encerramento.
- Ícones da Dock têm cache e estado de execução usa notificações NSWorkspace.
- Reduce Motion desativa a animação de resize e magnificação conforme suporte do componente.

## Reproduzir e ampliar

1. Compile Release e execute o bundle, feche Settings e aguarde os caches iniciais estabilizarem.
2. Registre PID, `ps -p PID -o %cpu,rss`, configuração e duração. Compare repouso, Island aberta, música, status, Dock e vários widgets.
3. Use Xcode → Product → Profile ou `xcrun xctrace record --template 'Time Profiler' --attach PID --time-limit 10s --output /tmp/BetterApple.trace`.
4. Rode Allocations e Leaks por períodos maiores, abra/feche painéis repetidamente e acompanhe crescimento persistente.
5. Use Animation Hitches/SwiftUI para transições e valide Reduce Motion; FPS ainda não foi medido.
6. Meça lançamento com App Launch e inclua macOS 14/15, monitores externos, Spaces e sono prolongado.

Capturas Instruments ficam locais em `/tmp` e não são versionadas. Podem conter metadados do ambiente do processo; o repositório conserva apenas resultados resumidos. Nenhuma afirmação de ausência de vazamentos é feita sem esses perfis adicionais.

## Personalização 0.2.0

A nova rodada executou **12 testes XCTest sem falhas**, **18 verificações internas** e os quatro harnesses nativos (serviços, produtividade, Dock, widgets). As verificações cobrem migração de preferências antigas, presets/Custom, manutenção da janela durante personalização, histórico opt-in, preferências do timer, duplicação/estilo de widgets, fusos horários, configuração por monitor e roundtrip JSON. A automação externa continua retornando permission_denied; os fluxos de mouse/teclado não foram declarados validados por esses testes internos.

Em Release 0.2.0, com Island compacta, status compacto desligado, Settings fechada, sem Dock/widgets ou player conectado, foram feitas 20 leituras de ps a cada segundo, após 2 segundos iniciais: RSS médio **76,41 MiB**, máximo **84,03 MiB**; CPU média reportada **0,01%**, máxima **0,2%**. São amostras curtas, não uma comprovação de redução em relação a 0.1 nem da meta em uso comum. Os dados estão em Validation/2026-11-08-personalization.json.

Status compacto ao vivo é opt-in: o serviço do módulo selecionado segue a mesma frequência de uma Island expandida, apenas enquanto a janela está visível. Clocks sem segundos usam agendamento alinhado a um minuto. Novos temas, presets e preferências não criam novos timers globais. Reduce Transparency usa fundos opacos nas três superfícies.

## Movimento e UX 0.3.0

Validação: **15 testes do núcleo**, **32 verificações internas** e **seis harnesses nativos** passaram. As verificações incluem reversão rápida, geometria final, movimentação sem salvar frames transitórios, recolhimento da Dock a 10 px, preparação do editor durante a expansão e input no binding. Ativação/key em primeiro plano não foram concedidos pelo contexto do macOS e aparecem separadamente como não certificados.

Uma captura **Animation Hitches** de **15,90 s** concluiu durante a carga Debug de 20 ciclos finitos (Reduce Motion desligado). Os exports de hitches, frame lifetimes e superfícies não trouxeram linhas utilizáveis. **Zero linhas não prova zero hitches**: não há resultado de FPS ou ausência de hitches. O trace bruto fica local em `/tmp`; somente resumo e escopo foram versionados.

No Release 0.3.0 em repouso, Island compacta, Settings fechada e sem Dock/widgets/player habilitados: 20 leituras de ps, uma por segundo após 2 s iniciais, deram RSS médio **85,38 MiB**, máximo **85,61 MiB**, CPU média reportada **0,005%**, máxima **0,1%**. Trata-se de amostra curta e RSS, sem garantia de footprint físico, RAM em uso comum ou ausência de vazamentos.

O modo `--validate --profile-motion` existe apenas em Debug, usa preferências isoladas e encerra após o trabalho finito. Não adiciona animações em repouso no aplicativo Release. Resultados completos em `Validation/2026-11-08-motion.json` e julgamento por alteração em `UX_REVIEW.md`.

## Alteração 0.4 — câmera

Nenhuma nova medição de CPU, RAM ou FPS foi realizada nesta etapa. O estado compacto Camera não mantém demanda dos módulos, mesmo se a preferência antiga de status compacto estiver ligada. O cap usa hover/clique por eventos e não adiciona polling, display link ou animação contínua. Testes de geometria/estado não demonstram cumprimento das metas de performance. Evidência funcional em [Validation/2026-11-09-camera.json](Validation/2026-11-09-camera.json).

## Seleção de recursos e conteúdo de widgets — 0.4.1

Desligar Widgets desmonta também painéis em fade e elimina activeKinds; desligar Island/Dock fecha suas janelas. O prazo de um timer iniciado é preservado. Não há polling extra para os switches. A validação detectou e corrigiu a montagem ausente do conteúdo SwiftUI em novos widgets; medições históricas com painéis vazios não demonstram o consumo de widgets funcionais. Profiling com conteúdo real permanece pendente, sem novas afirmações de RAM/CPU/FPS. Relatório: [Validation/2026-11-09-features.json](Validation/2026-11-09-features.json).

## Silhueta no topo — 0.5

Cap e corpo existem também no monitor sem câmera; há uma janela adicional em comparação ao fallback anterior de faixa única. A mudança usa eventos de hover e animações finitas, sem display link/polling novo. O estado compacto continua sem demanda dos módulos. Não foram refeitas medições de CPU/RAM/FPS; a duplicação por tela precisa entrar no próximo profiling.
