"""Provider-neutral LLM hookup for A2 Pulse.

The model comes from LLM_MODEL (LiteLLM naming, e.g. gpt-4o-mini,
claude-haiku-4-5, gemini/gemini-2.0-flash, ollama/llama3) plus that provider's
key. With no model or no key every caller uses its heuristic/template fallback
and no LLM code runs at all. When on, each call gets a hard deadline
(LLM_TIMEOUT_S) and falls back on timeout or error.

Optional: LLM_API_KEY (one key for any provider) and LLM_API_BASE (an
OpenAI-compatible gateway URL, with LLM_MODEL like "openai/<model>").
jac.toml passes the same two settings to the ambient `by llm` model.
"""

import os;
import re;
import time;
import from pathlib { Path }
import threading;
# Must come before any byLLM import: empty/off LLM_MODEL would otherwise crash it.
import from services.llm_env { llm_model_off }
import from jaclang.byllm.lib { Model }

glob LLM_TIMEOUT_S: float = 8.0;

# Provider prefix (LiteLLM "provider/model", or a bare-name family) -> env keys, any one of which unlocks it.
glob PROVIDER_KEYS: dict[str, list[str]] = {
    "openai": ["OPENAI_API_KEY"],
    "anthropic": ["ANTHROPIC_API_KEY"],
    "gemini": ["GEMINI_API_KEY", "GOOGLE_API_KEY"],
    "vertex_ai": ["GOOGLE_APPLICATION_CREDENTIALS"],
    "mistral": ["MISTRAL_API_KEY"],
    "groq": ["GROQ_API_KEY"],
    "deepseek": ["DEEPSEEK_API_KEY"],
    "together_ai": ["TOGETHERAI_API_KEY", "TOGETHER_API_KEY"],
    "openrouter": ["OPENROUTER_API_KEY"],
    "xai": ["XAI_API_KEY"],
    "cohere": ["COHERE_API_KEY"],
    "azure": ["AZURE_API_KEY"],
    "bedrock": ["AWS_ACCESS_KEY_ID"],
    "ollama": [],
    "ollama_chat": [],
    "local": []
};

# Bare model names LiteLLM maps to a provider without a "provider/" prefix.
glob BARE_FAMILIES: list[list[str]] = [
    ["gpt-", "openai"], ["o1", "openai"], ["o3", "openai"], ["o4", "openai"],
    ["chatgpt", "openai"], ["claude", "anthropic"], ["gemini-", "gemini"]
];

glob _llm_status: dict[str, any] = {},
     brief_llm: any = None;

"""Read the project .env into os.environ without overriding anything already set.
`jac run` / `jac test` do not load .env on their own."""
def _load_dotenv {
    here = Path(str(__file__ or ".")).resolve().parent.parent / ".env";
    for path in [here, Path.cwd() / ".env"] {
        if not path.is_file() {
            continue;
        }
        try {
            for line in path.read_text().splitlines() {
                s = line.strip();
                if not s or s.startswith("#") or "=" not in s {
                    continue;
                }
                (k, v) = s.split("=", 1);
                k = k.strip().removeprefix("export ").strip();
                v = v.strip().strip('"').strip("'");
                if k and k not in os.environ {
                    os.environ[k] = v;
                }
            }
        } except Exception {
            continue;
        }
        return;
    }
}

"""Which provider a LiteLLM model name routes to ("" when unknown)."""
def llm_provider(model: str) -> str {
    m = model.strip().lower();
    if "/" in m {
        return m.split("/", 1)[0];
    }
    if m.startswith("local:") {
        return "local";
    }
    for fam in BARE_FAMILIES {
        if m.startswith(fam[0]) {
            return fam[1];
        }
    }
    return "";
}

"""Decide once whether the LLM is on. LLM_API_KEY is a generic override for any provider."""
def _resolve_status -> dict[str, any] {
    raw = os.environ.get("LLM_MODEL");
    model = (raw or "").strip();
    if raw is None or model == "" {
        return {"on": False, "model": "", "provider": "", "reason": "LLM_MODEL is not set"};
    }
    if llm_model_off(model) {
        return {"on": False, "model": "", "provider": "", "reason": "LLM_MODEL is off"};
    }
    provider = llm_provider(model);
    generic = os.environ.get("LLM_API_KEY", "").strip();
    if generic {
        return {"on": True, "model": model, "provider": provider or "custom", "reason": "", "api_key_env": "LLM_API_KEY"};
    }
    if os.environ.get("LLM_API_BASE", "").strip() {
        return {"on": False, "model": model, "provider": provider, "reason": "LLM_API_BASE is set but LLM_API_KEY is not"};
    }
    if provider not in PROVIDER_KEYS {
        return {"on": False, "model": model, "provider": provider, "reason": "unknown provider for " + model + "; set LLM_API_KEY"};
    }
    keys = PROVIDER_KEYS[provider];
    if len(keys) == 0 {
        return {"on": True, "model": model, "provider": provider, "reason": ""};
    }
    for k in keys {
        if len(os.environ.get(k, "").strip()) > 8 {
            return {"on": True, "model": model, "provider": provider, "reason": ""};
        }
    }
    return {"on": False, "model": model, "provider": provider, "reason": " or ".join(keys) + " is not set"};
}

