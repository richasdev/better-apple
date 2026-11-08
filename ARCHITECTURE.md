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

`CameraIslandGeometry` recebe retângulos globais e calcula a geometria sem AppKit. O gap validado entre `auxiliaryTopLeftArea` e `auxiliaryTopRightArea` determina centro e largura físicos. Coordenadas negativas são mantidas. Sem medições válidas, nenhum painel de nível statusBar é criado sobre menus.

Em Camera, `CameraCapPanel` é estreito, preto, sem sombra e sem capacidade de key. O `IslandPanel` com controles continua no nível floating, abaixo do maior limite entre safe area e barra visível. Os dois alimentam o mesmo estado de hover/deadline; passar do cap ao conteúdo mantém a expansão. Abertura por clique é idempotente mesmo após hover. Ambos respeitam a opção explícita de fullScreenAuxiliary e são desmontados juntos.

O cap permanece imóvel durante o resize do corpo. O estado compacto Camera não solicita demanda de dados, mesmo com a antiga opção de status compacto ativada. Preferências antigas decodificam Camera por padrão; uma migração única ativa hover sem descartar aparência, e preserva blobs incompatíveis sem gravá-los.
