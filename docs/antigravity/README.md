# Antigravity kit — Aesthetic Camera Coach

## Install

Installed layout in this repo:

```
your-project/
├── SPEC.md                    ← the contract
├── AGENTS.md                  ← from this kit
├── PROGRESS.md                ← the agent creates this in the bootstrap prompt
└── .agent/
    ├── rules/
    │   ├── 01-architecture.md
    │   ├── 02-spec-fidelity.md
    │   ├── 03-kotlin-android.md
    │   ├── 04-testing.md
    │   └── 05-security-privacy.md
    └── workflows/
        ├── build-phase.md
        └── spec-audit.md
```

`PROMPTS.md` and this README live in `docs/antigravity/` so the agent does not mistake them for project documentation. They are for you.

## What each piece does

| File | Loaded when | Purpose |
|---|---|---|
| `AGENTS.md` | Every session, automatically | Binds the agent to SPEC.md, lists the ten non-negotiables, sets the working style |
| `.agent/rules/*.md` | Every session, automatically | Standing constraints, split by concern so you can edit one without touching the rest |
| `.agent/workflows/*.md` | On `/build-phase`, `/spec-audit` | Repeatable playbooks with a mandatory plan-and-stop gate |
| `PROGRESS.md` | Read at session start | Phase state, so a fresh session knows where it is |

Rules and AGENTS.md together are ~230 lines, well inside the ~500–1000 line budget Antigravity recommends before rules start eating the context window.

## Order of operations

1. Drop the files in. Open the project in Antigravity.
2. Run the **bootstrap** prompt from `PROMPTS.md` §1. Read the gap list carefully — that is the agent telling you where your spec is thin, before it costs you anything.
3. Answer the open decisions, especially §25 Q3 (token broker or no OAuth) and Q8 (which reference device the budgets are quoted against).
4. `/build-phase 1`. Review the plan. Approve.
5. Repeat through phase 8, one phase per session.

## If Antigravity's version does not support `.agent/`

Older builds read only `AGENTS.md` / `GEMINI.md`. In that case concatenate the five rule files into the bottom of `AGENTS.md` under a `# Rules` heading, and paste the workflow body inline as the phase prompt instead of `/build-phase N`.
