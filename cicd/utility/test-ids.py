#!/usr/bin/env python3

##	Purpose: Test IDs. Every test the pipeline runs carries one, so a result can
##		be named on the console and a backlog item can point at the test that
##		covers it. An ID is when the test was written, as milliseconds since
##		2000-01-01 00:00 UTC in base 62 - seven symbols, so they sort by age.
##	Syntax:
##		test-ids.py new [-n COUNT] [--at TIME]   an ID for now, or for an ISO 8601 time
##		test-ids.py decode ID...                 when each ID was made
##		test-ids.py check                        every test has one, and no two share one
##		test-ids.py lookup NAME                  the ID of a Go or Zig test, by name
##		test-ids.py go  < 'go test -json'        one line per Go test, with its ID
##		test-ids.py zig < test runner stderr     one line per Zig test, with its ID
##		test-ids.py fuzzers                      the Zig fuzz tests, as 'ID<tab>name'
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


import argparse, datetime, json, pathlib, re, shlex, sys

DIGITS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
WIDTH  = 7
EPOCH  = datetime.datetime(2000, 1, 1, tzinfo=datetime.timezone.utc)

## The first commit. An ID from before it is a typo, not an old test.
FLOOR  = datetime.datetime(2026, 8, 1, tzinfo=datetime.timezone.utc)

REPO   = pathlib.Path(__file__).resolve().parents[2]
ID_RE  = re.compile(r"^[0-9A-Za-z]{%d}$" % WIDTH)

## Where each kind of test keeps its ID. Go and Zig tests have a comment in the
## lines just above them; the bash harnesses pass it as the first argument.
MARK_RE    = re.compile(r"//\s*test-id:\s*(\S+)")
GO_FUNC_RE = re.compile(r"^func ((?:Test|Fuzz)\w*)\(")
ZIG_TEST_RE = re.compile(r'^\s*test\s+"((?:[^"\\]|\\.)*)"\s*\{')
BASH_CALL_RE = re.compile(r"^\s*(fId|fWant\w+)\s+(.*)$")


def fEncode(ms):
	text = ""
	while ms:
		ms, rem = divmod(ms, 62)
		text = DIGITS[rem] + text
	return text.rjust(WIDTH, "0")


def fDecode(text):
	ms = 0
	for ch in text:
		ms = ms * 62 + DIGITS.index(ch)
	return EPOCH + datetime.timedelta(milliseconds=ms)


def fMsSinceEpoch(when):
	return (when - EPOCH) // datetime.timedelta(milliseconds=1)


def fGoFiles():   return sorted((REPO / "go").rglob("*_test.go"))
def fZigFiles():  return sorted(p for d in ("zig/lib/src", "zig/cmd/src") for p in (REPO / d).rglob("*.zig"))
def fBashFiles(): return [REPO / "cicd/cicd.bash", *sorted((REPO / "cicd/utility").glob("*-test.bash"))]


def fMarkAbove(lines, index):
	"""The test-id in the comment block directly above a line, if there is one."""
	i = index - 1
	while i >= 0 and lines[i].lstrip().startswith("//"):
		found = MARK_RE.search(lines[i])
		if found:
			return found.group(1)
		i -= 1
	return None


def fScan():
	"""Every declared test as (id or None, suite, name, file:line)."""
	found = []
	for path in fGoFiles():
		lines = path.read_text(encoding="utf-8").splitlines()
		for i, line in enumerate(lines):
			m = GO_FUNC_RE.match(line)
			if m:
				found.append((fMarkAbove(lines, i), "go", m.group(1), f"{path.relative_to(REPO)}:{i + 1}"))
	for path in fZigFiles():
		lines = path.read_text(encoding="utf-8").splitlines()
		for i, line in enumerate(lines):
			m = ZIG_TEST_RE.match(line)
			if m:
				found.append((fMarkAbove(lines, i), "zig", m.group(1), f"{path.relative_to(REPO)}:{i + 1}"))
	for path in fBashFiles():
		if not path.exists():
			continue
		for i, line in enumerate(path.read_text(encoding="utf-8").splitlines()):
			m = BASH_CALL_RE.match(line)
			if not m or "(){" in line:
				continue
			where = f"{path.relative_to(REPO)}:{i + 1}"
			## fId "${label}" bash=<id> ps1=<id> "name" carries one per key.
			if m.group(1) == "fId":
				try:
					words = shlex.split(m.group(2))
				except ValueError:
					## A continued line, which only a helper passing things on uses.
					continue
				pairs = [w.split("=", 1) for w in words[1:-1] if "=" in w]
				for key, ident in pairs:
					found.append((ident, path.stem, f"{key}, line {i + 1}", where))
				if pairs:
					continue
			## Otherwise the ID is the first argument. A helper handing on its own
			## "$1" is not a test.
			first = m.group(2).split()[0] if m.group(2).split() else ""
			if first.startswith(("\"", "'", "$")):
				continue
			found.append((first, path.stem, f"line {i + 1}", where))
	return found


