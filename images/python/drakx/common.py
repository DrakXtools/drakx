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

# vim:ts=4:sw=4:et
