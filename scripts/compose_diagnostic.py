#!/usr/bin/env python3
"""Diagnose the compose stack and write one report to share with the DevOps team.

Runs the usual container commands (versions, config check, container states,
health checks, logs, ports, disk, Traefik routes), explains what looks wrong
in plain words, and saves everything as Markdown. Values from .env are masked
in the whole report, so it can be pasted into an issue.

Usually run as `just compose-diagnostic`. Standard library only; Python 3.9+.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import re
import shutil
import socket
import subprocess
import sys
import urllib.request
from datetime import datetime
from pathlib import Path

LOG_LINES = 40
# Log lines that usually explain a crash, across Node, Python, Postgres and Traefik.
CRASH = re.compile(r"Error:|ERROR|FATAL|panic:|Traceback|EADDRINUSE|app crashed|exited with code")
# What a watcher (nodemon, vite) prints after the app dies: true, but not the cause.
WATCHER = re.compile(r"app crashed|exited with code")
ANSI = re.compile(r"\x1b\[[0-9;]*m")
# Credentials that are not in .env: passwords inside URLs, and *PASSWORD/SECRET/TOKEN/KEY* values.
CREDENTIALS = [
    (re.compile(r"(://[^:/@\s]+:)[^@\s]+@"), r"\1***@"),
    (re.compile(r"(\b\w*(?:PASSWORD|SECRET|TOKEN|_KEY)\w*\s*[:=]\s*)\S+", re.I), r"\1***"),
]


class Report:
    def __init__(self, secrets: list[str]):
        # longest first, so a secret containing another is masked whole
        self.secrets = sorted({s for s in secrets if len(s) >= 6}, key=len, reverse=True)
        self.findings: list[str] = []
        self.sections: list[str] = []

    def mask(self, text: str) -> str:
        for s in self.secrets:
            text = text.replace(s, "***")
        for pattern, repl in CREDENTIALS:
            text = pattern.sub(repl, text)
        return text

    def problem(self, text: str) -> None:
        self.findings.append(self.mask(text))

    def section(self, title: str, body: str = "", cmd: str = "") -> None:
        parts = [f"## {title}"]
        if cmd:
            parts.append(f"`$ {cmd}`")
        if body:
            parts.append("```\n" + self.mask(body.rstrip()) + "\n```")
        self.sections.append("\n".join(parts))

    def summary(self) -> str:
        if not self.findings:
            return "- Nothing obviously wrong. Share the report with the DevOps team if the problem persists."
        return "\n".join(f"- {f}" for f in self.findings)

    def render(self, header: str) -> str:
        return f"{header}\n## What looks wrong\n{self.summary()}\n" + "\n".join(self.sections) + "\n"


def run(cmd: list[str], timeout: int = 60) -> tuple[int, str]:
    """Run a command, never raising: (exit code, stdout+stderr)."""
    try:
        r = subprocess.run(cmd, text=True, capture_output=True, timeout=timeout)
        return r.returncode, (r.stdout + r.stderr).strip()
    except FileNotFoundError:
        return 127, f"{cmd[0]}: command not found"
    except subprocess.TimeoutExpired:
        return 124, f"timed out after {timeout}s"


def read_env(path: Path) -> dict[str, str]:
    env = {}
    if path.exists():
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                env[key.strip()] = value.strip().strip('"').strip("'")
    return env


def port_answers(port: int) -> bool:
    with socket.socket() as s:
        s.settimeout(1)
        return s.connect_ex(("127.0.0.1", port)) == 0


def check_environment(rep: Report, tool: str, compose: list[str]) -> bool:
    lines = [f"OS: {platform.platform()}", f"Python: {platform.python_version()}"]
    for label, cmd in [("git", ["git", "describe", "--always", "--dirty"]),
                       ("branch", ["git", "rev-parse", "--abbrev-ref", "HEAD"]),
                       ("just", ["just", "--version"]),
                       (tool, [tool, "--version"]),
                       ("compose", compose + ["version"])]:
        out = run(cmd)[1]
        lines.append(f"{label}: {out.splitlines()[0] if out else '?'}")
    rep.section("Environment", "\n".join(lines))

    code, out = run([tool, "info"])
    if code != 0:
        hint = ("start the Podman machine: `podman machine start`" if tool == "podman" and platform.system() == "Darwin"
                else "start Docker Desktop or the Docker service" if tool == "docker"
                else "enter the dev shell (`nix develop`) or check `podman info`")
        rep.problem(f"`{tool}` is not answering, so no container can run: {hint}.")
        rep.section(f"{tool} info", out[-3000:], f"{tool} info")
        return False
    return True


def check_env_file(rep: Report, root: Path) -> None:
    example, env = read_env(root / ".env.example"), read_env(root / ".env")
    if not (root / ".env").exists():
        rep.problem("`.env` is missing: run `cp .env.example .env` (the dev shell does it for you).")
        return
    missing = sorted(set(example) - set(env))
    if missing:
        rep.problem(f"`.env` lacks variables that `.env.example` has: {', '.join(missing)}. "
                    "Copy them over (the dev shell does it on entry).")
    placeholders = sorted(k for k, v in env.items() if v.startswith("change-me-"))
    if placeholders:
        rep.problem(f"`.env` still has placeholder secrets: {', '.join(placeholders)}. "
                    "Enter the dev shell once, or replace them with random values.")
    rep.section(".env (values hidden)", "\n".join(f"{k}=***" for k in env) or "(empty)")


def check_config(rep: Report, compose: list[str]) -> list[str]:
    code, out = run(compose + ["config"])
    unresolved = sorted(set(re.findall(r"\$\{(\w+)", out)))
    if code != 0:
        rep.problem("`docker-compose.yml` does not resolve; the error is under *compose config*.")
        # only the error: the resolved file itself would bloat the report
        rep.section("compose config", out[-3000:], " ".join(compose + ["config"]))
    elif unresolved:
        rep.problem(f"Variables left unreplaced (Podman keeps unset ones as text): {', '.join(unresolved)}. "
                    "Define them in `.env`.")
    code, services = run(compose + ["config", "--services"])
    return services.split() if code == 0 else []


def project_name(root: Path) -> str:
    """Compose's project name: COMPOSE_PROJECT_NAME, else the folder name."""
    return os.environ.get("COMPOSE_PROJECT_NAME") or re.sub(r"[^a-z0-9_-]", "", root.name.lower())


