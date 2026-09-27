"""Normalize LLM_MODEL before byLLM resolves its ambient model.

jac.toml sets `default_model = "${LLM_MODEL:-mockllm}"`, but Jac's `:-` only
falls back when the variable is unset. An empty LLM_MODEL (a blank line in
.env, an empty platform env var) would reach byLLM as "" and make every
module import raise when no provider key is set. Empty or "off"-style values
therefore mean "LLM off": byLLM's own BYLLM_DEFAULT_MODEL override (read when
the ambient model is first resolved) is pointed at its null model.

Import this before anything that imports jaclang.byllm.
"""

import os;

glob LLM_OFF_VALUES: list[str] = ["", "off", "none", "false", "0", "disabled"];

"""True when an LLM_MODEL value means the LLM is off."""
def llm_model_off(value: str) -> bool {
    return value.strip().lower() in LLM_OFF_VALUES;
}

def normalize_llm_env {
    value = os.environ.get("LLM_MODEL");
    if value is not None and llm_model_off(value) and not os.environ.get("BYLLM_DEFAULT_MODEL", "").strip() {
        os.environ["BYLLM_DEFAULT_MODEL"] = "mockllm";
    }
}

with entry {
    normalize_llm_env();
}
