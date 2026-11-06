- Eval baseline misses: "make the photos in ~/Pictures/trip half as big" routes to compress-images (PoC routed it to resize-images); "my screenshots folder is huge" invents folder and quality.
- Completion: `path` params complete nothing; zsh's own file completion can't be mixed into ArgumentParser's custom
  completion, so it needs a hand-written action or listing files ourselves.
- Completion for bash and fish: ArgumentParser generates both, but they're untested with the custom hooks.
