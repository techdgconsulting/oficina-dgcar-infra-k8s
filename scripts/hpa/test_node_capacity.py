import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock

spec = importlib.util.spec_from_file_location("capacity", Path(__file__).parents[2] / "terraform/node-pod-capacity.py")
capacity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capacity)


class NodeCapacityTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.host = Path(self.temporary.name)
        self.directory = self.host / "etc/kubernetes/kubelet/config.json.d"
        self.directory.mkdir(parents=True)
        env = self.host / "etc/eks/kubelet/environment"
        env.parent.mkdir(parents=True)
        env.write_text("KUBELET_ARGS=--config-dir=/etc/kubernetes/kubelet/config.json.d")
        self.base = self.directory / "40-nodeadm.conf"
        self.original = '{"maxPods":11,"kubeReserved":{"memory":"376Mi"},"authentication":{"anonymous":{"enabled":false}}}'
        self.base.write_text(self.original)

    def test_changes_only_max_pods_in_separate_dropin(self):
        restart = Mock()
        capacity.configure(self.host, restart)
        self.assertEqual(self.base.read_text(), self.original)
        result = json.loads((self.directory / "99-oficina-pod-capacity.conf").read_text())
        self.assertEqual(set(result), {"apiVersion", "kind", "maxPods"})
        self.assertEqual(result["maxPods"], 17)
        restart.assert_called_once()

    def test_failed_restart_removes_new_dropin(self):
        with self.assertRaisesRegex(RuntimeError, "restart failed"):
            capacity.configure(self.host, Mock(side_effect=RuntimeError("restart failed")))
        self.assertFalse((self.directory / "99-oficina-pod-capacity.conf").exists())
        self.assertEqual(self.base.read_text(), self.original)

    def test_refuses_node_without_dropin_support(self):
        (self.host / "etc/eks/kubelet/environment").write_text("KUBELET_ARGS=--config=/etc/kubernetes/kubelet/config.json")
        restart = Mock()
        with self.assertRaisesRegex(RuntimeError, "left unchanged"):
            capacity.configure(self.host, restart)
        restart.assert_not_called()
        self.assertFalse((self.directory / "99-oficina-pod-capacity.conf").exists())


if __name__ == "__main__":
    unittest.main()
