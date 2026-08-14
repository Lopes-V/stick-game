# Chaos Stick Arena

Arena fighter 2D para 2–4 jogadores na mesma rede local. O host roda uma simulação authoritative em Godot; os demais jogadores abrem um link no navegador, entram no lobby e jogam sem instalar o projeto. Todo visual atual é procedural e usa formas nativas da Godot.

## Requisitos

- Godot 4.x configurada por uma das opções abaixo.
- Python 3 apenas para o servidor HTTP do launcher LAN.
- Para editar o projeto, use Godot 4.x. Para refazer `web_build/`, também são
  necessários os templates oficiais de exportação Web.
- Navegador com WebAssembly/WebGL 2 para cada jogador.

Não há plugins, pacotes, assets ou serviços externos obrigatórios.

## Godot no Windows

O executável da Godot não está versionado. O launcher valida cada candidato com
`--version`, aceita versões Godot 4.x compatíveis e rejeita wrappers
`*_console.exe`, builds Mono/headless e caminhos quebrados.

### Opção A — Godot no PATH

Instale a Godot 4.x e disponibilize `godot4`, `godot` ou `Godot.exe` no `PATH`.
Para conferir no PowerShell:

```powershell
Get-Command godot4, godot, Godot.exe -ErrorAction SilentlyContinue
```

### Opção B — variável GODOT_EXE

Informe o caminho completo do executável principal para a sessão atual e inicie
o host na mesma janela:

```powershell
$env:GODOT_EXE = "C:\Godot\Godot_v4.7.1-stable_win64.exe"
.\HOST_GAME.bat
```

O nome e a versão podem variar; o requisito é ser uma Godot 4.x válida.

### Opção C — Godot portátil

Coloque o executável principal portátil diretamente em `tools/godot/`, por
exemplo `tools/godot/Godot_v4.7.1-stable_win64.exe`. Não é necessário usar esse
nome exato. O arquivo correspondente `_console.exe` não funciona sozinho.

Executáveis e arquivos compactados da engine em `tools/godot/` são
intencionalmente ignorados pelo Git. Se nenhuma instalação válida for encontrada,
o launcher encerra antes do build/patch e mostra essas três opções.

## Como executar

Fluxo recomendado no Windows:

1. Dê duplo clique em `HOST_GAME.bat`.
2. O launcher valida Python e Godot, verifica o projeto e a build Web, inicia o
   servidor Godot headless somente em `127.0.0.1:9000`, inicia o gateway
   HTTP/WebSocket em `0.0.0.0:8080` e só então mostra `ONLINE`.
3. O navegador do host abre `http://localhost:8080`.
4. Envie o link `http://IP_DA_LAN:8080` mostrado na tela para 1–3 pessoas na mesma rede.
5. Todos informam o nome, marcam `READY`, e o primeiro navegador (host da sala) usa `START GAME`.

Linux: torne os scripts executáveis e rode `./host_game.sh`. Também é possível abrir `project.godot` no editor e pressionar F6/F5 para testar um cliente nativo enquanto um servidor está ativo.

Servidor manual:

```text
godot --headless --path . -- --server
python tools/lan_http_server.py --directory web_build --port 8080 --websocket-upstream-port 9000
```

O cliente Web deriva o WebSocket de `window.location.host` e conecta em
`ws://IP_DA_LAN:8080/ws`; não existe IP hardcoded. O mesmo processo Python serve
os arquivos Web e encaminha `/ws` de forma transparente para o Godot em
`127.0.0.1:9000`. As portas pública e interna, limite de jogadores, início do
Chaos e pontuação ficam em `server_config.json`. Clientes nativos de debug podem
usar conexão direta com `--connect=HOST --connect-port=PORT` ou
`--connect-url=ws://HOST:PORT` e o servidor pode receber um bind manual com
`--server-bind=ENDERECO`.

O servidor mantém a física authoritative a 60 Hz. O cliente captura comandos de
movimento a 60 Hz, agrupa dois comandos por pacote e envia 30 pacotes/s; o
servidor continua publicando 30 snapshots/s. O jogador local usa prediction e
reconciliation pelos números de sequência confirmados, enquanto jogadores
remotos são exibidos com um buffer de interpolação de aproximadamente 50 ms.
Teletransportes do Void Loop limpam o histórico e são aplicados por snap.

O `CharacterBody2D` do jogador mantém a transformação de gameplay: authoritative
no servidor, predicted para o jogador local e interpolada para jogadores remotos.
Um `VisualRig` filho acompanha essa transformação com spring apenas visual e
expõe `WeaponAnchor`; sway/recoil da arma não alteram colisão nem o muzzle
authoritative usado pelos tiros.

