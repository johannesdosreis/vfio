# RTX A1000 numa VM Windows 11 (GPU passthrough dinâmico)

Configuração do HP ZBook Power G10 para passar a NVIDIA RTX A1000 para uma VM Windows 11 só
enquanto ela está ligada. A tela do Windows aparece no KDE pelo Looking Glass, e dá para jogar a
VM de outro aparelho pelo Moonlight. Com a VM desligada, a NVIDIA volta para o Linux sozinha.

A ideia veio do PR de GPU passthrough do Omarchy ([basecamp/omarchy#3454](https://github.com/basecamp/omarchy/discussions/3455)),
mas o código é próprio: o do Omarchy depende de Hyprland, UWSM e dos scripts `omarchy-*`, e não trata
GPU de notebook sem saída de vídeo. Veja [Diferenças em relação ao Omarchy](#diferenças-em-relação-ao-omarchy).

Configurado em 13/10/2026.

## Sumário

- [Hardware e sistema](#hardware-e-sistema)
- [Como funciona](#como-funciona)
- [Uso no dia a dia](#uso-no-dia-a-dia)
- [O que foi configurado](#o-que-foi-configurado)
- [Inventário de arquivos instalados](#inventário-de-arquivos-instalados)
- [Arquivos deste repositório](#arquivos-deste-repositório)
- [Solução de problemas](#solução-de-problemas)
- [Como desfazer](#como-desfazer)
- [Diferenças em relação ao Omarchy](#diferenças-em-relação-ao-omarchy)

## Hardware e sistema

| Item | Valor |
|---|---|
| Máquina | HP ZBook Power 15.6" G10 |
| CPU | i7-13800H: P-cores = CPUs 0–11 (núcleos 0–5, os núcleos 2 e 3 vão a 5,2 GHz), E-cores = CPUs 12–19 |
| GPU do desktop | Intel UHD (Raptor Lake-P), PCI `00:02.0` |
| GPU da VM | NVIDIA RTX A1000 6GB Laptop (GA107), PCI `01:00.0`, sozinha no grupo IOMMU 15 |
| RAM | 31 GB |
| Sistema | CachyOS, kernels `linux-cachyos` 7.2 e `linux-cachyos-lts` 6.18 |
| Boot | Limine via `limine-mkinitcpio-hook` (`limine-update`), btrfs + snapper |
| Desktop | KDE Plasma 6 Wayland, Krohnkite (tiling) |
| Rede | Wi-Fi `wlan0` (192.168.28.37) e cabo `eno1` (10.108.176.132) |

Particularidades do notebook que guiaram a configuração:

- **Notebook sem chave MUX.** A A1000 é um "3D controller" sem nenhuma saída de vídeo. As duas telas
  (interna e HDMI) ficam na Intel.
- **O vBIOS fica num chip da própria GPU,** não no BIOS do notebook: não existe método ACPI `_ROM`.
  O driver do Windows lê o vBIOS sozinho, então a VM não precisa de `romfile`.
- **A CPU declara 46 bits de endereço físico, mas a IOMMU só mapeia 39** (MGAW 39). Sem limitar a VM
  a 39 bits, o mapeamento de DMA falha. É o mesmo problema que o Omarchy encontrou em Intel de 12ª e
  13ª geração.

## Como funciona

```
Ligar (atalho "Windows 11 (VM)" ou win11-vm)
  └─ virsh start win11
      ├─ hook "prepare"  → vfio-dgpu detach
      │    ├─ para nvidia-powerd / Sunshine / waywallen, só se estiverem segurando a NVIDIA
      │    ├─ se outro programa estiver usando a NVIDIA: recusa e lista os processos
      │    ├─ descarrega os módulos nvidia e liga a GPU ao vfio-pci
      │    └─ religa o Sunshine (agora na VAAPI da Intel) e o waywallen (agora na Intel)
      ├─ QEMU sobe com a GPU, o /dev/kvmfr0 (Looking Glass) e a bateria falsa
      └─ hook "started"  → win11-portfwd add   (portas do Sunshine do Windows)
  └─ looking-glass-client mostra o Windows numa janela do KDE

Desligar o Windows
  ├─ hook "stopped"  → win11-portfwd del
  └─ hook "release"  → vfio-dgpu attach
       ├─ tira a GPU do vfio-pci e recarrega os módulos nvidia
       └─ religa o nvidia-powerd e reinicia o Sunshine (volta à NVENC) e o waywallen (volta à NVIDIA)
```

O KDE fica sempre na Intel. O Sunshine e o waywallen **seguem a NVIDIA**: usam-na enquanto ela está
no Linux e passam para a Intel enquanto a VM a tem. Em cada troca eles reiniciam, então uma
transmissão em andamento cai por alguns segundos e o papel de parede pisca.

Custo: com o waywallen na NVIDIA, ela não entra mais em economia de energia (Runtime D3). Medido:
cerca de 8 W a mais na GPU, com mais calor e menos bateria. Para voltar a deixar o waywallen sempre
na Intel, veja [Como desfazer](#como-desfazer).

## Uso no dia a dia

### Ligar e desligar

- **Ligar:** atalho **"Windows 11 (VM)"** no menu do KDE, ou `win11-vm` no terminal. Liga a VM se
  estiver desligada e abre o Looking Glass. Se ela não puder ligar, uma janela mostra o motivo.
- **Desligar:** botão direito no atalho → **"Desligar o Windows"**, ou `win11-vm shutdown`.
  O Windows às vezes leva alguns minutos para desligar, quando está instalando atualizações.

### Antes de ligar: quem está usando a NVIDIA?

```bash
nvidia-users
```

Cada processo aparece como `ok` (o hook fecha e reabre sozinho, como o Sunshine) ou `FECHAR` (feche
antes de ligar a VM). Sem sudo, só mostra os seus processos. `sudo nvidia-users` ou
`sudo vfio-dgpu status` mostram também os serviços do sistema.

### Looking Glass

- Clique na janela para capturar o teclado e o mouse. O **Ctrl direito** solta a captura e é a tecla
  dos atalhos do Looking Glass. Por exemplo, **Ctrl direito + F** alterna tela cheia.
- **Copiar e colar** entre Linux e Windows funciona para texto e imagens (pelo agente SPICE).
  Arquivos não passam.
- O Windows enxerga um monitor virtual de **1920×1080 a 60 Hz**, renderizado pela A1000.

### Moonlight (streaming)

Dois hosts aparecem no Moonlight:

| Host | O que transmite | Codificador | Como adicionar |
|---|---|---|---|
| Notebook (Sunshine do Linux) | Desktop Linux | NVENC com a VM desligada, Intel (VAAPI) com ela ligada | Aparece sozinho |
| `win11` (Sunshine do Windows) | Windows, direto | NVENC da A1000 | Manual: `10.108.176.132:49989` (cabo) ou `192.168.28.37:49989` (Wi-Fi) |

O host `win11` só existe com a VM ligada. Para jogar a VM de outro aparelho, use o `win11`. O PIN de
pareamento é digitado em `https://localhost:49990`, dentro do Windows.

### Comandos úteis

| Comando | Para quê |
|---|---|
| `win11-vm` / `win11-vm shutdown` | Ligar e abrir o Looking Glass / desligar o Windows |
| `nvidia-users` | O que está usando a NVIDIA (código de saída 1 = algo bloqueia a VM) |
| `sudo vfio-dgpu status` | Driver atual da NVIDIA, módulos carregados, processos com a GPU aberta |
| `sudo vfio-dgpu detach` / `attach` | Trocar a GPU manualmente entre Linux e vfio-pci, sem VM |
| `sudo win11-portfwd status` | Regras e contadores do redirecionamento de portas |
| `journalctl -t vfio-dgpu` | Log das trocas de GPU |
| `./vfio/verify-after-reboot.sh` | Checa IOMMU, swap, ordem das GPUs e KWin depois de um reboot |
| `sudo ./vfio/test-dynamic.sh` | Duas idas e voltas da GPU sem VM, mostrando o que o KWin tem aberto |
| `sudo ./vfio/test-follow.sh` | Uma ida e volta com pausa, mostrando em que GPU o Sunshine e o waywallen ficaram |
| `sudo ./vfio/diag-portfwd.sh` | Mostra se as conexões do Moonlight chegam e são repassadas |
| `ssh win11` | Terminal no Windows (`cmd`), com a chave "Stara SSH" |
| `./vfio/vm-ps.py 'comando'` | Roda PowerShell no Windows como SYSTEM, pelo guest agent |
| `./vfio/vm-put.py 'C:\pasta' arquivo...` | Copia arquivos do Linux para o Windows, pelo guest agent |

Os scripts em `./vfio/` são executados a partir da raiz deste repositório.

## O que foi configurado

### 1. Boot, IOMMU e swap

`/etc/default/limine` tem uma única linha de cmdline:

```
KERNEL_CMDLINE[default]+="quiet nowatchdog splash rw rootflags=subvol=/@ root=UUID=… systemd.zram=0 zswap.enabled=1 zswap.shrinker_enabled=1 zswap.compressor=lz4 zswap.max_pool_percent=30 intel_iommu=on iommu=pt"
```

- **`intel_iommu=on iommu=pt`:** liga a IOMMU de forma explícita. O `pt` deixa os dispositivos do
  próprio Linux sem tradução de endereços, o que é mais rápido.
- **zram e zswap:** antes, `systemd.zram=0` e os parâmetros do zswap estavam em linhas soltas, fora do
  `KERNEL_CMDLINE`, e o `limine-entry-tool` ignorava essas linhas sem avisar. Agora o zram está
  desligado e o zswap (lz4, 30% da RAM) fica na frente do swapfile de 32 GB (`/swap/swapfile`).
- **Uma linha só:** o `limine-entry-tool` lê o arquivo linha por linha, e uma segunda linha
  `KERNEL_CMDLINE[default]+=` é posta **antes** da primeira, não depois.
- **Backup:** `/etc/default/limine.bak-20261013`. Aplicado com `vfio/apply-limine.sh`, que roda o
  `limine-update`.

### 2. GPU dinâmica: `vfio-dgpu` e o hook do libvirt

A GPU **não** é presa ao vfio-pci no boot. Ela fica com o driver nvidia e só vai para a VM enquanto
a VM está ligada. Assim CUDA, NVENC e `prime-run` continuam disponíveis no Linux no resto do tempo.

- **`/usr/local/bin/vfio-dgpu`** (fonte: `vfio/vfio-dgpu`):
  - **`detach`:** para os serviços que estão segurando a NVIDIA (`nvidia-powerd`,
    `nvidia-persistenced`, Sunshine). Recusa, listando os processos, se sobrar qualquer outro.
    Descarrega `nvidia_drm`, `nvidia_modeset`, `nvidia_uvm` e `nvidia` e liga a GPU ao `vfio-pci`
    via `driver_override`. No fim, religa o Sunshine e o waywallen, que sobem na Intel.
  - **`attach`:** desfaz a troca, carrega os quatro módulos nvidia **explicitamente** e religa os
    serviços. Também reinicia o Sunshine e o waywallen, para eles voltarem à NVIDIA.
  - **Seguidores:** `FOLLOW_UNITS` (Sunshine) são serviços normais. `FOLLOW_FLATPAKS` (waywallen)
    rodam num escopo próprio do Flatpak, fora do serviço que os inicia: o hook os identifica pelo
    cgroup e os fecha com `flatpak kill`.
  - **Limite de inícios:** antes de cada reinício que ele mesmo provoca, o hook roda
    `systemctl reset-failed`. O Sunshine aceita só 5 inícios a cada 8 min 20 s, e ligar e desligar
    a VM algumas vezes seguidas estourava esse limite (o mesmo valia para o `nvidia-powerd`).
  - **`status`:** driver atual, módulos carregados e processos com a GPU aberta.
- **`/etc/libvirt/hooks/qemu`** (fonte: `vfio/libvirt-qemu-hook`): chama `vfio-dgpu detach` em
  `prepare` e `attach` em `release`, só para VMs com um `<hostdev>` apontando para `01:00.0`. Para a
  VM `win11`, também chama `win11-portfwd` em `started`, `reconnect` e `stopped`.
- **`/etc/modprobe.d/vfio.conf`:** `options vfio-pci disable_idle_d3=1`. Mantém a GPU ligada (D0)
  enquanto o vfio-pci a segura; GPUs de notebook podem não acordar de D3cold.
- **Na VM:** o `<hostdev>` é `managed='no'`, porque quem faz a troca é o hook, não o libvirt.

Por que carregar os módulos explicitamente: o kmod só respeita a **primeira** linha `softdep` de cada
módulo, e o próprio `nvidia.ko` já declara uma (`pre: ecdh_generic,ecdsa_generic`). Por isso o
`softdep nvidia post: nvidia-uvm nvidia-drm` do pacote `nvidia-utils` é ignorado, e o `nvidia_drm` não
voltava.

### 3. Manter o desktop fora da NVIDIA

Se qualquer programa ficar com a NVIDIA aberta, a VM não liga. Quatro ajustes cuidam disso:

1. **KWin preso à Intel.**
   - `/etc/udev/rules.d/61-dri-igpu.rules` cria o link fixo `/dev/dri/igpu` para a placa da Intel.
     Os números `cardN` mudam a cada boot, e os caminhos `by-path` têm `:`, que o `KWIN_DRM_DEVICES`
     usa como separador.
   - `~/.config/environment.d/90-kwin-igpu.conf` define `KWIN_DRM_DEVICES=/dev/dri/igpu`. O KWin
     roda como serviço do usuário (`plasma-kwin_wayland.service`) e lê o `environment.d`. Sem isso,
     ele pegaria a NVIDIA de volta quando ela retornasse da VM (hotplug).
2. **A Intel sempre com o primeiro nó de render (`renderD128`).**
   - `/etc/modprobe.d/igpu-first.conf` tem
     `install nvidia /usr/bin/modprobe i915 ; /usr/bin/modprobe --ignore-install nvidia $CMDLINE_OPTS`,
     e o initramfs foi reconstruído (`limine-update`).
   - Sem isso, a ordem i915/nvidia era uma corrida a cada boot. Programas que abrem "a primeira GPU"
     (o waywallen e o plugin de papel de parede dele, dentro do `plasmashell`) pegavam a NVIDIA nos
     boots em que ela ficava com o `renderD128`.
   - É uma regra `install`, e não `softdep`, pelo mesmo motivo do item anterior.
3. **waywallen** (papel de parede animado, Flatpak) segue a GPU:
   - o drop-in `~/.config/systemd/user/app-org.waywallen.waywallen@autostart.service.d/gpu.conf`
     faz o autostart rodar `~/.local/bin/waywallen-gpu`;
   - antes de iniciar, o `waywallen-gpu` aponta o `render_node` dos plugins de vídeo e imagem
     (`~/.var/app/org.waywallen.waywallen/config/waywallen/config.toml`) para a NVIDIA, se ela estiver
     no Linux, ou para a Intel, com `FLATPAK_GL_DRIVERS=default`, se estiver na VM. Essa variável
     deixa as bibliotecas da NVIDIA fora da sandbox: a extensão `GL.nvidia` do Flatpak faz o
     renderizador abrir a NVIDIA mesmo com o `render_node` na Intel;
   - backup da configuração original: `config.toml.bak-20261013`.
4. **Janela do Looking Glass sem piscar.**
   - O Krohnkite reorganizava a janela quando o foco mudava. A classe `looking-glass-client` entrou
     no `ignoreClass` do Krohnkite, em `~/.config/kwinrc` (backup `~/.config/kwinrc.bak-20261013`).
   - O cliente usa buffer duplo (`[egl] doubleBuffer=yes`), por causa do efeito "Escurecer janelas
     inativas" do KDE.

### 4. A máquina virtual `win11`

Definição atual exportada em `vfio/win11-current.xml`. A da fase de instalação é a `vfio/win11.xml`.

| Item | Configuração | Por quê |
|---|---|---|
| Máquina | q35, OVMF com Secure Boot, sem chaves cadastradas (modo setup), TPM 2.0 (swtpm, CRB) | Requisitos do Windows 11 |
| Memória | 16 GiB, sem balloon | Com VFIO, toda a memória da VM fica travada na RAM |
| CPU | 8 vCPUs = 4 P-cores com HT (CPUs 4–11, inclui os núcleos de 5,2 GHz); emulador e I/O nos E-cores 12–15 | O host fica com os P-cores 0–1 e os E-cores |
| Modelo de CPU | `host-passthrough`, `maxphysaddr limit=39`, enlightenments do Hyper-V, `kvm hidden` | A IOMMU só mapeia 39 bits |
| GPU | `<hostdev>` 01:00.0, `managed='no'`, `rom bar='off'`, subsystem IDs 103c:8bf2 via `qemu:override` | Troca feita pelo hook; GPU sem ROM BAR; o driver de notebook confere esses IDs |
| Bateria falsa | SSDT `/var/lib/libvirt/acpi/ssdt-battery.aml` (fonte `vfio/ssdt-battery.asl`, compilado com `iasl`), via `-acpitable` | O driver NVIDIA de notebook dá Code 43 sem bateria |
| Looking Glass | `ivshmem-plain` + `memory-backend-file` em `/dev/kvmfr0`, 32 MiB, via `qemu:commandline` | O libvirt não tem um elemento para IVSHMEM com kvmfr |
| Disco | virtio, qcow2 de 100 GB (ocupa só o que usa), `cache=none io=native discard=unmap`, iothread | Desempenho |
| Local do disco | `/var/lib/libvirt/images`, transformado em **subvolume btrfs** com nodatacow | Fica fora dos snapshots do snapper |
| Rede | virtio na rede NAT `default`, MAC `52:54:00:e6:c6:07`, reserva DHCP → 192.168.122.144 | IP fixo para o redirecionamento de portas |
| Vídeo | `none`; SPICE em 127.0.0.1:5900 só para teclado, mouse, áudio e área de transferência; mouse e teclado virtio | Quem desenha é a A1000, a imagem vem pelo Looking Glass |
| Guest agent | canal `org.qemu.guest_agent.0` | Desligamento limpo, `vm-ps.py`, `vm-put.py` |

Scripts que montaram a VM: `vfio/setup-vm.sh` (subvolume, disco, SSDT, `virsh define`),
`vfio/apply-lg-config.py` (modo Looking Glass) e `vfio/apply-kvmfr.py` (troca para o kvmfr).

### 5. Looking Glass e kvmfr

- **Pacotes do AUR** (instalados pelo seu gerenciador gráfico):
  - `looking-glass` B7-7, o cliente;
  - `looking-glass-module-dkms` B7-7, o módulo `kvmfr`. O DKMS o recompila para cada kernel que tem
    headers instalados.
- **Configuração do módulo:**
  - `/etc/modprobe.d/kvmfr.conf`: `options kvmfr static_size_mb=32`;
  - `/etc/modules-load.d/kvmfr.conf`: carrega o módulo no boot;
  - `/etc/udev/rules.d/99-kvmfr.rules`: `/dev/kvmfr0` com dono `johannes:kvm`, permissão `0660`.
    O QEMU roda como `libvirt-qemu`, que está no grupo `kvm`.
- **libvirt:** `/etc/libvirt/qemu.conf` ganhou um `cgroup_device_acl` (a lista padrão + `/dev/kvmfr0`).
  Backup: `/etc/libvirt/qemu.conf.bak-20261013`.
- **Cliente** (`~/.config/looking-glass/client.ini`):
  - `shmFile=/dev/kvmfr0`, com DMA-BUF. O log mostra "Using DMA buffer support".
  - Tecla de escape `KEY_RIGHTCTRL`, porque o notebook não tem Scroll Lock.
  - `rawMouse`, buffer duplo, SPICE em 127.0.0.1:5900.

32 MB comportam 1920×1080 SDR. Para 2560×1440, aumente para 64 MB em três lugares:
`kvmfr.conf`, `SIZE` em `vfio/apply-kvmfr.py` (reaplicar com a VM desligada) e as resoluções do
monitor virtual no Windows.

### 6. Dentro do Windows

- **Windows 11 Pro**, build 26300, pt-BR.
- **`virtio-win-guest-tools` 0.1.302:** drivers virtio, QEMU Guest Agent e o agente SPICE (área de
  transferência).
- **Driver NVIDIA** 32.0.15.9595, sem Code 43.
- **Driver IVSHMEM** da Red Hat (`virtio-win10-prewhql-0.1-161`). Ele não vem na ISO virtio. O zip foi
  baixado pelo Linux, porque o fedorapeople mostra uma página anti-robô para o PowerShell.
- **Looking Glass Host B7**, como serviço automático. O log fica em
  `C:\ProgramData\Looking Glass (host)\looking-glass-host.txt`.
- **Virtual Display Driver 25.7.23** (dispositivo `Root\MttVDD`). Ele dá à A1000 um monitor para o
  Looking Glass capturar. Configuração em `C:\VirtualDisplayDriver\vdd_settings.xml`: GPU NVIDIA, só
  1920×1080 a 60 Hz.
- **Fornecedores Confiáveis:** os certificados da Red Hat e da SignPath Foundation, que assinam o
  IVSHMEM e o VDD. Sem eles, os drivers não instalam em modo silencioso.
- **Sunshine** v2026.914.233613, como serviço `SunshineService`.
  - Configuração em `C:\Program Files\Sunshine\config\sunshine.conf`: `sunshine_name = win11` e
    `port = 49989`.
  - As regras do firewall liberam o `sunshine.exe`.
- `C:\vfio-setup\` tem os instaladores usados. Pode ser apagada.

### 7. Sunshine

**Linux** (serviço de usuário `app-dev.lizardbyte.app.Sunshine.service`):

- **Drop-in** `~/.config/systemd/user/app-dev.lizardbyte.app.Sunshine.service.d/gpu-encoder.conf`:
  troca o `ExecStart` por `~/.local/bin/sunshine-gpu`.
- **`sunshine-gpu`** olha onde a NVIDIA está quando o Sunshine inicia:
  - **com o driver nvidia:** o Sunshine escolhe sozinho (NVENC);
  - **com o vfio-pci:** força `encoder=vaapi` e `adapter_name` na Intel
    (`/dev/dri/by-path/pci-0000:00:02.0-render`), pela linha de comando. Sem a NVIDIA, a escolha
    automática trava dentro do `libcuda` e entra em loop. E o `adapter_name` do arquivo pode estar
    na NVIDIA, que nesse momento não existe.
- **`~/.config/sunshine/sunshine.conf`:** a placa (`adapter_name`) é a que estiver escolhida na
  interface web do Sunshine. Hoje é `/dev/dri/renderD129`, a NVIDIA. Backup em
  `sunshine.conf.bak-20261013`.
- **O hook reinicia o Sunshine em cada troca** de GPU (`FOLLOW_UNITS` no `vfio-dgpu`). Uma
  transmissão em andamento cai por alguns segundos.
- **Monitor virtual automático:** o Sunshine captura a tela `Virtual-Monitor`
  (`output_name`), e o `global_prep_cmd` do `sunshine.conf` cria e remove essa tela sozinho:
  - quando uma sessão do Moonlight começa, roda `~/.local/bin/sunshine-virtual-monitor start`, que
    sobe o `krfb-virtualmonitor` como serviço próprio (`krfb-virtual-monitor.service`, via
    `systemd-run`) na resolução pedida pelo aparelho (`SUNSHINE_CLIENT_WIDTH`/`HEIGHT`), com o VNC na
    porta 5903 (a 5900 é do SPICE da VM), e espera o KWin criar a tela;
  - quando a sessão termina, roda `sunshine-virtual-monitor stop`. A sessão só termina quando o app
    é **encerrado**: Ctrl+Alt+Shift+**E** no Moonlight do PC, ou "encerrar" no menu do "Desktop" na
    lista de apps. Ctrl+Alt+Shift+**Q** só desconecta: a sessão e o monitor virtual continuam, e
    reconectar reaproveita os dois;
  - fora de uma sessão, o Sunshine sobe normalmente sem essa tela e usa uma tela física só para
    testar os codificadores.

**Windows:** porta base 49989.

- Portas: TCP 49984, 49989 e 50010; UDP 49998 a 50002. Interface web em 49990, só dentro da VM.
- A VM fica numa rede NAT atrás do notebook, e Wi-Fi não faz ponte de rede. Por isso o Linux repassa
  essas portas: `/usr/local/bin/win11-portfwd` (fonte `vfio/win11-portfwd`), chamado pelo hook.
  - Regras de DNAT em `nat PREROUTING`, para tudo que não vem do `virbr0`, em qualquer rede do
    notebook.
  - Uma regra `ACCEPT ctstate DNAT` na cadeia `LIBVIRT_FWI`. Sem ela, o libvirt rejeita conexões
    novas que entram na rede NAT.
- O backend de firewall do libvirt é `iptables`. As cadeias do libvirt vêm antes das do ufw, então o
  ufw (ativo, "deny incoming") não interfere.

### 8. SSH para o Windows

- **Windows:** o servidor OpenSSH já vem neste build. O serviço `sshd` foi ligado com início
  automático, e a regra "OpenSSH SSH Server (sshd)" do firewall vale para o perfil Privado.
- **Chave:** a pública "Stara SSH" (ed25519) foi autorizada em
  `C:\ProgramData\ssh\administrators_authorized_keys`, o arquivo usado porque `johannes` é
  administrador. O OpenSSH do Windows exige que só Administradores e SISTEMA tenham acesso a ele.
- **Linux:** atalho `win11` no fim do `~/.ssh/config` (backup `~/.ssh/config.bak-20261013`). Ele
  oferece só a chave "Stara SSH" (`IdentitiesOnly yes`), que vem do agente do 1Password. Com várias
  chaves no agente, o Windows desistiria antes de chegar à certa.
- **Uso:** `ssh win11`. O shell padrão é o `cmd`. Só funciona a partir do notebook; a porta 22 não é
  repassada para a rede.

### 9. Deskflow (teclado e mouse do Linux no Windows)

- **Linux (servidor, já usado antes com `NMTENGPROD6301-win11` à esquerda):** a VM `VM23711` entrou
  na célula à direita do notebook, no `~/.config/Deskflow/Deskflow.conf` (`screens\9\name` e uma
  seção `[computer_VM23711]`). Backups: `Deskflow.conf.bak-20261013` e
  `deskflow-server.conf.bak-20261013`.
- **Borda:** no KDE, o notebook fica à direita do Dell. O Deskflow só troca nas bordas externas do
  desktop, então o mouse vai para o Windows pela **borda direita da tela do notebook**.
- **ufw:** `24800/tcp on virbr0 ALLOW 192.168.122.144`. A regra `24800 ALLOW Anywhere`, que já
  existia, também cobriria a VM.
- **Windows (cliente):** Deskflow 1.27.0 (MSI sem assinatura digital; o SHA-256 confere com o
  publicado no GitHub), serviço `Deskflow` automático. Ele conecta em `192.168.122.1` com o nome
  `VM23711`. A primeira configuração e o aceite das impressões digitais TLS dos dois lados são
  feitos na interface.

### 10. Pacotes

| Pacote | Origem | Para quê |
|---|---|---|
| `acpica` | repositório | `iasl`, para compilar a bateria falsa |
| `dkms` | repositório (dependência) | Compilar o kvmfr a cada kernel |
| `looking-glass-module-dkms`, `looking-glass` | AUR | kvmfr e cliente B7 |
| `wayland-protocols` | repositório (só para compilar) | Build do pacote do AUR |

Já estavam instalados: `qemu-full`, `libvirt`, `virt-manager`, `edk2-ovmf`, `swtpm`, `freerdp`.

## Inventário de arquivos instalados

### Sistema (root)

| Arquivo | Fonte no repo | Função |
|---|---|---|
| `/etc/default/limine` | `vfio/limine.new` | Cmdline: IOMMU + zswap |
| `/etc/modprobe.d/vfio.conf` | `vfio/vfio.conf` | `disable_idle_d3=1` |
| `/etc/modprobe.d/igpu-first.conf` | `vfio/igpu-first.conf` | i915 antes do nvidia |
| `/etc/modprobe.d/kvmfr.conf` | `vfio/kvmfr.modprobe.conf` | kvmfr de 32 MB |
| `/etc/modules-load.d/kvmfr.conf` | `vfio/kvmfr.modules-load.conf` | Carregar o kvmfr no boot |
| `/etc/udev/rules.d/61-dri-igpu.rules` | `vfio/61-dri-igpu.rules` | Link `/dev/dri/igpu` |
| `/etc/udev/rules.d/99-kvmfr.rules` | `vfio/99-kvmfr.rules` | Permissões do `/dev/kvmfr0` |
| `/etc/libvirt/hooks/qemu` | `vfio/libvirt-qemu-hook` | Troca da GPU + redirecionamento de portas |
| `/etc/libvirt/qemu.conf` (trecho final) | `vfio/install-kvmfr-config.sh` | `cgroup_device_acl` com `/dev/kvmfr0` |
| `/usr/local/bin/vfio-dgpu` | `vfio/vfio-dgpu` | detach / attach / status |
| `/usr/local/bin/win11-portfwd` | `vfio/win11-portfwd` | Portas do Sunshine do Windows |
| `/var/lib/libvirt/images/` (subvolume) + `win11.qcow2` | `vfio/setup-vm.sh` | Disco da VM |
| `/var/lib/libvirt/acpi/ssdt-battery.aml` | `vfio/ssdt-battery.asl` | Bateria falsa |
| Rede `default` do libvirt: reserva DHCP | — | win11 = 192.168.122.144 |

### Usuário (`johannes`)

Os arquivos inteiros têm cópia em `vfio/home/`, no mesmo caminho relativo à pasta pessoal.

| Arquivo | Função | Cópia |
|---|---|---|
| `~/.config/environment.d/90-kwin-igpu.conf` | KWin só na Intel | `vfio/home/…` |
| `~/.config/looking-glass/client.ini` | Configuração do cliente | `vfio/home/…` |
| `~/.local/bin/win11-vm` + `~/.local/share/applications/win11-vm.desktop` | Atalho "Windows 11 (VM)" | `vfio/home/…` |
| `~/.local/bin/nvidia-users` | Quem está usando a NVIDIA | `vfio/home/…` |
| `~/.local/bin/sunshine-gpu` + `~/.config/systemd/user/app-dev.lizardbyte.app.Sunshine.service.d/gpu-encoder.conf` | Sunshine escolhe NVENC ou VAAPI | `vfio/home/…` |
| `~/.config/sunshine/sunshine.conf` | Captura, placa e `global_prep_cmd` do Sunshine | `vfio/home/…` |
| `~/.local/bin/sunshine-virtual-monitor` | Cria e remove o monitor virtual a cada sessão do Moonlight | `vfio/home/…` |
| `~/.local/bin/waywallen-gpu` + `~/.config/systemd/user/app-org.waywallen.waywallen@autostart.service.d/gpu.conf` | waywallen segue a GPU | `vfio/home/…` |
| `~/.config/kwinrc`, só a chave `[Script-krohnkite] ignoreClass` | Krohnkite ignora o Looking Glass | comando abaixo |
| `~/.var/app/org.waywallen.waywallen/config/waywallen/config.toml`, só os dois `render_node` | GPU do waywallen | escrito pelo `waywallen-gpu` a cada início |
| `~/.ssh/config`, só o bloco `Host win11` | Atalho `ssh win11` | veja a seção [SSH](#8-ssh-para-o-windows) |
| `~/.config/Deskflow/Deskflow.conf`, só `screens\9\name=VM23711` + `[computer_VM23711]` | VM à direita no Deskflow | refazer arrastando a tela na interface do Deskflow |

### Restaurar os arquivos de usuário

Numa instalação nova, ou se algum desses arquivos se perder, rode a partir da raiz deste repositório:

```bash
cp -a vfio/home/. ~/ && systemctl --user daemon-reload && kbuildsycoca6
```

O `kwinrc` guarda muitas outras configurações, então só a chave do Krohnkite é reaplicada. O
`render_node` do waywallen não precisa de nada: o `waywallen-gpu` o reescreve a cada início. A lista do Krohnkite abaixo é o padrão dele mais
`looking-glass-client`. Depois, desligue e ligue o script do Krohnkite em
Configurações → Gerenciador de janelas → Scripts do KWin.

```bash
kwriteconfig6 --file kwinrc --group Script-krohnkite --key ignoreClass "krunner,yakuake,spectacle,kded5,xwaylandvideobridge,plasmashell,ksplashqml,org.kde.plasmashell,org.kde.polkit-kde-authentication-agent-1,org.kde.kruler,kruler,kwin_wayland,ksmserver-logout-greeter,looking-glass-client"
```


## Arquivos deste repositório

| Arquivo | Tipo |
|---|---|
| `home/` | Cópia dos arquivos de usuário, nos mesmos caminhos de `~` (ver [Restaurar os arquivos de usuário](#restaurar-os-arquivos-de-usuário)) |
| `vfio-dgpu`, `libvirt-qemu-hook`, `win11-portfwd` | Fonte dos scripts instalados |
| `*.conf`, `*.rules`, `limine.new`, `ssdt-battery.asl` | Fonte das configurações instaladas (`90-kwin-igpu.conf` é igual ao de `home/`) |
| `apply-limine.sh`, `install-dynamic.sh`, `install-igpu-first.sh`, `install-kvmfr-config.sh`, `install-portfwd.sh`, `install-sunshine-libva-fix.sh`, `setup-vm.sh` | Instaladores (rodar com sudo) |
| `apply-lg-config.py`, `apply-kvmfr.py` | Ajustes na VM (modo de teste por padrão; `--apply` com a VM desligada) |
| `win11-current.xml` | Definição atual da VM (backup/referência) |
| `win11.xml` | Definição da fase de instalação (com VGA, ISOs, e1000e) |
| `vm-ps.py`, `vm-put.py` | Comandos e arquivos no Windows via guest agent |
| `verify-after-reboot.sh`, `test-dynamic.sh`, `test-follow.sh`, `diag-portfwd.sh` | Diagnóstico |
| `dump-vbios.sh`, `check-vbios.py`, `acpi/` | Investigação do vBIOS. `acpi/` tem o DSDT e os SSDTs do notebook, sem a MSDM (que guarda a chave do Windows) |
| `limine.diff` | Registro da mudança no `/etc/default/limine` |
| `looking-glass.tmpfiles` | **Obsoleto:** regra do `/dev/shm`, substituída pelo kvmfr |
| `build-kvmfr.sh` | **Não usado:** o kvmfr foi instalado pelo gerenciador de pacotes |

## Solução de problemas

**A VM não liga ("dGPU still in use").** Algum programa está com a NVIDIA aberta. A janela de
erro do `win11-vm` mostra a saída do `nvidia-users`: feche o que aparecer como `FECHAR` e tente de
novo. Apps Electron/Chromium também abrem a NVIDIA sozinhos: o app do ChatGPT/Codex, por exemplo,
abre com o processo `on_device_model`. O histórico fica em `journalctl -t vfio-dgpu`.

**Depois de um reboot, o desktop não aparece.** Pode ser o `KWIN_DRM_DEVICES` apontando para um
`/dev/dri/igpu` que não existe. Aperte Ctrl+Alt+F3, entre no terminal, rode o comando abaixo e
reinicie:

```bash
rm ~/.config/environment.d/90-kwin-igpu.conf
```

**Looking Glass sem imagem:**
- confira `ls -l /dev/kvmfr0` (deve ser `johannes kvm`);
- confira o log do host no Windows:
  `./vfio/vm-ps.py "Get-Content 'C:\ProgramData\Looking Glass (host)\looking-glass-host.txt' -Tail 30"`;
- o cliente e o host precisam ser da mesma versão (B7).

**A janela do Looking Glass pisca.** Confira se `looking-glass-client` continua no `ignoreClass` do
Krohnkite (um update do script pode resetar a configuração) e se `doubleBuffer=yes` está no
`client.ini`.

**O Sunshine do Linux reinicia em loop.** Confira se o drop-in está ativo:
`systemctl --user cat app-dev.lizardbyte.app.Sunshine.service` deve mostrar
`ExecStart=%h/.local/bin/sunshine-gpu`.

**O Sunshine trava em loop com a VM ligada ("Couldn't initialize va display").** O pacote
`sunshine` 2026.1015 do CachyOS traz a `libva` embutida, procurando os drivers em
`/home/runner/work/build-deps/build-deps/build/libva/lib/dri`. Como o binário tem *capabilities*,
a `libva` ignora `LIBVA_DRIVERS_PATH`. Sem VAAPI, o Sunshine tenta o codificador Vulkan e trava no
`libvulkan_intel`. O contorno, `vfio/install-sunshine-libva-fix.sh`, cria esse caminho como link para
`/usr/lib/dri`. Quando o pacote for corrigido, apague `/home/runner`. Desde essa versão, o hook
também religa o Sunshine se ele estiver "failed" quando a VM desliga.

**Um serviço não volta depois de uma troca ("start-limit-hit").** O hook já zera o limite antes
dos reinícios dele. Se acontecer por outro motivo, rode
`systemctl --user reset-failed app-dev.lizardbyte.app.Sunshine.service` (ou
`sudo systemctl reset-failed nvidia-powerd.service`) e inicie de novo.

**O papel de parede some ou para.** `systemctl --user status app-org.waywallen.waywallen@autostart.service`
e `sudo ./vfio/test-follow.sh` mostram em que GPU o renderizador está.

**O Moonlight não conecta no `win11`:**
- a VM está ligada?
- use o IP da rede em que o aparelho do Moonlight está;
- `sudo ./vfio/diag-portfwd.sh` mostra se as conexões chegam (DNAT) e são repassadas (ACCEPT);
- depois de `systemctl restart libvirtd` com a VM ligada, o libvirt recria as cadeias de firewall
  dele e o hook (`reconnect`) deveria recolocar as regras. Isso não foi testado; se faltarem, rode
  `sudo win11-portfwd add`.

**Code 43 no Windows** (hoje não acontece). Se aparecer depois de alguma atualização, o plano B é
extrair o vBIOS pelo GPU-Z num Windows real e passá-lo à VM com `romfile`.

**Depois de atualizar o kernel:**
- `dkms status looking-glass` deve listar o kernel novo como `installed`. O DKMS só compila se os
  headers do kernel estiverem instalados;
- rode `./vfio/verify-after-reboot.sh`.

## Como desfazer

Do mais simples para o mais profundo. Os comandos de sistema precisam de sudo.

- **Sunshine do Windows acessível de fora:** apague `/usr/local/bin/win11-portfwd` e o bloco
  `if [[ $vm == win11 ]]` do hook.
- **Sunshine do Linux:**
  - apague o drop-in `gpu-encoder.conf` e rode `systemctl --user daemon-reload`;
  - restaure `~/.config/sunshine/sunshine.conf.bak-20261013`.
- **waywallen sempre na Intel** (sem seguir a GPU, para a NVIDIA poder dormir):
  - em `~/.local/bin/waywallen-gpu`, deixe só o ramo da Intel (`render_node` na Intel e
    `FLATPAK_GL_DRIVERS=default`), e reinicie o waywallen. O hook continua funcionando: como ele não
    segura mais a NVIDIA, não é fechado nas trocas;
  - para tirar o lançador de vez: apague o drop-in `gpu.conf` do autostart do waywallen e rode
    `systemctl --user daemon-reload`. Nesse caso, a extensão `GL.nvidia` do Flatpak volta a fazer o
    waywallen abrir a NVIDIA.
- **Krohnkite:** restaure `~/.config/kwinrc.bak-20261013`.
- **kvmfr:**
  - volte a VM para `<shmem>` (o oposto do `apply-kvmfr.py`) e o `client.ini` para
    `/dev/shm/looking-glass`;
  - remova os arquivos `kvmfr` de `/etc/modprobe.d`, `/etc/modules-load.d` e `/etc/udev/rules.d`;
  - restaure `/etc/libvirt/qemu.conf.bak-20261013`;
  - desinstale `looking-glass-module-dkms`.
- **VM:** `virsh -c qemu:///system undefine win11 --nvram`. O disco fica em
  `/var/lib/libvirt/images/win11.qcow2` até você apagá-lo.
- **GPU dinâmica:**
  - remova `/etc/libvirt/hooks/qemu`, `/usr/local/bin/vfio-dgpu` e `/etc/modprobe.d/vfio.conf`;
  - reinicie o libvirtd.
- **Ordem das GPUs:** remova `/etc/modprobe.d/igpu-first.conf` e rode `sudo limine-update`.
- **KWin:** remova `~/.config/environment.d/90-kwin-igpu.conf` e
  `/etc/udev/rules.d/61-dri-igpu.rules`.
- **Boot:**
  ```bash
  sudo cp -a /etc/default/limine.bak-20261013 /etc/default/limine && sudo limine-update
  ```
  Isso volta o zram também.

## Diferenças em relação ao Omarchy

| | Omarchy (PR #3454, não integrado) | Aqui |
|---|---|---|
| Desktop | Hyprland + UWSM | KDE Plasma (KWin preso à Intel via `environment.d`) |
| VM | Container Docker `dockurr/windows` | libvirt, com virt-manager |
| GPU sem saída de vídeo | Não trata: precisa de monitor ou dummy plug | Virtual Display Driver no Windows |
| Code 43 em GPU de notebook | Não trata | Bateria falsa + subsystem IDs |
| Troca da GPU | No boot, ou "modo híbrido" | Sempre dinâmica, pelo hook, com checagem de quem usa a GPU |
| Ordem das GPUs / programas que abrem a "primeira GPU" | Não trata | i915 sempre primeiro (regra `install`) |
| Limite de 39 bits (Intel 12/13ª geração) | `host-phys-bits-limit=39` no compose | `maxphysaddr limit=39` no libvirt |
| Looking Glass | kvmfr | kvmfr com DMA-BUF |
| Streaming | — | Sunshine no Linux (troca de codificador automática) e no Windows (redirecionamento de portas) |
