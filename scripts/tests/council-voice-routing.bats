#!/usr/bin/env bats
# Pins headless_model_for_voice (cheval-council.sh): voice-name → within-company
# headless terminal. The case arms are ORDER-SENSITIVE (top-down first match);
# these tests pin the two documented hazards (cursor-before-reviewer,
# fable-before-claude/reviewer) so a reorder can't silently misroute a voice.

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../cheval-council.sh"
    # Extract the real shipped function text and load it.
    eval "$(sed -n '/^headless_model_for_voice()/,/^}/p' "$SCRIPT")"
}

@test "voice routing: jam-reviewer-fable → claude-fable-headless (top tier, critical reviews)" {
    [ "$(headless_model_for_voice jam-reviewer-fable)" = "anthropic:claude-fable-headless" ]
}

@test "voice routing: fable arm precedes reviewer/claude catch-alls (order hazard)" {
    [ "$(headless_model_for_voice fable-claude-reviewer)" = "anthropic:claude-fable-headless" ]
}

@test "voice routing: cursor arm still precedes reviewer (regression)" {
    [ "$(headless_model_for_voice jam-reviewer-cursor)" = "cursor:cursor-headless" ]
}

@test "voice routing: existing default set unchanged" {
    [ "$(headless_model_for_voice jam-reviewer-claude-headless)" = "anthropic:claude-headless" ]
    [ "$(headless_model_for_voice jam-reviewer-gpt)" = "openai:codex-headless" ]
    [ "$(headless_model_for_voice deep-thinker)" = "google:gemini-headless" ]
    [ "$(headless_model_for_voice unknown-voice)" = "openai:codex-headless" ]
}
