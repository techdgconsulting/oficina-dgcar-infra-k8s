"""Guard against applying changes outside the approved operational scope."""
import importlib.util
import os
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("operational", Path(__file__).with_name("validate-operational.py"))
operational = importlib.util.module_from_spec(spec)
spec.loader.exec_module(operational)


def change(address, actions, after=None):
    return {"address": address, "mode": "managed", "change": {"actions": actions, "after": after}}


class ScopeTest(unittest.TestCase):
    @patch.dict(os.environ, {"OPERATIONAL_PHASE": "deploy"})
    def test_reject_business_change_even_when_other_changes_are_approved(self):
        plan = {"resource_changes": [change("helm_release.new_relic_kubernetes[0]", ["update"]),
                                     change("newrelic_one_dashboard.business[0]", ["update"])]}
        with self.assertRaisesRegex(ValueError, "unapproved"):
            operational.validate_plan(plan)

    @patch.dict(os.environ, {"OPERATIONAL_PHASE": "deploy"})
    def test_reject_aws_mutation(self):
        with self.assertRaisesRegex(ValueError, "unapproved"):
            operational.validate_plan({"resource_changes": [change("aws_eks_cluster.main", ["update"])]})

    @patch.dict(os.environ, {"OPERATIONAL_PHASE": "deploy"})
    def test_reject_dashboard_replacement(self):
        with self.assertRaisesRegex(ValueError, "unapproved"):
            operational.validate_plan({"resource_changes": [change("newrelic_one_dashboard.operational[0]", ["delete", "create"])]})

    @patch.dict(os.environ, {"OPERATIONAL_PHASE": "retire"})
    def test_retire_only_accepts_deleting_the_two_old_dashboards(self):
        operational.validate_plan({"resource_changes": [change(address, ["delete"]) for address in operational.LEGACY]})
        with self.assertRaisesRegex(ValueError, "outside"):
            operational.validate_plan({"resource_changes": [change("newrelic_one_dashboard.business[0]", ["delete"])]})


class ExternalHealthTest(unittest.TestCase):
    @patch.object(operational.time, "sleep")
    @patch.object(operational.time, "time", return_value=1000)
    def test_waits_for_recovery_instead_of_failing_on_previous_outage(self, clock, sleep):
        results = [[], [{"result": "FAILED", "checked_at": 990000}],
                   [{"result": "SUCCESS", "checked_at": 1000000, "uptime": 80}]]
        with patch.object(operational, "nrql", side_effect=results) as query:
            health = operational.wait_for_external_health()
        self.assertEqual(query.call_count, 3)
        self.assertEqual(health["uptime"], 80)

    @patch.object(operational.time, "sleep")
    @patch.object(operational.time, "time", return_value=1000)
    def test_does_not_accept_stale_success(self, clock, sleep):
        results = [[{"result": "SUCCESS", "checked_at": 600000}],
                   [{"result": "SUCCESS", "checked_at": 1000000}]]
        with patch.object(operational, "nrql", side_effect=results) as query:
            operational.wait_for_external_health()
        self.assertEqual(query.call_count, 2)

    def test_keeps_failure_when_monitor_does_not_recover(self):
        with patch.object(operational, "nrql", return_value=[{"result": "FAILED", "checked_at": 1000000}]):
            with self.assertRaisesRegex(ValueError, "Timed out"):
                operational.wait_for_external_health(timeout=0)


if __name__ == "__main__":
    unittest.main()
