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


if __name__ == "__main__":
    unittest.main()