def fCmd_New(args):
	when = datetime.datetime.now(datetime.timezone.utc)
	if args.at:
		when = datetime.datetime.fromisoformat(args.at)
		if when.tzinfo is None:
			when = when.astimezone()
	ms = fMsSinceEpoch(when)
	for n in range(args.n):
		print(fEncode(ms + n))
	return 0


def fCmd_Decode(args):
	for ident in args.ids:
		if not ID_RE.match(ident):
			print(f"{ident}: not a {WIDTH}-symbol base 62 ID")
			continue
		print(f"{ident}  {fDecode(ident).isoformat(timespec='milliseconds')}")
	return 0


TOKEN_RE = re.compile(r"(?<![0-9A-Za-z])[0-9A-Za-z]{%d}(?![0-9A-Za-z])" % WIDTH)


def fStrays(seen, ceiling):
	"""IDs the scan above never reached, so nothing checked them. An ID kept in
	an array went unchecked this way. A word needs a digit or a capital past its
	first letter to count, or 'Element' would."""
	problems = []
	marked = {*fGoFiles(), *fZigFiles()}
	for path in [*fGoFiles(), *fZigFiles(), *fBashFiles()]:
		if not path.exists():
			continue
		for i, line in enumerate(path.read_text(encoding="utf-8").splitlines()):
			where = f"{path.relative_to(REPO)}:{i + 1}"
			## Only Go and Zig use the comment. In bash it is just text.
			for found in MARK_RE.finditer(line) if path in marked else ():
				if found.group(1) not in seen:
					problems.append(f"{where}: test-id '{found.group(1)}' is not directly above a test")
			## A retired test left in a comment is not a test.
			if line.lstrip().startswith(("#", "//")):
				continue
			for word in TOKEN_RE.findall(line):
				if word in seen or not re.search(r"[0-9A-Z]", word[1:]):
					continue
				if FLOOR <= fDecode(word) <= ceiling:
					problems.append(f"{where}: '{word}' looks like a test ID, but no test line names it. Use fId's keyed form.")
	return problems


def fZigFuzzTests():
	"""The Zig tests that call std.testing.fuzz, as (id, name)."""
	found = []
	for path in fZigFiles():
		lines = path.read_text(encoding="utf-8").splitlines()
		for i, line in enumerate(lines):
			m = ZIG_TEST_RE.match(line)
			if not m:
				continue
			end = next((j for j in range(i + 1, len(lines)) if lines[j] == "}"), len(lines))
			if any("std.testing.fuzz(" in body for body in lines[i + 1:end]):
				found.append((fMarkAbove(lines, i), m.group(1)))
	return found


def fCmd_Fuzzers(_args):
	tests = fZigFuzzTests()
	for ident, name in tests:
		print(f"{ident or '???????'}\t{name}")
	return 0 if tests else 1


def fCmd_Check(_args):
	problems = []
	seen = {}
	tests = fScan()
	ceiling = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=1)
	for ident, suite, name, where in tests:
		if ident is None:
			problems.append(f"{where}: {suite} test '{name}' has no test-id")
			continue
		if not ID_RE.match(ident):
			problems.append(f"{where}: '{ident}' is not a {WIDTH}-symbol base 62 ID")
			continue
		when = fDecode(ident)
		if not FLOOR <= when <= ceiling:
			problems.append(f"{where}: '{ident}' decodes to {when:%Y-%m-%d}, outside {FLOOR:%Y-%m-%d} to now")
		if ident in seen:
			problems.append(f"{where}: '{ident}' is already used at {seen[ident]}")
		else:
			seen[ident] = where
	problems += fStrays(seen, ceiling)
	for line in problems:
		print(f"  {line}")
	if problems:
		print(f"  {len(problems)} problem(s) across {len(tests)} tests. 'test-ids.py new' makes an ID.")
		return 1
	print(f"IDs ........: {len(tests)} tests, all unique")
	return 0


def fIdsByName(suite):
	return {name: ident for ident, s, name, _ in fScan() if s == suite}


