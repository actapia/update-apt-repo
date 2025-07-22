import argparse
import os
from collections import OrderedDict
from InsertableOrderedDict import InsertableOrderedDict
from IPython import embed

repo_root = os.path.expanduser("~/HTML/CS485/repo")

class Stanza:
    def __init__(self):
        self.fields = InsertableOrderedDict()

    def add_line(self,line):
        if not line.startswith(" "):
            line_split = line.split(":")
            self.fields[line_split[0]] = ":".join(line_split[1:])
        else:
            last_field = self.fields.last_key()
            self.fields[last_field] = "{}\n{}".format(self.fields[last_field],line)

    def add_field_after(self,prevf,field,value):
        self.fields.insert_after(prevf,field," "+value)

    def add_field_before(self,nextf,field,value):
        self.fields.insert_before(nextf,field," "+value)

    def __getitem__(self,key):
        return self.fields[key].strip()

    def __setitem__(self,key,value):
        self.fields[key] = value

    def __str__(self):
        return "\n".join(":".join(i) for i in self.fields.items())

    def __bool__(self):
        return bool(self.fields)

    @classmethod
    def read_stanzas(cls,f):
        stanzas = OrderedDict()
        current_stanza = Stanza()
        for line in f:
            stripped = line.strip()
            if stripped:
                current_stanza.add_line(line.rstrip())
            else:
                try:
                    stanzas[current_stanza["Package"]] = current_stanza
                except KeyError:
                    embed()
                current_stanza = Stanza()
        if current_stanza:
            stanzas[current_stanza["Package"]] = current_stanza
        return stanzas

    @classmethod
    def read_stanzas_from_filename(cls, fn):
        try:
            with open(fn, "r") as f:
                return cls.read_stanzas(f)
        except FileNotFoundError:
            return OrderedDict()
        

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("-p","--packages")
    parser.add_argument("-s","--sources")
    parser.add_argument("-x","--extra",help="Additional sources.")
    args = parser.parse_args()
    package_stanzas = Stanza.read_stanzas_from_filename(args.packages)
    source_stanzas = Stanza.read_stanzas_from_filename(args.sources)
    for source_stanza in source_stanzas.values():
        binaries = [b.strip() for b in source_stanza["Binary"].split(",")]
        for binary in binaries:
            try:
                package_stanza = package_stanzas[binary]
            except KeyError:
                next
            try:
                package_stanza.add_field_after("Package","Source",source_stanza["Package"])
            except KeyError:
                pass
    print("\n\n".join([str(s) for s in package_stanzas.values()]),end="")
