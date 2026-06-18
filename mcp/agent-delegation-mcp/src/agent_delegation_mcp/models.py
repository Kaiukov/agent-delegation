from __future__ import annotations

from dataclasses import dataclass, field
from typing import Literal
import time

AgentRuntime = Literal["shell", "pi", "codex", "claude"]


@dataclass(eq=True)
class AgentRecord:
    uuid: str
    runtime: str
    prompt: str
    cwd: str
    session: str
    log_file: str
    worktree: str | None = None
    status: str = "running"
    created_at: float = field(default_factory=time.time)
    completed_at: float | None = None
    duration_sec: float | None = None
    pid: int | None = None
    command: str = ""
    exit_code: int | None = None
    reason: str | None = None

    def to_dict(self) -> dict:
        return {
            "uuid": self.uuid,
            "runtime": self.runtime,
            "prompt": self.prompt,
            "cwd": self.cwd,
            "session": self.session,
            "log_file": self.log_file,
            "worktree": self.worktree,
            "status": self.status,
            "created_at": self.created_at,
            "completed_at": self.completed_at,
            "duration_sec": self.duration_sec,
            "pid": self.pid,
            "command": self.command,
            "exit_code": self.exit_code,
            "reason": self.reason,
        }

    @classmethod
    def from_dict(cls, data: dict) -> "AgentRecord":
        return cls(
            uuid=data["uuid"],
            runtime=data["runtime"],
            prompt=data["prompt"],
            cwd=data["cwd"],
            session=data["session"],
            log_file=data["log_file"],
            worktree=data.get("worktree"),
            status=data.get("status", "running"),
            created_at=float(data.get("created_at", time.time())),
            completed_at=data.get("completed_at"),
            duration_sec=data.get("duration_sec"),
            pid=data.get("pid"),
            command=data.get("command", ""),
            exit_code=data.get("exit_code"),
            reason=data.get("reason"),
        )
