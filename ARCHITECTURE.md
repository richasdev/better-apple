# Arquitetura

## Decisões

O núcleo Foundation é uma biblioteca Swift Package separada. O executável usa SwiftUI para apresentação e AppKit para janelas, menu e integração com o desktop. O aplicativo Xcode consome a biblioteca local via SPM. Não há pacotes externos.

`AppCoordinator` compõe uma única instância de cada serviço e dos gerenciadores de superfícies. `AppModel` persiste as preferências da Island e presets; Dock e widgets têm documentos Codable próprios. Exportação JSON da suíte reúne esses documentos em um envelope versionado e valida todos os dados antes de aplicá-los. Configurações de login usam o estado real de `SMAppService`.

| Área | Responsabilidade |
|---|---|
| `Sources/BetterApple/App` | Entrada, ciclo de vida, composição e validação interna Debug |
| `Sources/BetterAppleCore` | Parser seguro, countdown e preferências validadas sem UI |
| `Core/Persistence` | Modelo observado e armazenamento local |
| `Features/DynamicIsland` | Painéis por monitor, expansão, registro de módulos e conteúdo |
| `Features/Dock` | Aplicativos fixados, NSWorkspace, drag-and-drop e janela independente |
| `Features/Widgets` | Registro de layouts e janelas editáveis com conteúdos funcionais |
| `Features/Settings` | Navegação nativa e edição das preferências |
| `Services` | EventKit, Apple Events, Mach, IOKit, Core Audio e timer |

## Janelas e módulos

`IslandManager` mantém a associação explícita entre cada painel e seu NSScreen. Largura, altura e posição são limitadas à área disponível. `safeAreaInsets` e `visibleFrame` delimitam o conteúdo abaixo da câmera e dos comandos da barra de menus; Macs sem notch usam uma faixa discreta abaixo da barra. Sem a opção de tela cheia, `fullScreenAuxiliary` não é usado. A opção de vários monitores cria uma Island por tela; o estado expandido/módulo é compartilhado.

`IslandModule` fornece identidade e conteúdo; `IslandModuleRegistry` registra implementações por protocolo. Adicionar comportamento de módulo não exige alterar o gerenciador de janelas, embora adicionar uma identidade persistível exija estender `ModuleID` e os defaults/migração. Módulos são criados quando exibidos.

Widgets usam NSPanel com nível normal, sem substituir WidgetKit ou o desktop do sistema. O modo de edição habilita resize e arraste com um handle AppKit. Cada widget pode existir várias vezes, compartilhando os serviços. A Dock usa uma janela independente no monitor selecionado, com notificações de abertura/fechamento de aplicativos e área fina de revelação para auto-hide. A opção allDisplays agora mantém uma janela Dock por tela, com associação explícita e hover independente.

## Atualizações e concorrência

- Estado de UI isolado em MainActor.
- EventKit: store criado sob demanda, consultas em fila serial, notificações de alteração e próximo prazo relevante; nenhum polling periódico.
- Música: `MusicPlayerAdapter` e comandos tipados; Music/Spotify usam dicionários AppleScript públicos. Uma fila serial executa scripts com timeout. Polling a cada dois segundos somente quando conectado e visível; comandos de sliders são agrupados.
- Sistema: leitura em fila utility a cada três segundos apenas com demanda visível; Core Audio oferece volume somente em dispositivos compatíveis.
- Temporizador: prazo absoluto, tarefa de conclusão única e ticks de apresentação somente enquanto há UI visível.
- CPU/música/calendário consideram oclusão real das janelas. Sono/despertar suspende e reconcilia demanda. Conteúdo de widgets explicitamente ocultos é desmontado; clocks usam TimelineView e não têm timer global próprio.
- Observadores são armazenados e removidos; callbacks capturam gerenciadores fracamente. Widgets agrupam gravações de layout/notas e fazem flush ao encerrar. Settings libera seu hosting view ao fechar.

## Referência Atoll e independência

