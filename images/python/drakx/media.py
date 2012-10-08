class Media(object):
    def __init__(self, name):
        self.name = name

    def getSynthesis(self):
        return "/media/%s/release/media_info/synthesis.hdlist.cz" % self.name

    name = None
    pkgs = []

# vim:ts=4:sw=4:et
