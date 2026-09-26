import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("project", Path(__file__).resolve().parents[1] / "tools/project.py")
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)

class Checks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "task.md").write_text("任务", encoding="utf-8")
        self.data = {"schema_version": 1, "tasks": [
            {"id": "T01", "title": "身份", "type": "parent", "parent": None,
             "depends_on": [], "source": ["V4"], "acceptance": "证据",
             "integration": "G7", "path": "task.md"}]}

    def test_valid_tasks(self):
        self.assertEqual([], p.validate_tasks(self.root, self.data))

    def test_missing_field(self):
        del self.data["tasks"][0]["acceptance"]
        self.assertTrue(p.validate_tasks(self.root, self.data))

    def test_unknown_dependency(self):
        self.data["tasks"][0]["depends_on"] = ["T99"]
        self.assertTrue(p.validate_tasks(self.root, self.data))

    def test_cycle(self):
        self.data["tasks"][0]["depends_on"] = ["T01"]
        self.assertTrue(p.validate_tasks(self.root, self.data))

    def test_indirect_cycle(self):
        second = copy.deepcopy(self.data["tasks"][0])
        second.update(id="T02", depends_on=["T01"])
        self.data["tasks"][0]["depends_on"] = ["T02"]
        self.data["tasks"].append(second)
        self.assertTrue(p.validate_tasks(self.root, self.data))

    def test_path_escape(self):
        for value in ("../outside", "/outside", "Z:/outside", "bad\\path"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                p.safe_path(self.root, value, exists=False)

    def test_missing_path(self):
        self.data["tasks"][0]["path"] = "missing.md"
        self.assertTrue(p.validate_tasks(self.root, self.data))

    def test_missing_tool(self):
        with patch.object(p.shutil, "which", return_value=None):
            self.assertEqual("MISSING", p.doctor(["nonexistent"]) [0]["status"])

    def test_available_python(self):
        self.assertEqual("AVAILABLE", p.doctor(["python"])[0]["status"])

    def test_missing_project_honest(self):
        self.assertEqual([], p.validate_projects(self.root, {
            "schema_version": 1, "status": "MISSING", "projects": []}))

    def test_registered_empty(self):
        self.assertTrue(p.validate_projects(self.root, {
            "schema_version": 1, "status": "REGISTERED", "projects": []}))

    def test_project_bad_entry(self):
        data = {"schema_version": 1, "status": "REGISTERED", "projects": [{
            "id": "real", "entry": "../outside", "top": "top", "device": "verified",
            "tool": {"name": "PDS", "version": "verified"},
            **{k: [] for k in ("sources", "constraints", "ip", "initialization",
                              "firmware", "models", "external_dependencies", "outputs")}}]}
        self.assertTrue(p.validate_projects(self.root, data))

    def test_template_cannot_pass(self):
        self.assertIn("模板只能为NOT_RUN，不能伪报通过",
                      p.validate_evidence({"template": True, "status": "PASSED"}))

    def test_empty_pass_rejected(self):
        self.assertTrue(p.validate_evidence({"status": "PASSED", "template": False}))

    def test_evidence_real_hash_and_no_overwrite(self):
        subprocess.run(["git", "init", "-b", "main", str(self.root)],
                       check=True, capture_output=True)
        subprocess.run(["git", "-C", str(self.root), "add", "task.md"], check=True)
        subprocess.run(["git", "-C", str(self.root), "-c", "user.name=Test",
                        "-c", "user.email=test@example.invalid", "commit", "-m", "fixture"],
                       check=True, capture_output=True)
        folder = self.root / "docs/tasks"
        folder.mkdir(parents=True)
        (folder / "tasks.json").write_text(json.dumps(self.data), encoding="utf-8")
        data = p.evidence(self.root, "T01", "test", ["task.md"], "result.json")
        self.assertEqual("NOT_RUN", data["status"])
        self.assertEqual(p.digest(self.root / "task.md"), data["inputs"]["task.md"])
        self.assertTrue(data["dirty"])
        self.assertEqual([], p.validate_evidence(data))
        with self.assertRaises(ValueError):
            p.evidence(self.root, "T01", "test", ["task.md"], "result.json")
        with self.assertRaises(ValueError):
            p.evidence(self.root, "T99", "test", [], "another.json")

if __name__ == "__main__":
    unittest.main()