Análise em 2026-11-08 do branch `dev` do [Atoll](https://github.com/Ebullioscopic/Atoll), usando README, árvore do projeto e declarações/uso de APIs nas áreas de janelas, gerenciadores de música, controller de Apple Music e janela de configurações.

Observações: a separação entre painéis AppKit e conteúdo SwiftUI permite comportamento próximo ao notch; controllers por player separam comandos e atualização de metadados; a janela de configurações tem ciclo próprio; notificações e transições entre estados precisam de tratamento explícito. O repositório também inclui MediaRemoteAdapter e integrações além das APIs escolhidas para este aplicativo.

BetterApple implementa essas responsabilidades com modelos próprios, preferências Codable e registro por protocolo. Não importamos código, imagens, snippets, dependências ou binários do Atoll. MediaRemote, SkyLight, IOReport/SMC privados e manipulações da Dock do sistema não fazem parte deste projeto. Essa independência técnica não substitui revisão jurídica de licença/marcas antes de distribuição.

Referências oficiais: [NSScreen safe areas](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets), [NSPanel](https://developer.apple.com/documentation/appkit/nspanel), [EventKit](https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoevents(completion:)), [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice). Limitações por serviço em [Services/README.md](Sources/BetterApple/Services/README.md).

## Personalização e continuidade de estado (0.2)

IslandSettings armazena IslandAppearance opcional para ler exportações v1 antigas. Campos visuais validam limites; temas e material são resolvidos na camada SwiftUI. Edições usam IslandManager.applySettings sem recriar painéis/hosting views; alterações no conjunto de telas ainda recriam as janelas. Pin é estado transitório. O status compacto opcional participa da agregação de demanda.

CalculatorService é uma instância compartilhada entre Island e widgets; CalculatorHistory contém dados Codable validados e limitados, sem execução de código. History está desligado por padrão e sua desativação apaga entradas. TimerPreferences contém apenas preferências; deadlines não são importados ou exportados.

DockPreferences e WidgetDisplayOptions decodificam campos novos com defaults; widgets antigos usam opções ausentes. A suíte valida todos os documentos antes de tocar nos managers e exporta configurações de grade, timer e opt-in de histórico. Histórico matemático e estado de reprodução não entram nos arquivos exportados.

Scripts/validate_native.py compila o núcleo em diretório temporário e executa harnesses reais dos quatro subsistemas, sem bibliotecas de terceiros e sem solicitar Calendar/Automation. O projeto Xcode continua gerado sem dependências externas.

## Movimento, interação e revisão (0.3)

SurfaceMotionPlan no núcleo limita duração, atraso de revelação e fechamento; Reduce Motion/zero duração eliminam o agendamento de conteúdo. WorkspaceMotion fornece curvas e feedback consistentes. Não existem loops decorativos. A Island mantém a árvore do editor montada durante a revelação, mas só direciona foco ao painel explicitamente escolhido; Settings e perda de key limpam a intenção. Conteúdo e geometria usam tarefas finitas invalidadas por geração. Hosting views de painéis com geometria AppKit usam sizingOptions vazio, evitando mínimos implícitos que impedem recolhimento.

Dock e widgets preservam áreas/identidades durante animações, bloqueiam callbacks antigos e não gravam posições transitórias. SurfaceNoticeManager mostra erros de ação sem ativar a aplicação, permite foco intencional, pausa o deadline durante interação e encerra observadores/tarefas ao descartar.

A validação distingue editor nativo preparado e binding de ativação/key concedidos pelo macOS. O relatório inclui contexto não certificado; não se altera a policy de produção para contornar limitações do ambiente. O modo Debug --profile-motion é uma carga finita isolada, não uma função de produção. A revisão por mudança está em UX_REVIEW.md.

## Âncora da câmera (0.4)

`CameraIslandGeometry` recebe retângulos globais e calcula a geometria sem AppKit. O gap validado entre `auxiliaryTopLeftArea` e `auxiliaryTopRightArea` determina centro e largura físicos. Coordenadas negativas são mantidas. Na versão 0.5, sem medições válidas, usa-se um notch visual de 185 pt em vez de presumir hardware existente. Um cap é criado em todo monitor válido, conforme a referência visual solicitada.

Em Camera, `CameraCapPanel` é preto, sem sombra e sem capacidade de key, acompanhando a largura do corpo mais os ombros côncavos de 12 pt em cada lado. O `IslandPanel` com controles continua no nível floating, abaixo do maior limite entre safe area e barra visível. Os dois alimentam o mesmo estado de hover/deadline; passar do cap ao conteúdo mantém a expansão. Abertura por clique é idempotente mesmo após hover. Ambos respeitam a opção explícita de fullScreenAuxiliary e são desmontados juntos.

O topo do cap permanece imóvel, enquanto posição horizontal/largura e corpo são animados no mesmo NSAnimationContext. O estado compacto Camera não solicita demanda de dados, mesmo com a antiga opção de status compacto ativada. Preferências antigas decodificam Camera por padrão; uma migração única ativa hover sem descartar aparência, e preserva blobs incompatíveis sem gravá-los.

## Seleção de recursos (0.4.1)

IslandSettings.enabled e DockPreferences.enabled são as fontes persistidas existentes. WidgetManager.enabled é a fonte única para Widgets, persistida em widgets.enabled, com true para instalações antigas. É independente de suspended (repouso) e de WidgetConfiguration.visible (escolha individual). activeKinds e refresh exigem enabled; o desligamento também desmonta painéis em fade e encerra edição. show() retoma suspensão, sem alterar enabled.

General e menu bar usam essas mesmas fontes. MenuNeedsUpdate atualiza as marcas, e ações de abrir Island/editar widgets ficam indisponíveis quando o recurso está desligado. O envelope JSON v1 recebe widgetsEnabled opcional; ausência preserva a escolha local, false é aplicado antes do layout para evitar uma exibição transitória. O timer mantém seu prazo mesmo sem superfície visível.

## Clareza das Settings (0.4.2)

IslandSettingsView deriva os controles da placementMode: opções visuais e geométricas de Floating não aparecem no modo Camera, sem remover seus valores persistidos. O picker de cobertura continua usando allDisplays, com descrição explícita do estado compartilhado e fallback. Não mudou a política de janelas.

DockManager.prepareSettings faz uma atualização pontual dos metadados, sem ativar a Dock. Alterações de paths/showRunningApplications enquanto desligada também atualizam a lista por evento. DockSettingsView separa comportamento/posição/aparência e fornece unidades tanto visuais quanto acessíveis.

## Notch contínuo em todas as telas (0.5)

CameraIslandGeometry agora usa o mesmo caminho para hardware e notch visual: faixa superior igual ao maior entre safe area, barra visível e mínimo visual de 32 pt sem câmera. O cap fica encostado a screen.frame.maxY e sobrepõe o corpo em 4 pt. O corpo começa abaixo da faixa reservada. Cap e corpo têm o mesmo centro; a largura do cap inclui 12 pt por ombro. Medidas são limitadas para telas pequenas e coordenadas globais negativas.

NotchCapShape desenha os ombros côncavos e os cantos inferiores recolhidos; IslandOutline deixa o topo do corpo reto e arredonda somente a base. Cap e corpo usam containers NSView com autoresizing, isolando o dimensionamento AppKit do hosting SwiftUI. O NSAnimationContext move as duas janelas com a mesma curva/duração e a reconciliação imediata substitui também alvos pendentes do animator.

A silhueta larga passa deliberadamente pela área central da barra de menus, como solicitado na referência. A opção de participação em fullscreen continua explícita. O desenho não usa câmera, API privada, janela transparente de tela inteira nem polling extra.

## Módulos da Dock e estilos de desktop (0.6)

DockActivitySources injeta as instâncias compartilhadas de MusicService, SystemStatusService e TimerService. DockModule e DockContentMetrics resolvem lista/ordem e a mesma geometria para SwiftUI/AppKit em cada eixo. activeModules exige feature ligada, painel visível/não ocluído e área revelada. O coordenador agrega essa demanda às superfícies existentes; nenhum módulo cria um timer global próprio. Dock note é local, limitada a 100000 caracteres e opcional na suíte JSON.

Widgets guardam estilos opcionais para decodificar documentos antigos como Card. Presets alteram somente o item selecionado, preservando conteúdo e origem. Superfícies Desktop não desenham fundo; Pure black usa sRGB zero com texto branco e opacidade 1. Aparência nativa e ambiente SwiftUI são explícitos para evitar texto escuro herdado sobre preto. Tamanhos compactos reduzem padding/cabeçalhos, mantendo controles de edição.

CameraScreenMetrics recebe menuBarHeight de NSStatusBar; em telas sem recorte, usa a reserva de visibleFrame ou esse fallback público quando a barra está oculta. O estado recolhido tem cap da altura exata da barra e corpo de altura zero; a expansão continua abaixo dela. O MacBook mantém a borda física de4pt. A altura adaptativa é limitada por expandedHeight e pode ser desligada.

## Eventos e preferências do sistema (0.6)

BluetoothConnectionService usa registros IOBluetooth públicos, transporte serial utility fora do MainActor e ledger de identidades local para baseline silencioso/deduplicação/reconexão. stop invalida a geração imediatamente e enfileira remoção dos registros. A inicialização do framework pode esperar internamente por CoreBluetooth; não bloqueia mais a UI. O monitoramento é opt-in e não começa numa instalação padrão. Nenhum identificador é exportado. O coordenador monitora somente com Island/avisos ligados e fora de sleep. Debug --validate desliga acesso ao hardware; testes de UI injetam eventos de apresentação explicitamente. O aviso tem prazo finito, não toma teclado e não inicia dados de módulo quando compacto.

NativeDockService serializa a posse transacional da única preferência autohide por System Events. A baseline própria é registrada/flush uma vez antes de cada tentativa de mutação, sem polling; isso é um journal de melhor esforço, sem garantia de perda de energia. A restauração verifica o valor e conserva baseline em falha. O coordenador ativa a Dock em todas as telas somente após confirmação e restaura se o master for desligado. A opção de sistema fica fora do JSON para não disparar automação por importação.

O encerramento usa duas etapas: cancela a primeira solicitação enquanto a restauração assíncrona termina e repete com aprovação interna. Isso evita prender um Task MainActor no loop aninhado de terminateLater. Sem baseline/ação pendente, encerra imediatamente. Falhas reais oferecem Cancel Quit/ Quit Anyway. Testes usam um adaptador de preferências isolado e não chamam System Events. O parser aceita `typeTrue`/`typeFalse`/`typeBoolean`: NSAppleScript devolve booleanos AppleScript como `'true'`/`'fals'`; exigir só `typeBoolean` fazia toda resposta real falhar antes de escrever (bug corrigido na 0.7.1). O smoke verifica descritores reais locais de NSAppleScript, sem contatar System Events.

Marca original em Resources/Logo; package_icons.py empacota a variante escura em ICNS com ferramentas nativas. O gerador inclui Logo e ICNS no bundle. BrandMark escolhe a variante pela aparência; o ícone do aplicativo é atualizado por KVO, sem polling.

### Player selection and browser playback (0.6.1)
MusicService persists selection in its injected UserDefaults, prefers a running Spotify when no choice exists, and launches installed desktop apps only from explicit Connect. Browser adapters normalize JSON into the same track model. Both AppleScript URL filtering and JavaScript hostname validation restrict execution to exact YouTube hosts. A sentinel skips homepages without a video. Browser dictionaries supply only tab URLs and authorized JavaScript execution; DOM selectors remain a version-sensitive integration boundary. Visible/connected polling remains2s, no hidden browser polling. Commands and snapshots share the existing serialized AppleScript queue.

### Notch presentation and status events (0.7.0)
IslandState.overview separates the horizontal first level from selected detailed tools. Hover/reveal uses overview by default; explicit open/selectModule requests detailed editors. AppKit owns560×140 overview and configured detailed geometry, using the same finite transition and reversal reconciliation. Enabled music/calendar demand aggregates only for visible overview panels. Compact playback uses a deduplicated title/state/artwork projection; camera geometry optionally adds88pt outside the measured camera center without changing the collapsed top band. Cap occlusion participates in service demand.

SystemEventNoticeService observes default audio output with CoreAudio and power with an IOPS run-loop source. It records a silent baseline, deduplicates device identity, and announces low-battery threshold crossing once per discharge. stop invalidates callbacks/removes listeners. Bluetooth and system notices carry source identity so applying one permission toggle cannot dismiss another enabled source. Debug validation disables physical event listeners; layout fixture and event injection are explicit.

Notch hover (0.7.1): `IslandManager` keeps one finite `hoverTask` per pointer entry (`WorkspaceMotion.hoverIntent`, 0.15 s) and a `revealedByHover` flag. A hover-revealed overview uses `min(closeDelay, hoverExitGrace)`; any explicit open/select/showOverview clears the flag. Close tasks treat `RunLoop.main.currentMode == .eventTracking` as active interaction and `NSMenu.didEndTracking` rearms them. `CameraIslandGeometry.seamOverlap`/`collapsedDrawnInset` let `NotchCapShape` leave the collapsed overlap undrawn while windows keep it for hit-testing. No timers outside these finite tasks.
