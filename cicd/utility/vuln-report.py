#!/usr/bin/env python3

##	Purpose: Reads 'govulncheck -format json' on stdin and fails on any
##		advisory in a third-party module, at any level, called or not. The
##		standard library's only get counted. Those belong to whatever Go builds
##		the module, which is the user's toolchain, not the one this ran on.
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
	summaries, theirs, stdlib = {}, {}, set()
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
				stdlib.add(finding["osv"])
			continue
		theirs.setdefault(finding["osv"], f"{frame.get('module')}@{frame.get('version')}")
	for ident, where in sorted(theirs.items()):
		print(f"    {ident} in {where}: {summaries.get(ident, '')}")
	if stdlib:
		print(f"Stdlib .....: {len(stdlib)} called advisories for {goVersion}, not counted here")
	return 1 if theirs else 0


if __name__ == "__main__":
	sys.exit(main())


##	History:
##		- 20261019 JC: Created.
