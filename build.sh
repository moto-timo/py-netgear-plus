#!/bin/bash

# Exit if any programs fail:
set -e

# Can be /var/cache/pbuilder/result for some workflows:
RESULT_DIRECTORY=/var/cache/pbuilder/result

# Get some information from the changelog
SOURCE="$(dpkg-parsechangelog --show-field=Source)"
VERSION="$(dpkg-parsechangelog --show-field=Version)"

# Read "--git-dist=foo" and "--git-arch=bar" from the command-line:
DIST=bookworm
ARCH="$(dpkg --print-architecture)"
for ARG
do
    case "$ARG" in
        "--git-dist="*)
            DIST="${ARG#--git-dist=}"
            ;;
        "--git-arch="*)
            ARCH="${ARG#--git-arch=}"
            ;;
    esac
done

CHANGES_FILE="$RESULT_DIRECTORY/${SOURCE}_${VERSION}_${ARCH}.changes"
DEB_FILE="$RESULT_DIRECTORY/${SOURCE}_${VERSION}_${ARCH}.deb"
LOG_FILE="$RESULT_DIRECTORY/${SOURCE}_${VERSION}_${ARCH}.log"

# Calculate the pbuilder base tarball/path:
BASE=/var/cache/pbuilder/base
if [ -n "$DIST" -a "$DIST" != sid ]
then BASE="$BASE-$DIST"
fi
if [ -n "$ARCH" -a "$ARCH" != "$(dpkg --print-architecture)" ]
then BASE="$BASE-$ARCH"
fi

# Run pbuilder with arguments from the command-line:
echo -n "[$(date)] Running gbp buildpackage" >&2
set -o pipefail
sudo BUILDER=pbuilder gbp buildpackage "$@" \
    | tee "$LOG_FILE" \
    | while read LINE ; do echo -n . >&2 ; done
set +o pipefail
echo " OK" >&2
echo >&2

echo "[$(date)] Running lintian..." >&2
lintian --info --display-info --pedantic "$CHANGES_FILE"
echo "[$(date)] lintian: OK" >&2
echo >&2

echo "[$(date)] Running piuparts..." >&2
sudo piuparts --log-level info --basetgz "$BASE.tgz" "$DEB_FILE"
echo "[$(date)] piuparts: OK" >&2
echo >&2

echo "[$(date)] Running autopkgtest..." >&2
set +e
autopkgtest --no-built-binaries --apt-upgrade "$CHANGES_FILE" \
    -- unshare --release "$DIST" --arch "$ARCH"
RESULT="$?"
set -e
case "$RESULT" in
    0) echo "autopkgtest: OK" >&2 ;;
    8) echo "autopkgtest: no tests in this package, or all non-superficial tests were skipped" >&2 ;;
    *) exit "$RESULT" >&2
esac
echo >&2

echo "[$(date)] Success!" >&2
