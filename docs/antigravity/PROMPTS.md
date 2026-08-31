# Antigravity prompts — Aesthetic Camera Coach

Copy-paste these. They are short on purpose: the heavy lifting lives in `AGENTS.md` and `.agent/rules/`, which Antigravity loads on every session, so the prompt does not have to re-explain the project each time.

**Settings before you start**
- Mode: **Planning** (not Fast) for phases 1, 3, 4, 5, 7. Fast is fine for 2, 6, 8.
- Review policy: **Request Review** while you learn how it behaves. Loosen later, not sooner.
- Model: the strongest one you have quota for on phases 4 and 5 — that is where the math is. Cheaper models are fine for phase 1 scaffolding.
- Enable nested `AGENTS.md` loading in Settings → Agent if you want per-module rules later.

---

## 1. Bootstrap (run once)

> Read `SPEC.md` in full before doing anything else. There is no `FEATURE_DECK.md` in this repo - where SPEC.md references it, note the gap and move on. Do not write any implementation code in this session.
>
> Then produce three things:
>
> 1. **A spec comprehension report.** In your own words: what the app does, the two modes, why `:core:coaching` is isolated, and the five hardest technical problems in the build. I am checking whether you actually read it — if your summary is generic, you did not.
> 2. **A gap list.** Everything in the spec that is ambiguous, contradictory, or insufficient to implement from. Quote the section. Do not fix anything; just list it. Pay particular attention to §14.3 (the client-secret problem) and every constant marked *(calibrate)* in Appendix A.
> 3. **`PROGRESS.md`** at the repo root: a table of the eight phases from §23 with columns `Phase | Scope | Exit criterion | Status | Evidence | Blockers`. All statuses `Not started`. Add an `Open decisions` section seeded from §25.
>
> Then stop and wait. Do not scaffold the project.

---

## 2. Start a phase (run once per phase)

> `/build-phase 1`
>
> Follow the workflow exactly. Stop after the plan and wait for my review.

Change the number each time. That is the whole prompt — the workflow file carries the rest.

If you do not have workflows set up, use this instead:

> Build phase 1 from `SPEC.md` §23. Read the phase scope and exit criterion, then every §4 feature entry in scope, then the sections those reference.
>
> Produce an implementation plan first: scope (feature IDs, and what you are explicitly NOT doing), every file you will create, the §7 contracts you implement, every Appendix A constant you will use, the test list mapped one-to-one to the §4 acceptance criteria, how you will demonstrate the exit criterion, and any open questions the spec does not answer.
>
> Stop after the plan. Do not write implementation code until I approve it.

---

## 3. Approve a plan

> Approved. Implement it. One feature ID at a time, tests first for anything in `:core:coaching`, run the tests after each feature. Cite the spec section in a comment for every formula you implement. Stop and ask if you hit anything the spec does not cover.

Or, when the plan is wrong:

> Not yet. Problems with the plan:
>
> 1. …
> 2. …
>
> Revise the plan and show it again. Do not write code.

---

## 3b. Mid-phase reachability check (use before you believe "it's done")

Cheap insurance. Send this any time the agent claims a phase is finished:

> Before I accept this: trace the path from a cold app launch to the feature you just built — launcher, Activity, nav graph route, screen. Is `Navigation.kt` still rendering a Phase 1 placeholder for that route? Then run section 3b of the build-phase workflow on the connected device and tell me what the screenshot actually shows.

Phase 2 was reported complete three times while every screen it built was unreachable from the running app, because the nav graph was never touched. Unit tests cannot catch that.

---

## 4. Close a phase

> Verify phase N against the §23 exit criterion and the step-3 checklist in the build-phase workflow. Show me actual command output for the exit criterion — not a claim that it passes.
>
> Then produce the walkthrough and update `PROGRESS.md`.
>
> Do not start the next phase.

---

## 5. When it drifts (you will need this)

> Stop. You have deviated from `SPEC.md`. Specifically: <what it did>.
>
> The spec says <section> <what it says>.
>
> Per `AGENTS.md`, deviations are proposed, not implemented. Revert the deviation, or — if you believe the spec is wrong — state the case and wait. Do not proceed until this is resolved.

For the recurring failure mode of inlined constants:

> `/spec-audit :core:coaching`

---

## 6. Phase-specific additions

Paste these **with** the phase-2 prompt for the phases that need them.

**Phase 3 (Pinterest) — the blocker:**

> Before writing any OAuth code, read §14.3. The Pinterest v5 token endpoint requires a client secret, which cannot ship in an APK. Confirm with me which resolution has been chosen — token broker (B1-Opt-A) or dropping OAuth from v1 — and do not write token-exchange code until I answer. Build F-B3 (paste-a-link) first regardless; it has no auth dependency and it is what makes the app usable if OAuth slips.

**Phase 4 (coaching core) — the important one:**

> This phase touches no camera code and no Android APIs. `:core:coaching` is a `kotlin("jvm")` module; if you need an Android type, you have put the code in the wrong place.
>
> Write the sign-error regression suite (§20.2) before the delta engine. Write the match-scorer property tests (§12.6) before the scorer. Assemble the golden set (§20.4) as a resource directory with a JSON label file and record the baseline accuracy in `PROGRESS.md` — that number is what protects every later tuning change.
>
> Constants marked *(calibrate)* stay at their placeholder values. Do not fit them to make a test pass; mark the call site and move on.

**Phase 5 (live loop) — where it gets expensive:**

> Build the debug trace recorder first (§20.4/§20.5): frame sequences plus synchronized sensor logs, so tuning happens offline against replays instead of by walking outside with a phone. Record 15 traces before you tune anything.
>
> Measure S1 (sample latency p95), S2 (sustained fps) and S4 (instruction flip rate) on a real device and put the numbers in `PROGRESS.md`. If any budget is missed, report it — do not adjust the budget.
>
> The overlay interpolates between samples and redraws at display refresh. It must not tick at the 8 Hz sample rate.

**Phase 7 (Mode A):**

> Development runs against the Pinterest sandbox flavor. Trial access is 1000 requests per day for the whole app (§14.5) — a naive sync burns it in one run. Implement the rate-limit reserve and resumable indexing before you first run the sync worker, not after.

---

## 7. Running agents in parallel

Antigravity can run several agents at once. It is worth it only where the work does not share files. Safe splits:

| Agent A | Agent B | Why it is safe |
|---|---|---|
| Phase 4 `:core:coaching` | Golden-set assembly + label file | Different directories, no shared source |
| Phase 3 `:data:pinterest` | Phase 2 `:core:camera` | Different modules, no shared source |
| Any phase | `/spec-audit` on completed modules | Audit is read-only |

Do not parallelize across a module boundary that one agent is actively changing, and do not run two agents that both touch `SPEC.md`.

---

## 8. The habit that matters

Review the **plan**, not the code. Correcting the agent's reasoning before it writes 500 lines is the difference between this working and this becoming a repo you have to read line by line. When you are tempted to hit approve to get to the code faster, that is exactly the moment to read the plan properly.
