#include "CEditLine.h"

#include <errno.h>
#include <histedit.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

// C rather than Swift: libedit's API is variadic (el_set) and takes a prompt callback that can't capture state.
// The readline() compatibility layer can't prefill: it clears text inserted from its startup hooks. Single keys are
// read here too, as the signal handler that restores the terminal needs the state saved before changing it.

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

// Puts the terminal back as it was before libedit or key mode changed it, then ends pls with the same signal.
static void restore_terminal_and_reraise(int signo) {
    if (has_terminal_before) tcsetattr(STDIN_FILENO, TCSANOW, &terminal_before);
    signal(signo, SIG_DFL);
    raise(signo);
}

// Ends pls through restore_terminal_and_reraise on an ending signal while the terminal is changed, saving the
// previous handlers in `previous` for release_ending_signals.
static void catch_ending_signals(struct sigaction previous[]) {
    has_terminal_before = tcgetattr(STDIN_FILENO, &terminal_before) == 0;
    struct sigaction handler = {0};
    handler.sa_handler = restore_terminal_and_reraise;
    sigemptyset(&handler.sa_mask);
    for (int i = 0; i < ending_signal_count; i++) {
        sigaction(ending_signals[i], NULL, &previous[i]);
        // A signal ignored on purpose (e.g. SIGHUP under nohup) stays ignored.
        if (previous[i].sa_handler != SIG_IGN) sigaction(ending_signals[i], &handler, NULL);
    }
}

static void release_ending_signals(const struct sigaction previous[]) {
    for (int i = 0; i < ending_signal_count; i++) sigaction(ending_signals[i], &previous[i], NULL);
}

// Switches the terminal to reading key by key without echo; Ctrl-C still sends SIGINT. Returns 0 without a terminal.
static int enter_key_mode(struct sigaction previous[]) {
    catch_ending_signals(previous);
    if (!has_terminal_before) {
        release_ending_signals(previous);
        return 0;
    }
    struct termios keys = terminal_before;
    keys.c_lflag &= ~(ICANON | ECHO);
    keys.c_cc[VMIN] = 1;
    keys.c_cc[VTIME] = 0;
    tcsetattr(STDIN_FILENO, TCSANOW, &keys);
    return 1;
}

static void leave_key_mode(const struct sigaction previous[]) {
    tcsetattr(STDIN_FILENO, TCSANOW, &terminal_before);
    release_ending_signals(previous);
}

static int read_byte(void) {
    unsigned char byte;
    ssize_t count;
    do {
        count = read(STDIN_FILENO, &byte, 1);
    } while (count < 0 && errno == EINTR);
    return count == 1 ? byte : -1;
}

int pls_read_key(void) {
    struct sigaction previous[ending_signal_count];
    if (!enter_key_mode(previous)) return -1;
    int key = read_byte();
    leave_key_mode(previous);
    return key;
}

void pls_discard_enter(int milliseconds) {
    struct sigaction previous[ending_signal_count];
    if (!enter_key_mode(previous)) return;
    struct pollfd input = {.fd = STDIN_FILENO, .events = POLLIN};
    if (poll(&input, 1, milliseconds) > 0) read_byte();
    leave_key_mode(previous);
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

    struct sigaction previous[ending_signal_count];
    catch_ending_signals(previous);

    if (prefill != NULL) el_push(editor, prefill);
    int count = 0;
    // NULL or no characters: end of input (Ctrl-D on an empty line) or a read error such as a hangup; both cancel.
    const char *line = el_gets(editor, &count);

    release_ending_signals(previous);

    if (line == NULL || count <= 0) return NULL;
    char *copy = strdup(line);
    if (copy == NULL) return NULL;
    copy[strcspn(copy, "\n")] = '\0';
    return copy;
}
