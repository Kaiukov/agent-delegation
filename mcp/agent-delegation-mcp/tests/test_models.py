from agent_delegation_mcp.models import AgentRecord


def test_agent_record_round_trip_and_defaults():
    record = AgentRecord(
        uuid="abc123",
        runtime="shell",
        prompt="echo hi",
        cwd="/tmp",
        session="adm-abc123",
        log_file="/tmp/abc123.log",
        completed_at=123.456,
        duration_sec=0.789,
    )

    assert record.status == "running"
    payload = record.to_dict()
    assert payload["completed_at"] == 123.456
    assert payload["duration_sec"] == 0.789
    assert AgentRecord.from_dict(payload) == record
