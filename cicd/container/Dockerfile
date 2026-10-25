# Build and test tools for 'cicd.bash --container'. Everything the build and
# test stages call, pinned, so a run here does not depend on what the host has
# installed. The demo, dogfood, backup and git stages stay on the host.
#
# The tag is this file's git hash, so any edit here means a new image.
#
# Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
# SPDX-License-Identifier: GPL-2.0-or-later

FROM debian:trixie-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f

# Apt is pinned only as far as the base image is. Trixie point releases move
# these little, and the toolchains that matter come from tarballs below.
# llvm is for llvm-ar, llvm-readobj and llvm-pdbutil. rpm, rpm2cpio, cpio and dpkg
# only read what nfpm writes. libicu and libgssapi are for pwsh. Shellcheck comes from
# upstream, since trixie has 0.10 and its warnings differ. gcc's sanitizers and
# analyzer and clang's analyzer are the C checks, which a host run calls from here.
# clang is named by major so a new base can't move it without the build failing.
# clang-tools has analyze-build and clang-extdef-mapping, for the cross-file
# analyzer, and heaptrack is for the C soak. Both are --leakcheck only.
RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		bash ca-certificates curl git xz-utils zstd zip unzip file \
		gcc libc6-dev binutils llvm clang-19 clang-tools-19 heaptrack \
		python3 rpm rpm2cpio cpio \
		libicu76 libgssapi-krb5-2 \
	&& rm -rf /var/lib/apt/lists/*

# cicd.bash reads GO_VER too, and builds the shipped reactor wasm with it.
ARG GO_VER=1.26.9
ARG GO_SHA256=42d158b4d8f7b61ac0a830567c940a86098fb7aac52e467a5ebec03ef5cc2f8d
ARG ZIG_VER=0.17.0
ARG ZIG_SHA256=1cbe9df9f27e6b78d14ccbca43b6703a404ef79ef1c463de901d7f088d4e2026
ARG NFPM_VER=2.47.0
ARG NFPM_SHA256=0660ca602b2d2d2ae4781a06c692b3eeb9d437ffea05b831d76e41f4a3188783
ARG SC_VER=0.11.0
# Upstream posts no checksums. Taken from the download, 20261010.
ARG SC_SHA256=8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198
ARG PWSH_VER=7.6.6
ARG PWSH_SHA256=ddbc4a2d113bbd46d283cfedcbcd117a70caefd7673f41f2b4e0000badf103bc

WORKDIR /tmp/dl
RUN curl -fsSLo go.tgz "https://go.dev/dl/go${GO_VER}.linux-amd64.tar.gz" \
	&& echo "${GO_SHA256}  go.tgz" | sha256sum -c - \
	&& tar -C /opt -xzf go.tgz \
	&& curl -fsSLo zig.txz "https://ziglang.org/download/${ZIG_VER}/zig-x86_64-linux-${ZIG_VER}.tar.xz" \
	&& echo "${ZIG_SHA256}  zig.txz" | sha256sum -c - \
	&& mkdir /opt/zig && tar -C /opt/zig --strip-components=1 -xJf zig.txz \
	&& curl -fsSLo nfpm.tgz "https://github.com/goreleaser/nfpm/releases/download/v${NFPM_VER}/nfpm_${NFPM_VER}_Linux_x86_64.tar.gz" \
	&& echo "${NFPM_SHA256}  nfpm.tgz" | sha256sum -c - \
	&& tar -C /usr/local/bin -xzf nfpm.tgz nfpm \
	&& curl -fsSLo sc.txz "https://github.com/koalaman/shellcheck/releases/download/v${SC_VER}/shellcheck-v${SC_VER}.linux.x86_64.tar.xz" \
	&& echo "${SC_SHA256}  sc.txz" | sha256sum -c - \
	&& tar -C /usr/local/bin --strip-components=1 -xJf sc.txz "shellcheck-v${SC_VER}/shellcheck" \
	&& curl -fsSLo pwsh.tgz "https://github.com/PowerShell/PowerShell/releases/download/v${PWSH_VER}/powershell-${PWSH_VER}-linux-x64.tar.gz" \
	&& echo "${PWSH_SHA256}  pwsh.tgz" | sha256sum -c - \
	&& mkdir /opt/pwsh && tar -C /opt/pwsh -xzf pwsh.tgz && chmod +x /opt/pwsh/pwsh \
	&& ln -s /opt/pwsh/pwsh /usr/local/bin/pwsh \
	&& cd / && rm -rf /tmp/dl

# The Go checkers, which a host run calls from here too. go install checks each
# module against Go's checksum database, which stands in for a sha256.
ARG STATICCHECK_VER=v0.8.2
ARG GOVULNCHECK_VER=v1.9.0
RUN export GOBIN=/usr/local/bin GOPATH=/tmp/gopath GOCACHE=/tmp/gocache GOTOOLCHAIN=local CGO_ENABLED=0 GOFLAGS=-trimpath \
	&& /opt/go/bin/go install "honnef.co/go/tools/cmd/staticcheck@${STATICCHECK_VER}" \
	&& /opt/go/bin/go install "golang.org/x/vuln/cmd/govulncheck@${GOVULNCHECK_VER}" \
	&& rm -rf /tmp/gopath /tmp/gocache

# PSScriptAnalyzer for the PowerShell lint, which a host run calls from here
# too. The PowerShell Gallery package, unpacked where pwsh looks for modules.
# The gallery's own SHA512 for it matched the download, 20261019.
ARG PSSA_VER=1.25.0
ARG PSSA_SHA256=14e634c828eb98efb9f40b2918ba90f139ed5eccdf663a2a747736d996995d60
RUN curl -fsSLo /tmp/pssa.nupkg "https://www.powershellgallery.com/api/v2/package/PSScriptAnalyzer/${PSSA_VER}" \
	&& echo "${PSSA_SHA256}  /tmp/pssa.nupkg" | sha256sum -c - \
	&& mkdir -p "/opt/pwsh/Modules/PSScriptAnalyzer/${PSSA_VER}" \
	&& unzip -q /tmp/pssa.nupkg -d "/opt/pwsh/Modules/PSScriptAnalyzer/${PSSA_VER}" \
		-x '_rels/*' 'package/*' '\[Content_Types\].xml' '*.nuspec' \
	&& rm /tmp/pssa.nupkg

# Runs as the caller's uid, which has no passwd entry here. /cache is where the
# named volume goes, and a new volume takes this dir's mode, so anyone can write.
# Zig's global cache has a volume of its own, so cicd.bash can empty it whole.
RUN mkdir -m 1777 /cache /cache/home /zig-cache
ENV PATH=/opt/go/bin:/opt/zig:${PATH} \
	HOME=/cache/home \
	ZIG_GLOBAL_CACHE_DIR=/zig-cache \
	GOTOOLCHAIN=local \
	POWERSHELL_TELEMETRY_OPTOUT=1 \
	POWERSHELL_UPDATECHECK=Off \
	DOTNET_CLI_TELEMETRY_OPTOUT=1
WORKDIR /
