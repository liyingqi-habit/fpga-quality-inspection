"""仓库结构检查；不解析原生 PDS，不执行硬件。Python 3.10+，仅标准库。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]

def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))

def safe_path(root, value, exists=True):
    if not isinstance(value, str) or not value or "\\" in value:
        raise ValueError("路径须为非空仓库相对路径，使用 /")
    if Path(value).is_absolute() or re.match(r"^[A-Za-z]:", value):
        raise ValueError("不允许绝对路径")
    target = (root / value).resolve()
    if not target.is_relative_to(root.resolve()):
        raise ValueError("路径越出仓库")
    if exists and not target.exists():
        raise ValueError("路径不存在: " + value)
    return target

def validate_tasks(root, data):
    errors = []
    rows = data.get("tasks")
    if data.get("schema_version") != 1 or not isinstance(rows, list) or not rows:
        return ["任务清单 schema_version/tasks 无效"]
    ids = set()
    for row in rows:
        if not isinstance(row, dict):
            errors.append("任务必须为对象")
            continue
        for key in ("id", "type", "title", "depends_on", "source",
                    "acceptance", "integration", "path"):
            if key not in row or (key != "depends_on" and not row[key]):
                errors.append("缺任务字段: " + key)
        ident = row.get("id", "")
        if not isinstance(ident, str) or not re.fullmatch(r"T\d{2}(?:-\d{2})?", ident):
            errors.append("任务ID格式错误")
        if ident in ids:
            errors.append("重复任务ID: " + str(ident))
        ids.add(ident)
        if row.get("type") not in ("parent", "task"):
            errors.append("任务类型无效")
        if row.get("type") == "task" and not row.get("parent"):
            errors.append("子任务缺parent")
        if not isinstance(row.get("source"), list) or not row.get("source"):
            errors.append("来源必须为非空列表")
        try:
            safe_path(root, row.get("path"))
        except (ValueError, TypeError) as exc:
            errors.append(str(exc))
    graph = {}
    for row in rows:
        if not isinstance(row, dict):
            continue
        ident = row.get("id", "")
        deps = row.get("depends_on")
        if not isinstance(deps, list) or not all(isinstance(x, str) for x in deps):
            errors.append("依赖必须为ID列表: " + str(ident))
            deps = []
        for dep in deps:
            if dep not in ids:
                errors.append("未知依赖: " + dep)
        if row.get("parent") and row["parent"] not in ids:
            errors.append("未知父任务: " + str(row["parent"]))
        if row.get("integration") not in ids | {"G7"}:
            errors.append("未知集成去向: " + str(row.get("integration")))
        graph[ident] = deps
    active, done = set(), set()
    def visit(ident):
        if ident in active:
            errors.append("循环依赖: " + str(ident))
            return
        if ident in done:
            return
        active.add(ident)
        for dep in graph.get(ident, []):
            visit(dep)
        active.remove(ident)
        done.add(ident)
    for ident in graph:
        visit(ident)
    return errors

def validate_projects(root, data):
    errors = []
    if data.get("schema_version") != 1 or data.get("status") not in ("MISSING", "REGISTERED"):
        errors.append("工程清单版本或状态无效")
    projects = data.get("projects")
    if not isinstance(projects, list):
        return errors + ["projects必须是列表"]
    if data.get("status") == "MISSING" and projects:
        errors.append("MISSING清单不可包含工程")
    if data.get("status") == "REGISTERED" and not projects:
        errors.append("REGISTERED必须有真实工程")
    for project in projects:
        if not isinstance(project, dict):
            errors.append("工程必须是对象")
            continue
        for key in ("id", "entry", "top", "device", "tool"):
            if not project.get(key) or project.get(key) == "MISSING":
                errors.append("真实工程缺字段: " + key)
        if project.get("example"):
            errors.append("示例不可登记为真实工程")
        tool = project.get("tool", {})
        if not isinstance(tool, dict) or not tool.get("name") or not tool.get("version"):
            errors.append("工具名称/版本缺失")
        paths = [project.get("entry")]
        for key in ("sources", "constraints", "ip", "initialization", "firmware", "models"):
            values = project.get(key)
            if not isinstance(values, list):
                errors.append("工程缺输入列表: " + key)
            else:
                paths.extend(values)
        for value in paths:
            try:
                safe_path(root, value)
            except (ValueError, TypeError) as exc:
                errors.append(str(exc))
        for key in ("external_dependencies", "outputs"):
            if not isinstance(project.get(key), list):
                errors.append("工程缺列表: " + key)
    return errors

def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()

def git(root, *args):
    result = subprocess.run(["git", "-C", str(root), *args],
                            capture_output=True, check=True)
    return result.stdout.decode("utf-8", errors="strict").strip()

def inventory(root):
    # Git跟踪和未忽略文件；输入资料不得借由全盘遍历混入。
    raw = subprocess.run(["git", "-C", str(root), "ls-files", "-z",
                          "--cached", "--others", "--exclude-standard"],
                         capture_output=True, check=True).stdout
    return sorted(set(x.decode("utf-8") for x in raw.split(b"\0") if x))

def doctor(required=("git", "python")):
    results = []
    for name in required:
        executable = sys.executable if name == "python" else shutil.which(name)
        if not executable:
            results.append({"tool": name, "status": "MISSING"})
            continue
        try:
            proc = subprocess.run([executable, "--version"], capture_output=True,
                                  text=True, timeout=15)
            results.append({"tool": name, "path": executable,
                            "status": "AVAILABLE" if proc.returncode == 0 else "FAILED",
                            "version": (proc.stdout or proc.stderr).strip().splitlines()[0]})
        except (OSError, subprocess.TimeoutExpired, IndexError) as exc:
            results.append({"tool": name, "status": "FAILED", "error": str(exc)})
    return results

def validate_evidence(data):
    errors = []
    keys = ("task_id", "test_id", "source_sha", "dirty", "diff_sha256", "inputs",
            "tool_versions", "ip_model_firmware_constraints", "board", "operator",
            "operations", "seed", "expected", "actual", "raw_evidence", "uncovered", "status")
    for key in keys:
        if key not in data:
            errors.append("证据缺字段: " + key)
    if data.get("status") not in ("PASSED", "FAILED", "NOT_RUN", "BLOCKED", "N/A"):
        errors.append("证据状态无效")
    if data.get("template") is True and data.get("status") != "NOT_RUN":
        errors.append("模板只能为NOT_RUN，不能伪报通过")
    if data.get("status") in ("PASSED", "FAILED"):
        for key in ("operator", "operations", "actual", "raw_evidence", "tool_versions"):
            if not data.get(key) or data.get(key) == "MISSING":
                errors.append("已运行记录缺真实内容: " + key)
    return errors

def evidence(root, task, test, inputs, output):
    tasks = read_json(root / "docs/tasks/tasks.json")["tasks"]
    if task not in {x["id"] for x in tasks}:
        raise ValueError("未知任务ID")
    source_sha = git(root, "rev-parse", "HEAD")
    tracked_diff = subprocess.run(["git", "-C", str(root), "diff", "HEAD", "--binary"],
                                  capture_output=True, check=True).stdout
    dirty = bool(git(root, "status", "--porcelain"))
    tracked = set(git(root, "ls-files").splitlines())
    untracked = {p: digest(safe_path(root, p)) for p in inventory(root)
                 if p not in tracked and safe_path(root, p).is_file()}
    data = {"schema_version": 1, "template": True, "status": "NOT_RUN",
            "created_utc": datetime.now(timezone.utc).isoformat(),
            "task_id": task, "test_id": test, "source_sha": source_sha,
            "dirty": dirty, "diff_sha256": hashlib.sha256(tracked_diff).hexdigest(),
            "untracked_sha256": untracked,
            "inputs": {p: digest(safe_path(root, p)) for p in inputs},
            "tool_versions": {"python": sys.version.split()[0]},
            "ip_model_firmware_constraints": "MISSING", "board": "MISSING",
            "operator": "MISSING", "operations": [], "seed": "MISSING",
            "expected": "待按任务填写", "actual": "未运行",
            "raw_evidence": [], "uncovered": ["PDS、仿真、上板和整机均未由此命令运行"]}
    path = safe_path(root, output, exists=False)
    if path.exists():
        raise ValueError("拒绝覆盖已有证据")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(data, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    return data

def check(root):
    errors = []
    required = ["README.md", "AGENTS.md", "CONTRIBUTING.md", "SECURITY.md",
                "docs/START_HERE.md", "docs/PRODUCT.md", "docs/ROADMAP.md",
                "docs/SCHEDULE.md", "docs/setup/PROJECTS.md",
                "docs/setup/PDS_FILE_POLICY.md", "docs/setup/GITHUB_SETUP.md",
                "docs/acceptance/FINAL_ACCEPTANCE.md", "docs/acceptance/GATES.md",
                ".github/workflows/repo-baseline.yml"]
    for value in required:
        try:
            safe_path(root, value)
        except ValueError as exc:
            errors.append(str(exc))
    for value, validator in (("docs/tasks/tasks.json", validate_tasks),
                             ("docs/setup/projects.json", validate_projects)):
        try:
            errors.extend(validator(root, read_json(root / value)))
        except (OSError, ValueError, TypeError) as exc:
            errors.append(value + ": " + str(exc))
    for value in inventory(root):
        parts = Path(value).parts
        if any(p in ("private_inputs", "codex_handoff_v4", ".bootstrap-local") for p in parts):
            errors.append("不应公开的目录: " + value)
        if Path(value).name.startswith(".env") or Path(value).suffix.lower() in (".pem", ".key"):
            errors.append("疑似凭据文件: " + value)
        try:
            path = safe_path(root, value)
        except ValueError as exc:
            errors.append(str(exc))
            continue
        if path.is_symlink():
            errors.append("符号链接需人工审查: " + value)
            continue
        if not path.is_file():
            errors.append("非普通文件需审查: " + value)
            continue
        if path.suffix.lower() not in (".md", ".py", ".json", ".yml", ".yaml", ".txt"):
            continue  # 不转码/解析厂商二进制
        try:
            content = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            errors.append("本项目文本非UTF-8，需人工核验: " + value)
            continue
        if re.search(r"(?m)^(?:<{7}|={7}|>{7})(?: |$)", content):
            errors.append("合并冲突标记: " + value)
        if re.search(r"(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----)", content):
            errors.append("疑似秘密: " + value)
        if re.search(r"[A-Za-z]:[\\/]Users[\\/]", content):
            errors.append("私人本机绝对路径: " + value)
        if path.suffix == ".md":
            for dest in re.findall(r"!?\[[^\]]*\]\(([^)\s]+)\)", content):
                if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", dest) or dest.startswith("#"):
                    continue
                target = dest.split("#", 1)[0]
                if target:
                    try:
                        relative = (path.parent / target).resolve().relative_to(root.resolve()).as_posix()
                        safe_path(root, relative)
                    except ValueError:
                        errors.append("坏本地链接: " + value + " -> " + dest)
        if value.startswith("evidence/") and path.suffix == ".json":
            try:
                errors.extend(validate_evidence(read_json(path)))
            except ValueError as exc:
                errors.append(str(exc))
    return errors

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    d = sub.add_parser("doctor")
    d.add_argument("--require", nargs="+", default=["git", "python"])
    sub.add_parser("check")
    e = sub.add_parser("evidence")
    for name in ("task", "test", "output"):
        e.add_argument("--" + name, required=True)
    e.add_argument("--input", action="append", default=[])
    args = parser.parse_args()
    try:
        if args.command == "doctor":
            rows = doctor(args.require)
            print(json.dumps(rows, ensure_ascii=False, indent=2))
            print("PDS/IP/仿真器：未验证；AVAILABLE仅表示版本命令成功。")
            return int(any(x["status"] != "AVAILABLE" for x in rows))
        if args.command == "check":
            errors = check(ROOT)
            for error in errors:
                print("错误: " + error)
            print("结构检查失败" if errors else "仓库结构检查通过；不代表PDS/硬件通过。")
            return int(bool(errors))
        evidence(ROOT, args.task, args.test, args.input, args.output)
        print("已创建NOT_RUN证据模板，没有运行测试。")
        return 0
    except (OSError, ValueError, TypeError, subprocess.SubprocessError) as exc:
        print("失败: " + str(exc), file=sys.stderr)
        return 1

if __name__ == "__main__":
    sys.exit(main())
