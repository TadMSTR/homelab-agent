# steward (retired; decommissioned 2026-11-13)

steward was the sole **proposer** of changes to forge's root-owned agent-config surface —
the per-agent capability manifests and the central workspace-access policy. It applied
nothing.

## Retirement

steward was taken out of service in 2026-09, and config changes stopped routing through a
proposer agent. It was fully decommissioned on 2026-11-13: its capability manifest, its
`scoped-mcp-steward` tool-broker unit and its forge-config-mcp grant record were removed, its
read-write deploy key was deleted, and the broker's port is free. Its
[forge-config-mcp](forge-config-mcp.md) service was disabled on 2026-11-15; whether that
server is removed or kept is still to be decided. Some leftovers of the dedicated OS identity
(the system user, a launcher script, a sudoers rule) are still on the host, and their removal
is tracked in vikunja#1104.

The rest of this doc is kept as a design record. The reasoning (why a config proposer
should hold its own OS identity, why the applier's invariants must sit out of every
reviewer's reach) is still the reference for anything that takes this role later. Read it
in the past tense: none of the processes, units or commands below run any more.

## Why it exists

Config was writable by the agents it governed. That is the defect in one sentence: an
allowlist is not a boundary if the entity being granted access authors the entry. Every
resident agent could edit every other agent's capability manifest, because the manifest
directory was a symlink into a git tree all of them held write on.

## The design, in the order that matters

1. **steward proposes; a human merges; a root-owned script applies.** Three parties, and
   steward is only the first.
2. **The applier holds hardcoded invariants that no proposal can lift** — not with a
   countersign, not merged, not both. That is what dissolves the self-modification
   recursion: steward may propose changes to its own config exactly as it proposes changes
   to anyone else's, because the invariants don't live anywhere steward or its reviewers
   can reach.
3. **A closed op vocabulary** ([forge-config-mcp](forge-config-mcp.md)) means dangerous
   edits aren't *representable*, not merely rejected — the tool for granting a new module
   is deliberately absent. Complementary to (2), not a substitute for it: both layers are
   built and both must hold.
4. **Its own OS identity.** steward runs as its own dedicated system user under systemd,
   not as the shared agent user under the process manager. Explaining why matters, because
   it reads as fussy otherwise: the agent's bearer token lives in an env file, and identity
   *is* the token. Under a shared user that file must stay readable by every agent sharing
   it, so any of them could authenticate as steward. Only a dedicated user permits a
   mode-400 file — the group grants traversal, not protection, and relaxing 400 to 440 "for
   consistency" would silently undo the entire control.
5. **Security countersigns**, and a verdict that doesn't state which invariant each hunk
   touches, plus the worst case if the diff is wrong, is not an approval — enforced by the
   applier itself, not merely requested by process.

## What this does *not* do

The obvious framing — "config is locked down now" — overstates it:

- **The shell bypass is still open.** The majority of resident agents still hold arbitrary
  shell as the shared agent user and reach every one of these config files regardless of
  what steward enforces. This build *unblocks* that lockdown; it does not perform it.
- **Enforcement is at git staging and commit, not the filesystem.** Other agents can still
  *edit* config on disk. They can no longer *commit* it through the sanctioned path.
- **steward's own isolation is partial.** Its mode-400 env file protects its tool-broker
  identity. Its git identity rests on a bearer token shared fleet-wide, so that identity is
  separated from every other agent by port alone, not by credential.

## Architecture

```
steward (agent-steward, systemd)
    │
    ├─ scoped-mcp-steward     tool broker, bearer-authed, own port
    │      └─ closed module allowlist (Invariant 1 of the applier — see below)
    │
    └─ forge-config-mcp       the only tool that can author a proposal
           └─ config_propose()
                  │  renders ops → manifests/*.yml, pushes a branch,
                  │  writes the four-artefact proposal record
                  ▼
           git PR (opened by steward, merged by a human)
                  ▼
           forge-config-apply.sh   root-owned, password-required
                  │  Gate 4: hardcoded invariants no proposal can lift
                  ▼
           /etc/forge/manifests/*.yml, workspace-policy.yml
```

## Process

| Field | Value |
|-------|-------|
| OS user | dedicated, not shared with other agents |
| Supervision | systemd — deliberately **not** the process manager the other resident agents run under |
| Tool broker | its own scoped-mcp instance, on its own port, bearer-authed |
| Ability to act | [forge-config-mcp](forge-config-mcp.md) only — no shell, no filesystem-write module of any kind |

It runs under its own OS identity because [forge-config-mcp](forge-config-mcp.md) writes a
group-restricted proposal store that the shared agent user cannot write. See that doc for
why the store, the git clone, and the deploy key all belong to steward rather than being
grafted onto its own git-proxy instance.

## The applier: the last line, and the only writer of `/etc/forge`

Root-owned, password-required, and the only path by which a merged proposal ever reaches
the live config. It reads the merged tree at the default branch — never a proposal branch
directly — and refuses to apply if any Gate 4 invariant fails, however thoroughly the
proposal was countersigned and merged.

**Tested, not just asserted.** Before this design shipped, the build ran one real proposal
end to end as a gate before removing anyone's manifest-write access, and separately proved
the invariants hold by authoring a fully countersigned, genuinely merged proposal granting
steward a shell-equivalent tool — and confirming the applier still refused it. A design
claim of this shape is worth documenting as *tested*, with the shape of the test, rather
than merely asserted.

## Operations

There is nothing to operate. While steward ran, its tool broker and the config-authoring
server were separate systemd units (`scoped-mcp-steward`, `forge-config-mcp`), restarted
independently and only by the operator — steward had no restart-my-own-process tool,
consistent with it holding no shell. The `scoped-mcp-steward` unit file is gone; to confirm
the other is still off:

```bash
systemctl is-enabled forge-config-mcp   # disabled
systemctl is-active forge-config-mcp    # inactive
```

## scoped-mcp integration

steward's manifest exposes only a small, allowlisted module set — checked by the applier's
Gate 4 Invariant 1 before every manifest change to steward is accepted, so the set itself
cannot silently widen through a proposal. No module in it is shell-capable; adding one that
would be is a change reviewed as code, not as config.

steward holds no `matrix` module for direct messaging and no filesystem-write module of any
kind. The only module that lets it act on the world is
[forge-config-mcp](forge-config-mcp.md).

## Related docs

- [forge-config-mcp.md](forge-config-mcp.md) — the closed op vocabulary steward uses to
  author every proposal
- [scoped-mcp.md](scoped-mcp.md) — the per-agent tool-proxy pattern steward's own instance
  follows
