# BetterApple

Aplicativo nativo de personalização e produtividade para macOS 14+, escrito do zero em Swift, SwiftUI e AppKit. Versão de desenvolvimento **0.1.0**. Sem dependências externas de runtime, backend ou telemetria.

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

## Permissões e privacidade

Calendário só pede acesso após o botão de conexão. Abra Apple Music ou Spotify antes de conectar; o macOS pode solicitar Automation para cada player. Negativas geram mensagem de erro e exigem reconexão explícita. Ajustes de permissões ficam em **System Settings → Privacy & Security**.

Nenhuma função atual exige administrador, Accessibility ou Screen Recording. A Dock nativa não é alterada. Para ocultá-la, use a opção oficial de ocultação automática em **System Settings → Desktop & Dock**. Arte remota do Spotify é carregada do endereço HTTPS fornecido pelo player; não há coleta ou servidor do BetterApple.

Notas e preferências são armazenadas em UserDefaults no Mac. Exportações JSON incluem notas e caminhos de aplicativos. Temporizadores e eventos lidos não são enviados a serviços externos. O registro de login é gerenciado por `SMAppService`; importar um JSON não concede permissões nem altera esse registro.

## Validação

`swift test` executa os testes do parser, countdown e configurações. O harness [Scripts/service-smoke.swift](Scripts/service-smoke.swift) documenta como compilar e executar verificações reais dos serviços sem solicitar Calendar/Automation.

Build Debug aceita `--validate`: executa verificações internas com UserDefaults isolado e salva resultados/capturas em `/tmp/BetterApple-validation`. Essa rotina abre janelas temporárias, executa um timer curto e encerra. Não é incluída no build Release.

```sh
/opt/homebrew/bin/rtk proxy build/Build/Products/Debug/BetterApple.app/Contents/MacOS/BetterApple --validate
```

## Referência e distribuição

[Atoll](https://github.com/Ebullioscopic/Atoll) foi consultado como referência de arquitetura e comportamento. Nenhum código, recurso gráfico ou framework desse projeto GPLv3 foi incorporado. Veja [ARCHITECTURE.md](ARCHITECTURE.md).

A licença de distribuição do BetterApple ainda não foi definida; por isso não há `LICENSE` concedendo direitos de distribuição nesta etapa. Definir licença, revisar marcas para o nome público e preparar assinatura/notarização são requisitos antes de distribuir.
