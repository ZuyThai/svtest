# Task 01 - Kubernetes Node Provisioning

This directory provisions a production-ready Ubuntu 24.04 LTS Kubernetes worker node with pure Ansible. The node is prepared for `kubeadm join` against an existing cluster.

## What it configures

- Sysadmin users with generated passwords, home directories, SSH keys if provided, and sudo access.
- Hostname, `/etc/hosts`, and systemd-resolved DNS settings.
- Common production CLI/debugging tools and chrony.
- Swap disabled immediately and persistently.
- Kubernetes kernel modules and sysctl settings.
- containerd runtime with the systemd cgroup driver, Kubernetes pause image, CRI enabled, log sizing, overlayfs, and production-oriented service defaults.
- `kubelet`, `kubeadm`, and `kubectl` from `pkgs.k8s.io`.
- auditd exec logging for user and direct root sessions to `/var/log/k8s-user-commands/audit.log`.
- A validation script at `/usr/local/sbin/validate-k8s-node-prereqs`.

## Run

Run Ansible from Linux or WSL with SSH access to the target Ubuntu 24.04 node.

```bash
cd task01
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
```

Edit `inventory/hosts.ini` and `group_vars/k8s_nodes.yml`, especially:

- `ansible_host`
- `ansible_user`
- `k8s_node_hostname`
- `kubernetes_minor_version`
- DNS servers and `sysadmin_users`

Provision the node:

```bash
ansible-playbook site.yml
```

Generated sysadmin passwords are stored on the Ansible controller under:

```text
task01/generated_passwords/<inventory-host>/<username>
```

That directory is intentionally ignored by git.

## Validate

The provisioning playbook runs validation by default. You can also rerun it:

```bash
ansible-playbook validate.yml
```

Or on the target node:

```bash
sudo /usr/local/sbin/validate-k8s-node-prereqs
```

The script exits non-zero and prints each failed prerequisite if any kernel setting, swap state, containerd setting, Kubernetes package, or audit rule is incorrect.

## Join existing cluster

After provisioning, use the join command from the existing control plane and pass the containerd CRI socket explicitly:

```bash
sudo kubeadm join <control-plane-endpoint>:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --cri-socket unix:///run/containerd/containerd.sock
```

## Audit log

Command execution audit events are written to:

```text
/var/log/k8s-user-commands/audit.log
```

Useful queries:

```bash
sudo ausearch -if /var/log/k8s-user-commands/audit.log -k user-commands
sudo ausearch -if /var/log/k8s-user-commands/audit.log -k root-commands
```

