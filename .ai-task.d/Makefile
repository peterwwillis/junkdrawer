# .ai-task.d/Makefile - run ai-task.sh smoke tests
#
# Each run creates a throwaway Linear ticket, launches a REAL
# `ai-task.sh start` session against it with a do-nothing prompt (no tools,
# no work) on the Haiku model, verifies claude actually starts in its tmux
# pane, then cleans everything up: tmux session killed, worktrees removed,
# ticket canceled. Cost: one short Haiku turn per run (a fraction of a cent).
#
# Targets:
#   smoke         both runs (basic + AWS ReadOnly mode)
#   smoke-basic   basic startup only - AWS mode skipped, fast, no aws-sso
#   smoke-aws     AWS ReadOnly run only - needs a valid `aws-sso login`
#                 session; failure here usually means the session expired
#   clean         clean up after an interrupted run (scoped to the session/
#                 ticket/sandbox recorded in tests/.last-run.env)

TESTS_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))/tests

.PHONY: smoke smoke-basic smoke-aws clean

smoke: smoke-basic smoke-aws

smoke-basic:
	bash "$(TESTS_DIR)/ai-task-smoke.sh" --basic

smoke-aws:
	bash "$(TESTS_DIR)/ai-task-smoke.sh" --aws

clean:
	bash "$(TESTS_DIR)/ai-task-smoke.sh" --clean
