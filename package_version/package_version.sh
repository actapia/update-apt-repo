#!/usr/bin/env bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
if [ "$#" -eq 1 ]; then
    package="$(basename "$PWD")"
    version="$1"
elif [ "$#" -eq 2 ]; then
    package="$1"
    version="$2"
elif [ "$#" -gt 2 ]; then
    >&2 echo "Too many arguments."
else
    >&2 echo "Too few arguments."
fi
rm -f "$package.tar.xz"
changes_files=( "${package}_$version"*.changes )
# shellcheck disable=SC2199
if [[ -e "${changes_files[@]}" ]]; then
    # shellcheck disable=SC2128
    changes_file="$changes_files"
    readarray -t package_files < <(awk -f "$DIR/get_changes_filenames.awk" "$changes_file")
    #| xargs -d "\n" tar cJvf "$package.tar.xz"
    has_source=false
    for f in "${package_files[@]}"; do
	if [[ "$f" == *.tar.gz ]]; then
	    has_source=true
	    break
	fi
    done
    if [ $has_source = false ]; then
	>&2 echo -e "\033[33mWARNING: Changes file does not appear to include source.\033[0m"
    fi
    tar -hcJvf "$package.tar.xz" "$changes_file" "${package_files[@]}"
else
    echo "No changes file found for version $version. (glob ${package}_$version*.changes)"
fi
#tar cJvf "$package.tar.xz" "$package_$1.dsc" "$package_$1"*.tar.gz "$package_$1"*.buildinfo "$package_$1"*.changes "$package_$1"*.deb
