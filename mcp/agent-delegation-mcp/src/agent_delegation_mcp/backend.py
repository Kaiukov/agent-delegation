from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import uuid as uuidlib
from typing import Any
import shlex

from . import runtime as runtime_module
from .models import AgentRecord


class AgentBackend:
    def __init__(self, state_dir: Path):
        self.state_dir = state_dir
        self.agents_dir = self.state_dir / "agents"
        self.logs_dir = self.state_dir / "logs"
        self.worktrees_dir = self.state_dir / "worktrees"
        self.agents_dir.mkdir(parents=True, exist_ok=True)
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
        harnesses: Any = None,
        env: dict[str, str] | None = None,
        timeout_sec: int = 30,
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
            harnesses=harnesses,
        )
        command = shlex.join(argv)
        script_path = self.state_dir / "launchers" / f"{agent_uuid}.sh"
        script_path.parent.mkdir(parents=True, exist_ok=True)
        script_path.write_text(
            "#!/usr/bin/env bash\n"
            "set -euo pipefail\n"
            f"exec {command}\n"
        )
        script_path.chmod(0o755)

        proc_env = os.environ.copy()
        if env:
            proc_env.update({str(k): str(v) for k, v in env.items()})

        self._tmux("new-session", "-d", "-s", session, "-c", workdir, env=proc_env)
        self._tmux("pipe-pane", "-o", "-t", session, f"cat >> {shlex.quote(str(log_file))}", env=proc_env)
        self._tmux("send-keys", "-t", session, str(script_path), "Enter", env=proc_env)

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
            pid=None,
            command=command,
            reason=None,
        )
        self._save_record(record)
        return record.to_dict()

    def get_agent_status(self, uuid: str) -> dict:
        record = self._load_record(uuid)
        result = self._tmux("has-session", "-t", record.session, check=False)
        alive = result.returncode == 0
        if not alive and record.status == "running":
            record.status = "exited"
            self._save_record(record)
        payload = record.to_dict()
        payload["alive"] = alive
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
        result = self._tmux("kill-session", "-t", record.session, check=False)
        record.status = "killed"
        record.reason = reason
        self._save_record(record)
        return record.to_dict()

    def list_agents(self) -> dict:
        agents = []
        for path in sorted(self.agents_dir.glob("*.json")):
            agents.append(AgentRecord.from_dict(json.loads(path.read_text())).to_dict())
        return {"agents": agents}
