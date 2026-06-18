from agent_delegation_mcp.models import AgentRecord


def test_agent_record_round_trip_and_defaults():
    record = AgentRecord(
        uuid="abc123",
        runtime="shell",
        prompt="echo hi",
        cwd="/tmp",
        session="adm-abc123",
        log_file="/tmp/abc123.log",
    )

    assert record.status == "running"
    assert AgentRecord.from_dict(record.to_dict()) == record
