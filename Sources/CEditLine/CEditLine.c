#include "CEditLine.h"

#include <histedit.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

// C rather than Swift: libedit's API is variadic (el_set) and takes a prompt callback that can't capture state.
// The readline() compatibility layer can't prefill: it clears text inserted from its startup hooks.

static const char *current_prompt = "";

static const char *prompt(EditLine *editor) {
    (void)editor;
    return current_prompt;
}

// Signals that end pls while it waits at a prompt. libedit's own handling (EL_SIGNAL) isn't used: it re-sends the
// signal to the whole process group, which would also end a script that called `pls run`.
static const int ending_signals[] = {SIGINT, SIGTERM, SIGHUP, SIGQUIT};
enum { ending_signal_count = sizeof ending_signals / sizeof ending_signals[0] };

static struct termios terminal_before;
static int has_terminal_before;

// Puts the terminal back as it was before libedit switched it to raw mode, then ends pls with the same signal.
static void restore_terminal_and_reraise(int signo) {
    if (has_terminal_before) tcsetattr(STDIN_FILENO, TCSANOW, &terminal_before);
    signal(signo, SIG_DFL);
    raise(signo);
}

char *pls_read_line(const char *text, const char *prefill) {
    static EditLine *editor;
    if (editor == NULL) {
        editor = el_init("pls", stdin, stderr, stderr);
        if (editor == NULL) return NULL;
        el_set(editor, EL_EDITOR, "emacs");
        el_set(editor, EL_PROMPT, prompt);
    }
    current_prompt = text;

    has_terminal_before = tcgetattr(STDIN_FILENO, &terminal_before) == 0;
    struct sigaction handler = {0};
    handler.sa_handler = restore_terminal_and_reraise;
    sigemptyset(&handler.sa_mask);
    struct sigaction previous[ending_signal_count];
    for (int i = 0; i < ending_signal_count; i++) {
        sigaction(ending_signals[i], NULL, &previous[i]);
        // A signal ignored on purpose (e.g. SIGHUP under nohup) stays ignored.
        if (previous[i].sa_handler != SIG_IGN) sigaction(ending_signals[i], &handler, NULL);
    }

    if (prefill != NULL) el_push(editor, prefill);
    int count = 0;
    // NULL or no characters: end of input (Ctrl-D on an empty line) or a read error such as a hangup; both cancel.
    const char *line = el_gets(editor, &count);

    for (int i = 0; i < ending_signal_count; i++) sigaction(ending_signals[i], &previous[i], NULL);

    if (line == NULL || count <= 0) return NULL;
    char *copy = strdup(line);
    if (copy == NULL) return NULL;
    copy[strcspn(copy, "\n")] = '\0';
    return copy;
}
