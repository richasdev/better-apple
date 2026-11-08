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

`IslandManager` mantém a associação explícita entre cada painel e seu NSScreen. Largura, altura e posição são limitadas à área disponível. `safeAreaInsets` e `visibleFrame` evitam a câmera e os comandos da barra de menus; Macs sem notch usam o mesmo painel abaixo da barra. Sem a opção de tela cheia, `fullScreenAuxiliary` não é usado. A opção de vários monitores cria uma Island por tela; o estado expandido/módulo é compartilhado.

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