O launcher prepara a exportação **sem threads** para funcionar por HTTP dentro
da rede privada. O jogo é exclusivo para PC e usa teclado + mouse. Navegadores
móveis exibem uma tela `PC ONLY` antes de qualquer conexão multiplayer; notebooks
com touchscreen não são bloqueados apenas por possuírem toque.
Como `AudioWorklet` também exige HTTPS, a build LAN usa automaticamente o
driver de áudio Dummy. Isso não remove nenhum som atual, pois o protótipo ainda
não depende de arquivos de áudio.

## Build Web

No Windows, execute `BUILD_WEB.bat`; no Linux, `./build_web.sh`. Ambos usam o
preset `Web` de `export_presets.cfg` e geram `web_build/index.html` e os arquivos
`.js`, `.wasm` e `.pck` correspondentes. `build_web.ps1` usa a mesma descoberta e
validação robusta de Godot do launcher.

`web_build/` é artefato local e não é versionado. `HOST_GAME.bat` detecta os
arquivos ausentes e executa o build automaticamente; se os templates oficiais
de exportação Web não estiverem instalados, o launcher informa claramente a
falha e aponta seus logs.

## Controles

Teclado e mouse:

- `A` / `D`: mover.
- `W` ou `Space`: pular.
- Mouse: mirar.
- Clique esquerdo ou `J`: atacar/disparar.
- Clique direito ou `K`: arremessar arma.
- `E`: pegar/trocar arma.

Gamepad, joystick e controles touch não são suportados.

Ferramentas do host: `F1` adiciona dummy, `F2` faz chover uma arma, `F3` inicia Chaos, `F4` força o próximo evento, `F5` reinicia o round e `F10` alterna o overlay de debug.

## Mecânicas

Impact começa em 0% e aumenta com socos, tiros, explosões, objetos e body slams.
O percentual segue uma curva suave de knockback. Golpes não matam por threshold
no centro: o KO ocorre ao cruzar os limites laterais ou o limite superior da arena.

As sete armas-base são pistol, shotgun, rifle, sniper, rocket launcher, katana e grenade launcher. Armas soltas têm física, atravessam o Void Loop e causam impacto quando arremessadas. Golden Gun e Cursed Shotgun aparecem raramente no Chaos.

No Void Loop, cruzar a parte inferior conecta o corpo ao céu sem respawn: velocidade, Impact e arma são preservados com limites seguros e cooldown. Jogadores podem voltar em body slam; rockets, granadas, armas, caixas e barris também usam o loop.

Após 30 segundos, o Core inicia Chaos e escala até o nível MAX. O diretor authoritative combina eventos modulares como Low/High Gravity, Super Knockback, Wind, Flying Objects, Weapon Rain, Gravity Pulse, Explosive Rain, Blackout, Moving Platforms, Core Shockwave, Floor Panic, Ammo Overload e Mirror Projectiles.

O último jogador vivo marca um ponto. A arena, modificadores, objetos temporários, projéteis e eventos são limpos entre rounds. O primeiro a cinco pontos vence a partida.

## Estrutura

- `scenes/main/`: cena inicial única.
- `scripts/core/`: ciclo da partida, rounds, câmera e Void Loop.
- `scripts/network/`: lobby, IDs, RPC de input e snapshots.
- `scripts/player/`, `scripts/weapons/`, `scripts/map/`: simulação authoritative.
- `scripts/chaos/events/`: eventos independentes e reversíveis.
- `scripts/ui/`, `scripts/effects/`: apresentação local não-authoritative.
- `tools/`: HTTP LAN e validação automatizada.

## Rede e firewall

Somente `8080/TCP` precisa estar acessível na LAN: arquivos Web, `/status` e o
WebSocket `/ws` compartilham essa porta. O Godot escuta apenas em
`127.0.0.1:9000`, que não precisa nem deve ser acessível pelos outros aparelhos.
O launcher não exige privilégios administrativos, não altera o Windows Firewall
e não configura o roteador. Se `8080` ainda estiver bloqueada, a política da rede
ou do computador precisa permitir essa única porta; redes de convidados também
podem bloquear comunicação entre dispositivos.

## Validação rápida

Descoberta da Godot no Windows:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\test_godot_discovery.ps1
```

Projeto e gameplay:

```text
godot --headless --editor --path . --quit
godot --headless --path . --script res://tools/map_validation.gd
godot --headless --path . -- --server --test-bots=4 --auto-start --smoke-test --seed=424242
```

O smoke test valida quatro jogadores e seus inputs, rig/muzzle separados,
prediction reset, pickup, tiro/munição, arremesso, entregas nos pontos do Reactor,
Void Loop de jogador/objeto, pelo menos oito eventos modulares, KO, score e a
sequência de limpeza round 1 → round 2 → round 3 sem nós temporários vazando.
