# Inception of Things

## Contents

- [Overview](#overview)
- [Setup](#setup)
- [Part 1 — K3s and Vagrant](#part-1--k3s-and-vagrant)
- [Part 2 — K3s and three applications](#part-2--k3s-and-three-applications)
- [Part 3 — K3d and Argo CD](#part-3--k3d-and-argo-cd)

## Overview

Inception of Things is a 42 systems administration project about virtual
machine provisioning, Kubernetes networking, and GitOps. The project runs inside
an outer Debian VM named `iot-vm`.

```text
Physical host
└── QEMU/KVM runs the outer Debian VM (`iot-vm`)
    ├── cloud-init prepares it on first boot
    ├── Parts 1 and 2: Vagrant → libvirt nested VMs → K3s
    └── Part 3: Docker → K3d → K3s
                         ├── Traefik exposes web endpoints
                         └── Argo CD reconciles GitHub manifests
```

The **physical host** is the computer running QEMU. The **outer VM** is
`iot-vm`. Parts 1 and 2 create **nested VMs** inside the outer VM.

## Setup

### Physical-host prerequisites

The physical host needs x86-64 KVM access, QEMU, curl, xorriso, OpenSSH, Git,
and Python 3 for the Part 2 browser proxy. On a Debian-based host, install them
with:

```sh
sudo apt install qemu-system-x86 qemu-utils curl xorriso openssh-client git python3
```

The host user must be able to read and write `/dev/kvm`.

### Start and access the outer VM

For the first launch, provide the public half of the SSH key registered for
your 42 account, as this will allow us to clone the project directly inside the
`iot-vm` during evaluation.

```sh
SSH_KEY="$(cat "$HOME/.ssh/id_ed25519.pub")" ./tools/launch-vm.sh
```

Keep the QEMU console open.

From a second terminal on the physical host, connect to the outer VM:

```sh
./tools/connect-vm.sh
```

The script uses `$HOME/.ssh/id_ed25519` by default. Set `SSH_KEY_PATH` to use
a different private key.

Inside the outer VM, wait for first-boot configuration to finish:

```sh
cloud-init status --wait
```

Cloud-init adds `mbernard` to the `kvm` and `libvirt` groups. Reconnect if the
SSH session was opened before that step completed.

### Clone the project

Inside the outer VM, clone the repository to its local disk. Parts 1 and 2
share this checkout with their nested VMs through NFS.

```sh
git clone https://github.com/foobarberis/inception-of-things.git ~/inception-of-things
```

## Part 1 — K3s and Vagrant

Part 1 creates a two-node K3s cluster. `mbernardS` is the K3s server at
`192.168.56.110`; `mbernardSW` is the agent at `192.168.56.111`.

### Tools and flow

- **Vagrant** builds and manages reproducible virtual-machine environments
  from a `Vagrantfile` in a single workflow. Here, it creates the two nested
  Debian VMs.
- **libvirt** is the virtualization layer behind Vagrant. Vagrant describes
  the machines in the `Vagrantfile`; libvirt actually creates and controls
  their virtual CPUs, memory, disks, private network, and lifecycle through
  KVM/QEMU. It is needed because Vagrant coordinates VM environments but is
  not a hypervisor itself.
- **NFS** shares the Part 1 directory as `/vagrant` in both VMs. The server
  writes its K3s join token there, and the worker reads it.
- **Kubernetes** is a container orchestration system. You declare the desired
  state of applications—for example, which containers should run and how many
  copies—and it schedules them, networks them, and works to keep that state
  running.
- **K3s** is a lightweight Kubernetes distribution suited to this lab. Its
  server provides the cluster control plane; its agent registers as a worker
  and runs workloads assigned by the control plane.
- **kubectl** is Kubernetes' command-line client. The server uses it to
  inspect the cluster, and the validator uses it to confirm that both nodes
  are ready.

### Run

Inside the outer VM.

```sh
cd ~/inception-of-things/p1
vagrant up
```

### Test

From the same directory, run:

```sh
./scripts/validate.sh
```

The validator checks both VM hostnames and addresses, the K3s server and agent
services, and the two ready cluster nodes.

### Destroy

From the same directory, run:

```sh
vagrant destroy -f
```

**Run this command before starting Part 2. It removes both nested VMs and frees their resources.**

## Part 2 — K3s and three applications

Part 2 uses one nested VM, `mbernardS`, at `192.168.56.110`. It runs a K3s
server and three web applications.

### Traefik and Ingress

Part 2 introduces **Traefik** and **Ingress**, which work together to make
applications inside Kubernetes reachable through HTTP.

- **Traefik** is a reverse proxy and Kubernetes Ingress controller. It listens
  for incoming HTTP requests and sends each request to the appropriate
  Kubernetes Service.
- An **Ingress** is a Kubernetes resource that declares HTTP-routing rules,
  such as matching a hostname or URL path. It does not route traffic itself:
  Traefik reads the Ingress and enforces its rules.

`ingressClassName: traefik` assigns `apps-ingress` to Traefik. Its `rules`
list declares the desired routes:

- `Host: app1.com` with any path below `/` goes to `app1-svc`.
- `Host: app2.com` with any path below `/` goes to `app2-svc`.
- The rule without a `host` field matches every other host and goes to
  `app3-svc`.

Each rule uses `path: /` with `pathType: Prefix`, so it matches `/` and every
path below it. When a request reaches `192.168.56.110:80`, Traefik reads its
`Host` header and path, selects the most specific matching Ingress rule, and
forwards the request to that rule's Service. The Service then sends it to one
of the matching application Pods. In short, the Ingress declares the routes;
Traefik enforces them.

### Run

Inside the outer VM, run this from `~/inception-of-things/p2`:

```sh
vagrant up
```

### Test

From the same directory, run:

```sh
./scripts/validate.sh
```

The validator confirms the K3s node, the three workloads and their replica
counts, the Ingress, and the responses for App 1, App 2, and the App 3
catch-all route.

#### Test in a physical-host browser

The physical host cannot directly reach the nested VM's libvirt address. Keep
the outer VM and Part 2 VM running, then create the tunnel in one
**physical-host** terminal:

```sh
./tools/tunnel-p2.sh
```

The script makes Traefik available locally at `127.0.0.1:18088`. In a second
physical-host terminal, run the proxy from the repository root:

```sh
./tools/proxy.py
```

Open these URLs in a browser on the physical host:

- <http://127.0.0.1:8081/> sends `Host: app1.com` and displays App 1.
- <http://127.0.0.1:8082/> sends `Host: app2.com` and displays App 2.
- <http://127.0.0.1:8083/> sends `Host: app3.com`, which matches no named
  rule and displays the App 3 catch-all route.

Browsers derive the `Host` header from the URL and do not normally allow a
page to set it manually. The proxy changes the header while forwarding each
local request to Traefik. Stop the tunnel and proxy with `Ctrl-C` when done.

### Destroy

From the same directory, run:

```sh
vagrant destroy -f
```

**Run this command before starting Part 3. It removes the nested VM and its K3s cluster.**

## Part 3 — K3d and Argo CD

Part 3 replaces nested VMs with an `iot-p3` K3d cluster running in Docker. The
cluster has an `argocd` namespace for Argo CD and a `dev` namespace for
`wil-playground`. Argo CD deploys that application from manifests in a separate
public GitHub repository.

### Docker, K3d, and the deployment flow

Part 3 reuses K3s, `kubectl`, and Traefik from the earlier parts. It
introduces the following tools:

- **Docker** runs containers on the outer VM. In this part, the K3d cluster
  nodes are Docker containers.
- **K3d** creates and manages the K3s cluster inside Docker, avoiding the need
  for additional VMs.
- **GitHub** stores the Kubernetes manifests that describe the desired
  application deployment.
- **Docker Hub** stores the versioned application images:
  `wil42/playground:v1` and `wil42/playground:v2`.

Traefik, introduced in Part 2, exposes the application and the Argo CD web
interface through ports forwarded by QEMU to the physical host.

### GitOps and Argo CD

**GitOps** is a deployment approach in which a Git repository is the source of
truth for the desired state of a system. Instead of changing the cluster
manually, a change is committed and pushed to Git. A controller then compares
the running cluster with the repository and reconciles the cluster to match the
committed manifests. Git history provides an auditable record of deployment
changes and makes rollback a Git change as well.

**Argo CD** is that GitOps controller in this project. It runs in the `argocd`
namespace. The `Application` in `p3/confs/argocd.yaml` tracks
<https://github.com/melobern/mbernard-iot> at `HEAD`, applies its root-level
manifests to `dev`, and enables automated synchronization, pruning, and
self-healing.

The deployment flow is:

1. Kubernetes/K3d runs the cluster.
2. Argo CD runs as Pods in the argocd namespace.
3. Argo CD watches the GitHub repository.
4. When it sees the deployment YAML, it asks the Kubernetes API to create/update resources in dev.
5. Kubernetes creates the Deployment, pulls the Docker Hub image, and runs the app Pod.

For example, changing `wil42/playground:v1` to `wil42/playground:v2` in the
GitHub manifest makes `v2` the desired state. Argo CD applies that change to
the cluster. Direct manual changes to this workload can be reverted by Argo
CD's self-healing; deployment changes should therefore be made through Git.

### One-time Docker prerequisite

Docker must be installed once in the outer VM before starting Part 3. From the
project root, run:

```sh
./p3/scripts/docker.sh
```

Disconnect and reconnect to the outer VM after this command so the new Docker
group membership applies.

### Run

Inside the outer VM, run this from the project root:

```sh
./p3/scripts/install.sh
```

The installer installs `kubectl` and K3d when needed, creates the cluster and
namespaces, installs Argo CD, and applies the `Application` and Argo CD
Ingress.

### Test

From the project root in the outer VM, run:

```sh
./p3/scripts/validate.sh
```

The validator waits for Argo CD to synchronize, lists the required namespaces
and the application Pod in `dev`, and queries the application's initial `v1`
response.

### Destroy

From the outer VM, run:

```sh
k3d cluster delete iot-p3
```

**This removes the Part 3 cluster. Docker remains installed for a later run.**

### Test a remote GitOps version change

Do this test on the **physical host**, never in the outer VM. It proves that
Argo CD obtains the version change from the remote GitHub repository rather
than from a local change in the cluster or this project checkout.

The physical host needs Git and a GitHub SSH key authorized to push to
`melobern/mbernard-iot`. From the root of this repository on the physical host,
run:

```sh
./tools/change-gitops-version.sh
```

On its first run, the script clones the separate GitOps repository to
`~/goinfre/mbernard-iot`. It detects whether `deployment.yaml` uses `v1` or `v2`,
`~/mbernard-iot`. It detects whether `deployment.yaml` uses `v1` or `v2`,
toggles the image tag, commits the change, and pushes it to GitHub. Set
`GITOPS_DIR` to use a different clone location. The script does not modify this
project checkout or apply anything directly to the cluster.

On the physical host, open <https://localhost:8086> to watch Argo CD
synchronize the new Git revision. Sign in as `admin` with the initial password
obtained from the command printed by the installer. If automated
synchronization has not happened yet, use **Refresh** and then **Sync** in the
Argo CD interface.

Finally, still on the physical host, verify the externally reachable
application:

```sh
curl -sS http://localhost:8888/
```

The response must contain the version selected by the script. From the normal
initial `v1` state, the first run selects `v2` and returns:

```json
{"status":"ok", "message": "v2"}
```

A second run toggles the manifest back to `v1`, which restores the initial
state for another demonstration.