def fCmd_Lookup(args):
	for suite in ("go", "zig"):
		ident = fIdsByName(suite).get(args.name)
		if ident:
			print(ident)
			return 0
	return 1


def fLine(status, ident, name):
	label = {"pass": "ok ....", "fail": "FAIL ..", "skip": "skip .."}[status]
	print(f"  {label}: {ident or '???????'} {name}", flush=True)


def fCmd_Go(_args):
	"""Reads 'go test -json'. Subtests stay inside their parent's line."""
	ids = fIdsByName("go")
	output = {}
	failed = 0
	for raw in sys.stdin:
		try:
			event = json.loads(raw)
		except ValueError:
			print(raw, end="")
			continue
		test = event.get("Test")
		action = event.get("Action")
		if action == "output":
			if test:
				output.setdefault(test.split("/")[0], []).append(event.get("Output", ""))
			elif event.get("Output", "").rstrip("\n") not in ("PASS", "FAIL") and not event.get("Output", "").startswith(("ok ", "FAIL\t", "ok\t")):
				print(event.get("Output", ""), end="")
			continue
		if action in ("build-output",):
			print(event.get("Output", ""), end="")
			continue
		if not test or "/" in test or action not in ("pass", "fail", "skip"):
			if action == "fail" and not test:
				failed += 1
			continue
		ident = ids.get(test)
		fLine(action, ident, test)
		if action == "fail" or ident is None:
			failed += 1
			if ident is None:
				print(f"    {test} has no test-id comment.")
			for text in output.get(test, []):
				if not text.startswith(("=== ", "--- ")):
					print(f"    {text}", end="")
	return 1 if failed else 0


ZIG_START_RE = re.compile(r"^\d+/\d+ (.+?)\.\.\.(.*)$")
ZIG_END_RE   = re.compile(r"^(OK|SKIP|FAIL \(.*\))$")


def fCmd_Zig(_args):
	"""Reads the test runner's own stderr, which prints 'N/M name...OK' when it
	is not talking to a terminal. Anything a test prints lands between the dots
	and the verdict."""
	ids = fIdsByName("zig")
	failed = 0
	current = None
	held = []

	def fFinish(verdict):
		nonlocal failed, current, held
		## 'tests.test.some name' - the module, then the name as written.
		qualified = current
		_, _, name = qualified.partition(".test.")
		current, lines, held = None, held, []
		if re.search(r"\.test_\d+$", qualified):
			return
		status = "pass" if verdict == "OK" else "skip" if verdict == "SKIP" else "fail"
		ident = ids.get(name)
		fLine(status, ident, name or qualified)
		if status == "fail" or ident is None:
			failed += 1
			if ident is None:
				print(f"    '{name}' has no test-id comment.")
			if status == "fail":
				print(f"    {verdict}")
			for text in lines:
				print(f"    {text}")

	for raw in sys.stdin:
		line = raw.rstrip("\n")
		if current is None:
			m = ZIG_START_RE.match(line)
			if not m:
				if line and not line.startswith("All ") :
					print(f"  {line}")
				continue
			current, rest = m.group(1), m.group(2)
			if ZIG_END_RE.match(rest):
				fFinish(rest)
			elif rest:
				held.append(rest)
			continue
		if ZIG_END_RE.match(line):
			fFinish(line)
		else:
			held.append(line)
	if current is not None:
		held.append("(the runner stopped before this test finished)")
		fFinish("FAIL (crashed)")
	return 1 if failed else 0


def main():
	ap = argparse.ArgumentParser(description="Make, check and report test IDs.")
	sub = ap.add_subparsers(dest="cmd", required=True)
	p = sub.add_parser("new");    p.add_argument("-n", type=int, default=1); p.add_argument("--at")
	p = sub.add_parser("decode"); p.add_argument("ids", nargs="+")
	sub.add_parser("check")
	p = sub.add_parser("lookup"); p.add_argument("name")
	sub.add_parser("go")
	sub.add_parser("zig")
	sub.add_parser("fuzzers")
	args = ap.parse_args()
	return {"new": fCmd_New, "decode": fCmd_Decode, "check": fCmd_Check, "lookup": fCmd_Lookup,
		"go": fCmd_Go, "zig": fCmd_Zig, "fuzzers": fCmd_Fuzzers}[args.cmd](args)


if __name__ == "__main__":
	sys.exit(main())


##	History:
##		- 20260930 JC: Created.
##		- 20261004 JC: check also flags an ID no test line names. Added fuzzers.
