# Memory Architecture

Forge's agent memory system has two parallel layers: **flat notes** (the canonical source of truth,
organised into three promotion tiers) and **indices** (derived from the notes, enabling different
query styles). Graphiti is a third, complementary layer for relational and temporal knowledge that
doesn't map well to flat text.

---

## The Three-Tier Note Store

All agent memory begins as markdown files. Files move forward through tiers as they are promoted;
nothing is deleted outright — older tiers are archived to NFS.

```mermaid
flowchart LR
    S["**Session tier**\n.memsearch/spool/\n(per-project)"]
    W["**Working tier**\n~/.claude/memory/\n(main note store)"]
    D["**Distilled tier**\n~/.claude/memory/distilled/\n(long-lived summaries)"]
    A[("**NFS archive**\natlas <nas-ip>\nappend-only")]

    S -- "memory-promote-daily\n23:00 daily" --> W
    W -- "memory-sync-weekly\nMon 07:00" --> D
    W -- "memory-archive-mirror\n02:30 daily" --> A
    D -- "memory-archive-mirror\n02:30 daily" --> A
```

| Tier | Location | What lives here | Written by |
|------|----------|----------------|-----------|
| Session | `~/.claude/projects/*/.memsearch/spool/` | Raw session transcripts (per-project) | memsearch plugin, memsearch-summarize |
| Working | `~/.claude/memory/` | Active notes, decisions, agent memories | Agents, memory-promote-daily |
| Distilled | `~/.claude/memory/distilled/` | Compressed long-term summaries | memory-sync-weekly |
| Archive | NFS (atlas) | All tiers, append-only with change history | memory-archive-mirror |

---

## The Index Layer

The note files are the source of truth. The indices are derived and can be rebuilt. Four indices
serve different query needs:

```mermaid
flowchart TD
    notes["**~/.claude/memory/**\nmarkdown files (working + distilled)"]

    notes --> mw["memsearch-watch\npoll 300s"]
    mw --> milvus[("**Milvus** :19530\nvector index\n(BGE-M3 embeddings)")]
    milvus --> mm["**memsearch-mcp** :8493\nhybrid vector+BM25+reranker"]

    milvus --> qmd_svc["**qmd** :8181\nsemantic + BM25 + HyDE\n(9k docs, 40+ collections)"]
    notes --> qr["qmd-refresh\nhourly cron"]
    qr --> qmd_svc

    notes --> meta["**memory-metadata-mcp** :8490\nSQLite frontmatter index"]
    meta --> sqlite[("**.metadata.db**\nSQLite")]
    sqlite --> os_sync["memory-os-sync\nalways-on 30s"]
    os_sync --> opensearch[("**OpenSearch** :9202\nfull-text BM25")]
    opensearch --> search["**memory-search-mcp** :8491\nfull-text body search"]
```

### Choosing a query path

| Need | Use | Why |
|------|-----|-----|
| Semantic / fuzzy recall across memory notes | `memsearch-mcp` | Hybrid vector+BM25 with local reranker — best recall |
| Semantic search across all forge docs (not just notes) | `qmd` | Covers 9k docs across 40+ collections |
| Filter notes by tag, date, tier, or category | `memory-metadata-mcp` | Structured frontmatter queries without reading bodies |
| Find notes containing a specific phrase or term | `memory-search-mcp` | Full-text BM25 over note bodies |

---

## Procedural Layer

The skills system is the procedural memory tier — reusable agent behaviors stored as SKILL.md files.
Unlike the note store (observations, decisions) or Graphiti (entity relationships), skills encode
*how to do things*: multi-step procedures, tool sequencing, and domain-specific workflows.

```mermaid
flowchart LR
    subgraph "Procedural layer"
        skills_repo["agent-platform-skills\ngitea repo\n(SKILL.md files)"]
        skills_dir["~/.claude/skills/\n(hard links to repo)"]
        sysrem["System-reminder injection\nClaude Code settings"]
    end

    skills_repo -- "qmd hourly refresh" --> qmd_proc["qmd :8181\nagent-platform-skills collection"]
    skills_repo -- "hard links" --> skills_dir
    skills_dir -- "settings.json" --> sysrem

    agents["Forge agents"] -- "qmd query at runtime" --> qmd_proc
    sysrem -- "available skills list\ninjected at session start" --> agents
```

| Access path | When to use |
|-------------|-------------|
| System-reminder injection | Immediate: skills available without a query |
| qmd (`agent-platform-skills` collection) | Retrieval: search for a skill by task description |

Skills are not promoted through the session/working/distilled pipeline — they are versioned in Git
and indexed by qmd independently. The authoritative source is the Gitea repo; the hard links at
`~/.claude/skills/` keep deployed copies in sync automatically.

---

## Graphiti — Relational Layer

Graphiti is a parallel system, not part of the note or index layer. It stores **entities and
relationships** (not document chunks) in Neo4j with temporal metadata — when facts were true and
when they changed.

Use Graphiti for:
- "What services does SWAG depend on?"
- "When did this architectural decision change?"
- "Which agents have access to which tools?"

Use the note/index layer for:
- Free-text observations, session notes, decisions
- Anything an agent wrote down mid-session

```mermaid
flowchart LR
    subgraph "Note + Index layer"
        W2["~/.claude/memory/"] --> milvus2[("Milvus")]
        W2 --> sqlite2[("SQLite / OpenSearch")]
    end

    subgraph "Graph layer"
        neo4j[("**Neo4j** :7687")] --> graphiti_mcp["**graphiti-mcp** :8000"]
    end

    agents["Forge agents"] --> milvus2
    agents --> sqlite2
    agents --> graphiti_mcp
    agents --> W2
```

