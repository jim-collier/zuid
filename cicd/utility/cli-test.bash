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

## Every case names its test ID first, then what it checks. New IDs come from
## test-ids.py. A check written out by hand starts with fId instead.
passed=0
failed=0
curId=""
curName=""
fId(){ curId="$1"; curName="$2" ;}
fPass(){
	if [[ -z "${curId}" ]]; then fFail "no test ID"; return 0; fi
	passed=$((passed + 1)); printf '  ok ....: %s %s\n' "${curId}" "${curName}"
	curId=""
}
fFail(){  ## detail
	failed=$((failed + 1)); printf '  FAIL ..: %s %s: %s\n' "${curId:-???????}" "${curName}" "$*"
	curId=""
}

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

fWantLen(){  ## id, label, expected length, args...
	fId "$1" "$2"
	local -r want="$3"; shift 3
	local got=""
	got="$(fRun "$@" || true)"
	if [[ "${#got}" == "${want}" ]]
		then fPass
		else fFail "got ${#got} bytes, want ${want} ('${got:0:40}')"
	fi
}

fWantExact(){  ## id, label, expected, args...
	fId "$1" "$2"
	local -r want="$3"; shift 3
	local got=""
	got="$(fRun "$@" || true)"
	if [[ "${got}" == "${want}" ]]
		then fPass
		else fFail "got '${got}', want '${want}'"
	fi
}

fWantLines(){  ## id, label, expected line count, args...
	fId "$1" "$2"
	local -r want="$3"; shift 3
	local got=0
	## BSD wc pads the count with spaces.
	got="$(fRun "$@" | wc -l | tr -d ' ')"
	if [[ "${got}" == "${want}" ]]
		then fPass
		else fFail "got ${got} lines, want ${want}"
	fi
}

## Warnings are advisory, so the run has to succeed as well as say the thing.
fWantWarning(){  ## id, label, text the warning must contain, args...
	fId "$1" "$2"
	local -r needle="$3"; shift 3
	local err="" rc=0
	err="$("${bin}" "$@" 2>&1 >/dev/null)" || rc=$?
	if ((rc != 0)); then
		fFail "exited ${rc}, expected a warning and success"
		return 0
	fi
	if [[ "${err}" == *"${needle}"* ]]
		then fPass
		else fFail "said '${err}', wanted '${needle}'"
	fi
}

fWantQuiet(){  ## id, label, args...
	fId "$1" "$2"; shift 2
	local err="" rc=0
	err="$("${bin}" "$@" 2>&1 >/dev/null)" || rc=$?
	if ((rc == 0)) && [[ -z "${err}" ]]
		then fPass
		else fFail "exited ${rc} and said '${err}'"
	fi
}

fWantFailure(){  ## id, label, text the message must contain, args...
	fId "$1" "$2"
	local -r needle="$3"; shift 3
	local out="" rc=0
	out="$("${bin}" "$@" 2>&1)" || rc=$?
	if ((rc == 0)); then
		fFail "exited 0, expected a refusal"
		return 0
	fi
	if [[ "${out}" == *"${needle}"* ]]
		then fPass
		else fFail "exited ${rc} but said '${out}', wanted '${needle}'"
	fi
}


fWantContains(){  ## id, label, text the output must contain, args...
	fId "$1" "$2"
	local -r needle="$3"; shift 3
	local got="" rc=0
	got="$("${bin}" "$@" 2>&1)" || rc=$?
	if ((rc == 0)) && [[ "${got}" == *"${needle}"* ]]
		then fPass
		else fFail "exited ${rc}, wanted '${needle}' in '${got:0:80}'"
	fi
}

fWantAbsent(){  ## id, label, text the output must not contain, args...
	fId "$1" "$2"
	local -r needle="$3"; shift 3
	local got=""
	got="$(fRun "$@" || true)"
	if [[ -n "${got}" && "${got}" != *"${needle}"* ]]
		then fPass
		else fFail "'${needle}' is in '${got:0:80}'"
	fi
}

