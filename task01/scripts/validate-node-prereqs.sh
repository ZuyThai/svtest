#!/usr/bin/env bash
set -u

SYSCTL_FILE="${SYSCTL_FILE:-/etc/sysctl.d/99-kubernetes-cri.conf}"
EXPECTED_PAUSE_IMAGE="${EXPECTED_PAUSE_IMAGE:-registry.k8s.io/pause:3.10}"
EXPECTED_AUDIT_LOG_FILE="${EXPECTED_AUDIT_LOG_FILE:-/var/log/k8s-user-commands/audit.log}"
EXPECTED_CRI_SOCKET="${EXPECTED_CRI_SOCKET:-unix:///run/containerd/containerd.sock}"

failures=()

fail() {
  failures+=("$1")
}

check_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    fail "missing command: ${command_name}"
  fi
}

check_module() {
  local module_name="$1"
  if ! lsmod | awk '{print $1}' | grep -qx "$module_name"; then
    fail "kernel module not loaded: ${module_name}"
  fi
}

check_sysctl_file() {
  if [[ ! -f "$SYSCTL_FILE" ]]; then
    fail "sysctl file missing: ${SYSCTL_FILE}"
    return
  fi

  local key value actual
  while IFS='=' read -r key value; do
    key="$(echo "$key" | xargs)"
    value="$(echo "$value" | xargs)"
    [[ -z "$key" || "$key" == \#* ]] && continue

    actual="$(sysctl -n "$key" 2>/dev/null || true)"
    if [[ "$actual" != "$value" ]]; then
      fail "sysctl ${key}: expected ${value}, got ${actual:-<unset>}"
    fi
  done < "$SYSCTL_FILE"
}

check_no_swap() {
  if [[ "$(swapon --noheadings --show=NAME 2>/dev/null | wc -l)" -ne 0 ]]; then
    fail "swap is still active"
  fi

  if awk '($1 !~ /^#/ && $3 == "swap") { found=1 } END { exit found ? 0 : 1 }' /etc/fstab; then
    fail "uncommented swap entry remains in /etc/fstab"
  fi
}

check_containerd() {
  if ! systemctl is-active --quiet containerd; then
    fail "containerd service is not active"
  fi

  if ! systemctl is-enabled --quiet containerd; then
    fail "containerd service is not enabled"
  fi

  if [[ ! -S "${EXPECTED_CRI_SOCKET#unix://}" ]]; then
    fail "containerd CRI socket missing: ${EXPECTED_CRI_SOCKET}"
  fi

  if [[ ! -f /etc/containerd/config.toml ]]; then
    fail "containerd config missing: /etc/containerd/config.toml"
    return
  fi

  if ! grep -Eq 'SystemdCgroup[[:space:]]*=[[:space:]]*true' /etc/containerd/config.toml; then
    fail "containerd is not configured with SystemdCgroup = true"
  fi

  if ! grep -Fq "sandbox_image = \"${EXPECTED_PAUSE_IMAGE}\"" /etc/containerd/config.toml; then
    fail "containerd sandbox_image is not ${EXPECTED_PAUSE_IMAGE}"
  fi

  if grep -Eq '^disabled_plugins[[:space:]]*=.*cri' /etc/containerd/config.toml; then
    fail "containerd CRI plugin appears to be disabled"
  fi
}

check_kubernetes_tools() {
  check_command kubeadm
  check_command kubelet
  check_command kubectl

  if ! systemctl is-enabled --quiet kubelet; then
    fail "kubelet service is not enabled"
  fi
}

check_audit() {
  if ! systemctl is-active --quiet auditd; then
    fail "auditd service is not active"
  fi

  if [[ ! -f "$EXPECTED_AUDIT_LOG_FILE" ]]; then
    fail "audit command log file missing: ${EXPECTED_AUDIT_LOG_FILE}"
  fi

  if ! auditctl -l 2>/dev/null | grep -q -- 'execve'; then
    fail "audit execve rule is not loaded"
  fi

  if ! auditctl -l 2>/dev/null | grep -q -- 'execveat'; then
    fail "audit execveat rule is not loaded"
  fi
}

check_command sysctl
check_command lsmod
check_command swapon
check_command systemctl
check_command grep
check_command awk

check_module overlay
check_module br_netfilter
check_sysctl_file
check_no_swap
check_containerd
check_kubernetes_tools
check_audit

if [[ "${#failures[@]}" -gt 0 ]]; then
  echo "Kubernetes node prerequisite validation failed:" >&2
  for failure in "${failures[@]}"; do
    echo " - ${failure}" >&2
  done
  exit 1
fi

echo "Kubernetes node prerequisite validation passed."
