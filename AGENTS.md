# Agent instructions — Camsthetics (iOS)

Project knowledge lives in `docs/`. Always read the relevant companion documents
before touching code in this repo.

**Required reading (read before any code change in or near
`CamstheticsServices/`, `CamstheticsEngine/`, or the camera/vision/motion app
screens):**

- `docs/OPEN_OPTIMIZATIONS.md` — **mandatory while it exists.** Live backlog of
  unpatched performance / hardware-ceiling findings, each with an exact
  `file:line` and required on-device verification. Work the `OPEN` items, or
  make sure any change you make does not silently re-validate/undo them. Once a
  change closes all of them, follow that doc's own §0 and delete the file (and
  remove every "Required Reading" pointer to it, including this one).

**Landmarks to consult:** `docs/IMPLEMENTATION_PLAN.md` (phases/exit criteria),
`docs/ARCHITECTURE.md` (pipeline separation & fidelity rules, normative),
`docs/PRODUCT_SPEC.md` (FIDELITY requirements), `docs/DECISIONS.md` (ADR log —
notably ADR-012 on-device verification discipline), `docs/PHASE2_CAPTURE_PROOF.md`
& `docs/PHASE2_FIDELITY10.md` (measured device findings).

**Non-negotiables (from the docs):** analysis/preview/capture pipelines are
architecturally independent — analysis changes must never touch captured-photo
bytes (ADR-009/ADR-013, FIDELITY-01/02). No Simulator-based camera validation
(ADR-012). No hard-coded per-device assumptions; query at runtime (ADR-010,
ADR-011).