def anonymous_volumes(tool: str, container: dict, project: str) -> list[str]:
    """Mount points backed by a volume without this project's label (an anonymous volume)."""
    found = []
    for m in container.get("Mounts") or []:
        if m.get("Type") != "volume":
            continue
        code, label = run([tool, "volume", "inspect", m.get("Name", ""), "--format",
                           '{{index .Labels "com.docker.compose.project"}}'])
        if code != 0 or label.strip() != project:
            found.append(m.get("Destination", "?"))
    return found


def inspect_containers(tool: str, root: Path) -> list[dict]:
    code, ids = run([tool, "ps", "-aq", "--filter", f"label=com.docker.compose.project.working_dir={root}"])
    if code != 0 or not ids.split():
        return []
    code, out = run([tool, "inspect", *ids.split()])
    try:
        return json.loads(out) if code == 0 else []
    except json.JSONDecodeError:
        return []


def check_containers(rep: Report, tool: str, compose: list[str], root: Path, services: list[str]) -> set[str]:
    rep.section("compose ps", run(compose + ["ps"])[1], " ".join(compose + ["ps"]))
    containers = inspect_containers(tool, root)
    running = set()
    if not containers:
        rep.problem("No container of this project exists: start the stack with `just up -d`.")
        return running
    seen = set()
    for c in containers:
        labels = c.get("Config", {}).get("Labels") or {}
        service = labels.get("com.docker.compose.service", c.get("Name", "?").lstrip("/"))
        seen.add(service)
        state = c.get("State", {})
        status = state.get("Status", "?")
        health = state.get("Health") or state.get("Healthcheck") or {}
        if status == "running":
            running.add(service)
        else:
            rep.problem(f"`{service}` is {status} (exit code {state.get('ExitCode')}): its logs below say why.")
        if c.get("RestartCount", 0):
            rep.problem(f"`{service}` restarted {c['RestartCount']} time(s): it crashes on start, see its logs.")
        if health.get("Status") == "unhealthy":
            last = (health.get("Log") or [{}])[-1].get("Output", "").strip()
            rep.problem(f"`{service}` is unhealthy; Traefik does not route to it. "
                        f"Last health check said: {last[:200] or '(nothing)'}")
        for path in anonymous_volumes(tool, c, project_name(root)):
            rep.problem(f"`{service}` stores `{path}` in an anonymous volume, which this report cannot list "
                        "and `just nuke` may leave behind: mount a named volume there in `docker-compose.yml`.")
        if health.get("Status") == "starting":
            rep.problem(f"`{service}` has not passed its health check yet: wait a few seconds and re-run, "
                        "or read its logs if it stays like this.")
        name = c.get("Name", "").lstrip("/") or c.get("Id", "")[:12]
        logs = ANSI.sub("", run([tool, "logs", "--tail", str(LOG_LINES), name])[1])
        hits = [line.strip() for line in logs.splitlines() if CRASH.search(line)]
        crash = next((h for h in hits if not WATCHER.search(h)), hits[0] if hits else "")
        if crash:
            # a watcher (nodemon, vite) keeps the container "running" after the app dies
            rep.problem(f"`{service}` logs show an error: `{crash[:200]}`")
        rep.section(f"logs: {service} ({status}{', ' + health['Status'] if health.get('Status') else ''})",
                    logs or "(no output)", f"{tool} logs --tail {LOG_LINES} {name}")
    for service in sorted(set(services) - seen):
        rep.problem(f"`{service}` has no container: `just up -d` creates it, or `just rebuild {service}`.")
    return running