Graphiti is populated by `add_memory` calls from agents at infrastructure change events (deploys,
topology changes, service additions). It is not fed by the promotion pipeline.

See [graphiti.md](graphiti.md) for configuration, stack details, and operations.

---

## Full System Map

```mermaid
flowchart TD
    spool["Session spool\n.memsearch/spool/\n(raw per-project transcripts)"]
    working["Working notes\n~/.claude/memory/\n(active agent knowledge)"]
    distilled["Distilled notes\n~/.claude/memory/distilled/\n(compressed long-term summaries)"]
    nfs[("NFS archive\natlas\n(append-only, all tiers)")]

    spool -- "① promote-daily 23:00\nscores notes, promotes\nhigh-value ones to working" --> working
    working -- "② sync-weekly Mon 07:00\ncompresses & summarizes\nworking notes into distilled" --> distilled
    working & distilled -- "③ archive-mirror 02:30\npoint-in-time backup snapshot\nwith change history" --> nfs

    working --> summarize["memsearch-summarize :8494\n(session digest writer)"]
    summarize -- "④ sends raw note chunks\nfor LLM summarization" --> anthropic["Anthropic API"]
    anthropic -- "⑤ returns digest summary\nwritten back as new note" --> summarize
    summarize -- "⑥ summary note enters\nnext promotion cycle" --> spool

    working -- "⑦ watches for new/changed\nmarkdown files (300s poll)" --> watch["memsearch-watch\n(file-change detector)"]
    watch -- "⑧ embeds with BGE-M3\nupserts into vector index" --> milvus[("Milvus :19530\n(vector index)")]
    milvus -- "⑨ hybrid vector+BM25+reranker\nbest semantic recall" --> memsearch_mcp["memsearch-mcp :8493"]
    milvus -- "⑩ semantic search backend\nfor forge-wide doc corpus" --> qmd["qmd :8181\n(9k docs, 40+ collections)"]
    working -- "⑪ hourly re-index of\nall memory collections" --> qr["qmd-refresh\n(hourly cron)"]
    qr --> qmd

    working -- "⑫ parses frontmatter tags,\ntier, dates into SQLite" --> metadb[(".metadata.db\n(SQLite frontmatter index)")]
    metadb -- "⑬ syncs fields/tags\nfor full-text indexing" --> os_sync["memory-os-sync\n(always-on, 30s poll)"]
    os_sync --> opensearch[("OpenSearch :9202\n(full-text BM25 index)")]
    opensearch -- "⑭ full-text phrase/\nkeyword search" --> search_mcp["memory-search-mcp :8491"]
    metadb -- "⑮ structured queries on\ntags, dates, tiers" --> meta_mcp["memory-metadata-mcp :8490"]

    neo4j[("Neo4j :7687\n(entity + relationship graph)")] -- "⑯ temporal entity queries\nwhat changed and when" --> graphiti_mcp["graphiti-mcp :8000"]

    subgraph "MCP query surface — agents call these"
        memsearch_mcp
        qmd
        meta_mcp
        search_mcp
        graphiti_mcp
    end
```

### Hop-by-hop reference

| # | From → To | What it does |
|---|-----------|-------------|
| ① | spool → working | `memory-promote-daily` scores session notes nightly and moves high-value ones into the main working store |
| ② | working → distilled | `memory-sync-weekly` reads working notes and compresses them into concise long-lived summaries |
| ③ | working/distilled → NFS | `memory-archive-mirror` takes a daily snapshot of all tiers to atlas — append-only, retains change history |
| ④–⑤ | working ↔ Anthropic | `memsearch-summarize` chunks a project's spool, calls Claude to write a digest, and saves the result |
| ⑥ | summarize → spool | The new summary re-enters the spool so it gets scored and promoted by the next ① cycle |
| ⑦–⑧ | working → Milvus | `memsearch-watch` polls for changed files, embeds them with BGE-M3, and upserts vectors into Milvus |
| ⑨ | Milvus → memsearch-mcp | Agents query via hybrid vector + BM25 + cross-encoder reranker — highest-recall recall path |
| ⑩–⑪ | working/Milvus → qmd | `qmd-refresh` re-indexes all memory collections hourly; qmd also uses Milvus as its vector backend |
| ⑫ | working → .metadata.db | `memory-metadata-mcp` parses frontmatter (tier, tags, dates) into a local SQLite file on each write |
| ⑬ | .metadata.db → OpenSearch | `memory-os-sync` watches the SQLite file and pushes changes to OpenSearch for full-text indexing |
| ⑭ | OpenSearch → memory-search-mcp | Agents search note *bodies* by phrase or keyword via BM25 |
| ⑮ | .metadata.db → memory-metadata-mcp | Agents filter notes by structured fields (tag, date range, tier) without reading file bodies |
| ⑯ | Neo4j → graphiti-mcp | Agents query entities, relationships, and when facts changed — the relational/temporal layer |

---

## Related Docs

- [memory-stack.md](memory-stack.md) — Milvus + OpenSearch Docker stack
- [memory-services.md](memory-services.md) — PM2 indexing services and promotion pipeline
- [memsearch.md](memsearch.md) — memsearch library, reranker, configuration
- [memsearch-mcp.md](memsearch-mcp.md) — MCP server wrapping memsearch
- [memsearch-summarize.md](memsearch-summarize.md) — session transcript summarizer
- [graphiti.md](graphiti.md) — Neo4j knowledge graph (relational layer)
