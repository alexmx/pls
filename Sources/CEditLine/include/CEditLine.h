#ifndef CEDITLINE_H
#define CEDITLINE_H

/// Reads a line from the terminal with libedit: `prompt` on stderr, `prefill` (may be NULL) already typed in and
/// editable. Returns NULL at end of input (Ctrl-D on an empty line); otherwise a line without its newline, which the
/// caller frees.
char *pls_read_line(const char *prompt, const char *prefill);

#endif