def check_ports(rep: Report, env: dict[str, str], running: set[str]) -> None:
    lines = []
    for name, default in (("PROXY_PORT", 8000), ("PROXY_DASHBOARD_PORT", 8080)):
        port = int(env.get(name, default))
        busy = port_answers(port)
        lines.append(f"{name}={port}: {'answering' if busy else 'free'}")
        if busy and "proxy" not in running:
            rep.problem(f"Port {port} ({name}) is taken by another program while the proxy is down: "
                        f"stop that program or set another {name} in `.env`.")
    rep.section("Host ports", "\n".join(lines))


def check_routes(rep: Report, env: dict[str, str], running: set[str]) -> None:
    if "proxy" not in running:
        return
    url = f"http://127.0.0.1:{env.get('PROXY_DASHBOARD_PORT', '8080')}/api/http/routers"
    try:
        with urllib.request.urlopen(url, timeout=3) as r:
            routers = json.load(r)
    except (OSError, ValueError) as e:
        rep.problem(f"The Traefik dashboard does not answer ({e}); the proxy may be misconfigured.")
        return
    lines = [f"{r.get('name')}: {r.get('rule')} [{r.get('status')}]" for r in routers]
    for r in routers:
        if r.get("status") != "enabled":
            rep.problem(f"Traefik route `{r.get('name')}` is {r.get('status')}: {r.get('error', '')}")
    rep.section("Traefik routes", "\n".join(lines), f"curl {url}")


def check_resources(rep: Report, tool: str, root: Path) -> None:
    usage = shutil.disk_usage(root)
    pct = 100 * usage.used // usage.total
    if pct >= 90:
        rep.problem(f"The disk holding the project is {pct}% full: images and builds fail when it fills up. "
                    f"`{tool} system prune` frees unused images.")
    rep.section("Disk", f"{root}: {pct}% used, {usage.free // 2**30} GiB free\n" + run([tool, "system", "df"])[1],
                f"{tool} system df")
    # This project's volumes only: other projects' names stay private.
    # `system df` above already counts every volume without naming it.
    cmd = [tool, "volume", "ls", "--filter", f"label=com.docker.compose.project={project_name(root)}"]
    rep.section("Volumes of this project", run(cmd)[1] or "(none)", " ".join(cmd))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--tool", default=shutil.which("podman") and "podman" or "docker",
                        help="container tool (default: podman if installed, else docker)")
    parser.add_argument("--out", default="", help="report file (default: .compose-diagnostic-<time>.md)")
    args = parser.parse_args()

    root = Path(run(["git", "rev-parse", "--show-toplevel"])[1] or ".").resolve()
    compose = [args.tool, "compose"]
    env = read_env(root / ".env")
    # the dev shell exports .env, so compose may use values .env no longer holds
    keys = set(env) | set(read_env(root / ".env.example"))
    rep = Report(list(env.values()) + [os.environ[k] for k in keys if k in os.environ])
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    print("Collecting diagnostics, this takes a few seconds...", file=sys.stderr)

    os.chdir(root)
    if check_environment(rep, args.tool, compose):
        check_env_file(rep, root)
        services = check_config(rep, compose)
        running = check_containers(rep, args.tool, compose, root, services)
        check_ports(rep, env, running)
        check_routes(rep, env, running)
        check_resources(rep, args.tool, root)
    else:
        check_env_file(rep, root)

    header = f"# Compose diagnostic — {root.name} — {datetime.now().isoformat(timespec='seconds')}"
    text = rep.render(header)
    out = Path(args.out or root / f".compose-diagnostic-{stamp}.md")
    out.write_text(text, encoding="utf-8")
    # the terminal gets the verdict only; logs and state are in the file
    print(f"What looks wrong:\n{rep.summary()}\n")
    print(f"Full report: {out}\nAttach it to an issue or send it to the DevOps team "
          "(.env values and credentials are masked; skim it before sharing).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
