#!/usr/bin/env python3

##	Purpose: Reads 'govulncheck -format json' on stdin and fails on any
##		advisory in a third-party module, at any level, called or not, and on
##		any the standard library has in code we call. The Go that's scanned
##		builds the shipped reactor wasm, so its library is ours to keep
##		current. One it has that we never call only gets counted.
##	Syntax: govulncheck -format json ./... | vuln-report.py
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


import json, sys


def main():
	## The stream is indented objects back to back, not one per line.
	text, decoder, pos = sys.stdin.read(), json.JSONDecoder(), 0
	summaries, theirs, stdlib, uncalled = {}, {}, {}, set()
	goVersion = "?"
	while True:
		while pos < len(text) and text[pos].isspace():
			pos += 1
		if pos >= len(text):
			break
		obj, pos = decoder.raw_decode(text, pos)
		if "config" in obj:
			goVersion = obj["config"].get("go_version", goVersion)
		if "osv" in obj:
			summaries[obj["osv"]["id"]] = obj["osv"].get("summary", "")
		finding = obj.get("finding")
		if not finding:
			continue
		frame = finding["trace"][0]
		if frame.get("module") == "stdlib":
			if frame.get("function"):
				stdlib.setdefault(finding["osv"], f"{frame.get('package')}.{frame['function']}")
			else:
				uncalled.add(finding["osv"])
			continue
		theirs.setdefault(finding["osv"], f"{frame.get('module')}@{frame.get('version')}")
	for ident, where in sorted(theirs.items()):
		print(f"    {ident} in {where}: {summaries.get(ident, '')}")
	for ident, where in sorted(stdlib.items()):
		print(f"    {ident} in {goVersion}, called from {where}: {summaries.get(ident, '')}")
	uncalled -= stdlib.keys()
	if uncalled:
		print(f"Stdlib .....: {len(uncalled)} advisories for {goVersion} in code we don't call, not counted")
	return 1 if theirs or stdlib else 0


if __name__ == "__main__":
	sys.exit(main())


##	History:
##		- 20261019 JC: Created.
##		- 20261019 JC: Called stdlib advisories fail too.
