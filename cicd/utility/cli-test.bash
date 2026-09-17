#!/usr/bin/env bash

# shellcheck disable=2155  ## 'Declare and assign separately.' Cumbersome for locals.

##	Purpose:
##		Runs the built command and checks what it prints and what it exits with.
##		The vectors cover the two modules; this covers the surface around them -
##		argument handling, the defaults, and the refusals - which nothing else
##		looks at.
##	Syntax:
##		cli-test.bash [--bin <path>]
##	History: At bottom.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT

set -Eeuo pipefail

fEcho(){ printf '[ %s ]\n' "$*" ;}
fLine(){ printf '%s\n' "$*" ;}
fDie(){  printf '\n%s: %s\n\n' "cli-test" "$*" >&2; exit 1 ;}

passed=0
failed=0
fPass(){ passed=$((passed + 1)); printf '  ok ....: %s\n' "$*" ;}
fFail(){ failed=$((failed + 1)); printf '  FAIL ..: %s\n' "$*" ;}

repoRoot="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
bin="${repoRoot}/zig/zig-out/bin/zuid"

while (($#)); do case "$1" in
	--bin)     bin="${2:?}"; shift 2 ;;
	-h|--help) sed -n '/^##	Purpose:/,/^##	History:/p' "${BASH_SOURCE[0]}" | sed '$d; s/^##	\{0,1\}//'; exit 0 ;;
	*) fDie "unknown option: $1 (try --help)" ;;
esac; done

[[ -x "${bin}" ]] || fDie "not executable: ${bin}. Build the Zig side first."


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## Helpers. Each case names what it expects, so a failure reads without having
## to go and run the thing by hand.

## Output of a run that is expected to succeed.
fRun(){ "${bin}" "$@" 2>/dev/null ;}

fWantLen(){  ## label, expected length, args...
	local -r label="$1" want="$2"; shift 2
	local got=""
	got="$(fRun "$@" || true)"
	if [[ "${#got}" == "${want}" ]]
		then fPass "${label}"
		else fFail "${label}: got ${#got} bytes, want ${want} ('${got:0:40}')"
	fi
}

fWantExact(){  ## label, expected, args...
	local -r label="$1" want="$2"; shift 2
	local got=""
	got="$(fRun "$@" || true)"
	if [[ "${got}" == "${want}" ]]
		then fPass "${label}"
		else fFail "${label}: got '${got}', want '${want}'"
	fi
}

fWantFailure(){  ## label, text the message must contain, args...
	local -r label="$1" needle="$2"; shift 2
	local out="" rc=0
	out="$("${bin}" "$@" 2>&1)" || rc=$?
	if ((rc == 0)); then
		fFail "${label}: exited 0, expected a refusal"
		return 0
	fi
	if [[ "${out}" == *"${needle}"* ]]
		then fPass "${label}"
		else fFail "${label}: exited ${rc} but said '${out}', wanted '${needle}'"
	fi
}


#•••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••••
## The command cannot be handed a clock, so nothing here has an exact expected
## value except the literals. Widths are what it can be held to: every
## component but an unhashed name is fixed width, which is what makes an
## identifier splittable by offset.

fEcho "Command: ${bin}"
fLine ""

## Derived widths in base 62: time 6, hash 8, uuid 22, random 6.
fWantLen "the default is a 6-symbol timestamp" 6
fWantLen "hashed host is 8 symbols"            8  --format '%h'
fWantLen "a uuid is 22 symbols"                22 --format '%g'
fWantLen "random is 6 symbols"                 6  --format '%r'
fWantLen "and a literal passes through"        3  --format 'abc'
fWantExact "a doubled percent is one percent"  "%" --format '%%'

## An empty value means the default on both flags, which is what the Go module's
## zero Request.Format and the C module's empty format already did. The command
## passed an empty format straight through and printed an empty identifier, so
## 'zuid -f "$FMT"' with the variable unset succeeded and produced nothing.
fWantLen "an empty format means %d" 6 --format ''
fWantLen "an empty base means 62"   6 --base ''
fWantLen "and both at once"         6 --format '' --base ''

## An identifier used to be capped by a fixed 4096-byte buffer inside the
## module, so a repeated component or a long literal was refused outright.
fWantLen "200 uuids render"       4400 --format "$(python3 -c 'print("%g" * 200)')"
fWantLen "a long literal renders" 5000 --format "$(python3 -c 'print("x" * 5000)')"

## But not without limit, and the ceiling says so in words.
fWantFailure "a runaway format is refused by size" "past what this command will print" \
	--format "$(python3 -c 'print("%g" * 60000)')"

## The refusals, each by its own message rather than an error name.
fWantFailure "an unknown component is refused" "Unknown format component" --format '%x'
fWantFailure "the unknown component is named"  "'%x'" --format '%x'
fWantFailure "a bare percent is refused"       "bare" --format '%d%'
fWantFailure "a raw-byte base is refused"      "raw bytes" --base bytes
fWantFailure "a base with tab digits refused"  "control characters" --base 98keyboard
fWantFailure "an unknown base is refused"      "no-such-base-here" --base no-such-base-here
fWantFailure "a bad precision is refused"      "out of range" --precision 2
fWantFailure "a missing value is refused"      "base" --base

## The unknown-base message used to be the conversion library's own text, in its
## style: lower case, double quotes. Only the near match it found is kept now.
fWantFailure "an unknown base reads in one style" "Unknown base 'no-such-base-here'." --base no-such-base-here
fWantFailure "a near miss keeps the suggestion"   "Did you mean '62'?" --base 62x
fWantFailure "a blank base is refused"            "is blank" --base '  '

## A name long enough to outgrow the 512-byte error buffer used to lose the
## error code along with the text, and came back as a bare internal failure.
fWantFailure "a very long base is still a base" "Unknown base" \
	--base "$(python3 -c 'print("a" * 1000)')"

fLine ""
fEcho "Passed: ${passed}, failed: ${failed}"
fLine ""
((failed == 0)) || exit 1


##	History:
##		- 20260917 JC: Created, for the buffer ceiling and the empty format.
