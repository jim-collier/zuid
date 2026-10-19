# check=skip=InvalidDefaultArgInFrom
# CodeQL for 'cicd.bash --leakcheck', on top of the main image. It's about
# 480 MB, so it lives here, and only a --leakcheck run builds or starts it.
#
# The tag is this file's git hash plus the main image's, so an edit to either
# means a new one.
#
# GitHub's CodeQL terms allow it on a codebase under an OSI license, and in CI
# when that codebase is on GitHub.com. Both hold for zuid. Don't push this
# image anywhere.
#
# Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
# SPDX-License-Identifier: GPL-2.0-or-later

ARG BASE
FROM ${BASE}

# The per-language bundles are the CLI plus one extractor and its queries. The
# rest of the two is the same, byte for byte, so the Go one goes over the C one.
ARG CODEQL_VER=2.27.2
ARG CODEQL_CPP_SHA256=638338a6489c4229c06012239f570dd76992b4ed862c1a7922d46496622a72ca
ARG CODEQL_GO_SHA256=0cfb942cd33fb71d3a3b84dad626ef8895ea3f1ceb097bc8cdb7d4493f032ae9

WORKDIR /tmp/dl
RUN base="https://github.com/github/codeql-action/releases/download/codeql-bundle-v${CODEQL_VER}" \
	&& curl -fsSLo cpp.tar.zst "${base}/codeql-bundle-cpp-linux64.tar.zst" \
	&& echo "${CODEQL_CPP_SHA256}  cpp.tar.zst" | sha256sum -c - \
	&& curl -fsSLo go.tar.zst "${base}/codeql-bundle-go-linux64.tar.zst" \
	&& echo "${CODEQL_GO_SHA256}  go.tar.zst" | sha256sum -c - \
	&& tar -C /opt --zstd -xf cpp.tar.zst \
	&& tar -C /opt --zstd -xf go.tar.zst --skip-old-files \
	&& ln -s /opt/codeql/codeql /usr/local/bin/codeql \
	&& codeql version --format=terse | grep -qx "${CODEQL_VER}" \
	&& cd / && rm -rf /tmp/dl
WORKDIR /
