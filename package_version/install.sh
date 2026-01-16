#!/usr/bin/env bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
if ! [[ -v DESTDIR ]]; then
    DESTDIR="$HOME/.local/bin"
fi
mkdir -p "$DESTDIR"
cp "$DIR"/{package_version.sh,get_changes_filenames.awk} \
   "$DIR"/_package_version_completions.sh "$DESTDIR"
read -p "Source tab completions in ~/.bashrc?" -n 1 -r
echo
if [[ "$REPLY" = "y" || "$REPLY" = "Y" ]]; then
    if ! grep -q ~/.bashrc -e 'Lines added by package_version/install.sh'; then
	cat > ~/.bashrc <<EOF
# Lines added by package_version/install.sh
source _package_version_completions.sh
# End lines added by package_version/install.sh
EOF
    fi  
fi
