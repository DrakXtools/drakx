import subprocess, StringIO

BLACK     = 30
RED       = 31
GREEN     = 32
YELLOW    = 33
BLUE      = 34
MAGENTA   = 35
CYAN      = 36
WHITE     = 37
RESET     = 39
BRIGHT    = 1
DIM       = 2
NORMAL    = 22
RESET_ALL = 0

def color(text, fgcolor = RESET, bgcolor = RESET, style = NORMAL):
    esc = '\033[%dm'
    colorstring = esc % fgcolor
    colorstring += esc % (bgcolor+10)
    colorstring += esc % style
    colorstring += text
    colorstring += esc % RESET_ALL

    return colorstring

# not exactly top notch, but whatever...
def signPackage(gpgName, passPhrase, package):
    io = StringIO.StringIO()

    print "Signing packages..."
    passDef = ""
    if passPhrase:
        # these defines are to override some strange rpm bug...
        passDef = """-D "__gpg_check_password_cmd %%{__gpg} gpg --batch --no-verbose --passphrase %s -u '%%{_gpg_name}' -so -" -D "__gpg_sign_cmd %%{__gpg} gpg --batch --no-verbose --no-armor --passphrase %s --no-secmem-warning -u '%%{_gpg_name}' -sbo %%{__signature_filename} %%{__plaintext_filename}" """ % (passPhrase, passPhrase)
    exp = subprocess.Popen(["echo","-e","""
spawn rpm -D "_gpg_name %s" %s --resign %s

expect -exact "Enter pass phrase: "
send -- "\n"
expect eof
""" % (gpgName, passDef, package)],stdout=subprocess.PIPE)

    sign = subprocess.Popen(["expect", "-f", "-"], stdin=exp.stdout)
    sign.wait()
    print "Signing done"

# vim:ts=4:sw=4:et
