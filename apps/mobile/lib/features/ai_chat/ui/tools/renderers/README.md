# Tool Output Renderers

Pure Flutter renderers for AI tool JSON payloads.

Rules:

- Keep renderers stateless and free of Riverpod/repository access.
- Parse only the payload passed to `renderToolOutput`.
- Add domain-specific renderer files here instead of growing the `ui/` root.
- If a renderer needs live domain data, move that behavior behind an app/domain
  composition seam instead of importing another feature from AI Chat.
