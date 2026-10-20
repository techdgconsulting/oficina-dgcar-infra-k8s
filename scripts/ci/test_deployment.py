import json
import os
import unittest
from unittest.mock import patch
import deployment as d

SOURCE = "a" * 40

def parent(environment="homolog", workflow="provision", branch="homolog", **extra):
    return dict(status="in_progress", path=f".github/workflows/{workflow}-{environment}.yml",
                head_branch=branch, event="workflow_dispatch", **extra)

class DeploymentSafetyTests(unittest.TestCase):
    def test_environment_branch_pairs(self):
        for environment, branch in (("homolog", "homolog"), ("prod", "main")):
            d.pair(environment, branch)

    def test_cross_environment_and_feature_branches_rejected(self):
        for environment, branch in (("prod", "homolog"), ("homolog", "main"), ("prod", "feature/test")):
            with self.subTest(environment=environment, branch=branch), self.assertRaises(ValueError):
                d.pair(environment, branch)

    def test_non_deleting_changes_allowed(self):
        for actions in (["create"], ["update"], ["no-op"], ["read"]):
            d.non_destructive({"resource_changes": [{"address": "aws_db_instance.db", "change": {"actions": actions}}]})

    def test_deletion_and_both_replacement_orders_blocked(self):
        for actions in (["delete"], ["delete", "create"], ["create", "delete"]):
            with self.subTest(actions=actions), self.assertRaisesRegex(ValueError, "aws_db_instance.db"):
                d.non_destructive({"resource_changes": [{"address": "aws_db_instance.db", "change": {"actions": actions}}]})

    def test_incomplete_and_errored_plans_blocked(self):
        for plan in ({"complete": False}, {"errored": True}):
            with self.assertRaises(ValueError):
                d.non_destructive(plan)

    def test_invalid_source_rejected(self):
        for value in ("homolog", "main", "abc123", "../file", "a" * 39, "g" * 40):
            with self.assertRaises(ValueError):
                d.sha(value)

    def test_active_matching_parent_allowed(self):
        d.verify_parent(parent(), "homolog", "homolog", "apply")

    def test_completed_parent_rejected(self):
        run = parent(); run["status"] = "completed"
        with self.assertRaises(ValueError):
            d.verify_parent(run, "homolog", "homolog", "apply")

    def test_parent_from_another_environment_rejected(self):
        with self.assertRaises(ValueError):
            d.verify_parent(parent(environment="prod", branch="main"), "homolog", "homolog", "apply")

    def test_wrong_parent_workflow_or_branch_rejected(self):
        for run in (parent(workflow="ci"), parent(branch="feature/test")):
            with self.assertRaises(ValueError):
                d.verify_parent(run, "homolog", "homolog", "apply")

    def test_automatic_destroy_rejected(self):
        run = parent(workflow="destroy", branch="main"); run["event"] = "push"
        with self.assertRaises(ValueError):
            d.verify_parent(run, "homolog", "main", "destroy")

    def test_apply_parent_cannot_authorize_destroy(self):
        with self.assertRaises(ValueError):
            d.verify_parent(parent(), "homolog", "homolog", "destroy")

    def test_existing_manual_destroy_allowed(self):
        d.verify_parent(parent(workflow="destroy", branch="main"), "homolog", "main", "destroy")

    def test_worker_uses_exact_component_source(self):
        env = dict(TARGET_ENVIRONMENT="homolog", GITHUB_REF_NAME="homolog", DEPLOY_ACTION="deploy",
                   PARENT_RUN_ID="123", SOURCE_SHA=SOURCE, GITHUB_REPOSITORY="techdgconsulting/oficina-dgcar-api")
        run = parent(display_title=f"Provisionar | api | {SOURCE}")
        with patch.dict(os.environ, env), patch.object(d, "gh", side_effect=[json.dumps(run), '{"status":"identical"}']) as api:
            d.worker()
            self.assertIn(SOURCE + "...homolog", api.call_args.args[-1])

    def test_worker_rejects_unrelated_component_or_commit(self):
        env = dict(TARGET_ENVIRONMENT="homolog", GITHUB_REF_NAME="homolog", DEPLOY_ACTION="deploy",
                   PARENT_RUN_ID="123", SOURCE_SHA=SOURCE, GITHUB_REPOSITORY="techdgconsulting/oficina-dgcar-api")
        for title in (f"Provisionar | database | {SOURCE}", "Provisionar | api | " + "b" * 40):
            with patch.dict(os.environ, env), patch.object(d, "gh", return_value=json.dumps(parent(display_title=title))), self.assertRaises(ValueError):
                d.worker()

    def test_worker_rejects_commit_outside_protected_branch(self):
        env = dict(TARGET_ENVIRONMENT="homolog", GITHUB_REF_NAME="homolog", DEPLOY_ACTION="deploy",
                   PARENT_RUN_ID="123", SOURCE_SHA=SOURCE, GITHUB_REPOSITORY="techdgconsulting/oficina-dgcar-api")
        run = parent(display_title=f"Provisionar | api | {SOURCE}")
        with patch.dict(os.environ, env), patch.object(d, "gh", side_effect=[json.dumps(run), '{"status":"diverged"}']), self.assertRaises(ValueError):
            d.worker()

    def test_request_routes_prod_to_main_without_full_provision(self):
        env = dict(TARGET_ENVIRONMENT="prod", GITHUB_REF_NAME="main", SOURCE_SHA=SOURCE, COMPONENT="api")
        with patch.dict(os.environ, env), patch.object(d, "gh") as api:
            d.request()
            args = api.call_args.args
            self.assertIn("provision-prod.yml", args)
            self.assertIn("component=api", args)
            self.assertNotIn("component=all", args)
            self.assertIn("source_sha=" + SOURCE, args)

    def test_request_rejects_environment_mismatch_before_dispatch(self):
        env = dict(TARGET_ENVIRONMENT="prod", GITHUB_REF_NAME="homolog", SOURCE_SHA=SOURCE, COMPONENT="api")
        with patch.dict(os.environ, env), patch.object(d, "gh") as api, self.assertRaises(ValueError):
            d.request()
        api.assert_not_called()

if __name__ == "__main__":
    unittest.main()
