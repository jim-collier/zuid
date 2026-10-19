#!/usr/bin/env python3

##	Purpose: Reads what CodeQL found and decides. Any finding in our own code
##		fails, style ones too. In third-party code, under a vendor/ folder,
##		only the security and correctness ones count, since its style isn't
##		ours to fix. A finding listed in codeql-suppressions.txt, with the
##		backlog item for its fix, is left out. A listing nothing matched
##		fails, so it gets taken out once the fix is in. CodeQL's own in-source
##		suppression comments are ignored.
##		'coverage' fails if a file the build compiled isn't in the database,
##		which is how a build that compiled nothing would look.
##	Syntax:
##		codeql-report.py report <sarif> <go|c> <suppressions file>
##		codeql-report.py coverage <database dir> <file...>
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


import json, os, sys, zipfile


bugTags = {"security", "correctness"}


def isThirdParty(path):
	return path.startswith("vendor/") or "/vendor/" in path


def loadSuppressions(path, language):
	entries = []
	with open(path, encoding="utf-8") as f:
		for number, line in enumerate(f, 1):
			fields = line.split("#", 1)[0].split()
			if not fields:
				continue
			if len(fields) != 4 or len(fields[1]) != 16 or not fields[1].isdigit():
				sys.exit(f"{path}:{number}: wants <language> <backlog ID> <rule> <file>, with the 16-digit backlog ID")
			if fields[0] == language:
				entries.append({"id": fields[1], "rule": fields[2], "path": fields[3], "hits": 0})
	return entries


def report(sarifPath, language, suppressionsPath):
	with open(sarifPath, encoding="utf-8") as f:
		sarif = json.load(f)
	entries = loadSuppressions(suppressionsPath, language)
	counted, style = [], 0
	for run in sarif.get("runs", []):
		tags = {}
		for component in [run["tool"]["driver"], *run["tool"].get("extensions", [])]:
			for rule in component.get("rules", []):
				tags[rule["id"]] = set(rule.get("properties", {}).get("tags", []))
		for result in run.get("results", []):
			rule = result.get("ruleId") or result.get("rule", {}).get("id", "?")
			where = result["locations"][0]["physicalLocation"]
			path = where["artifactLocation"]["uri"]
			line = where.get("region", {}).get("startLine", 0)
			entry = next((e for e in entries if e["rule"] == rule and e["path"] == path), None)
			if entry:
				entry["hits"] += 1
				continue
			if isThirdParty(path) and not tags.get(rule, set()) & bugTags:
				style += 1
				continue
			text = result.get("message", {}).get("text", "").splitlines()
			counted.append(f"    {rule} at {path}:{line}: {text[0] if text else ''}")
	stale = [e for e in entries if not e["hits"]]
	for e in entries:
		if e["hits"]:
			print(f"Suppressed .: {e['hits']} of {e['rule']} in {e['path']}, until {e['id']} is fixed")
	if style:
		print(f"Not counted: {style} style findings in third-party code")
	for text in counted:
		print(text)
	for e in stale:
		print(f"    {e['id']} in {os.path.basename(suppressionsPath)} matched nothing, so it can come out: {e['rule']} in {e['path']}")
	print(f"Findings ...: {len(counted)}")
	return 1 if counted or stale else 0


def coverage(dbDir, files):
	if not files:
		sys.exit("No files given, so there's nothing to look for.")
	archive = os.path.join(dbDir, "src.zip")
	if not os.path.isfile(archive):
		print(f"No {archive}, so the database has no source in it.")
		return 1
	with zipfile.ZipFile(archive) as z:
		inside = {os.path.realpath("/" + name) for name in z.namelist()}
	missing = [f for f in files if os.path.realpath(f) not in inside]
	for f in missing:
		print(f"    Not in the database: {f}")
	if missing:
		print(f"{len(missing)} of the {len(files)} files the build compiled aren't in the database, so CodeQL didn't see them compile.")
		return 1
	print(f"Database ...: all {len(files)} files the build compiled")
	return 0


def main(argv):
	if len(argv) == 4 and argv[0] == "report":
		return report(*argv[1:])
	if len(argv) >= 2 and argv[0] == "coverage":
		return coverage(argv[1], argv[2:])
	sys.exit("Syntax: codeql-report.py report <sarif> <go|c> <suppressions file> | coverage <database dir> <file...>")


if __name__ == "__main__":
	sys.exit(main(sys.argv[1:]))


##	History:
##		- 20261019 JC: Created.
