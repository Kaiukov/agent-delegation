from __future__ import annotations

import json
import os
import shutil
import subprocess
import time
import shlex
import uuid as uuidlib
from pathlib import Path

from . import runtime as runtime_module
from .models import AgentRecord


class AgentBackend:
    def __init__(self, state_dir: Path):
        self.state_dir = state_dir
        self.agents_dir = self.state_dir / "agents"
        self.exits_dir = self.state_dir / "exits"
        self.logs_dir = self.state_dir / "logs"
        self.worktrees_dir = self.state_dir / "worktrees"
        self.agents_dir.mkdir(parents=True, exist_ok=True)
        self.exits_dir.mkdir(parents=True, exist_ok=True)
        self.logs_dir.mkdir(parents=True, exist_ok=True)
        self.worktrees_dir.mkdir(parents=True, exist_ok=True)

    def _agent_path(self, agent_uuid: str) -> Path:
        return self.agents_dir / f"{agent_uuid}.json"

    def _log_path(self, agent_uuid: str) -> Path:
        return self.logs_dir / f"{agent_uuid}.log"

    def _load_record(self, agent_uuid: str) -> AgentRecord:
        path = self._agent_path(agent_uuid)
        if not path.exists():
            raise FileNotFoundError(agent_uuid)
        return AgentRecord.from_dict(json.loads(path.read_text()))

    def _save_record(self, record: AgentRecord) -> None:
        self._agent_path(record.uuid).write_text(json.dumps(record.to_dict(), indent=2, sort_keys=True))

    def _finalize_record(
        self,
        record: AgentRecord,
        status: str,
        *,
        exit_code: int | None = None,
        reason: str | None = None,
    ) -> AgentRecord:
        record.status = status
        if exit_code is not None:
            record.exit_code = exit_code
        if reason is not None:
            record.reason = reason
        if record.completed_at is None:
            record.completed_at = time.time()
            record.duration_sec = round(record.completed_at - record.created_at, 3)
        self._save_record(record)
        return record

    def _tmux_available(self) -> bool:
        return shutil.which("tmux") is not None

    def _tmux(self, *args: str, env: dict[str, str] | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
        cmd = ["tmux", *args]
        result = subprocess.run(
            cmd,
            env=env,
            text=True,
            capture_output=True,
        )
        if check and result.returncode != 0:
            raise subprocess.CalledProcessError(result.returncode, cmd, output=result.stdout, stderr=result.stderr)
        return result

    def _is_git_repo(self, cwd: str) -> bool:
        result = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--is-inside-work-tree"],
            text=True,
            capture_output=True,
        )
        return result.returncode == 0 and result.stdout.strip() == "true"

    def _create_worktree(self, agent_uuid: str, cwd: str) -> str:
        if not self._is_git_repo(cwd):
            raise RuntimeError("cwd is not a git repo")
        path = self.worktrees_dir / agent_uuid[:8]
        if path.exists():
            raise RuntimeError(f"worktree path already exists: {path}")
        branch = f"adm-{agent_uuid[:8]}"
        result = subprocess.run(
            ["git", "-C", cwd, "worktree", "add", "-b", branch, str(path), "HEAD"],
            text=True,
            capture_output=True,
        )
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip() or "failed to create worktree")
        return str(path)

    def spawn_agent(
        self,
        runtime,
        prompt,
        cwd,
        worktree: bool = False,
        provider: str | None = None,
        model: str | None = None,
        thinking: str | None = None,
        harnesses: list[str] | None = None,
        env: dict[str, str] | None = None,
        timeout_sec: int = 0,
    ) -> dict:
        if not self._tmux_available():
            raise RuntimeError("tmux not found")

        agent_uuid = uuidlib.uuid4().hex
        session = f"adm-{agent_uuid[:8]}"
        log_file = self._log_path(agent_uuid)
        log_file.parent.mkdir(parents=True, exist_ok=True)
        log_file.touch(exist_ok=True)

        workdir = cwd
        worktree_path = None
        if worktree:
            worktree_path = self._create_worktree(agent_uuid, cwd)
            workdir = worktree_path

        argv = runtime_module.build_command(
            runtime,
            prompt,
            provider=provider,
            model=model,
            thinking=thinking,
        )
        command = shlex.join(argv)
        script_path = self.state_dir / "launchers" / f"{agent_uuid}.sh"
        script_path.parent.mkdir(parents=True, exist_ok=True)
        exit_marker = self.exits_dir / f"{agent_uuid}.exit"
        timeout_marker = self.exits_dir / f"{agent_uuid}.timeout"
        script_lines = [
            "#!/usr/bin/env bash",
            "set -uo pipefail",
            "set -m",
            f"TIMEOUT={timeout_sec}",
            "ec=0",
            f"run_main() {{ {command}; }}",
            'if [ "$TIMEOUT" -gt 0 ]; then',
            '  run_main & __p=$!',
            '  ( sleep "$TIMEOUT"',
            f'    if kill -0 "$__p" 2>/dev/null; then',
            f"      printf '%s' \"$TIMEOUT\" > {shlex.quote(str(timeout_marker))}",
            '      kill -TERM -"$__p" 2>/dev/null',
            "      sleep 2",
            '      kill -KILL -"$__p" 2>/dev/null',
            '    fi ) & __w=$!',
            '  wait "$__p"; ec=$?',
            '  kill "$__w" 2>/dev/null || true',
            "else",
            "  run_main; ec=$?",
            "fi",
        ]
        for i, harness in enumerate(harnesses or [], start=1):
            script_lines.extend(
                [
                    f'echo "[harness {i}] {harness}"',
                    f'eval {shlex.quote(harness)}; hc=$?',
                    f'if [ "$hc" -ne 0 ]; then echo "[harness {i} FAILED rc=$hc]"; ec="$hc"; fi',
                ]
            )
        script_lines.extend(
            [
                f"printf '%s' \"$ec\" > {shlex.quote(str(exit_marker))}",
                'exit "$ec"',
            ]
        )
        script_path.write_text(
            "\n".join(script_lines) + "\n"
        )
        script_path.chmod(0o755)

        proc_env = os.environ.copy()
        if env:
            proc_env.update({str(k): str(v) for k, v in env.items()})

        self._tmux("new-session", "-d", "-s", session, "-c", workdir, env=proc_env)
        self._tmux("pipe-pane", "-o", "-t", session, f"cat >> {shlex.quote(str(log_file))}", env=proc_env)
        self._tmux("send-keys", "-t", session, "exec " + shlex.quote(str(script_path)), "Enter", env=proc_env)

        record = AgentRecord(
            uuid=agent_uuid,
            runtime=str(runtime),
            prompt=prompt,
            cwd=cwd,
            session=session,
            log_file=str(log_file),
            worktree=worktree_path,
            status="running",
            created_at=time.time(),
            completed_at=None,
            duration_sec=None,
            pid=None,
            command=command,
            exit_code=None,
            reason=None,
        )
        self._save_record(record)
        return record.to_dict()

    def get_agent_status(self, uuid: str) -> dict:
        record = self._load_record(uuid)
        if record.status in {"killed", "done", "failed", "timeout", "exited"}:
            payload = record.to_dict()
            payload["alive"] = False
            return payload

        timeout_marker = self.exits_dir / f"{uuid}.timeout"
        exit_marker = self.exits_dir / f"{uuid}.exit"

        if timeout_marker.exists():
            try:
                timeout_sec = int(timeout_marker.read_text().strip() or "0")
            except ValueError:
                timeout_sec = 0
            exit_code = None
            if exit_marker.exists():
                try:
                    exit_code = int(exit_marker.read_text().strip() or "0")
                except ValueError:
                    exit_code = None
            finalized = self._finalize_record(
                record,
                "timeout",
                exit_code=exit_code,
                reason=f"timeout after {timeout_sec}s",
            )
            payload = finalized.to_dict()
            payload["alive"] = False
            return payload

        if exit_marker.exists():
            try:
                exit_code = int(exit_marker.read_text().strip() or "0")
            except ValueError:
                exit_code = None
            if exit_code is not None:
                finalized = self._finalize_record(
                    record,
                    "done" if exit_code == 0 else "failed",
                    exit_code=exit_code,
                )
                payload = finalized.to_dict()
                payload["alive"] = False
                return payload

        result = self._tmux("has-session", "-t", record.session, check=False)
        if result.returncode == 0:
            payload = record.to_dict()
            payload["alive"] = True
            return payload

        finalized = self._finalize_record(record, "exited")
        payload = finalized.to_dict()
        payload["alive"] = False
        return payload

    def read_agent_output(self, uuid: str, lines: int = 80) -> dict:
        record = self._load_record(uuid)
        path = Path(record.log_file)
        if not path.exists():
            return {"uuid": uuid, "output": ""}
        output_lines = path.read_text(errors="replace").splitlines()
        text = "\n".join(output_lines[-lines:])
        if text:
            text += "\n"
        return {"uuid": uuid, "output": text}

    def send_agent_message(self, uuid: str, message: str) -> dict:
        record = self._load_record(uuid)
        result = self._tmux("has-session", "-t", record.session, check=False)
        if result.returncode != 0:
            return {"uuid": uuid, "sent": False, "reason": "session not found"}
        self._tmux("send-keys", "-t", record.session, message, "Enter")
        return {"uuid": uuid, "sent": True}

    def kill_agent(self, uuid: str, reason: str | None = None) -> dict:
        record = self._load_record(uuid)
        self._tmux("kill-session", "-t", record.session, check=False)
        finalized = self._finalize_record(record, "killed", reason=reason)
        return finalized.to_dict()

    def cleanup_worktree(self, uuid: str, force: bool = False) -> dict:
        record = self._load_record(uuid)
        if not record.worktree:
            return {"uuid": uuid, "cleaned": False, "reason": "no worktree"}

        worktree_path = Path(record.worktree)
        if not worktree_path.exists():
            return {"uuid": uuid, "cleaned": False, "reason": "worktree path missing"}

        cmd = ["git", "-C", record.cwd, "worktree", "remove"]
        if force:
            cmd.append("--force")
        cmd.append(str(worktree_path))
        result = subprocess.run(cmd, text=True, capture_output=True)
        if result.returncode != 0:
            return {"uuid": uuid, "cleaned": False, "reason": result.stderr.strip()}
        return {"uuid": uuid, "cleaned": True, "worktree": str(worktree_path)}

    def list_agents(self) -> dict:
        agents = []
        for path in sorted(self.agents_dir.glob("*.json")):
            agents.append(AgentRecord.from_dict(json.loads(path.read_text())).to_dict())
        return {"agents": agents}
