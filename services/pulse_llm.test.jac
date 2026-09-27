"""llm_status diagnostic tests (MockLLM, no network)."""

import os;
import from jaclang.byllm.lib { MockLLM, MockError }

test "llm_status is disabled unless DEBUG_LLM is set" {
    os.environ.pop("DEBUG_LLM", None);
    res = llm_status();
    assert "disabled" in str(res["error"]);
    assert "model" not in res and "keys_present" not in res;
}

test "llm_status reports mode, model and a test call without key values" {
    os.environ["DEBUG_LLM"] = "1";
    os.environ["OPENAI_API_KEY"] = "sk-test-secret-value-1234567890";
    set_llm(MockLLM(model_name="mockllm", config={"outputs": ["ok"]}), "mockllm");
    res = llm_status();
    set_llm(None);
    assert res["llm_on"] and res["model"] == "mockllm";
    assert res["test"]["ran"] and res["test"]["ok"] and res["test"]["reply"] == "ok";
    assert res["test"]["latency_ms"] >= 0;
    assert res["keys_present"]["OPENAI_API_KEY"] is True;
    assert "sk-test-secret-value-1234567890" not in str(res);
    os.environ.pop("OPENAI_API_KEY", None);
}

test "a failing test call returns a redacted error" {
    os.environ["DEBUG_LLM"] = "1";
    os.environ["OPENAI_API_KEY"] = "sk-test-secret-value-1234567890";
    set_llm(MockLLM(model_name="mockllm", config={"outputs": [MockError(error=RuntimeError("401 Incorrect API key provided: sk-test-secret-value-1234567890"))]}), "mockllm");
    res = llm_status();
    set_llm(None);
    assert res["test"]["ran"] and not res["test"]["ok"];
    assert "401" in str(res["test"]["error"]);
    assert "sk-test" not in str(res["test"]["error"]), res["test"]["error"];
    os.environ.pop("OPENAI_API_KEY", None);
}

test "llm off skips the test call" {
    os.environ["DEBUG_LLM"] = "1";
    set_llm(None);
    res = llm_status();
    assert not res["llm_on"] and res["test"] == {"ran": False};
    assert _redact("Bearer abcdefghijkl and key-zzzzzzzz") == "[redacted] and [redacted]";
}

test "every LLM call error is redacted, so traces and logs never carry key hints" {
    def fail_auth -> str {
        raise RuntimeError("Incorrect API key provided: sk-bogus********************0000. See docs.");
    }
    res = call_with_deadline(fail_auth, [], 1.0);
    assert not res["ok"];
    assert "sk-bogus" not in str(res["error"]) and "[redacted]" in str(res["error"]), res["error"];
}