def _configure {
    _load_dotenv();
    _llm_status = _resolve_status();
    brief_llm = None;
    if _llm_status["on"] {
        generic = os.environ.get("LLM_API_KEY", "").strip();
        base = os.environ.get("LLM_API_BASE", "").strip();
        brief_llm = Model(model_name=_llm_status["model"], api_key=generic, config=({"base_url": base} if base else {}));
        try {
            import litellm;
            # Bound the provider request itself too, so timed-out worker threads die soon after the deadline.
            litellm.request_timeout = LLM_TIMEOUT_S + 2.0;
            litellm.num_retries = 0;
        } except Exception {
        }
        via = " via LLM_API_BASE" if os.environ.get("LLM_API_BASE", "").strip() else "";
        print(f"LLM: {_llm_status['model']} ({_llm_status['provider']}){via}, {int(LLM_TIMEOUT_S)}s timeout");
    } else {
        print(f"LLM: off, using fallbacks ({_llm_status['reason']})");
    }
}

"""True when an LLM is configured with a key. Cheap: no network, no imports."""
def llm_enabled -> bool {
    return bool(_llm_status.get("on", False)) and brief_llm is not None;
}

"""Model name for traces and the UI ("" when off)."""
def llm_model_label -> str {
    return str(_llm_status.get("model", "")) if llm_enabled() else "";
}

def llm_config_status -> dict[str, any] {
    return dict(_llm_status);
}

"""Swap the model (tests inject MockLLM here). None turns the LLM off."""
def set_llm(model: any, label: str = "") {
    brief_llm = model;
    _llm_status = {
        "on": model is not None,
        "model": label or (str(model.model_name) if model is not None else ""),
        "provider": "test",
        "reason": "" if model is not None else "disabled"
    };
}

"""Run fn(*args) with a hard deadline. Never raises.
Returns {"ok", "value", "error", "ms"}. The call runs on a daemon thread, so a
provider that hangs past the deadline is abandoned and never blocks shutdown."""
def call_with_deadline(fn: any, args: list[any], seconds: float = LLM_TIMEOUT_S) -> dict[str, any] {
    box: dict[str, any] = {"value": None, "error": ""};
    def work {
        try {
            box["value"] = fn(*args);
        } except Exception as e {
            # Provider errors can echo a masked key; scrub before it reaches traces or logs.
            box["error"] = _redact(f"{type(e).__name__}: {str(e)}");
        }
    }
    t0 = time.perf_counter();
    th = threading.Thread(target=work, daemon=True, name="pulse-llm");
    th.start();
    th.join(timeout=seconds);
    ms = round((time.perf_counter() - t0) * 1000, 1);
    if th.is_alive() {
        return {"ok": False, "value": None, "error": f"timed out after {seconds}s", "ms": ms};
    }
    if box["error"] {
        return {"ok": False, "value": None, "error": box["error"], "ms": ms};
    }
    return {"ok": True, "value": box["value"], "error": "", "ms": ms};
}

# ---------------------------------------------------------------- diagnostics
def llm_ping -> str by brief_llm(temperature=0.0, max_tokens=5, max_output_retries=0);
sem llm_ping = "Connectivity check. Reply with exactly the word: ok";

"""Env var names that can carry an LLM credential (names only are ever reported)."""
def _key_env_names -> list[str] {
    names: list[str] = ["LLM_API_KEY"];
    for keys in PROVIDER_KEYS.values() {
        for k in keys {
            if k not in names {
                names.append(k);
            }
        }
    }
    return names;
}

"""Scrub anything key-shaped from a provider error before returning it."""
def _redact(msg: str) -> str {
    out = msg;
    for k in _key_env_names() {
        v = os.environ.get(k, "").strip();
        if len(v) > 8 {
            out = out.replace(v, "[redacted]");
        }
    }
    return re.sub(r"(sk-|sk_|AIza|key-|Bearer\s+)[\w\-\*\.]{4,}", "[redacted]", out)[:300];
}

"""What the running process sees: LLM mode, model, which key names are set
(never values), and optionally one tiny test call through the same model and
8s deadline the Editor and Ask box use."""
def diagnose(probe: bool = True) -> dict[str, any] {
    ambient = "";
    try {
        import from jaclang.byllm.config_loader { get_byllm_config }
        ambient = os.environ.get("BYLLM_DEFAULT_MODEL", "").strip() or str(get_byllm_config().get_model_config().get("default_model", ""));
    } except Exception {
        ambient = "unknown";
    }
    st = llm_config_status();
    out: dict[str, any] = {
        "llm_on": llm_enabled(),
        "model": str(st.get("model", "")),
        "provider": str(st.get("provider", "")),
        "reason_off": str(st.get("reason", "")),
        "gateway_base_url_set": bool(os.environ.get("LLM_API_BASE", "").strip()),
        "ambient_by_llm_model": ambient,
        "keys_present": {k: bool(os.environ.get(k, "").strip()) for k in _key_env_names()},
        "timeout_s": LLM_TIMEOUT_S,
        "test": {"ran": False}
    };
    if probe and llm_enabled() {
        res = call_with_deadline(llm_ping, []);
        out["test"] = {
            "ran": True,
            "ok": res["ok"],
            "latency_ms": res["ms"],
            "reply": _redact(str(res["value"] or ""))[:40] if res["ok"] else "",
            "error": "" if res["ok"] else _redact(str(res["error"]))
        };
    }
    return out;
}

"""Diagnostic endpoint: LLM mode, model and one tiny test call (ok or error, latency).
Only answers when DEBUG_LLM=1 is set in the server environment; never returns key values."""
def:pub llm_status(probe: bool = True) -> dict {
    if os.environ.get("DEBUG_LLM", "").strip().lower() not in ["1", "true", "yes"] {
        return {"error": "llm_status is disabled; set DEBUG_LLM=1 on the server to enable it"};
    }
    return diagnose(probe);
}

with entry {
    _configure();
}
