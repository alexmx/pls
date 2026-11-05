#include "CEditLine.h"

#include <histedit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// C rather than Swift: libedit's API is variadic (el_set) and takes a prompt callback that can't capture state.
// The readline() compatibility layer can't prefill: it clears text inserted from its startup hooks.

static const char *current_prompt = "";

static const char *prompt(EditLine *editor) {
    (void)editor;
    return current_prompt;
}

char *pls_read_line(const char *text, const char *prefill) {
    static EditLine *editor;
    if (editor == NULL) {
        editor = el_init("pls", stdin, stderr, stderr);
        el_set(editor, EL_EDITOR, "emacs");
        el_set(editor, EL_PROMPT, prompt);
        // Restores the terminal before a signal like Ctrl-C ends pls mid-line.
        el_set(editor, EL_SIGNAL, 1);
    }
    current_prompt = text;
    if (prefill != NULL) el_push(editor, prefill);
    int count = 0;
    const char *line = el_gets(editor, &count);
    if (line == NULL || count <= 0) return NULL;
    char *copy = strdup(line);
    copy[strcspn(copy, "\n")] = '\0';
    return copy;
}
