#!/usr/bin/env bash

# Tell build process to exit if there are any errors.
set -euo pipefail

# Pull in repos
get_yaml_array REPOS '.repos[]' "$1"
if [[ ${#REPOS[@]} -gt 0 ]]; then
    echo "Adding repositories"
    for REPO in "${REPOS[@]}"; do
        REPO="${REPO//%OS_VERSION%/${OS_VERSION}}"
        curl --output-dir "/etc/yum.repos.d/" -O "${REPO//[$'\t\r\n ']}"
    done
fi

get_yaml_array KEYS '.keys[]' "$1" 
if [[ ${#KEYS[@]} -gt 0 ]]; then
    echo "Adding keys"
    for KEY in "${KEYS[@]}"; do
        rpm --import "${KEY//[$'\t\r\n ']}"
    done
fi

# Create symlinks to fix packages that create directories in /opt
get_yaml_array OPTFIX '.optfix[]' "$1"
if [[ ${#OPTFIX[@]} -gt 0 ]]; then
    echo "Creating symlinks to fix packages that install to /opt"
    # Create symlink for /opt to /var/opt since it is not created in the image yet
    mkdir -p "/var/opt"
    ln -s "/var/opt"  "/opt"
    # Create symlinks for each directory specified in recipe.yml
    for OPTPKG in "${OPTFIX[@]}"; do
        OPTPKG="${OPTPKG%\"}"
        OPTPKG="${OPTPKG#\"}"
        OPTPKG=$(printf "$OPTPKG")
        mkdir -p "/usr/lib/opt/${OPTPKG}"
        ln -s "../../usr/lib/opt/${OPTPKG}" "/var/opt/${OPTPKG}"
        echo "Created symlinks for ${OPTPKG}"
    done
fi

get_yaml_array INSTALL '.install[]' "$1"
get_yaml_array REMOVE '.remove[]' "$1"

if [[ ${#INSTALL[@]} -gt 0 ]]; then
    for PKG in "${INSTALL[@]}"; do
        if [[ "$PKG" =~ ^https?:\/\/.* ]]; then
            REPLACED_PKG="${PKG//%OS_VERSION%/${OS_VERSION}}"
            echo "Installing directly from URL: ${REPLACED_PKG}"
            rpm-ostree install "$REPLACED_PKG"
            INSTALL=( "${INSTALL[@]/$PKG}" ) # delete URL from install array
        fi
    done
fi

# The installation is done with some wordsplitting hacks
# because of errors when doing array destructuring at the installation step.
# This is different from other ublue projects and could be investigated further.
INSTALL_STR=$(echo "${INSTALL[*]}" | tr -d '\n')
REMOVE_STR=$(echo "${REMOVE[*]}" | tr -d '\n')

# Install and remove RPM packages
if [[ ${#INSTALL[@]} -gt 0 && ${#REMOVE[@]} -gt 0 ]]; then
    echo "Installing & Removing RPMs"
    echo "Installing: ${INSTALL_STR[*]}"
    echo "Removing: ${REMOVE_STR[*]}"
    # Doing both actions in one command allows for replacing required packages with alternatives
    rpm-ostree override remove $REMOVE_STR $(printf -- "--install=%s " $INSTALL_STR)
elif [[ ${#INSTALL[@]} -gt 0 ]]; then
    echo "Installing RPMs"
    echo "Installing: ${INSTALL_STR[*]}"
    rpm-ostree install $INSTALL_STR
elif [[ ${#REMOVE[@]} -gt 0 ]]; then
    echo "Removing RPMs"
    echo "Removing: ${REMOVE_STR[*]}"
    rpm-ostree override remove $REMOVE_STR
fi
