# Performance e validação

## Ambiente medido

2026-11-08: MacBook Pro Apple silicon, 16 GiB de memória física, macOS **27.0.1 (26A434)**, Xcode **27.0 (27A266a)**, Swift **6.4**, linguagem Swift 5 e deployment target macOS 14. Não houve execução em macOS 14/15 ou hardware Intel nesta sessão.

## Resultados reais

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
