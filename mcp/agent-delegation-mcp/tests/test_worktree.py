from __future__ import annotations

import shutil
import subprocess
import time
from pathlib import Path

import pytest

from agent_delegation_mcp.backend import AgentBackend


pytestmark = pytest.mark.skipif(shutil.which("tmux") is None, reason="needs tmux")


def _poll_status(backend: AgentBackend, agent_uuid: str, deadline: float) -> dict:
    status = backend.get_agent_status(agent_uuid)
    while time.time() < deadline:
        if status.get("status") in {"done", "failed", "killed", "exited", "timeout"}:
            return status
        time.sleep(0.2)
        status = backend.get_agent_status(agent_uuid)
    return status


def _init_git_repo(repo_dir: Path) -> None:
    subprocess.run(["git", "init", str(repo_dir)], check=True, text=True, capture_output=True)
    subprocess.run(
        ["git", "-C", str(repo_dir), "config", "user.email", "tests@example.com"],
        check=True,
        text=True,
        capture_output=True,
    )
    subprocess.run(
        ["git", "-C", str(repo_dir), "config", "user.name", "Tests"],
        check=True,
        text=True,
        capture_output=True,
    )
    (repo_dir / "README.md").write_text("test repo\n")
    subprocess.run(["git", "-C", str(repo_dir), "add", "README.md"], check=True, text=True, capture_output=True)
    subprocess.run(["git", "-C", str(repo_dir), "commit", "-m", "init"], check=True, text=True, capture_output=True)


def test_worktree_spawn_creates_unique_existing_paths(tmp_path: Path):
    repo_dir = tmp_path / "repo"
    repo_dir.mkdir()
    _init_git_repo(repo_dir)

    backend = AgentBackend(tmp_path / "state")

    first = backend.spawn_agent(runtime="shell", prompt="echo first", cwd=str(repo_dir), worktree=True)
    second = backend.spawn_agent(runtime="shell", prompt="echo second", cwd=str(repo_dir), worktree=True)

    first_status = _poll_status(backend, first["uuid"], time.time() + 10)
    second_status = _poll_status(backend, second["uuid"], time.time() + 10)

    assert first_status["status"] in {"done", "failed", "exited"}
    assert second_status["status"] in {"done", "failed", "exited"}
    assert first_status["worktree"]
    assert second_status["worktree"]
    assert first_status["worktree"] != second_status["worktree"]
    assert Path(first_status["worktree"]).exists()
    assert Path(second_status["worktree"]).exists()

    cleaned_first = backend.cleanup_worktree(first["uuid"])
    assert cleaned_first["cleaned"] is True
    assert "worktree" in cleaned_first

    cleaned_first_again = backend.cleanup_worktree(first["uuid"])
    assert cleaned_first_again["cleaned"] is False

    cleaned_second = backend.cleanup_worktree(second["uuid"])
    assert cleaned_second["cleaned"] is True


def test_worktree_spawn_requires_git_repo(tmp_path: Path):
    backend = AgentBackend(tmp_path / "state")

    with pytest.raises(RuntimeError, match="git repo"):
        backend.spawn_agent(
            runtime="shell",
            prompt="echo hi",
            cwd=str(tmp_path),
            worktree=True,
        )


def test_cleanup_worktree_without_worktree_returns_reason(tmp_path: Path):
    backend = AgentBackend(tmp_path / "state")

    record = backend.spawn_agent(runtime="shell", prompt="echo hi", cwd=str(tmp_path), worktree=False)
    status = _poll_status(backend, record["uuid"], time.time() + 10)

    assert status["status"] == "done"

    cleaned = backend.cleanup_worktree(record["uuid"])
    assert cleaned["cleaned"] is False
    assert cleaned["reason"] == "no worktree"