fWantMatch(){  ## id, label, regex the whole output must match, args...
	fId "$1" "$2"
	local -r pattern="$3"; shift 3
	local got=""
	got="$(fRun "$@" || true)"
	if [[ "${got}" =~ ${pattern} ]]
		then fPass
		else fFail "'${got}' does not match ${pattern}"
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
fWantLen Eq9kVKj "the default is a 6-symbol timestamp" 6
fWantLen Eq9kVKk "hashed host is 8 symbols"            8  --format '%h'
fWantLen Eq9kVKl "a uuid is 22 symbols"                22 --format '%g'
fWantLen Eq9kVKm "random is 6 symbols"                 6  --format '%r'
fWantLen Eq9kVKn "and a literal passes through"        3  --format 'abc'
fWantExact Eq9kVKo "a doubled percent is one percent"  "%" --format '%%'

## An empty value means the default on both flags, which is what the Go module's
## zero Request.Format and the C module's empty format already did. The command
## passed an empty format straight through and printed an empty identifier, so
## 'zuid -f "$FMT"' with the variable unset succeeded and produced nothing.
fWantLen Eq9mL16 "an empty format means %d" 6 --format ''
fWantLen Eq9mL17 "an empty base means 62"   6 --base ''
fWantLen Eq9mL18 "and both at once"         6 --format '' --base ''

## An identifier used to be capped by a fixed 4096-byte buffer inside the
## module, so a repeated component or a long literal was refused outright.
fWantLen Eq9kVKp "200 uuids render"       4400 --format "$(python3 -c 'print("%g" * 200)')"
fWantLen Eq9kVKq "a long literal renders" 5000 --format "$(python3 -c 'print("x" * 5000)')"

## But not without limit, and the ceiling says so in words.
fWantFailure Eq9kVKr "a runaway format is refused by size" "past what this command will print" \
	--format "$(python3 -c 'print("%g" * 60000)')"

## The refusals, each by its own message rather than an error name.
fWantFailure Eq9kVKs "an unknown component is refused" "Unknown format component" --format '%x'
fWantFailure Eq9xBUh "the unknown component is named"  "'%x'" --format '%x'
fWantFailure Eq9kVKt "a bare percent is refused"       "bare" --format '%d%'
fWantFailure Eq9kVKx "a raw-byte base is refused"      "raw bytes" --base bytes
fWantFailure Eq9xBUi "a base with tab digits refused"  "control characters" --base 98keyboard
fWantFailure Eq9kVKu "an unknown base is refused"      "no-such-base-here" --base no-such-base-here
fWantFailure Eq9kVKv "a bad precision is refused"      "out of range" --precision 2
fWantFailure Eq9kVKw "a missing value is refused"      "base" --base

## The unknown-base message used to be the conversion library's own text, in its
## style: lower case, double quotes. Only the near match it found is kept now.
fWantFailure EqABve4 "an unknown base reads in one style" "Unknown base 'no-such-base-here'." --base no-such-base-here
fWantFailure EqABve5 "a near miss keeps the suggestion"   "Did you mean '62'?" --base 62x
fWantFailure EqABve6 "a blank base is refused"            "is blank" --base '  '

## A name long enough to outgrow the 512-byte error buffer used to lose the
## error code along with the text, and came back as a bare internal failure.
fWantFailure EqABve7 "a very long base is still a base" "Unknown base" \
	--base "$(python3 -c 'print("a" * 1000)')"

## The salt changes the hashed names and nothing else. An empty one hashes the
## name on its own, which is what keeps older identifiers comparable.
fWantLen EqAI7sg "a salted host is the same width"  8 --format '%h' --salt pepper
fWantExact EqAI7sh "an empty salt is the default"   "$(fRun --format '%h')" --format '%h' --salt ''
fWantExact EqAI7si "a literal name ignores the salt" "$(fRun --format '%h' --no-hash)" --format '%h' --no-hash --salt pepper
fWantFailure EqAI7sj "a missing salt is refused"    "salt" --salt
fWantFailure EqAI7sk "an over-long salt is refused" "Want at most 256" \
	--format '%h' --salt "$(python3 -c 'print("s" * 257)')"

## --count prints that many lines and nothing else. One run reads the clock
## once, so a format with nothing random in it comes out the same every line -
## printed as-is, with a warning rather than something appended to hide it.
fWantLines EqAb38a "one identifier by default"   1
fWantLines EqAb38b "a count prints that many"    3 --count 3
fWantLines EqAb38c "the short spelling too"      5 -n 5
fWantLines EqAb38d "and the attached form"       4 -n=4
fWantWarning EqAb38e "repeats are reported"      "2 of 3 identifiers repeat" -n 3 --format '%d'
fWantWarning EqAb38f "the warning suggests %r"   "add %r to the format" -n 3 --format '%d'
fWantQuiet EqAb38g "random output does not warn" -n 20 --format '%d%r'
fWantQuiet EqAb38h "one identifier cannot repeat" -n 1 --format '%d'

## Narrow enough random draws collide on their own, which is the case the
## warning is really for - it counts what repeated, not whether %r was typed.
fWantWarning EqAb38i "a narrow draw still counts" "identifiers repeat" \
	-n 100 --base 16 --rand-chars 1 --format '%r'

fWantFailure EqAb38j "a zero count is refused"     "out of range" --count 0
fWantFailure EqAb38k "a negative count is refused" "out of range" --count -1
fWantFailure EqAb38l "a count past the ceiling"    "Want 1 to 1000000" --count 1000001
fWantFailure EqAb38m "a non-numeric count"         "is not a number" --count abc
fWantFailure EqAb38n "a missing count is refused"  "count" --count

## A reader that quits early closed the pipe under the writer. That used to end
## in Zig's own error trace and a non-zero exit, which is not a failed run.
## pipefail carries the writer's status through wc, and the '|| pipeRc' keeps
## errexit from taking the whole harness down with it.
pipeRc=0
pipeLines="$("${bin}" -n 10000 --format '%d%r' 2>/dev/null | head -n 2 | wc -l | tr -d ' ')" || pipeRc=$?
fId EqAb38o "a closed pipe ends the run quietly"
if [[ "${pipeLines}" == "2" ]] && ((pipeRc == 0))
	then fPass
	else fFail "got ${pipeLines} lines, exit ${pipeRc}"
fi

## Two salts have to differ, or the flag is doing nothing.
fId EqAI7sl "two salts give two fingerprints"
if [[ "$(fRun --format '%h' --salt pepper)" == "$(fRun --format '%h' --salt Pepper)" ]]
	then fFail "both gave the same one"
	else fPass
fi


## Precision moves the unit, and the width follows the horizon in that unit.
fWantLen ErOiQbL "-p -1 counts minutes, 5 symbols"       5 --precision -1
fWantLen ErOiQbM "-p 1 counts milliseconds, 8 symbols"   8 --precision 1

## A value attaches with '=' or follows as the next argument, and all four
## spellings are the same thing. Base 16 is 9 wide, so a value that went
## missing shows as the default's 6.
fWantLen ErOiQbN "-b=16 attaches"          9 -b=16
fWantLen ErOiQbO "--base=16 attaches"      9 --base=16
fWantLen ErOiQbP "-b 16 follows"           9 -b 16
fWantLen ErOiQbQ "--base 16 follows"       9 --base 16

## Only a leading-dash argument splits, and only at its first '=', so a format
## carrying one survives either way.
fWantExact ErOiQbR "a format may carry an '='"      "a=b" --format 'a=b'
fWantExact ErOiQbS "and so may an attached one"     "a=b" --format=a=b
fWantFailure ErOiQbT "--no-hash refuses a value"    "takes no value" --no-hash=1
fWantFailure ErOiQbU "-h refuses a value"           "takes no value" -h=1
fWantFailure ErOiQbV "-v refuses a value"           "takes no value" -v=1

## Dropped from the command as confusing. The modules keep the option.
fWantFailure ErOiQbW "--hash-chars is gone"         "Argument invalid" --hash-chars 5

## The verb is quoted whole, however many bytes it is.
fWantFailure ErOiQbX "a multi-byte unknown component is named whole" "'%é'" --format '%é'
fWantFailure ErOiQbY "a zero --rand-chars is refused" "out of range for --rand-chars" --rand-chars 0

## --version is one bare line for scripts and the installers' head -n1. The
## copyright lives in --about.
fWantLines ErOiQbZ "--version is one line"                  1 --version
fWantMatch ErOiQba "--version is the version and build"     '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)? \(build [0-9a-z]+\)$' --version
fWantAbsent ErOiQbb "--version carries no copyright"        "Copyright" --version
fWantContains ErOiQbc "--about carries the copyright"       "Copyright ©" --about
fWantContains ErOiQbd "--about names both licenses"         "The Go module and the C library are Apache-2.0." --about
fWantContains ErOiQbe "--donate says where to give"         "https://github.com/sponsors/jim-collier" --donate
fWantContains ErOyR7K "--donate names Ko-fi too"          "https://ko-fi.com/jimcollier" --donate

## The help builds its curated line from the list itself, so the two cannot
## drift. It wraps, so the words are what gets compared.
curated="16, 32w, 36, 62, 64tt, 128tt, 256tt, 512tt, 1024tz, 2048tz"
fId ErOiQbf "help lists the curated bases"
helpText="$(fRun --help || true)"
helpList="$(awk '/Curated set:/ { on = 1; sub(/.*Curated set:/, ""); } on && /Any base/ { exit } on { print }' <<< "${helpText}" | tr -s ' \n' ' ' | sed 's/^ //; s/ $//')"
if [[ "${helpList}" == "${curated}" ]]
	then fPass
	else fFail "got '${helpList}'"
fi

## Help and about have a blank line above and below, and the options list has
## no gaps in it.
fId ErOiQbg "help is set off by blank lines, with no gaps in its options"
helpFirst="$(head -n1 <<< "${helpText}")"
helpGaps="$(awk '/^Options:/ { on = 1; next } on && /^$/ { exit } on { print }' <<< "${helpText}" | grep -c -- '--donate' || true)"
helpRaw="$("${bin}" --help 2>/dev/null | tail -c 2 | od -An -c | tr -d ' ')"
if [[ -z "${helpFirst}" && "${helpGaps}" == "1" && "${helpRaw}" == '\n\n' ]]
	then fPass
	else fFail "first line '${helpFirst}', options through --donate: ${helpGaps}, ends '${helpRaw}'"
fi

## Every curated base renders a timestamp.
fId ErOiQbh "every curated base renders"
badBases=""
for base in ${curated//,/}; do
	[[ -n "$(fRun --base "${base}" || true)" ]] || badBases+=" ${base}"
done
if [[ -z "${badBases}" ]]
	then fPass
	else fFail "nothing from:${badBases}"
fi

fLine ""
fEcho "Passed: ${passed}, failed: ${failed}"
fLine ""
((failed == 0)) || exit 1


##	History:
##		- 20260917 JC: Created, for the buffer ceiling and the empty format.
##		- 20260917 JC: --count, its refusals, and the closed-pipe case.
##		- 20260930 JC: Test IDs. Precision, attached values, --version, --about, --donate, help.
