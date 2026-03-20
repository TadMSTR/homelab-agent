# docs/assets

Static assets for the homelab-agent documentation.

## Diagrams

Diagram files use the `.drawio.svg` format: SVG with embedded draw.io XML. They render inline in GitHub and any browser, and are fully editable in [draw.io](https://app.diagrams.net) — drag-and-drop the file or use File → Open from → This device.

| File | Used in | Description |
|------|---------|-------------|
| `architecture-layers.drawio.svg` | [architecture.md](../architecture.md#system-overview) | Three-layer system overview: host tooling, Docker services, agent engine |
| `memory-flow.drawio.svg` | [architecture.md](../architecture.md#memory-flow-knowledge-accumulation) | Memory tier pipeline: session → working → distilled → knowledge graph |
| `network-topology.drawio.svg` | [architecture.md](../architecture.md#network-topology) | Docker network routing: SWAG → Authelia → containers |

## Other assets

| File | Description |
|------|-------------|
| `banner.png` | README banner image |
