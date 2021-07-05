from llist import dllist
from IPython import embed

def insertbefore(li,value,node):
    return li.insert(value,node)

def insertafter(li,value,node):
    return li.insert(value,node.next)

# A simple ordered dict that supports insertion before and after elements.
class InsertableOrderedDict:
    def __init__(self):
        self._list = dllist()
        self._dict = dict()

    def __getitem__(self,key):
        return self._dict[key].value[1]

    def __setitem__(self,key,value):
        try:
            self._dict[key].value = (key,value)
        except KeyError:
            self._dict[key] = self._list.append((key,value))

    def insert_before(self,old_key,key,value):
        if key in self._dict:
            raise KeyError("Key already exists in dictionary")
        self._dict[key] = insertbefore(self._list,(key,value),self._dict[old_key])

    def insert_after(self,old_key,key,value):
        if key in self._dict:
            raise KeyError("Key already exists in dictionary")
        self._dict[key] = insertafter(self._list,(key,value),self._dict[old_key])

    def keys(self):
        for key, _ in self._list:
            yield key

    def values(self):
        for _, value in self._list:
            yield value

    def items(self):
        for key, value in self._list:
            yield (key, value)

    def __iter__(self):
        return iter(self.keys())

    def __bool__(self):
        return bool(self._dict)

    def first_key(self):
        return self._list.first.value[0]

    def last_key(self):
        return self._list.last.value[0]

if __name__ == "__main__":
    iod = InsertableOrderedDict()
    iod["a"] = "Apple"
    iod["p"] = "Pear"
    embed()
