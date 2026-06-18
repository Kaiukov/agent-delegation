from __future__ import annotations


def build_command(
    runtime: str,
    prompt: str,
    *,
    provider: str | None = None,
    model: str | None = None,
    thinking: str | None = None,
) -> list[str]:
    if runtime == "shell":
        return ["bash", "-lc", prompt]
    if runtime == "pi":
        argv = ["pi", "-p", prompt]
        if provider is not None:
            argv.extend(["--provider", provider])
        if model is not None:
            argv.extend(["--model", model])
        if thinking is not None:
            argv.extend(["--thinking", thinking])
        return argv
    if runtime == "codex":
        argv = ["codex", "exec", prompt]
        if model is not None:
            argv.extend(["--model", model])
        return argv
    if runtime == "claude":
        argv = ["claude", "-p", prompt]
        if model is not None:
            argv.extend(["--model", model])
        return argv
    raise ValueError(f"unknown runtime: {runtime}")
