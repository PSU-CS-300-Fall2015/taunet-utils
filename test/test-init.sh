#!/bin/sh
# Copyright © 2015 Bart Massey
# [This program is licensed under the GPL version 3 or later.]
# Please see the file COPYING in the source
# distribution of this software for license terms.

# Create regression test against known-good echo server.
# Tests should be hand-checked after creation for validity.
TAUNET_SEND=../dist/build/taunet-send/taunet-send
ECHO_SERVER=barton.cs.pdx.edu
if [ ! -x $TAUNET_SEND ]
then
    echo "no taunet-send at $TAUNET_SEND" >&2
    exit 1
fi
[ -d outputs ] || mkdir outputs
for i in inputs/*.txt
do
    N=`basename $i`
    $TAUNET_SEND $ECHO_SERVER <inputs/$N |
    sed '5d' >outputs/$N
done
