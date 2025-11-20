#!/usr/bin/env bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo >&2 "Root permissions are required to run this script. Please run this script as root."
    exit 2
fi

RESETFILE="$1"

restore_redhat() {

    # dnf can be a little wierd with the EPOCH thing and this doesn't really account for that,
    # I don't believe this will break things as it's mainly used for version comparisons
    PACKAGENAME=$(rpm --query --file "${RESETFILE}" --queryformat '%{NAME}')
    FULLPACKAGENAME=$(rpm --query --queryformat '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' --file "${RESETFILE}") 

    workdir=$(mktemp -d)
    trap 'echo " --> Cleaning up temporary directory: ${workdir}"; rm -rf -- "${workdir}"' EXIT
    cd "$workdir"

    if ! dnf download "${FULLPACKAGENAME}" --destdir="${workdir}"; then
        echo " --> Failed to download ${FULLPACKAGENAME}"
        exit 1
    fi

    if ! DOWNLOADED_RPM=$(find "$workdir" -maxdepth 1 -name "*${PACKAGENAME}*.rpm" -print -quit); then
        echo " --> Failed to download ${FULLPACKAGENAME}"
        exit 1
    fi

    if ! rpm -qlp "${DOWNLOADED_RPM}" | grep "${RESETFILE}" ; then
        # this should never happen
        echo " --> didn't find ${RESETFILE} in rpm"
        exit 1
    fi

    rpm2cpio "${DOWNLOADED_RPM}" | cpio -idmv ".${RESETFILE}"
    cp "${workdir}/${RESETFILE}" "${RESETFILE}"
    chmod 0644 "${RESETFILE}"

    cd "$OLDPWD"
}

restore_debian() {
    # dpkg-query manpage advises to set the locale to C.UTF-8 when machine parsing the output
    PACKAGENAME=$(LC_ALL=C.UTF-8 dpkg-query --search "${RESETFILE}" | awk -F: '{print $1}' | head -n 1)
    FULLPACKAGENAME=$(LC_ALL=C.UTF-8 dpkg-query --showformat="\${Package}=\${Version}" --show "${PACKAGENAME}")

    workdir=$(mktemp -d)
    trap 'echo " --> Cleaning up temporary directory: ${workdir}"; rm -rf -- "${workdir}"' EXIT
    cd "$workdir"

    apt-get download "${FULLPACKAGENAME}"
    if ! DOWNLOADED_DEB=$(find "$workdir" -maxdepth 1 -name "*${PACKAGENAME}*.deb" -print -quit); then
        echo " --> Failed to download ${FULLPACKAGENAME}"
        exit 1
    fi

    dpkg-deb --extract "${DOWNLOADED_DEB}" "$workdir"
    cp "${workdir}/${RESETFILE}" "${RESETFILE}"
    chmod 0644 "${RESETFILE}"

    cd "$OLDPWD"
}

if [ -f "/etc/os-release" ] || [ -f "/usr/lib/os-release" ]; then
    if [ -f "/etc/os-release" ]; then
        RELEASE_FILE="/etc/os-release"
    else
        RELEASE_FILE="/usr/lib/os-release"
    fi
    # shellcheck disable=SC1090
    OS_ID=$(source "$RELEASE_FILE"; echo -n "$ID")
    case "$OS_ID" in
    debian|ubuntu)
        echo "detected Debian, using apt/dpkg for package operations"
        restore_debian
        ;;
    fedora|rhel|rocky|almalinux)
        echo "detected RedHat, using rpm/dnf for package operations"
        restore_redhat
        ;;
    *)
        echo "Not supported"
        ;;
    esac
else
    echo -e "ERROR: Release files '/etc/os-release' and '/usr/lib/os-release' do not exist."
    exit 1
fi
