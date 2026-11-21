## Diagrams in Vanta documents

When authoring Vanta design docs, RFCs, specs, or implementation plans:

- Default to Mermaid for sequence diagrams. Keep editable source in
  the local Markdown document and provide a live preview.
- When SequenceDiagram.org is requested, preserve its editable source
  and provide an exported image plus a link to edit the diagram.
- Prefer FigJam through the available Figma tools and diagram skill
  for architecture/block diagrams that benefit from manual layout.
- Include a rendered diagram in the document and a reference to its
  editable source. Keep one authoritative source per diagram.
- Render and visually inspect diagrams for readable labels, clipping,
  and layout before handoff. Report when visual verification is unavailable.
- When publishing Markdown to Google Docs is requested, use Obsidian's
  gsync workflow. Read its current guidance and preserve local Mermaid
  blocks. Before re-uploading, account for remote edits and comments,
  since upload replaces the document content.
