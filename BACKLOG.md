- Eval baseline misses: "make the photos in ~/Pictures/trip half as big" routes to compress-images (PoC routed it to resize-images); "my screenshots folder is huge" invents quality=50 (the made-up folder is now dropped).
- Completion for bash and fish: ArgumentParser generates both, but they're untested with the custom hooks.
- Cache sentence embeddings: ranking a 300-automation library takes ~8s per request, nearly all of it embedding the
  same descriptions and examples again; cache them per automation (by content) in the state folder.
- Collections: a command to copy a collection's automation into your own library to change it; pinning a collection
  to a commit or tag instead of following its default branch.
- Background jobs are one per automation, so a second `timer` would replace the first; `timer` stays a plain script
  until jobs can run side by side.
- Tried and rejected (2026-11-07): asking the model to quote the request words behind each filled value, and dropping
  values it can't point to. It removed invented values but filled real ones worse (evals: 16/21 and 12/21 right
  values against 21/21). Explicit defaults, which doctor now suggests, fix invented values instead.
- Color in `pls list`, `pls show` and the collection review, through the `Style` helper the confirmation uses.
