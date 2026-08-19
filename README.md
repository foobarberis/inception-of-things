# Inception of Things

## Contents

- [Overview](#overview)
- [Setup](#setup)
- [Part 1 — K3s and Vagrant](#part-1--k3s-and-vagrant)
- [Part 2 — K3s and three applications](#part-2--k3s-and-three-applications)
- [Part 3 — K3d and Argo CD](#part-3--k3d-and-argo-cd)

## Overview

Inception of Things is a 42 systems administration project about virtual
machine provisioning, Kubernetes networking, and GitOps. The mandatory parts
run inside an outer Debian VM named `iot-vm`.

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
`iot-vm`. Parts 1 and 2 create **nested VMs** inside the outer VM. Keeping
these terms distinct is important, especially for the Part 3 GitOps test.

## Setup

### Physical-host prerequisites

The physical host needs x86-64 KVM access, QEMU, curl, xorriso, and OpenSSH.
On a Debian-based host, install them with:

```sh
sudo apt install qemu-system-x86 qemu-utils curl xorriso openssh-client
```

The host user must be able to read and write `/dev/kvm`; the launcher checks
this before it creates VM state.

### Start and access the outer VM

For the first launch, provide the public half of the SSH key registered for
your account:

```sh
SSH_KEY="$(cat "$HOME/.ssh/id_ed25519.pub")" ./setup/launch-vm.sh
```

The launcher downloads a pinned Debian image, creates a 20 GiB copy-on-write
disk and cloud-init seed in `~/goinfre/iot-vm`, and authorizes the key for
`mbernard`. Later launches reuse that state and can run without `SSH_KEY`.
Keep the QEMU console open.

From a second terminal on the physical host, connect to the outer VM with the
matching private key:

```sh
ssh -i "$HOME/.ssh/id_ed25519" -p 2222 \
  -o IdentitiesOnly=yes \
  -o UserKnownHostsFile=/dev/null \
  -o StrictHostKeyChecking=no \
  mbernard@localhost
```

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

Vagrant asks libvirt to create both VMs, then provisions K3s on the server.
The worker receives the shared token and joins the same cluster.

### Run

Inside the outer VM, run this from `~/inception-of-things/p1`:

```sh
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

Run this command before starting Part 2. It removes both nested VMs and frees
their resources.

## Part 2 — K3s and three applications

Part 2 uses one nested VM, `mbernardS`, at `192.168.56.110`. It runs a K3s
server and three web applications. Before starting it, complete Part 1's
Destroy step.

### Tools and flow

- **Vagrant** describes the nested VM, while **libvirt** creates, runs, and
  networks it as in Part 1. Together, they provide a reproducible VM
  environment without manually configuring a hypervisor.
- **K3s** supplies Kubernetes in that VM. Kubernetes maintains the desired
  state declared by the Deployments, Services, and Ingress; K3s also includes
  **Traefik**, the Ingress controller used in this part.
- A Kubernetes **Deployment** keeps a requested number of application Pods
  running. App 1 and App 3 have one replica each; App 2 has three.
- A Kubernetes **Service** gives each set of Pods a stable internal endpoint.
- A **ConfigMap** stores each application's HTML template.
- An **Ingress** is a routing rule. Traefik reads `apps-ingress` and sends
  requests with `Host: app1.com` to App 1 and `Host: app2.com` to App 2. Its
  catch-all rule sends every other host to App 3.

The provisioner installs K3s, waits for Traefik, creates the ConfigMaps, and
applies the Deployments, Services, and Ingress. Traefik then routes incoming
HTTP requests to the appropriate Service.

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

### Destroy

From the same directory, run:

```sh
vagrant destroy -f
```

Run this command before starting Part 3. It removes the nested VM and its K3s
cluster.

## Part 3 — K3d and Argo CD

Part 3 replaces nested VMs with an `iot-p3` K3d cluster running in Docker. It
creates the `argocd` and `dev` namespaces, then deploys `wil-playground` to
`dev` from a separate public GitHub repository. Before starting it, complete
Part 2's Destroy step.

### Tools and flow

- **Docker** runs containers on the outer VM. In this part, those containers
  become the K3d cluster nodes.
- **K3d** creates a K3s cluster inside Docker. K3s provides Kubernetes—the
  control plane and worker-node functions that keep declared cluster resources
  running—without creating additional VMs.
- **kubectl** manages and inspects the K3d cluster.
- **Traefik** is the cluster's web entry point. It exposes the application and
  the Argo CD web interface through ports forwarded by QEMU to the physical
  host.
- **Argo CD** is a GitOps continuous-delivery controller. Its `Application`
  resource observes the GitHub repository and reconciles the cluster so that
  the `dev` namespace matches the Kubernetes manifests stored there.
- **GitHub** stores the desired deployment manifest. Updating its image tag is
  the remote change that Argo CD synchronizes.
- **Docker Hub** stores the application's versioned images:
  `wil42/playground:v1` and `wil42/playground:v2`.

The `Application` tracks `https://github.com/melobern/mbernard-iot` at `HEAD`.
Argo CD applies its root-level manifests to `dev`; Kubernetes then pulls the
image named by the manifest from Docker Hub. The initial manifest uses `v1`.

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

The installer installs `kubectl` and K3d when needed, creates the cluster,
installs Argo CD, and applies the Argo CD `Application` and Ingress.

### Test

From the project root in the outer VM, run:

```sh
./p3/scripts/validate.sh
```

The validator waits for Argo CD to synchronize, displays the required
namespaces and application Pod, and checks that the application returns the
initial `v1` response.

### Destroy

From the outer VM, run:

```sh
k3d cluster delete iot-p3
```

This removes the Part 3 cluster. Docker remains installed for a later run.

### Demonstrate a remote GitOps version change

Do this test on the **physical host**, not in the outer VM. The physical host
pushes a change to GitHub; Argo CD in the outer VM then fetches that remote
change and reconciles the cluster. This demonstrates that the update does not
come from a local manifest change inside the cluster.

The physical host needs GitHub credentials authorized to push to
`melobern/mbernard-iot`. The following commands modify that separate GitOps
repository, not this project checkout:

```sh
git clone https://github.com/melobern/mbernard-iot.git ~/p3-gitops
cd ~/p3-gitops
grep -F 'wil42/playground:v1' deployment.yaml
sed -i 's/wil42\/playground:v1/wil42\/playground:v2/g' deployment.yaml
git add deployment.yaml
git commit -m 'Deploy playground v2'
git push
```

On the physical host, open <https://localhost:8086> to watch the Argo CD
application synchronize. Sign in as `admin` with the initial password obtained
from the command printed by the installer. If automated synchronization has
not happened yet, use **Refresh** and then **Sync** in the Argo CD interface.

Finally, still on the physical host, verify the externally reachable
application:

```sh
curl -sS http://localhost:8888/
```

It should return:

```json
{"status":"ok", "message": "v2"}
```

Return the GitOps manifest to `v1` after the demonstration if you need the
initial Part 3 test to remain reproducible.
