#!/bin/sh

set -eux

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

cabal v2-build kontrakcja-shake
cabal v2-run kontrakcja-shake -- $@
