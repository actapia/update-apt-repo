BEGIN {
    in_files = 0;
}
(in_files) {
    if ($1 != "") {
	print $NF;
    }
}
($0 == "Files:") {
    in_files = 1;
}
