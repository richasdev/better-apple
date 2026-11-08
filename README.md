# BetterApple

Aplicativo nativo de personalização e produtividade para macOS 14+, escrito do zero em Swift, SwiftUI e AppKit. Versão de desenvolvimento **0.5.0**. Sem dependências externas de runtime, backend ou telemetria.

Repositório privado: [richasdev/better-apple](https://github.com/richasdev/better-apple).

## Compilar e executar

Requisitos: macOS 14+, Xcode 15+ com Command Line Tools selecionado. A versão efetivamente validada está em [PERFORMANCE.md](PERFORMANCE.md).

1. Abra `BetterApple.xcodeproj` no Xcode.
2. Selecione o scheme **BetterApple**, destino **My Mac** e execute com ⌘R.
3. O ícone circular aparece na barra de menus. Abra **Settings…** para configurar as superfícies. Fechar Settings mantém o aplicativo ativo; use **Quit BetterApple** no menu para encerrar.

Pelo terminal, neste ambiente:

```sh
/opt/homebrew/bin/rtk proxy swift test
/opt/homebrew/bin/rtk proxy xcodebuild -project BetterApple.xcodeproj -scheme BetterApple -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build CODE_SIGN_IDENTITY=- build
/opt/homebrew/bin/rtk proxy open build/Build/Products/Debug/BetterApple.app
```

`swift build` também compila o executável e o núcleo, mas execute o bundle `.app` do Xcode para que as descrições de permissão e a identidade do aplicativo estejam disponíveis. A assinatura ad hoc atende desenvolvimento local; distribuição exige uma equipe Apple Developer, assinatura e notarização próprias.

O projeto Xcode está versionado. Após adicionar/remover arquivos Swift do aplicativo, atualize suas referências com `python3 Scripts/generate_project.py`. O gerador não requer XcodeGen ou bibliotecas adicionais.

## Funcionalidades implementadas

- Menu bar app com configurações nativas e persistência local.
- Dynamic Island: NSPanel real, expansão por hover/clique, fechamento com atraso, medidas/posição, modo mínimo, ordem e seleção de módulos, opção para vários monitores e tela cheia. O posicionamento respeita a área da barra de menus e o safe area da câmera.
- Calculadora com parser aritmético limitado e cópia do resultado; temporizador com pausa, retomada e alerta sonoro; calendário EventKit com próximos eventos.
- Música: adaptadores extensíveis de Apple Music e Spotify via Apple Events, metadados, capa quando disponível, navegação, progresso/seek e volume do player.
- Status: CPU, estimativa de RAM, bateria, tráfego de rede e volume do dispositivo quando suportado.
- Dock independente: aplicativos reais, indicadores de execução, reordenação interna, seleção de monitor, posição, tamanho/espaçamento/opacidade, blur, magnificação e auto-hide.
- Dez tipos de widgets: relógio digital/analógico, calendário, próximos eventos, calculadora, música, bateria, CPU/RAM, notas e timer. Layout persistido, edição com arraste/redimensionamento e controles de visibilidade, tema, cor, opacidade, borda e sombra.
- Atalho global opcional e configurável para a Island via Carbon, sem Accessibility; conflitos de registro são tratados.
- Presets Default, Minimal, Glass, Compact e Custom; importação/exportação JSON de Island, Dock e widgets.

“Implementado” descreve código integrado; veja [ROADMAP.md](ROADMAP.md) para as verificações executadas e os fluxos ainda não validados interativamente. O timer é compartilhado entre Island e widgets e não sobrevive ao encerramento do aplicativo.

## Silhueta Notchy (0.5)

A parte superior e o corpo animam juntos com a mesma curva e duração, mantendo o topo imóvel. Uma sobreposição preta de 4 pt evita costuras; a parte de cima não toma foco e usa o mesmo hover do conteúdo. Em todas as telas o desenho é preso à borda superior, incluindo monitores sem câmera. O modo Floating continua disponível com os ajustes anteriores. Nenhuma imagem ou código do aplicativo de referência foi incorporado.

## Clareza de configuração (0.4.2)

Dynamic Island tem uma seção Displays explícita: câmera/monitor automático ou todas as telas, explicando o notch desenhado em monitores comuns e o estado expandido compartilhado. No modo Camera, controles exclusivos de Floating ficam ocultos, com seus valores preservados. A Dock separa posição, comportamento, aparência e movimento, mostra unidades e pode ter seus apps configurados enquanto desligada, sem abrir janelas.

## Escolha seus recursos (0.4.1)

Abra **Settings → General → Choose your features** para ligar ou desligar **Dynamic Island**, **Personalized Dock** e **Widgets** independentemente. Cada linha tem acesso à configuração do recurso. Os mesmos três controles estão no menu da barra superior, com marca de seleção para os recursos ligados.

Desligar fecha as janelas e libera a demanda de dados da superfície. Configurações, aplicativos fixados, notas, posições e a visibilidade individual de cada widget permanecem salvos. Ao religar Widgets, apenas os que estavam selecionados voltam. O estado desligado persiste após reiniciar o aplicativo e despertar o Mac. Um temporizador já iniciado continua até seu prazo; desligar uma superfície não cancela o timer compartilhado.

O JSON exporta as três escolhas. Importações antigas sem `widgetsEnabled` mantêm a escolha atual dos Widgets. A Dock do macOS continua independente desses controles.

## Island integrada à câmera (0.5)

O posicionamento **Camera** usa uma silhueta preta de notch presa ao topo, com cantos superiores côncavos e inferiores arredondados. No MacBook, alinha-se ao recorte físico e deixa uma borda de 4 pontos quando recolhido. Ao passar o ponteiro, o conteúdo expande para baixo sem solicitar foco de teclado; clicar abre e prepara os controles. Sair recolhe após o atraso configurado, respeitando pin e edição. A câmera não é acessada nem exige permissão.

O recorte é medido pelas áreas auxiliares públicas de `NSScreen`. A parte superior acompanha a largura do corpo ao expandir; os controles ficam abaixo da faixa da câmera/barra. Em monitores sem notch, desenha o mesmo formato no topo, usando 185 pt como largura compacta e uma faixa superior mínima de 32 pt. A área central da barra fica coberta pelo notch desenhado, incluindo durante a expansão. Com apenas uma Island, a tela com notch tem preferência sobre um monitor externo principal.

O modo Camera usa preto opaco para combinar com o recorte. Em **Dynamic Island → Placement → Floating**, continuam disponíveis deslocamentos, vidro, opacidade e temas armazenados. A atualização ativa Camera e hover uma única vez, preservando widgets, notas e preferências visuais; escolhas posteriores são respeitadas.

## Personalização 0.2

Em **Dynamic Island**, escolha tema claro/escuro/sistema, superfície sólida ou vidro, cor, opacidade, cantos, borda, sombra e duração da animação. O botão de pin mantém a Island aberta. A opção **Live compact status** mostra dados do módulo selecionado; fica desligada por padrão para reduzir atividade em repouso. Ajustes visuais preservam a janela e a expressão da calculadora.

Em **Dock**, personalize magnificação, animação, material, cor e rótulos. Ative aplicativos em execução para fixá-los pelo menu contextual, ou mostre uma Dock em cada tela. O menu permite abrir, revelar no Finder e solicitar encerramento normal de um aplicativo, sem force quit.

Em **Widgets**, abra as opções de cada widget: nome, tamanho de texto, conteúdo, fuso horário e relógio 12/24h com segundos opcionais. É possível duplicar, centralizar, trazer à frente, mostrar/ocultar todos e organizar automaticamente. O snap usa o handle de arraste e o fim do redimensionamento; arrastar o fundo continua disponível, mas não garante snap. Sem segundos, relógios atualizam uma vez por minuto.

A calculadora é compartilhada entre Island e widgets. Seu histórico é opcional, desligado por padrão, limitado a 30 entradas e apagado ao desativá-lo. Return registra um cálculo; o histórico permite reutilizar ou excluir entradas. O timer tem nome, presets editáveis, alerta Glass/Ping ou silencioso, progresso, extensão de um minuto e reinício.

O JSON mantém compatibilidade com exportações anteriores e agora inclui opções de widgets/grade, preferências do timer e a opção de histórico. Expressões do histórico e temporizadores em execução não são exportados.

## Fluidez e UX 0.3

A Island coordena resize e revelação do conteúdo, preserva a entrada durante a expansão e aceita reversões rápidas. Pedidos de teclado são explícitos e direcionados ao painel; passar o ponteiro não solicita ativação. A Dock amplia ícones e desloca vizinhos sem mudar as áreas estáveis de hover. O auto-hide respeita interação, menus e teclado.

Widgets exibem/ocultam e organizam com transições finitas, preservam notas durante movimento e recusam uma organização sem espaço em vez de sobrepor tudo. O modo de edição traz os widgets à frente. Remover uma nota preenchida pede confirmação. Controles pequenos, conteúdo mínimo, feedback de erro/cópia, entrada inválida do timer e eventos de dia inteiro foram revisados.

Settings mantém sua última seção durante a sessão, tem feedback de hover/press e avisos descartáveis. Erros da Dock geram um aviso nativo com ação para sua seção de configurações. Movimento e transparência reduzidos são respeitados; não há animações decorativas contínuas.

O procedimento de julgamento a cada mudança e seus limites estão em [UX_REVIEW.md](UX_REVIEW.md). Editor/binding, geometria e estados foram testados; isso não certifica teclado físico, VoiceOver, ativação entre aplicações ou 60 FPS.

## Permissões e privacidade

Calendário só pede acesso após o botão de conexão. Abra Apple Music ou Spotify antes de conectar; o macOS pode solicitar Automation para cada player. Negativas geram mensagem de erro e exigem reconexão explícita. Ajustes de permissões ficam em **System Settings → Privacy & Security**.

Nenhuma função atual exige administrador, Accessibility ou Screen Recording. A Dock nativa não é alterada. Para ocultá-la, use a opção oficial de ocultação automática em **System Settings → Desktop & Dock**. Arte remota do Spotify é carregada do endereço HTTPS fornecido pelo player; não há coleta ou servidor do BetterApple.

Notas e preferências são armazenadas em UserDefaults no Mac. Exportações JSON incluem notas e caminhos de aplicativos. Temporizadores e eventos lidos não são enviados a serviços externos. O registro de login é gerenciado por `SMAppService`; importar um JSON não concede permissões nem altera esse registro.

## Validação

`swift test` executa os testes do parser, countdown e configurações. Execute `python3 Scripts/validate_native.py` para compilar e rodar os seis harnesses nativos (serviços, produtividade, Dock, widgets e duas suítes de movimento), sem solicitar Calendar/Automation. O comando usa Python padrão e o compilador do Xcode, sem dependências externas.

Build Debug aceita `--validate`: executa verificações internas com UserDefaults isolado e salva resultados/capturas em `/tmp/BetterApple-validation`. Essa rotina abre janelas temporárias, executa um timer curto e encerra. Não é incluída no build Release.

```sh
/opt/homebrew/bin/rtk proxy build/Build/Products/Debug/BetterApple.app/Contents/MacOS/BetterApple --validate
```

## Referência e distribuição

[Atoll](https://github.com/Ebullioscopic/Atoll) foi consultado como referência de arquitetura e comportamento. Nenhum código, recurso gráfico ou framework desse projeto GPLv3 foi incorporado. Veja [ARCHITECTURE.md](ARCHITECTURE.md).

A licença de distribuição do BetterApple ainda não foi definida; por isso não há `LICENSE` concedendo direitos de distribuição nesta etapa. Definir licença, revisar marcas para o nome público e preparar assinatura/notarização são requisitos antes de distribuir.

Para uma sequência finita de 20 ciclos destinada ao Instruments, use o build Debug:

```sh
/opt/homebrew/bin/rtk proxy build/Build/Products/Debug/BetterApple.app/Contents/MacOS/BetterApple --validate --profile-motion
```

Esse modo utiliza preferências isoladas, respeita Reduce Motion e grava seu resultado em `/tmp/BetterApple-motion-profile`. A validação normal escreve o contexto de ativação e verificações não certificadas junto de seus resultados; falhas reais retornam código diferente de zero.
