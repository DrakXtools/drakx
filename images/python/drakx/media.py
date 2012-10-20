import os

class Media(object):
    def __init__(self, name):
        self.name = name

    def getSynthesis(self):
        return "/media/%s/release/media_info/synthesis.hdlist.cz" % self.name

    def getSize(self):
        return self.size/1024/1024

    def getCfgEntry(self, ext=".cz"):
        cfgentry = "\n" \
                "[%s]\n" \
                "synthesis=%s/media_info/synthesis.hdlist%s\n" \
                "pubkey=%s/media_info/pubkey\n" \
                "name=%s media\n" \
                "size=%dm\n" % (self.name,self.name,ext,self.name,self.name,self.getSize())
        return cfgentry

    name = None
    pkgs = []
    size = 0

# vim:ts=4:sw=4:et
