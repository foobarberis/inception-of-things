# Inception of Things

## Table of contents

- [Introduction](#introduction)
- [Stack Overview](#stack-overview)
- [Setup](#setup)
- [Part 1](#part-1)
- [Part 2](#part-2)
- [Part 3](#part-3)

## Introduction

Inception of Things is a 42 system-administration project about VM
provisioning, Kubernetes networking, and GitOps. Each part runs in one outer
Debian VM named `iot-vm`.

- **Part 1** provisions a two-node K3s cluster.
- **Part 2** deploys three applications and routes them by HTTP `Host` header.
- **Part 3** deploys an application to K3d through Argo CD GitOps.

## Stack Overview

```text
Physical host
└── QEMU/KVM
    └── outer Debian VM: iot-vm
        ├── cloud-init: first-boot user, packages, and groups
        ├── Parts 1/2: Vagrant/libvirt → nested VMs → K3s
        │                              └── Part 2: Traefik → app1/app2/app3
        └── Part 3: Docker → K3d (K3s)
                              ├── Traefik → Argo CD ingress
                              └── Argo CD → dev workload

GitHub:    melobern/mbernard-iot ──→ Argo CD Application ──→ Kubernetes manifests
Docker Hub: wil42/playground:v1|v2 ────────────────────────→ Part 3 workload image
```

QEMU/KVM isolates and accelerates the outer VM; cloud-init creates `mbernard`
and installs its nested-virtualization prerequisites on first boot. Parts 1 and
2 use Vagrant to define libvirt-managed nested guests, where K3s runs directly.
Part 3 has no nested Vagrant guests: Docker hosts K3d, which runs K3s in
containers. `kubectl` is the CLI used to inspect each K3s cluster.

Traefik is the K3s ingress controller used for Part 2 routing and the Part 3
Argo CD ingress. In Part 3, Argo CD watches the GitHub configuration repository
and reconciles its manifests; the deployed application image is pulled from
Docker Hub.

## Setup

### Prerequisites (physical host)

The host needs x86-64 KVM access, QEMU, curl, xorriso, and OpenSSH. On a
Debian-based host:

```sh
sudo apt install qemu-system-x86 qemu-utils curl xorriso openssh-client
```

`/dev/kvm` must be readable and writable by the host user; the launcher checks
this before it creates VM state.

### Start the outer VM (physical host)

From the repository root:

```sh
./setup/launch-vm.sh
```

On first launch, the script downloads a pinned Debian image to `~/goinfre`,
creates a 20 GB copy-on-write disk, SSH key, and cloud-init seed under
`~/goinfre/iot-vm`, then starts QEMU. Later launches reuse that state. The QEMU
console stays attached to this terminal.

In a second **physical-host** terminal, connect to the outer VM:

```sh
ssh -i "$HOME/goinfre/iot-vm/id_ed25519" -p 2222 \
  -o IdentitiesOnly=yes \
  -o UserKnownHostsFile=/dev/null \
  -o StrictHostKeyChecking=no \
  mbernard@localhost
```

Inside the **outer VM**, wait for first boot to finish:

```sh
cloud-init status --wait
```

Cloud-init adds `mbernard` to `kvm` and `libvirt`. If the SSH session was open
before that completed, reconnect before using Vagrant.

### Clone the project (outer VM)

Clone to the outer VM's local disk; Parts 1 and 2 export this checkout through
NFS to their nested guests.

```sh
git clone https://github.com/foobarberis/inception-of-things.git ~/inception-of-things
```

### Outer VM lifecycle

| Action | Command | Effect |
| --- | --- | --- |
| Graceful stop (**outer VM**) | `sudo poweroff` | Stops the guest and releases its CPU/RAM allocation. |
| Start or restart (**physical host**) | `./setup/launch-vm.sh` | Reuses the disk, key, and cloud-init state. |
| Force-stop (**QEMU console**) | `Ctrl-a`, then `x` | Immediately quits QEMU; use only if graceful shutdown is unavailable. |
| Destroy VM state (**physical host**, after QEMU stops) | `rm -rf "$HOME/goinfre/iot-vm"` | Removes the overlay disk, seed, and SSH key. The base image remains cached. |
| Remove the cached base image too (**physical host**) | `rm -f "$HOME"/goinfre/debian-13-generic-amd64-*.qcow2` | Frees the image cache; the next launch downloads it again. |

Closing SSH only disconnects the client. Halt nested Vagrant guests before
powering off the outer VM when a graceful shutdown of the whole lab is wanted.

## Part 1

### Layout

Part 1 uses the `cloud-image/debian-13` box and `p1_network`
(`192.168.56.0/24`). The outer VM exports `~/inception-of-things/p1` over NFS
as `/vagrant` in both guests. The server writes its K3s join token to
`/vagrant/node-token`; the worker reads it from the same share.

| Nested VM | K3s role | Private IP | Resources |
| --- | --- | --- | --- |
| `mbernardS` | Server, control plane, and `kubectl` | `192.168.56.110` | 1 vCPU, 1024 MiB |
| `mbernardSW` | Agent (worker) | `192.168.56.111` | 1 vCPU, 512 MiB |

### Provision (outer VM)

```sh
cd ~/inception-of-things/p1
vagrant up --provider=libvirt
```

The first run downloads the box, creates and NFS-mounts both guests, then
provisions the server followed by the worker. Later `vagrant up` commands only
start existing guests.

### Validate (outer VM)

The validator resolves its own directory, so it can run from anywhere:

```sh
bash ~/inception-of-things/p1/scripts/validate.sh
```

It prints Vagrant state, each guest's hostname, private address and K3s service,
then the node and system-pod lists. After provisioning, expect both guests to
be running, `k3s`/`k3s-agent` to be active, and two `Ready` nodes:
`mbernards` and `mbernardsw`. It does not wait for readiness, so run it after
provisioning completes.

For interactive nested-VM access during a defense, run these from
`~/inception-of-things/p1` in the **outer VM**:

```sh
vagrant ssh mbernardS
vagrant ssh mbernardSW
```

### Lifecycle and cleanup (outer VM)

Run these from `~/inception-of-things/p1`:

| Action | Command | Effect |
| --- | --- | --- |
| Show state | `vagrant status` | Shows both guest states and their provider. |
| Stop both guests | `vagrant halt` | Gracefully stops the guests while retaining disks and configuration. |
| Restart halted guests | `vagrant up --provider=libvirt` | Starts existing guests without provisioning again. |
| Re-run provisioning | `vagrant provision` | Re-runs the installers; use deliberately. |
| Destroy both guests | `vagrant destroy -f` | Deletes the nested guests and their disks. |
| Remove a stale join token after destruction | `rm -f node-token` | Clears the ignored shared token before a clean retry. |

For a clean rebuild:

```sh
vagrant destroy -f
rm -f node-token
vagrant up --provider=libvirt
./scripts/validate.sh
```

Destroying Part 1 frees nested-guest resources. Power off the outer VM as
[described above](#outer-vm-lifecycle) to release its 8 GiB allocation too.

## Part 2

### Layout

Part 2 is independent from Part 1 and uses one libvirt guest on `p2_network`
(`192.168.56.0/24`). `mbernardS` has 1 vCPU, 2048 MiB, and
`192.168.56.110`; it runs the K3s server, Traefik, and all three applications.
The provisioner mounts `p2` at `/vagrant`, creates the application ConfigMaps
from `confs/app*/index.html`, and applies the deployments, services, and
Ingress.

| Request `Host` header | Service selected by Traefik | Replicas |
| --- | --- | --- |
| `app1.com` | `app1-svc` | 1 |
| `app2.com` | `app2-svc` | 3 |
| Any other host | `app3-svc` | 1 |

The hostless Ingress rule is the fallback, so an unmatched host reaches app3.

### Provision (outer VM)

If Part 1 is running, halt it first to free nested-VM resources:

```sh
cd ~/inception-of-things/p1 && vagrant halt
```

Then provision Part 2:

```sh
cd ~/inception-of-things/p2
vagrant up --provider=libvirt
```

The first run creates and mounts the guest, installs K3s, waits for Traefik,
and deploys the applications. Later `vagrant up` commands only start it.

### Validate (outer VM)

```sh
bash ~/inception-of-things/p2/scripts/validate.sh
```

The validator prints the VM, node, workload, and Ingress details, then requests
all three routes. Expect one `Ready` node, app1 and app3 at `1/1`, app2 at
`3/3`, and these markers; the route requests fail the script if a marker is
missing:

```text
Hello from app1.
Hello from app2.
Hello from app3.
```

For a focused ingress inspection during a defense or while troubleshooting,
run this in the **outer VM**:

```sh
cd ~/inception-of-things/p2
vagrant ssh mbernardS -c 'kubectl describe ingress apps-ingress'
```

### Browser access (physical host)

The physical host cannot directly reach the nested libvirt address. Keep the
outer VM and Part 2 guest running, then use two **physical-host** terminals.
The first tunnel reaches Traefik through the outer VM; `18088` avoids QEMU's
existing host mapping for port `8888`.

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

In the second terminal, from a checkout containing `utils`, start the local
header-injecting proxy:

```sh
python3 utils/launch_proxy_from_host_for_p2.py
```

| Browser URL | Injected `Host` header | Expected application |
| --- | --- | --- |
| <http://127.0.0.1:8081/> | `app1.com` | app1 |
| <http://127.0.0.1:8082/> | `app2.com` | app2 |
| <http://127.0.0.1:8083/> | fallback | app3 |

The tunnel and proxy bind only to loopback. Stop each with `Ctrl-C` when done.

### Lifecycle and cleanup (outer VM)

Run these from `~/inception-of-things/p2`:

| Action | Command | Effect |
| --- | --- | --- |
| Show state | `vagrant status` | Shows the guest state and provider. |
| Stop | `vagrant halt` | Gracefully stops the nested VM. |
| Restart | `vagrant up --provider=libvirt` | Starts the existing VM without provisioning again. |
| Re-provision | `vagrant provision` | Runs the K3s and application installer again. |
| Clean rebuild | `vagrant destroy -f && vagrant up --provider=libvirt` | Recreates the VM and cluster. |

## Part 3

### GitOps layout

Part 3 replaces the nested Vagrant guests with the `iot-p3` K3d cluster inside
Docker. `p3/confs/argocd.yaml` creates the `wil-playground` Argo CD
`Application`: it tracks `https://github.com/melobern/mbernard-iot` at `HEAD`,
applies its root-level manifests to `dev`, and enables automated sync, pruning,
and self-healing. The initial workload image is `wil42/playground:v1`; the
GitOps update changes it to `v2`.

The installer maps outer-VM port `8888` to K3d's load balancer on `8888` and
outer-VM port `8086` to its port `443`. QEMU forwards physical-host ports
`8888` and `8086` to the matching outer-VM ports, so the application and Argo
CD are available at the URLs below.

### Install (outer VM)

Part 3 does not use Vagrant. If either earlier part is running, halt it first:

```sh
cd ~/inception-of-things/p1 && vagrant halt
cd ~/inception-of-things/p2 && vagrant halt
```

Install Docker as the normal VM user. Do **not** run this script through
`sudo`: it adds the current user to the `docker` group.

```sh
cd ~/inception-of-things
./p3/scripts/docker.sh
```

Disconnect and reconnect to the outer VM so the new group membership applies.
Then confirm Docker works without `sudo` and install the cluster and Argo CD:

```sh
cd ~/inception-of-things
docker run --rm hello-world
./p3/scripts/install.sh
```

The installer installs `kubectl` and K3d when needed, creates `iot-p3` if it
does not exist, creates `argocd` and `dev`, installs Argo CD, and applies the
Application and Argo CD Ingress. Downloading images and waiting for the Argo CD
server can take up to five minutes.

### Validate (outer VM)

```sh
bash ~/inception-of-things/p3/scripts/validate.sh
```

The validator exports the K3d kubeconfig, lists namespaces, waits up to five
minutes for `wil-playground` to become `Synced`, then displays the Application
and `dev` pods and queries the application endpoint. Expected output includes a
`Synced`/`Healthy` application, one running pod, and:

```json
{"status":"ok", "message": "v1"}
```

For a cluster-level defense check not included in the validator, run in the
**outer VM**:

```sh
export KUBECONFIG="$HOME/.kube/config"
kubectl get nodes -o wide
```

### Access Argo CD (physical host)

Retrieve the generated initial password in the **outer VM**:

```sh
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

On the **physical host**, open <https://localhost:8086> and log in as `admin`
with that password. A certificate warning is expected because Traefik uses its
default certificate. The application is available at
<http://localhost:8888/>.

### Test the GitOps version change

This modifies the separate GitOps repository, not this project checkout. In the
**outer VM** (or another machine with an identity authorized to push to
`melobern/mbernard-iot`):

```sh
cd ~
git clone https://github.com/melobern/mbernard-iot.git p3-gitops
cd ~/p3-gitops
grep -F 'wil42/playground:v1' deployment.yaml
sed -i 's/wil42\/playground:v1/wil42\/playground:v2/g' deployment.yaml
git add deployment.yaml
git commit -m 'Deploy playground v2'
git push origin main
```

Automated sync normally applies the revision shortly afterward. If it does not,
refresh the Application and use **Sync** in the Argo CD UI. Then verify the new
image and response in the **outer VM**:

```sh
kubectl get deployment wil-playground -n dev \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
kubectl rollout status deployment/wil-playground -n dev --timeout=180s
curl -sS http://localhost:8888/
```

The image should be `wil42/playground:v2` and the endpoint should return:

```json
{"status":"ok", "message": "v2"}
```

### Lifecycle and cleanup (outer VM)

| Action | Command | Effect |
| --- | --- | --- |
| Show state | `k3d cluster list` | Lists `iot-p3` and its state. |
| Stop | `k3d cluster stop iot-p3` | Stops Docker containers while retaining cluster state. |
| Restart | `k3d cluster start iot-p3` | Starts a stopped cluster. |
| Re-apply setup | `~/inception-of-things/p3/scripts/install.sh` | Reapplies namespaces, Argo CD configuration, and the Application to a running cluster. |
| Clean rebuild | `k3d cluster delete iot-p3 && ~/inception-of-things/p3/scripts/install.sh` | Deletes and recreates the K3d cluster; Docker remains installed. |
