#ifndef CEDITLINE_H
#define CEDITLINE_H

/// Reads a line from the terminal with libedit: `prompt` on stderr, `prefill` (may be NULL) already typed in and
/// editable. Returns NULL at end of input (Ctrl-D on an empty line); otherwise a line without its newline, which the
/// caller frees.
char *pls_read_line(const char *prompt, const char *prefill);

/// Reads one key from the terminal without waiting for Enter or echoing it. Returns its byte (Enter is '\n', Ctrl-D
/// is 4), or -1 if stdin isn't a terminal or at end of input.
int pls_read_key(void);

/// Waits up to `milliseconds` for one key without echoing it, and drops it if it's Enter. Any other key is dropped
/// too.
void pls_discard_enter(int milliseconds);

#endif
