#!/bin/sh

export VANGUARD_CORPUS_BUILD_MODE=SMALL_TESTABLE_SAMPLE && swift run VCDataBuilder vanguardTriePlist
