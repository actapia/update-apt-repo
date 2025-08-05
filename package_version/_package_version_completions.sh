#!/usr/bin/env bash
_pv_complete()
{
    DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    if [ "$COMP_CWORD" -eq 2 ]; then
	package="${COMP_WORDS[COMP_CWORD-1]}"
    elif [ "$COMP_CWORD" -eq 1 ]; then
	package="$(basename "$PWD")"
    else
	return
    fi
    for f in "${package}_${COMP_WORDS[COMP_CWORD]}"*.dsc; do
	# shellcheck disable=SC2001
	version="$(echo "$f" | sed -e "s/${package}_\(.*\)\.dsc/\1/")"
	changes_files=( "${package}_$version"*.changes )
	# shellcheck disable=SC2199
 	if [[ -e "${changes_files[@]}" ]]; then
	    # shellcheck disable=SC2128
	    changes_file="$changes_files"
	    missing_file=false
	    while IFS= read -r line; do
		if ! [ -f "$line" ]; then
		    missing_file=true
		    break
		fi
	    done < <(awk -f "$DIR/get_changes_filenames.awk" "$changes_file")
	    if [ "$missing_file" = false ]; then
		COMPREPLY+=("$version")
	    fi
	fi
    done
}

complete -F _pv_complete package_version.sh
