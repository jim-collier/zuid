#!/usr/bin/env python3

##	Purpose: Prints the version resource of a Windows exe or dll, one fact a
##		line, so the pipeline can check what Explorer's Properties tab would
##		show without a Windows machine. Reads the file itself, since
##		llvm-readobj only dumps the resource as hex.
##	Syntax: pe-version.py FILE
##		Prints 'resources N' (how many VERSIONINFO the file has), the fixed
##		numbers, then 'Name=Value' per string. Exits 1 with no resource, or one
##		it can't read.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


import struct, sys

RT_VERSION = 16


def fDie(msg):
	print(f"pe-version.py: {msg}", file=sys.stderr)
	sys.exit(1)


def fU16(data, at): return struct.unpack_from("<H", data, at)[0]
def fU32(data, at): return struct.unpack_from("<I", data, at)[0]
def fAlign4(n): return (n + 3) & ~3


def fSections(data):
	pe = fU32(data, 0x3C)
	if data[pe:pe + 4] != b"PE\0\0":
		fDie("not a PE file")
	sectionCount, optSize = fU16(data, pe + 6), fU16(data, pe + 20)
	opt = pe + 24
	## PE32+ puts the data directories 16 bytes further on than PE32.
	dirs = opt + (112 if fU16(data, opt) == 0x20B else 96)
	resRva = fU32(data, dirs + 2 * 8)
	sections = []
	for i in range(sectionCount):
		s = opt + optSize + i * 40
		sections.append((fU32(data, s + 12), max(fU32(data, s + 8), fU32(data, s + 16)), fU32(data, s + 20)))
	return resRva, sections


def fOffset(sections, rva):
	for va, size, raw in sections:
		if va <= rva < va + size:
			return raw + rva - va
	fDie(f"RVA 0x{rva:x} is in no section")


def fEntries(data, at):
	named, ids = fU16(data, at + 12), fU16(data, at + 14)
	return [(fU32(data, at + 16 + i * 8), fU32(data, at + 20 + i * 8)) for i in range(named + ids)]


def fKey(data, at):
	end = at
	while fU16(data, end):
		end += 2
	return data[at:end].decode("utf-16-le"), end + 2


## A version block: length, value length, type, key, value, then children,
## each part on a 4-byte boundary. A text value's length is in UTF-16 units.
def fBlock(data, at):
	length, valueLen, isText = fU16(data, at), fU16(data, at + 2), fU16(data, at + 4)
	key, end = fKey(data, at + 6)
	valueAt = fAlign4(end)
	valueEnd = valueAt + (valueLen * 2 if isText else valueLen)
	children, child = [], fAlign4(valueEnd)
	while child < at + length:
		block = fBlock(data, child)
		children.append(block)
		child = fAlign4(child + block["length"])
	return {"length": length, "key": key, "value": data[valueAt:valueEnd], "isText": isText, "children": children}


def fQuad(ms, ls): return f"{ms >> 16}.{ms & 0xFFFF}.{ls >> 16}.{ls & 0xFFFF}"


def main():
	if len(sys.argv) != 2:
		fDie("usage: pe-version.py FILE")
	data = open(sys.argv[1], "rb").read()
	resRva, sections = fSections(data)
	if resRva == 0:
		fDie("no resources")
	base = fOffset(sections, resRva)

	versions = [e for e in fEntries(data, base) if e[0] == RT_VERSION]
	if not versions:
		fDie("no version resource")
	## Type, then name, then language. Count every name and language under it.
	leaves = []
	for _, typeDir in versions:
		for _, nameDir in fEntries(data, base + (typeDir & 0x7FFFFFFF)):
			for _, leaf in fEntries(data, base + (nameDir & 0x7FFFFFFF)):
				leaves.append(base + leaf)
	print(f"resources {len(leaves)}")
	print(f"STAMP 0x{fU32(data, base + 4):x}")

	root = fBlock(data, fOffset(sections, fU32(data, leaves[0])))
	if root["key"] != "VS_VERSION_INFO" or len(root["value"]) < 52:
		fDie("the version resource has no VS_FIXEDFILEINFO")
	fixed = struct.unpack_from("<13I", root["value"])
	if fixed[0] != 0xFEEF04BD:
		fDie("bad VS_FIXEDFILEINFO signature")
	print(f"FILEVERSION {fQuad(fixed[2], fixed[3])}")
	print(f"PRODUCTVERSION {fQuad(fixed[4], fixed[5])}")
	print(f"FILEFLAGSMASK 0x{fixed[6]:x}")
	print(f"FILEFLAGS 0x{fixed[7]:x}")
	print(f"FILEOS 0x{fixed[8]:x}")
	print(f"FILETYPE 0x{fixed[9]:x}")
	print(f"FILEDATE 0x{(fixed[11] << 32) | fixed[12]:x}")

	for info in root["children"]:
		if info["key"] == "StringFileInfo":
			for table in info["children"]:
				print(f"StringTable {table['key']}")
				for entry in table["children"]:
					text = entry["value"].decode("utf-16-le").rstrip("\0")
					print(f"{entry['key']}={text}")
		elif info["key"] == "VarFileInfo":
			for var in info["children"]:
				pairs = struct.unpack_from(f"<{len(var['value']) // 2}H", var["value"])
				print(f"{var['key']} " + " ".join(f"{p:04x}" for p in pairs))
	return 0


if __name__ == "__main__":
	sys.exit(main())


##	History:
##		- 20261019 JC: Created.
