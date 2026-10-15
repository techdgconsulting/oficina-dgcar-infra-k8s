import importlib.util
from pathlib import Path
import unittest


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


network = module("prefix", "ensure-prefix.py")
preflight = module("preflight", "preflight.py")
scope = module("scope", "validate-plan.py")


class SafeguardsTest(unittest.TestCase):
    def test_never_releases_primary_or_active_addresses(self):
        interfaces = [{"NetworkInterfaceId": "eni-test", "PrivateIpAddresses": [
            {"PrivateIpAddress": "10.0.0.1", "Primary": True},
            {"PrivateIpAddress": "10.0.0.2", "Primary": False},
            {"PrivateIpAddress": "10.0.0.3", "Primary": False}]}]
        self.assertIsNone(network.releasable(interfaces, {"10.0.0.1", "10.0.0.2"}, {"10.0.0.2"}))
        self.assertEqual(network.releasable(interfaces, {"10.0.0.3"}, {"10.0.0.2"}), ("eni-test", "10.0.0.3"))
        self.assertIsNone(network.releasable(interfaces, set(), set()))

    def test_rejects_ec2_or_node_group_changes(self):
        for address in ("aws_eks_node_group.main", "aws_instance.worker", "newrelic_one_dashboard.business[0]"):
            with self.assertRaisesRegex(ValueError, "Unapproved"):
                scope.validate({"resource_changes": [{"address": address, "mode": "managed", "change": {"actions": ["update"]}}]})

    def test_rejects_destructive_helm_replacement(self):
        with self.assertRaisesRegex(ValueError, "Unapproved"):
            scope.validate({"resource_changes": [{"address": "helm_release.new_relic_kubernetes", "mode": "managed",
                                                   "change": {"actions": ["delete", "create"]}}]})

    def test_second_replica_must_fit_memory_even_when_pod_slots_exist(self):
        node = {"status": {"allocatable": {"cpu": "1930m", "memory": "1467996Ki", "pods": "17"}}}
        def pods(memory):
            return [{"status": {"phase": "Running"}, "spec": {"containers": [{"resources": {"requests": {"cpu": "1000m", "memory": memory}}}]}}]
        preflight.budget(node, pods("900Mi"), {"cpu": "250m", "memory": "512Mi"})
        with self.assertRaisesRegex(ValueError, "memory budget"):
            preflight.budget(node, pods("1000Mi"), {"cpu": "250m", "memory": "512Mi"})


if __name__ == "__main__":
    unittest.main()
