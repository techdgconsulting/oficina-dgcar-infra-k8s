"""Install a narrow AL2023 kubelet drop-in; never rewrite the base configuration."""
import json
import os
from pathlib import Path
import subprocess


TARGET_MAX_PODS = 17


def configure(host=Path("/host"), restart=None):
    directory = host / "etc/kubernetes/kubelet/config.json.d"
    environment = host / "etc/eks/kubelet/environment"
    if not directory.is_dir() or "--config-dir" not in environment.read_text():
        raise RuntimeError("Expected AL2023 kubelet drop-in support; node left unchanged")
    dropin = directory / "99-oficina-pod-capacity.conf"
    desired = {"apiVersion": "kubelet.config.k8s.io/v1beta1", "kind": "KubeletConfiguration", "maxPods": TARGET_MAX_PODS}
    previous = dropin.read_bytes() if dropin.exists() else None
    if previous is not None and json.loads(previous) == desired:
        print("Kubelet pod capacity already configured")
        return
    temporary = directory / ".oficina-capacity.tmp"
    temporary.write_text(json.dumps(desired) + "\n")
    os.replace(temporary, dropin)
    def restart_host():
        def enter_host():
            os.chroot(host)
            os.chdir("/")
        subprocess.run(["/usr/bin/nsenter", "--target", "1", "--mount", "--pid", "--",
                        "/usr/bin/systemctl", "restart", "kubelet"],
                       preexec_fn=enter_host, check=True, timeout=60)
    restart_action = restart or restart_host
    try:
        restart_action()
    except Exception:
        if previous is None:
            dropin.unlink()
        else:
            dropin.write_bytes(previous)
        try:
            restart_action()
        except Exception:
            print("Original drop-in restored; kubelet restart still requires attention")
        raise
    print(f"Installed kubelet drop-in: maxPods={TARGET_MAX_PODS}; EC2 unchanged")


if __name__ == "__main__":
    configure()
