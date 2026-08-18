# Inception of Things

## Table of contents

- [Introduction](#introduction)
- [Setup](#setup)
- [Part 1](#part-1)
- [Part 2](#part-2)
- [Part 3](#part-3)

## Introduction

Inception of Things is a 42 system-administration project that progressively
introduces virtual-machine provisioning, Kubernetes, networking, and GitOps.

- **Part 1** creates a two-node K3s cluster with Vagrant.
- **Part 2** runs three applications in K3s and routes requests by `Host`
  header.
- **Part 3** uses K3d and Argo CD to deploy an application through GitOps.

All parts run inside one outer Debian VM. QEMU/KVM isolates that VM from the
host; cloud-init prepares it on first boot. Parts 1 and 2 use
Vagrant/libvirt to create further nested guests, while Part 3 uses Docker,
K3d, and Argo CD inside the same outer VM.

## Setup

### Architecture and tools

```text
Host machine
└── QEMU/KVM
    └── outer Debian VM: iot-vm (8 GiB RAM, 4 vCPUs)
        ├── cloud-init: first-boot user and package setup
        ├── ~/inception-of-things: local project clone
        ├── Part 1 and Part 2: Vagrant + libvirt guests
        └── Part 3: Docker + K3d + Argo CD
```

| Tool | Role |
| --- | --- |
| QEMU/KVM | Runs the isolated outer Debian VM and provides hardware-accelerated nested virtualization. |
| cloud-init | Creates `mbernard`, installs the outer VM dependencies, and grants `kvm`/`libvirt` access on first boot. |
| Git | Places the project on the outer VM's local filesystem. |
| Vagrant/libvirt | Used by Parts 1 and 2 to define and manage reproducible nested VMs. |
| Docker, K3d, Argo CD | Used by Part 3; its workflow is documented later. |

### Host prerequisites

The host needs x86-64 KVM access, QEMU, curl, xorriso, and OpenSSH. On a
Debian-based host:

```sh
sudo apt install qemu-system-x86 qemu-utils curl xorriso openssh-client
```

`/dev/kvm` must be readable and writable by the host user. The launcher checks
this before creating VM state.

### Start the outer VM

All commands in this subsection run on the **host**.

From the repository root:

```sh
./setup/launch-vm.sh
```

On first launch, the script downloads a pinned Debian base image into
`~/goinfre`, creates a 20 GB copy-on-write disk and dedicated SSH key under
`~/goinfre/iot-vm`, renders a cloud-init seed, and starts QEMU. Later runs
reuse that state and simply restart the same outer VM.

The QEMU console remains attached to the terminal. Use a second terminal to
connect to the outer VM:

```sh
ssh -i "$HOME/goinfre/iot-vm/id_ed25519" -p 2222 \
  -o IdentitiesOnly=yes \
  -o UserKnownHostsFile=/dev/null \
  -o StrictHostKeyChecking=no \
  mbernard@localhost
```

Inside the outer VM, wait for first-boot installation to finish:

```sh
cloud-init status --wait
```

Cloud-init adds `mbernard` to the `kvm` and `libvirt` groups. If the SSH session
was opened before that completed, exit and reconnect before using Vagrant.

### Put the project on the outer VM

Clone the repository **inside** the outer VM, on its local disk:

```sh
git clone https://github.com/foobarberis/inception-of-things.git ~/inception-of-things
```

### Stop, restart, and destroy the outer VM

| Action | Command | Effect |
| --- | --- | --- |
| Stop gracefully | Inside the outer VM: `sudo poweroff` | Stops the guest and releases the outer VM's CPU/RAM allocation. |
| Start or restart | On the host: `./setup/launch-vm.sh` | Reuses the existing disk, key, and cloud-init state. |
| Force-stop | At the QEMU console: `Ctrl-a`, then `x` | Immediately quits QEMU; use only if graceful shutdown is unavailable. |
| Destroy VM state | On the host, after QEMU has stopped: `rm -rf "$HOME/goinfre/iot-vm"` | Removes the overlay disk, seed, and SSH key. The cached base image remains. |
| Remove the cached base image too | On the host: `rm -f "$HOME"/goinfre/debian-13-generic-amd64-*.qcow2` | Frees the base-image cache; the next start downloads it again. |

Closing an SSH session only disconnects the client; it does **not** stop the
outer VM. Halt nested Vagrant guests before powering off the outer VM when you
want a graceful shutdown of the whole lab.

## Part 1

### Architecture

Part 1 uses the `cloud-image/debian-13` Vagrant box and the libvirt provider to
build a two-node K3s cluster.

```text
outer VM: ~/inception-of-things/p1
├── NFS export
│   └── /vagrant in both nested guests
└── libvirt network: p1_network (192.168.56.0/24)
    ├── mbernardS   (1 vCPU, 1024 MiB, 192.168.56.110)
    │   └── K3s server: control plane and kubectl
    └── mbernardSW  (1 vCPU, 512 MiB, 192.168.56.111)
        └── K3s agent: worker node
```

The NFS share is the outer VM's local `p1` directory. The server writes its
K3s join token to `/vagrant/node-token`; the worker reads that same file and
joins the cluster. 

| Tool | Role in Part 1 |
| --- | --- |
| Vagrant | Reads `p1/Vagrantfile`, provisions both guests, and provides passwordless `vagrant ssh` access. |
| libvirt/QEMU | Runs the nested Debian guests and the `p1_network` private network. |
| NFS | Makes the outer VM's local `p1` directory available at `/vagrant` in both guests. |
| K3s | Runs the Kubernetes control plane on `mbernardS` and the agent on `mbernardSW`. |
| kubectl | Inspects the K3s cluster from the server. |

### Start and provision

Run these commands **inside the outer VM**:

```sh
cd ~/inception-of-things/p1
vagrant up --provider=libvirt
```

`Vagrantfile` already sets libvirt as its default provider, so `vagrant up`
also works. The explicit provider flag makes the intended provider clear.

On first use, Vagrant downloads the box, creates both guests, mounts the local
`p1` directory over NFS, runs the server provisioner, and then runs the worker
provisioner. The worker waits for the server's token before joining K3s.

### Validate

The script resolves its own `p1` directory, so it can be launched from any
working directory in the outer VM:

```sh
bash ~/inception-of-things/p1/scripts/validate.sh
```

It is a display-oriented checklist: it prints the Vagrant state, each guest's
hostname, private address and K3s service state, followed by the node and
system-pod lists. Inspect the output for both running guests, both expected IP
addresses, active services, and two `Ready` nodes. It does not poll for
readiness, so run it after provisioning has completed.

Useful interactive checks:

```sh
vagrant status
vagrant ssh mbernardS
vagrant ssh mbernardSW
vagrant ssh mbernardS -c 'kubectl get nodes -o wide'
```

The expected node result contains two `Ready` nodes. Kubernetes normalizes the
node names to lowercase (`mbernards` and `mbernardsw`):

```text
NAME         STATUS   ROLES           INTERNAL-IP
mbernards    Ready    control-plane   192.168.56.110
mbernardsw   Ready    <none>          192.168.56.111
```

### Stop, restart, and destroy

Run these commands from `~/inception-of-things/p1` inside the outer VM:

| Action | Command | Effect |
| --- | --- | --- |
| Show state | `vagrant status` | Shows both guest states and their provider. |
| Stop both guests | `vagrant halt` | Gracefully stops nested guests and frees their CPU/RAM; their disks and configuration remain. |
| Restart halted guests | `vagrant up --provider=libvirt` | Starts the existing guests without re-running provisioning. |
| Re-run provisioning | `vagrant provision` | Re-runs the installers; use deliberately, not as a normal restart. |
| Destroy both guests | `vagrant destroy -f` | Deletes the nested libvirt guests and their disks. |
| Remove the old join token after destruction | `rm -f node-token` | Removes the ignored shared token before a clean manual retry. |

For a clean Part 1 rebuild:

```sh
vagrant destroy -f
rm -f node-token
vagrant up --provider=libvirt
./scripts/validate.sh
```

Destroying Part 1 frees nested-guest resources. To also free the outer VM's
8 GiB allocation, halt or power off the outer VM as described in [Setup](#setup).

## Part 2

### Purpose and architecture

Part 2 runs three simple web applications on one K3s server and uses Traefik
Ingress rules to select an application from the HTTP `Host` header. It is
independent from Part 1: halt the Part 1 guests before starting this part to
free nested-VM resources.

```text
outer VM: ~/inception-of-things/p2
└── libvirt network: p2_network (192.168.56.0/24)
    └── mbernardS (1 vCPU, 2048 MiB, 192.168.56.110)
        ├── K3s server and Traefik Ingress controller
        ├── app1 deployment (1 nginx pod) ── app1-svc
        ├── app2 deployment (3 nginx pods) ── app2-svc
        └── app3 deployment (1 nginx pod) ── app3-svc
```

Each application serves a page from its `confs/app*/index.html` template. The
provisioner creates the ConfigMaps, deploys the nginx applications and their
ClusterIP services, then applies `confs/ingress.yaml`.

| Request `Host` header | Service selected by Traefik | Replicas |
| --- | --- | --- |
| `app1.com` | `app1-svc` | 1 |
| `app2.com` | `app2-svc` | 3 |
| Any other host | `app3-svc` | 1 |

The hostless Ingress rule is the fallback, so a request without either named
host reaches app3.

### Start and provision

Run these commands **inside the outer VM**:

```sh
cd ~/inception-of-things/p1 && vagrant halt
cd ~/inception-of-things/p2
vagrant up --provider=libvirt
```

The first `vagrant up` creates the nested VM, mounts `p2` at `/vagrant`,
installs K3s, waits for Traefik, and deploys the applications. Subsequent
`vagrant up` commands only start the existing VM.

### Test from the outer VM

The Part 2 checklist resolves its own `p2` directory, so it can be launched
from any working directory in the outer VM:

```sh
bash ~/inception-of-things/p2/scripts/validate.sh
```

It displays the VM state, hostname and private address, K3s node, deployments,
pods, services, Ingress rules, and the three expected page markers. Inspect the
output for one `Ready` node, app1 and app3 at `1/1`, app2 at `3/3`, and:

```text
Hello from app1.
Hello from app2.
Hello from app3.
```

Useful commands during a defense are:

```sh
vagrant ssh mbernardS -c 'kubectl get nodes -o wide'
vagrant ssh mbernardS -c 'kubectl get all'
vagrant ssh mbernardS -c 'kubectl get ingress -o wide'
vagrant ssh mbernardS -c 'kubectl describe ingress apps-ingress'
```

Modern Debian guests use predictable interface names such as `ens6`, rather
than `eth1`; use `ip -o -4 addr show to 192.168.56.110` to identify it.

### Test from a host web browser

The physical host cannot directly reach the nested libvirt address. A local SSH
tunnel reaches Traefik through the outer VM, and
`utils/launch_proxy_from_host_for_p2.py` exposes three loopback-only browser
ports while injecting the required `Host` header.

Keep the outer VM and Part 2 VM running, then use two terminals on the
**physical host**.

In the first terminal, create the tunnel. Port `18088` is used because the QEMU
launcher already reserves host port `8888`:

```sh
ssh -4 -N -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:18088:192.168.56.110:80 \
  -p 2222 \
  -i "$HOME/goinfre/iot-vm/id_ed25519" \
  -o IdentitiesOnly=yes \
  -o UserKnownHostsFile=/dev/null \
  -o StrictHostKeyChecking=no \
  mbernard@localhost
```

In a second terminal, from a checkout containing the `utils` directory, start
the proxy:

```sh
python3 utils/launch_proxy_from_host_for_p2.py
```

Open these URLs in the host browser:

| Browser URL | Injected `Host` header | Expected application |
| --- | --- | --- |
| <http://127.0.0.1:8081/> | `app1.com` | app1 |
| <http://127.0.0.1:8082/> | `app2.com` | app2 |
| <http://127.0.0.1:8083/> | fallback | app3 |

The proxy and tunnel bind only to loopback addresses. Stop them with `Ctrl-C`
in their respective terminals when finished.

### Stop, restart, and destroy

Run these commands from `~/inception-of-things/p2` inside the outer VM:

| Action | Command | Effect |
| --- | --- | --- |
| Show state | `vagrant status` | Shows the Part 2 guest state and provider. |
| Stop | `vagrant halt` | Gracefully stops the nested VM. |
| Restart | `vagrant up --provider=libvirt` | Starts the existing VM without provisioning again. |
| Re-provision | `vagrant provision` | Runs the K3s/application installer again. |
| Clean rebuild | `vagrant destroy -f && vagrant up --provider=libvirt` | Recreates the VM and cluster. |

## Part 3

> Documentation for Part 3 will be added later.
